import 'package:flutter/foundation.dart';

import '../library/book.dart';
import 'recap_backend.dart';
import 'recap_stop.dart';

/// Where the reader stopped in one open book, for the welcome-back pop-up.
///
/// The recap itself is an Ask conversation (`AskController.catchUp`); this
/// only finds out whether there is one to offer, and where it would stop.
class RecapController extends ChangeNotifier {
  RecapController({required this.book, required this.backend});

  final Book book;

  /// Where it finds out where the reader stopped.
  final RecapBackend backend;

  /// Bumped for each look at the reader's place, so an older, slower one can't
  /// replace a newer one.
  int _generation = 0;
  bool _disposed = false;

  RecapStart? _start;
  bool _failed = false;

  /// Whether it has looked at least once.
  bool get prepared => _start != null || _failed;

  /// Whether a recap can be offered, and if not, why not. Null until the first
  /// look, or if the last one failed.
  RecapStart? get start => _start;

  /// Where the reader stopped, or null if no recap can be offered now.
  RecapStop? get stop => switch (_start) {
    RecapCanStart(:final stop) => stop,
    _ => null,
  };

  /// Finds where the reader stopped. Called when the book opens.
  ///
  /// Listeners hear only the result, not the start: this may be called while
  /// the screen is being built. If the Story Map can't be read, there is
  /// nothing to offer.
  Future<void> prepare() async {
    final generation = ++_generation;
    RecapStart? start;
    var failed = false;
    try {
      start = await backend.prepare(book);
    } on Object catch (error) {
      debugPrint('Could not find where the reader stopped: $error');
      failed = true;
    }
    if (_disposed || generation != _generation) return;
    _start = start;
    _failed = failed;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
