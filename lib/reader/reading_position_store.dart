import 'dart:io';

import 'reader_position.dart';

/// Each book's reading position, kept on the device next to the library.
///
/// Every book has its own `reading_state/<book id>.json`.
class ReadingPositionStore {
  ReadingPositionStore(this.root);

  /// The store in the library folder of the app's support directory.
  ///
  /// Every caller shares one store, so writes for a book never race.
  static Future<ReadingPositionStore> open() => throw UnimplementedError();

  /// The library folder, the same one `BookRepository` uses.
  final Directory root;

  /// Completes once every save so far is written to disk.
  Future<void> get saved => throw UnimplementedError();

  /// The saved position for [bookId], or null if there is none or the file
  /// can't be read.
  Future<ReaderPosition?> load(String bookId) => throw UnimplementedError();

  Future<void> save(String bookId, ReaderPosition position) =>
      throw UnimplementedError();
}
