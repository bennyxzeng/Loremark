import 'package:flutter/foundation.dart';

import '../library/book.dart';
import '../settings/ai_settings.dart';
import 'recap_backend.dart';
import 'recap_client.dart';
import 'recap_source.dart';

/// The opening recap of one open book, shared by the welcome-back pop-up,
/// which offers it, and the Ask tab, which shows it.
///
/// Nothing is sent until [write] is called: every recap is a paid request.
class RecapController extends ChangeNotifier {
  RecapController({required this.book, required this._backend});

  final Book book;
  final RecapBackend _backend;

  /// Bumped for each look at the reader's place, so an older, slower one can't
  /// replace a newer one.
  int _generation = 0;
  bool _disposed = false;

  bool _preparing = false;
  RecapStart? _start;
  String? _prepareError;

  bool _writing = false;
  Recap? _recap;
  String? _error;

  /// Whether it is finding where a recap would stop.
  bool get preparing => _preparing;

  /// Whether it has looked at least once.
  bool get prepared => _start != null || _prepareError != null;

  /// Whether a recap could be written now, and if not, why not. Null until
  /// the first look, or if the last one failed.
  RecapStart? get start => _start;

  /// What a recap would use, or null if none could be written now.
  RecapSource? get source => switch (_start) {
    RecapCanStart(:final source) => source,
    _ => null,
  };

  /// Why the reader's place couldn't be found, if it couldn't.
  String? get prepareError => _prepareError;

  /// Whether a recap request is running.
  bool get writing => _writing;

  /// The latest recap, while the reader is still where it stops.
  Recap? get recap => _recap;

  /// Why the latest request failed, if it did.
  String? get error => _error;

  /// Finds where a recap would stop. Called when the book opens and each time
  /// the Ask tab does, since the reader may have read on, turned back, or
  /// updated the Story Map.
  ///
  /// A recap of anywhere else is dropped: an old one must never show for a
  /// new place. Listeners hear only the result, not the start: this may be
  /// called while a tab is being built.
  Future<void> prepare() async {
    final generation = ++_generation;
    _preparing = true;
    RecapStart? start;
    String? error;
    try {
      start = await _backend.prepare(book);
    } on Object {
      error =
          'Loremark couldn’t read what you’ve read of this book from its '
          'Story Map, so it can’t write a recap.';
    }
    if (_disposed || generation != _generation) return;
    _preparing = false;
    _start = start;
    _prepareError = error;
    if (_recap?.place != source?.place) {
      _recap = null;
      _error = null;
    }
    _notify();
  }

  /// Asks for a recap of the latest [source]. Does nothing if there is none or
  /// a request is already running, so one press is one request.
  Future<void> write(AiCredentials credentials) async {
    final source = this.source;
    if (source == null || _writing) return;
    _writing = true;
    _error = null;
    _notify();
    RecapResult result;
    try {
      result = await _backend.recap(source, credentials);
    } on Object {
      result = const RecapFailed('The recap didn’t come through. Try again.');
    }
    if (_disposed) return;
    _writing = false;
    switch (result) {
      case RecapReady(:final recap):
        // Kept only if the reader is still where it stops.
        if (recap.place == this.source?.place) _recap = recap;
      case RecapFailed(:final message):
        _error = message;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
