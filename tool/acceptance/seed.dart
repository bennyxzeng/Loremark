import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../../test/support/synthetic_book.dart';
import 'adb.dart';

const appPackage = 'com.example.loremark';

/// The app's `getApplicationSupportDirectory()` on Android, relative to the
/// `run-as` home (`/data/user/0/<package>`): `Context.getFilesDir()`.
const _library = 'files/library';
const _filesDir = '/data/user/0/$appPackage/files';

/// The generated book the harness reads in the app.
class HarnessBook {
  const HarnessBook({
    required this.bytes,
    required this.id,
    required this.title,
    required this.author,
    required this.markers,
    required this.chapters,
  });

  final Uint8List bytes;

  /// Lowercase hex SHA-256 of [bytes], which the app uses as the book id.
  final String id;
  final String title;
  final String author;

  /// One unique phrase planted at the start of each chapter, so a leak in the
  /// network capture can be traced to the chapter that reached it.
  final List<String> markers;
  final int chapters;
}

const harnessTitle = 'Acceptance Harbor';

/// The synthetic book with what Readium needs and the unit-test builder
/// leaves out: a navigation document, `dc:identifier`, `dc:language`,
/// `dcterms:modified`, and a `mimetype` entry stored first and uncompressed.
HarnessBook buildHarnessBook({
  int chapters = 12,
  int wordsPerChapter = 3000,
  int seed = 403,
}) {
  final markers = [
    for (var c = 0; c < chapters; c++)
      'LOREMARK-MARKER-c${c + 1}-s$seed-${(seed * 31 + c * 7919).toRadixString(36)}',
  ];
  final synthetic = buildSyntheticBook(
    chapters: chapters,
    wordsPerChapter: wordsPerChapter,
    seed: seed,
    title: harnessTitle,
    markers: {for (var c = 0; c < chapters; c++) c: markers[c]},
  );
  final source = ZipDecoder().decodeBytes(synthetic);
  List<int> content(String name) => source.findFile(name)!.content as List<int>;

  final items = [
    for (var c = 1; c <= chapters; c++)
      '<item id="ch$c" href="ch$c.xhtml" media-type="application/xhtml+xml"/>',
  ].join();
  final refs = [for (var c = 1; c <= chapters; c++) '<itemref idref="ch$c"/>']
      .join();
  final links = [
    for (var c = 1; c <= chapters; c++)
      '<li><a href="ch$c.xhtml">Chapter $c</a></li>',
  ].join();
  final text = {
    'META-INF/container.xml':
        '<?xml version="1.0"?>'
        '<container version="1.0" '
        'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles>'
        '</container>',
    'OEBPS/content.opf':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
        'unique-identifier="bookid">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="bookid">urn:loremark:acceptance:$seed</dc:identifier>'
        '<dc:title>$harnessTitle</dc:title>'
        '<dc:creator>Loremark Test Generator</dc:creator>'
        '<dc:language>en</dc:language>'
        '<meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>'
        '</metadata>'
        '<manifest>'
        '<item id="nav" href="nav.xhtml" '
        'media-type="application/xhtml+xml" properties="nav"/>'
        '$items</manifest><spine>$refs</spine></package>',
    'OEBPS/nav.xhtml':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops">'
        '<head><title>Contents</title></head><body>'
        '<nav epub:type="toc"><ol>$links</ol></nav></body></html>',
  };

  final archive = Archive();
  final mimetype = utf8.encode('application/epub+zip');
  archive.addFile(
    ArchiveFile.noCompress('mimetype', mimetype.length, mimetype),
  );
  for (final MapEntry(:key, :value) in text.entries) {
    archive.addFile(ArchiveFile.bytes(key, utf8.encode(value)));
  }
  for (var c = 1; c <= chapters; c++) {
    archive.addFile(
      ArchiveFile.bytes('OEBPS/ch$c.xhtml', content('OEBPS/ch$c.xhtml')),
    );
  }
  // A fixed timestamp keeps the bytes, and so the book id, the same on every
  // run for a given seed.
  for (final file in archive) {
    file.lastModTime = DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000;
  }
  final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
  return HarnessBook(
    bytes: bytes,
    id: sha256.convert(bytes).toString(),
    title: harnessTitle,
    author: 'Loremark Test Generator',
    markers: markers,
    chapters: chapters,
  );
}

/// The app's `library.json` for [book], with [lastOpened] auto-opened on
/// launch (`LibraryScreen` opens it by itself, which is how a relaunch lands
/// back in the reader).
String libraryJson(HarnessBook book, {required bool lastOpened}) => jsonEncode({
  'version': 1,
  'last_opened_id': lastOpened ? book.id : null,
  'books': [
    {
      'id': book.id,
      'title': book.title,
      'author': book.author,
      'epub_path': '$_filesDir/library/books/${book.id}.epub',
      'cover_path': null,
      'imported_at': '2026-01-01T00:00:00Z',
    },
  ],
});

/// A `reading_state/<id>.json` placing the reader at [section] and
/// [progression].
String readingStateJson(int section, double progression) => jsonEncode({
  'version': 1,
  'current': {'sectionIndex': section, 'progression': progression},
});

/// What `reading_state/<id>.json` holds, or null if the file is missing or
/// unreadable.
({int section, double progression})? parseReadingState(String json) {
  try {
    final decoded = jsonDecode(json);
    final current = (decoded as Map<String, dynamic>)['current'];
    if (current is! Map<String, dynamic>) return null;
    return (
      section: current['sectionIndex'] as int,
      progression: (current['progression'] as num).toDouble(),
    );
  } on Object {
    return null;
  }
}

/// Writes app data into a debuggable install, through `adb push` and
/// `run-as cp`. Seed only while the app is stopped: it loads `library.json`
/// once at start and rewrites it later.
class AppSeeder {
  AppSeeder(this.adb, this.book, this.scratchDir);

  final Adb adb;
  final HarnessBook book;

  /// A host directory for the staging files.
  final Directory scratchDir;

  static const _stage = '/data/local/tmp/loremark-acceptance';

  /// Installs the book and a fresh library file.
  Future<void> seedLibrary({required bool lastOpened}) async {
    final epub = File('${scratchDir.path}/book.epub')
      ..writeAsBytesSync(book.bytes);
    await adb.shell('mkdir -p $_stage');
    await adb.push(epub.path, '$_stage/book.epub');
    await _stageFile('library.json', libraryJson(book, lastOpened: lastOpened));
    await adb.runAs(
      appPackage,
      'mkdir -p $_library/books $_library/reading_state && '
      'cp $_stage/book.epub $_library/books/${book.id}.epub && '
      'cp $_stage/library.json $_library/library.json',
    );
  }

  /// Replaces the saved reading position of the book.
  Future<void> seedPosition(int section, double progression) async {
    await _stageFile('state.json', readingStateJson(section, progression));
    await adb.runAs(
      appPackage,
      'mkdir -p $_library/reading_state && '
      'cp $_stage/state.json $_library/reading_state/${book.id}.json',
    );
  }

  /// Removes the saved position, as for a book never opened.
  Future<void> clearPosition() =>
      adb.runAs(appPackage, 'rm -f $_library/reading_state/${book.id}.json');

  /// The saved position now on the device, or null.
  Future<({int section, double progression})?> readPosition() async {
    final result = await adb.shell(
      "run-as $appPackage sh -c 'cat $_library/reading_state/${book.id}.json'",
      check: false,
    );
    return parseReadingState(result);
  }

  Future<void> _stageFile(String name, String content) async {
    final file = File('${scratchDir.path}/$name')..writeAsStringSync(content);
    await adb.push(file.path, '$_stage/$name');
  }

  /// Removes the staging files from the device.
  Future<void> cleanUp() => adb.shell('rm -rf $_stage', check: false);
}
