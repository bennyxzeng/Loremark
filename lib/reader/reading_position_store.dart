import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'reader_position.dart';

/// Each book's reading position, kept on the device next to the library.
///
/// Every book has its own `reading_state/<book id>.json`, holding
/// `{"version": 1, "current": <ReaderPosition JSON>}`. `current` is the key
/// `ReadingProgressTracker` uses for the same file, which lets it add
/// `furthest` and `boundary` beside it later.
///
/// The reader saves on every page turn, so a write is one small file, and a
/// crash at any point leaves either the old position or the new one.
class ReadingPositionStore {
  ReadingPositionStore(this.root);

  static Future<ReadingPositionStore>? _shared;

  /// The store in the library folder of the app's support directory.
  ///
  /// Every caller shares one store, so writes for a book never race.
  static Future<ReadingPositionStore> open() => _shared ??= _create();

  static Future<ReadingPositionStore> _create() async {
    try {
      final support = await getApplicationSupportDirectory();
      return ReadingPositionStore(Directory('${support.path}/library'));
    } on Object {
      // Don't keep a failure for the rest of the run.
      _shared = null;
      rethrow;
    }
  }

  /// The library folder, the same one `BookRepository` uses.
  final Directory root;

  /// Saves waiting behind the running write, by book. A newer save for the
  /// same book replaces the one waiting, so page turns faster than the disk
  /// don't pile up writes.
  final _queued = <String, _QueuedSave>{};
  Future<void> _writing = Future.value();

  /// Completes once every save so far is written to disk.
  ///
  /// A failed write is reported to its own caller, not here.
  Future<void> get saved => _writing;

  static final _validId = RegExp(r'^[A-Za-z0-9_-]+$');

  /// The file for [bookId]. Ids are SHA-256 hashes, but a path separator or
  /// `..` must never reach the file system.
  File _file(String bookId) {
    if (!_validId.hasMatch(bookId)) {
      throw ArgumentError.value(bookId, 'bookId', 'Not a valid book id');
    }
    return File('${root.path}/reading_state/$bookId.json');
  }

  /// The saved position for [bookId], or null if there is none or the file
  /// can't be read.
  ///
  /// A broken file must never stop the book from opening, so it reads as no
  /// position.
  Future<ReaderPosition?> load(String bookId) async {
    final file = _file(bookId);
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic> || json['version'] != 1) return null;
      final current = json['current'];
      if (current is! Map<String, dynamic>) return null;
      return ReaderPosition.fromJson(current);
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// Writes [position] as the saved position for [bookId].
  ///
  /// Completes once [position], or a newer save for the same book, is on disk.
  /// Throws if the write fails; later saves are not affected.
  Future<void> save(String bookId, ReaderPosition position) async {
    final file = _file(bookId);
    final queued = _queued[bookId];
    if (queued != null) {
      queued.position = position;
      return queued.done.future;
    }
    final save = _queued[bookId] = _QueuedSave(position);
    _writing = _writing.then((_) async {
      // A save arriving from now on is newer than this write, so it queues
      // again instead of changing what is written.
      _queued.remove(bookId);
      try {
        await _write(file, save.position);
        save.done.complete();
      } on Object catch (error, stackTrace) {
        save.done.completeError(error, stackTrace);
      }
    });
    return save.done.future;
  }

  /// Writes to a temporary file first, so a crash mid-write cannot lose the
  /// position.
  ///
  /// The other keys of the existing file stay, since the progress tracker
  /// keeps its own beside `current`. Only the writes in the queue touch the
  /// file, so reading it here can't race another save.
  Future<void> _write(File file, ReaderPosition position) async {
    await file.parent.create(recursive: true);
    final state = await _readState(file);
    state['current'] = position.toJson();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(state), flush: true);
    await temp.rename(file.path);
  }

  /// What [file] holds, or a fresh state if it is missing, broken or from
  /// another version.
  Future<Map<String, dynamic>> _readState(File file) async {
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, dynamic> && json['version'] == 1) return json;
    } on FormatException {
      // Starts fresh, like [load] reads it as no position.
    } on FileSystemException {
      // Same.
    }
    return {'version': 1};
  }
}

class _QueuedSave {
  _QueuedSave(this.position);

  ReaderPosition position;
  final done = Completer<void>();
}
