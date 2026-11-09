import 'package:flutter/foundation.dart';

import '../library/book.dart';
import '../settings/ai_settings.dart';
import 'recap_backend.dart';
import 'recap_client.dart';
import 'recap_source.dart';

/// The opening recap of one open book, shared by the Read tab's welcome-back
/// card, which offers it, and the Ask tab, which shows it.
///
/// Nothing is sent until [write] is called: every recap is a paid request.
class RecapController extends ChangeNotifier {
  RecapController({required this.book, RecapBackend? backend})
    : _backend = backend ?? DeviceRecapBackend();

  final Book book;
  final RecapBackend _backend;

  /// Bumped for each look at the reader's place, so an older, slower one can't
  /// replace a newer one.
  int _generation = 0;
  bool _disposed = false;

  bool _preparing = false;
  bool _prepared = false;
  RecapSource? _source;
  String? _prepareError;

  bool _writing = false;
  Recap? _recap;
  String? _error;

  /// Whether it is finding where a recap would stop.
  bool get preparing => _preparing;

  /// Whether it has looked at least once, so a null [source] means there is
  /// nothing to recap yet rather than not knowing.
  bool get prepared => _prepared;

  /// What a recap would use, or null if the reader hasn't finished a section.
  RecapSource? get source => _source;

  /// Why the book couldn't be read to find the reader's place, if it couldn't.
  String? get prepareError => _prepareError;

  /// Whether a recap request is running.
  bool get writing => _writing;

  /// The latest recap, kept until a new one comes.
  Recap? get recap => _recap;

  /// Why the latest request failed, if it did.
  String? get error => _error;

  /// Finds where a recap would stop. Called when the book opens and each time
  /// the Ask tab does, since the reader may have read on.
  ///
  /// Listeners hear only the result, not the start: this may be called while a
  /// tab is being built, and what was found last time stays up meanwhile.
  Future<void> prepare() async {
    final generation = ++_generation;
    _preparing = true;
    RecapSource? source;
    String? error;
    try {
      source = await _backend.prepare(book);
    } on Object {
      error = 'Loremark couldn’t read this book to find your place.';
    }
    if (_disposed || generation != _generation) return;
    _preparing = false;
    _prepared = true;
    _source = source;
    _prepareError = error;
    _notify();
  }

  /// Asks for a recap of the latest [source]. Does nothing if there is none or
  /// a request is already running, so one press is one request.
  Future<void> write(AiCredentials credentials) async {
    final source = _source;
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
        _recap = recap;
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
