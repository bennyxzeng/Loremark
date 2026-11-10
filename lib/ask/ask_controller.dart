import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show TextEditingController;

import '../library/book.dart';
import '../settings/ai_settings.dart';
import '../story_update/story_model_choice.dart';
import 'ask_backend.dart';
import 'ask_boundary.dart';
import 'ask_engine.dart';
import 'ask_history.dart';
import 'ask_stream.dart';

/// Where a question is.
enum AskStage {
  /// Working out how far the reader has read.
  reading,

  /// Waiting for the model.
  thinking,

  /// Running lookups the model asked for.
  lookingUp,

  /// The answer is arriving.
  writing,

  /// It ended without an answer: see [AskPending.failure].
  failed,
}

/// The question being answered, or the last one, if it failed.
class AskPending {
  AskPending(this.question);

  final String question;
  AskStage stage = AskStage.reading;

  /// The answer so far, while it arrives.
  String text = '';

  /// What to tell the reader, once it failed.
  String? failure;

  bool get running => stage != AskStage.failed;
}

/// One book's Ask tab: its conversation, the question under way, and how far
/// the reader has read.
///
/// It outlives the tab's widgets, which are rebuilt when Ask locks and unlocks,
/// so a question under way and a half-written one survive going offline.
class AskController extends ChangeNotifier {
  AskController({
    required this.book,
    required this.backend,
    Future<AskHistoryStore> Function()? openHistory,
    this.post = postAskRequest,
    Future<String> Function()? loadPrompt,
    DateTime Function()? now,
  }) : _openHistory = openHistory ?? AskHistoryStore.open,
       _loadPrompt =
           loadPrompt ??
           (() => rootBundle.loadString('assets/chat/$askPromptName')),
       _now = now ?? DateTime.now;

  final Book book;
  final AskBackend backend;

  /// How requests reach the provider; tests replace the network.
  final AskHttpPost post;
  final Future<AskHistoryStore> Function() _openHistory;
  final Future<String> Function() _loadPrompt;
  final DateTime Function() _now;

  /// The question being written.
  final draft = TextEditingController();

  AskHistoryStore? _history;
  final _exchanges = <AskExchange>[];
  AskPending? _pending;
  AskBoundary? _boundary;
  Object? _boundaryError;
  bool _loaded = false;
  Future<void>? _refreshing;
  AskCancel? _cancel;
  bool _disposed = false;

  /// The conversation, oldest first.
  List<AskExchange> get exchanges => List.unmodifiable(_exchanges);

  AskPending? get pending => _pending;

  /// What answers can draw on, as of the last look at the reader's place.
  AskBoundary? get boundary => _boundary;

  /// Why the reader's place couldn't be worked out, if it couldn't.
  Object? get boundaryError => _boundaryError;

  /// Whether the conversation and the reader's place have been read once.
  bool get loaded => _loaded;

  bool get busy => _pending?.running ?? false;

  /// Looks again at how far the reader has read, and reads the conversation
  /// the first time. Calls made while one is running wait for it.
  Future<void> refresh() => _refreshing ??= _refresh().whenComplete(() {
    _refreshing = null;
  });

  Future<void> _refresh() async {
    try {
      final history = _history ??= await _openHistory();
      if (!_loaded) _exchanges.addAll(await history.load(book.id));
    } on Object catch (error) {
      debugPrint('Could not read the Ask conversation: $error');
    }
    try {
      _boundary = await openAskBoundary(backend, book);
      _boundaryError = null;
    } on Object catch (error) {
      _boundaryError = error;
    }
    _loaded = true;
    _notify();
  }

  /// Asks [question] with the reader's key and Ask's model. Does nothing while
  /// another question is under way.
  Future<void> ask(
    String question, {
    required AiCredentials credentials,
    required StoryModelChoice model,
    required StoryEffort effort,
  }) async {
    final text = question.trim();
    if (text.isEmpty || busy) return;
    final pending = _pending = AskPending(text);
    _notify();

    // Where the reader is now, held for the whole question.
    final AskBoundary boundary;
    try {
      boundary = await openAskBoundary(backend, book);
    } on Object catch (error) {
      debugPrint('Could not read the Story Map for Ask: $error');
      return _fail(
        pending,
        'Couldn’t read this book’s Story Map, so nothing was sent.',
      );
    }
    _boundary = boundary;
    _boundaryError = null;
    if (boundary.isEmpty) {
      return _fail(
        pending,
        'There’s nothing read yet to answer from. Read a page first.',
      );
    }

    final cancel = _cancel = AskCancel();
    pending.stage = AskStage.thinking;
    _notify();
    final AskAnswer answer;
    try {
      answer = await askStory(
        boundary: boundary,
        question: text,
        prompt: await _loadPrompt(),
        model: model,
        effort: effort,
        apiKey: credentials.apiKey,
        history: [for (final exchange in _exchanges) exchange.turn],
        post: post,
        cancel: cancel,
        onRound: () {
          pending
            ..text = ''
            ..stage = AskStage.thinking;
          _notify();
        },
        onText: (delta) {
          pending
            ..text += delta
            ..stage = AskStage.writing;
          _notify();
        },
        onLookup: (_) {
          pending.stage = AskStage.lookingUp;
          _notify();
        },
      );
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
    }
    if (_disposed) return;

    final cutOff = answer.status == 'incomplete';
    if (answer.answered || (cutOff && answer.text.trim().isNotEmpty)) {
      _exchanges.add(
        AskExchange(
          question: text,
          answer: answer.text,
          limit: boundary.reach.limit,
          askedAt: _now(),
          cutOff: cutOff,
        ),
      );
      _pending = null;
      _notify();
      await _save();
      return;
    }
    _fail(pending, describeAskFailure(answer));
  }

  /// Asks the question that failed again. Another paid request, so only when
  /// the reader says so.
  Future<void> retry({
    required AiCredentials credentials,
    required StoryModelChoice model,
    required StoryEffort effort,
  }) async {
    final failed = _pending;
    if (failed == null || failed.running) return;
    _pending = null;
    await ask(
      failed.question,
      credentials: credentials,
      model: model,
      effort: effort,
    );
  }

  /// Stops the question under way. What was said so far isn't kept.
  void stop() => _cancel?.cancel();

  /// Puts a failed question away.
  void dismiss() {
    if (_pending?.running ?? true) return;
    _pending = null;
    _notify();
  }

  /// Forgets the conversation.
  Future<void> clear() async {
    if (busy) return;
    _exchanges.clear();
    _pending = null;
    _notify();
    try {
      await (_history ??= await _openHistory()).delete(book.id);
    } on Object catch (error) {
      debugPrint('Could not clear the Ask conversation: $error');
    }
  }

  void _fail(AskPending pending, String message) {
    if (_disposed) return;
    pending
      ..stage = AskStage.failed
      ..text = ''
      ..failure = message;
    _notify();
  }

  Future<void> _save() async {
    try {
      await (_history ??= await _openHistory()).save(book.id, _exchanges);
    } on Object catch (error) {
      debugPrint('Could not save the Ask conversation: $error');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    draft.dispose();
    super.dispose();
  }
}

/// What to tell the reader about a question that got no answer.
String describeAskFailure(AskAnswer answer) {
  const mayCharge = 'Your provider may still charge for it.';
  final error = answer.error;
  final message = error?['message'];
  return switch (answer.status) {
    'cancelled' => 'Stopped. Nothing was kept.',
    'api_error' => switch (error?['category']) {
      'authentication' ||
      'permission_denied' => 'Your API key was rejected. Check it in Settings.',
      'rate_limit' =>
        'Your provider is limiting requests, or your credit has run out. '
            'Try again later.',
      'network' || 'timeout' => 'The request didn’t finish. $mayCharge',
      'server_error' => 'Your provider had a problem. Try again later.',
      _ => 'Your provider refused the request: $message.',
    },
    'refusal' => 'The model declined to answer. $mayCharge',
    'incomplete' => 'The answer was cut off before it began. $mayCharge',
    _ => 'The model gave no usable answer. $mayCharge',
  };
}
