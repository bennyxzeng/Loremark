import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Bytes standing in for a cover image.
final coverBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3]);

enum CoverStyle { none, epub2, epub3 }

/// One spine item of a test EPUB.
class EpubChapter {
  const EpubChapter({
    required this.id,
    required this.fileName,
    this.body = '',
    this.linear = true,
    this.raw,
    this.inArchive = true,
    this.inManifest = true,
  });

  final String id;

  /// The file name inside `OEBPS/`, which may contain characters that the
  /// manifest `href` has to percent-encode.
  final String fileName;

  /// Markup placed inside the `<body>` of a well-formed XHTML page.
  final String body;
  final bool linear;

  /// The whole file as is, in place of the page built from [body].
  final String? raw;

  /// False to leave the file out of the archive, as a broken EPUB might.
  final bool inArchive;

  /// False to leave the manifest `item` out while the spine still refers to
  /// [id].
  final bool inManifest;
}

/// A minimal EPUB with its package document in `OEBPS/` and its cover in
/// `OEBPS/images/`.
///
/// By default the spine is one `ch1` item that the manifest declares but the
/// archive does not contain. Pass [chapters] to build a real book.
Uint8List buildEpub({
  String? title = 'The Glass Harbor',
  String? author = 'A. Writer',
  CoverStyle cover = CoverStyle.epub3,
  List<EpubChapter> chapters = const [
    EpubChapter(id: 'ch1', fileName: 'ch1.xhtml', inArchive: false),
  ],
}) {
  final metadata = [
    if (title != null) '<dc:title>$title</dc:title>',
    if (author != null) '<dc:creator>$author</dc:creator>',
    if (cover == CoverStyle.epub2) '<meta name="cover" content="cover-img"/>',
  ].join();
  final properties = cover == CoverStyle.epub3
      ? ' properties="cover-image"'
      : '';
  final coverItem = cover == CoverStyle.none
      ? ''
      : '<item id="cover-img" href="images/cover%20art.jpg" '
            'media-type="image/jpeg"$properties/>';
  final chapterItems = [
    for (final chapter in chapters)
      if (chapter.inManifest)
        '<item id="${chapter.id}" href="${Uri.encodeFull(chapter.fileName)}" '
            'media-type="application/xhtml+xml"/>',
  ].join();
  final itemrefs = [
    for (final chapter in chapters)
      '<itemref idref="${chapter.id}"'
          '${chapter.linear ? '' : ' linear="no"'}/>',
  ].join();

  final files = {
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<?xml version="1.0"?>'
        '<container version="1.0" '
        'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles>'
        '</container>',
    'OEBPS/content.opf':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">$metadata'
        '</metadata>'
        '<manifest>$coverItem$chapterItems</manifest>'
        '<spine>$itemrefs</spine>'
        '</package>',
    for (final chapter in chapters)
      if (chapter.inArchive)
        'OEBPS/${chapter.fileName}':
            chapter.raw ??
            '<?xml version="1.0" encoding="UTF-8"?>'
                '<html xmlns="http://www.w3.org/1999/xhtml">'
                '<head><title>${chapter.id}</title></head>'
                '<body>${chapter.body}</body></html>',
  };
  final archive = Archive();
  for (final MapEntry(:key, :value) in files.entries) {
    archive.addFile(_fixedTime(ArchiveFile.bytes(key, utf8.encode(value))));
  }
  if (cover != CoverStyle.none) {
    archive.addFile(
      _fixedTime(ArchiveFile.bytes('OEBPS/images/cover art.jpg', coverBytes)),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

/// Gives [file] the same timestamp every time. A zip stores the time each
/// file was added, so without this two builds of the same book differ by a
/// byte whenever the clock ticks between them.
ArchiveFile _fixedTime(ArchiveFile file) {
  const seconds = 1700000000;
  return file
    ..creationTime = seconds
    ..lastModTime = seconds;
}
