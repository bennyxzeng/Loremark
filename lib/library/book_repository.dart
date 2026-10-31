import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'book.dart';
import 'epub_metadata.dart';

/// The reader's imported books, kept on the device.
///
/// Each EPUB is copied into [root], so the library still works after the
/// original file is moved or deleted. The list itself is `library.json`.
class BookRepository {
  BookRepository(this.root);

  /// The library in the app's private support directory.
  static Future<BookRepository> open() async {
    final support = await getApplicationSupportDirectory();
    final repository = BookRepository(Directory('${support.path}/library'));
    await repository.load();
    return repository;
  }

  final Directory root;
  final _books = <Book>[];
  String? _lastOpenedId;
  Future<void> _saving = Future.value();

  /// Completes once every change so far is written to disk.
  Future<void> get saved => _saving;

  File get _index => File('${root.path}/library.json');

  /// Books, most recently imported first.
  List<Book> get books => List.unmodifiable(_books);

  /// The book the reader opened last, to resume on launch.
  Book? get lastOpened => _find(_lastOpenedId);

  Book? _find(String? id) => _books.where((book) => book.id == id).firstOrNull;

  Future<void> load() async {
    _books.clear();
    _lastOpenedId = null;
    if (!await _index.exists()) return;
    final json =
        jsonDecode(await _index.readAsString()) as Map<String, dynamic>;
    _books.addAll([
      for (final book in json['books'] as List)
        Book.fromJson(book as Map<String, dynamic>),
    ]);
    _lastOpenedId = json['last_opened_id'] as String?;
  }

  /// Copies the EPUB at [sourcePath] into the library.
  ///
  /// Returns the existing book, with `isNew` false, if this exact file was
  /// imported before. Throws a [FormatException] if the file is not an EPUB.
  Future<({Book book, bool isNew})> importEpub(String sourcePath) async {
    final source = File(sourcePath);
    final fallbackTitle = source.uri.pathSegments.last.replaceFirst(
      RegExp(r'\.epub$', caseSensitive: false),
      '',
    );
    final bytes = await source.readAsBytes();
    // Hashing and unzipping a long novel takes long enough to drop frames.
    final (id, metadata) = await Isolate.run(
      () => (
        sha256.convert(bytes).toString(),
        readEpubMetadata(bytes, fallbackTitle: fallbackTitle),
      ),
    );

    final existing = _find(id);
    if (existing != null) return (book: existing, isNew: false);

    final epub = File('${root.path}/books/$id.epub');
    await epub.parent.create(recursive: true);
    await epub.writeAsBytes(bytes);
    File? cover;
    if (metadata.cover case final coverBytes?) {
      cover = File('${root.path}/covers/$id.${metadata.coverExtension}');
      await cover.parent.create(recursive: true);
      await cover.writeAsBytes(coverBytes);
    }

    final book = Book(
      id: id,
      title: metadata.title,
      author: metadata.author,
      epubPath: epub.path,
      coverPath: cover?.path,
      importedAt: DateTime.now(),
    );
    _books.insert(0, book);
    await _save();
    return (book: book, isNew: true);
  }

  Future<void> markOpened(Book book) async {
    if (_lastOpenedId == book.id) return;
    _lastOpenedId = book.id;
    await _save();
  }

  /// Removes [book] and its files from the library.
  Future<void> remove(Book book) async {
    _books.removeWhere((other) => other.id == book.id);
    if (_lastOpenedId == book.id) _lastOpenedId = null;
    await _save();
    for (final path in [book.epubPath, book.coverPath]) {
      if (path == null) continue;
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  /// Queues a write, so two saves never share the temporary file. A failed
  /// write is reported to its own caller and doesn't block later ones.
  Future<void> _save() =>
      _saving = _saving.catchError((Object _) {}).then((_) => _write());

  /// Writes to a temporary file first, so a crash mid-write cannot lose the
  /// library.
  Future<void> _write() async {
    await root.create(recursive: true);
    final temp = File('${_index.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'version': 1,
        'last_opened_id': _lastOpenedId,
        'books': [for (final book in _books) book.toJson()],
      }),
    );
    await temp.rename(_index.path);
  }
}
