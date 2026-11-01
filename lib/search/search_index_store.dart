import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../reader/epub_sections.dart';
import 'passage_search.dart';
import 'search_index.dart';
import 'search_index_codec.dart';

/// Opens search for the book [bookId] whose EPUB is at [epubPath].
///
/// Loads the saved index if there is a valid one, and otherwise builds it
/// (the first time takes a few seconds for a long novel) and saves it for
/// next time. [root] is the library folder; it defaults to the one in the
/// app's support directory, where `BookRepository` keeps its files.
///
/// Throws if the EPUB can't be read.
Future<PassageSearch> openPassageSearch({
  required String bookId,
  required String epubPath,
  Directory? root,
}) async {
  final store = root == null
      ? await SearchIndexStore.open()
      : SearchIndexStore(root);
  return store.load(bookId: bookId, epubPath: epubPath);
}

/// Each book's search index, kept on the device next to the library.
///
/// The index of a book is `search_index/<book id>.bin`. It is cheap to lose:
/// a missing, damaged or outdated file (another format or tokenizer version,
/// or another book's) is simply built again from the EPUB.
class SearchIndexStore {
  SearchIndexStore(this.root);

  static Future<SearchIndexStore>? _shared;

  /// The store in the library folder of the app's support directory. Every
  /// caller shares one, so two screens asking for the same book wait for one
  /// build.
  static Future<SearchIndexStore> open() => _shared ??= _create();

  static Future<SearchIndexStore> _create() async {
    try {
      final support = await getApplicationSupportDirectory();
      return SearchIndexStore(Directory('${support.path}/library'));
    } on Object {
      // Don't keep a failure for the rest of the run.
      _shared = null;
      rethrow;
    }
  }

  /// The library folder, the same one `BookRepository` uses.
  final Directory root;

  final _building = <String, Future<SearchIndex>>{};

  static final _validId = RegExp(r'^[A-Za-z0-9_-]+$');

  /// The file for [bookId]. Ids are SHA-256 hashes, but a path separator or
  /// `..` must never reach the file system.
  File file(String bookId) {
    if (!_validId.hasMatch(bookId)) {
      throw ArgumentError.value(bookId, 'bookId', 'Not a valid book id');
    }
    return File('${root.path}/search_index/$bookId.bin');
  }

  /// The search for [bookId], loaded or built. Concurrent calls for the same
  /// book share one load.
  Future<SearchIndex> load({required String bookId, required String epubPath}) {
    final path = file(bookId).path;
    // Reading, unzipping, indexing and writing all stay off the UI isolate,
    // and the finished index moves back without being copied.
    return _building[bookId] ??=
        Isolate.run(() => loadOrBuildSearchIndex(bookId, epubPath, path))
            .whenComplete(() {
              // A block, not an arrow: returning the removed future would make
              // whenComplete wait for itself.
              _building.remove(bookId);
            });
  }
}

/// The index saved at [indexPath] for [bookId], or one built from the EPUB at
/// [epubPath] and saved there. Runs synchronously; [SearchIndexStore] calls it
/// in an isolate.
SearchIndex loadOrBuildSearchIndex(
  String bookId,
  String epubPath,
  String indexPath,
) {
  final file = File(indexPath);
  try {
    return decodeSearchIndex(file.readAsBytesSync(), bookId: bookId);
  } on FileSystemException {
    // No index yet.
  } on FormatException {
    // Damaged or outdated: replaced below.
  }
  final index = buildSearchIndexFromEpub(
    bookId,
    File(epubPath).readAsBytesSync(),
  );
  try {
    _writeAtomically(file, encodeSearchIndex(index));
  } on FileSystemException {
    // Search still works this session; the next one builds again.
  }
  return index;
}

/// The index of the EPUB in [epubBytes]: its linear sections' paragraphs.
/// Throws a [FormatException] if the bytes are not an EPUB.
SearchIndex buildSearchIndexFromEpub(String bookId, Uint8List epubBytes) {
  final linear = [for (final item in spineFromBytes(epubBytes)) item.linear];
  return SearchIndex.build(
    bookId: bookId,
    sectionTexts: sectionTextsFromBytes(epubBytes),
    linear: linear,
  );
}

/// Writes to a temporary file first, so a crash mid-write cannot leave half
/// an index (which would only be rebuilt, but wastes the work).
void _writeAtomically(File file, Uint8List bytes) {
  file.parent.createSync(recursive: true);
  final temp = File(
    '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    temp.writeAsBytesSync(bytes, flush: true);
    temp.renameSync(file.path);
  } on FileSystemException {
    if (temp.existsSync()) temp.deleteSync();
    rethrow;
  }
}
