import 'dart:convert';

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

/// The prompt a recap is asked with, in `assets/chat/`: Ask's own rules, with
/// recapping in place of answering.
const askRecapPromptName = 'recap_v1.txt';

/// What a recap is asked as. It shows in the conversation as the reader's
/// question, and later questions see it as one, so a follow-up such as "who is
/// she again?" reads naturally after the recap.
const askRecapQuestion = 'Catch me up on the story so far.';

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

/// How long the reader can be away from Ask and come back to the same
/// conversation. Away longer, they come back to a new one.
const askIdleGap = Duration(minutes: 5);

/// The question being answered, or the last one, if it failed.
class AskPending {
  AskPending(this.question, {this.recap = false});

  final String question;

  /// Whether it is a recap, asked with the recap prompt: see
  /// [AskController.catchUp].
  final bool recap;
  AskStage stage = AskStage.reading;

  /// The answer so far, while it arrives.
  String text = '';

  /// What to tell the reader, once it failed.
  String? failure;

  bool get running => stage != AskStage.failed;
}

/// One book's Ask tab: the conversation shown, the book's saved ones, the
/// question under way, and how far the reader has read.
///
/// It outlives the tab's widgets, which are rebuilt when Ask locks and unlocks,
/// so a question under way and a half-written one survive going offline. It
/// starts on a new conversation, since one is made each time the book opens.
class AskController extends ChangeNotifier {
  AskController({
    required this.book,
    required this.backend,
    Future<AskHistoryStore> Function()? openHistory,
    this.post = postAskRequest,
    Future<String> Function()? loadPrompt,
    Future<String> Function()? loadRecapPrompt,
    DateTime Function()? now,
  }) : _openHistory = openHistory ?? AskHistoryStore.open,
       _loadPrompt =
           loadPrompt ??
           (() => rootBundle.loadString('assets/chat/$askPromptName')),
       _loadRecapPrompt =
           loadRecapPrompt ??
           (() => rootBundle.loadString('assets/chat/$askRecapPromptName')),
       _now = now ?? DateTime.now;

  final Book book;
  final AskBackend backend;

  /// How requests reach the provider; tests replace the network.
  final AskHttpPost post;
  final Future<AskHistoryStore> Function() _openHistory;
  final Future<String> Function() _loadPrompt;
  final Future<String> Function() _loadRecapPrompt;
  final DateTime Function() _now;

  /// The question being written.
  final draft = TextEditingController();

  AskHistoryStore? _history;
  String? _conversationId;
  final _exchanges = <AskExchange>[];
  var _conversations = <AskConversation>[];
  DateTime? _awaySince;
  AskPending? _pending;
  AskBoundary? _boundary;
  Object? _boundaryError;
  bool _loaded = false;
  Future<void>? _refreshing;
  AskCancel? _cancel;
  bool _disposed = false;

  /// The conversation shown, oldest first. Empty for a new one.
  List<AskExchange> get exchanges => List.unmodifiable(_exchanges);

  /// The id of the conversation shown, or null while it is new and unsaved.
  String? get conversationId => _conversationId;

  /// The book's saved conversations, the latest first.
  List<AskConversation> get conversations => List.unmodifiable(_conversations);

  AskPending? get pending => _pending;

  /// What answers can draw on, as of the last look at the reader's place.
  AskBoundary? get boundary => _boundary;

  /// Why the reader's place couldn't be worked out, if it couldn't.
  Object? get boundaryError => _boundaryError;

  /// Whether the saved conversations and the reader's place have been read
  /// once.
  bool get loaded => _loaded;

  bool get busy => _pending?.running ?? false;

  /// Looks again at how far the reader has read, and reads the saved
  /// conversations the first time. After [leave], if the reader was away for
  /// [askIdleGap] or more, starts a new conversation. Calls made while one is
  /// running wait for it.
  Future<void> refresh() => _refreshing ??= _refresh().whenComplete(() {
    _refreshing = null;
  });

  Future<void> _refresh() async {
    final away = _awaySince;
    _awaySince = null;
    if (away != null && !_now().isBefore(away.add(askIdleGap))) startNew();
    if (!_loaded) {
      try {
        _conversations = await (await _store()).list(book.id);
      } on Object catch (error) {
        debugPrint('Could not read the Ask conversations: $error');
      }
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
  }) => _ask(
    question,
    recap: false,
    credentials: credentials,
    model: model,
    effort: effort,
  );

  /// Starts a new conversation with a recap of the story so far, up to the end
  /// of the reader's page (use case 1): the welcome back's **Catch me up**.
  ///
  /// It is a question like any other, asked as [askRecapQuestion] with the
  /// recap prompt, and kept with the book's conversations, so the reader can
  /// ask more about it in the same conversation. The one shown before stays in
  /// [conversations]. Does nothing while a question is under way.
  Future<void> catchUp({
    required AiCredentials credentials,
    required StoryModelChoice model,
    required StoryEffort effort,
  }) async {
    if (busy) return;
    startNew();
    await _ask(
      askRecapQuestion,
      recap: true,
      credentials: credentials,
      model: model,
      effort: effort,
    );
  }

  Future<void> _ask(
    String question, {
    required bool recap,
    required AiCredentials credentials,
    required StoryModelChoice model,
    required StoryEffort effort,
  }) async {
    final text = question.trim();
    if (text.isEmpty || busy) return;
    final pending = _pending = AskPending(text, recap: recap);
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
        prompt: await (recap ? _loadRecapPrompt : _loadPrompt)(),
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
    // Debug and profile builds only; for seeing what questions cost.
    if (kDebugMode || kProfileMode) {
      final fields = {
        'status': answer.status,
        'history': _exchanges.length,
        ...askUsageSummary(answer.usage),
      };
      debugPrintSynchronously('LOREMARK_ASK_USAGE ${jsonEncode(fields)}');
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
      final id = _conversationId ??= AskHistoryStore.newId(_now());
      final conversation = AskConversation(id, _exchanges);
      _conversations = [
        conversation,
        for (final other in _conversations)
          if (other.id != id) other,
      ];
      _pending = null;
      _notify();
      await _save(conversation);
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
    await _ask(
      failed.question,
      recap: failed.recap,
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

  /// Notes that the reader has left Ask: see [refresh].
  void leave() => _awaySince ??= _now();

  /// Starts a new conversation. The one shown, if it has anything, stays in
  /// [conversations]. Does nothing while a question is under way.
  void startNew() {
    if (busy) return;
    _conversationId = null;
    _exchanges.clear();
    _pending = null;
    _notify();
  }

  /// Shows saved conversation [id], to carry on with. Does nothing while a
  /// question is under way.
  void open(String id) {
    if (busy) return;
    final conversation = _conversations.where((c) => c.id == id).firstOrNull;
    if (conversation == null) return;
    _conversationId = id;
    _exchanges
      ..clear()
      ..addAll(conversation.exchanges);
    _pending = null;
    _notify();
  }

  /// Forgets saved conversation [id]. If it is the one shown, a new one takes
  /// its place; while a question is under way in it, does nothing.
  Future<void> deleteConversation(String id) async {
    final shown = id == _conversationId;
    if (shown && busy) return;
    _conversations = [
      for (final other in _conversations)
        if (other.id != id) other,
    ];
    if (shown) {
      _conversationId = null;
      _exchanges.clear();
      _pending = null;
    }
    _notify();
    try {
      await (await _store()).delete(book.id, id);
    } on Object catch (error) {
      debugPrint('Could not delete the Ask conversation: $error');
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

  Future<AskHistoryStore> _store() async => _history ??= await _openHistory();

  /// Saves [conversation] as it was, whatever is shown by the time the store
  /// is ready.
  Future<void> _save(AskConversation conversation) async {
    try {
      await (await _store()).save(
        book.id,
        conversation.id,
        conversation.exchanges,
      );
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
