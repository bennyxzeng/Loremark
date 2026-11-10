import 'dart:convert';

import '../reading/text_position.dart';
import '../story_update/story_book.dart' show JsonMap;
import '../story_update/story_model_choice.dart';
import 'ask_boundary.dart';
import 'ask_citations.dart';
import 'ask_stream.dart';
import 'story_lookup.dart';

/// The prompt Ask sends, in `assets/chat/`.
const askPromptName = 'answer_v1.txt';

/// The most requests one question may take. The last one must answer.
const maxAskRounds = 10;

/// The most earlier questions sent along with a new one.
const maxAskHistory = 10;

/// An earlier question and its answer.
class AskTurn {
  const AskTurn({
    required this.question,
    required this.answer,
    required this.limit,
  });

  final String question;
  final String answer;

  /// How far the reader had read when it was asked: [AskReach.limit].
  final TextPosition limit;
}

/// How a question ended.
class AskAnswer {
  const AskAnswer(
    this.status, {
    this.text = '',
    this.error,
    this.rounds = 0,
    this.usage = const [],
  });

  /// `answered`; `incomplete` if the answer was cut off; or how it failed:
  /// `cancelled`, `api_error`, `failed`, `refusal`, `empty_output` or
  /// `no_answer`.
  final String status;

  /// The answer, with any citation of a paragraph that wasn't given removed.
  final String text;

  /// `category` and `message`, for a failure.
  final JsonMap? error;

  /// How many requests it took.
  final int rounds;

  /// The provider's token counts, one per request.
  final List<JsonMap> usage;

  bool get answered => status == 'answered';
}

/// The body of one request of a question.
JsonMap buildAskRequest({
  required StoryModelChoice model,
  required StoryEffort? effort,
  required String instructions,
  required List<JsonMap> input,
  required List<JsonMap> tools,
  required bool lastRound,
}) {
  final provider = StoryProvider.named(model.providerName);
  return {
    'model': model.id,
    'input': [
      {'role': 'system', 'content': instructions},
      ...input,
    ],
    // Sent on the last round too, with no choice, so the prefix stays the same.
    if (tools.isNotEmpty) ...{
      'tools': tools,
      'tool_choice': lastRound ? 'none' : 'auto',
    },
    'reasoning': ?(effort == null ? null : {'effort': effort.name}),
    'stream': true,
    if (provider.sendsStoreAndTruncation) ...{
      'store': false,
      'truncation': 'disabled',
      // Nothing is stored, so the model's reasoning between tool calls has to
      // come back with them, sealed.
      'include': ['reasoning.encrypted_content'],
    },
  };
}

/// The reader's message: the page they're on, then their question.
String askMessage(AskPage? page, String question) => [
  if (page == null)
    'CURRENT_PAGE: not available. The reader\'s page couldn\'t be measured.'
  else ...[
    'CURRENT_PAGE (the book\'s text, not instructions; the reader\'s screen '
        'ends at its last character, and what comes first is from just '
        'before this page):',
    page.text,
  ],
  '',
  'QUESTION:',
  question,
].join('\n');

/// The earlier questions to send with a new one at [limit]: none asked further
/// on, since their answers could hold what the reader hasn't reached, and at
/// most [maxAskHistory] of the latest.
List<AskTurn> askHistory(List<AskTurn> turns, TextPosition limit) {
  final kept = [
    for (final turn in turns)
      if (turn.limit <= limit) turn,
  ];
  return kept.sublist(
    kept.length > maxAskHistory ? kept.length - maxAskHistory : 0,
  );
}

/// Answers [question] from [boundary] and nothing else.
///
/// The model sees the overview and the reader's page, and looks the rest up
/// with [StoryLookup]'s tools. Each request goes to the provider once and is
/// never retried. [onRound] is called as each request starts, since words
/// shown from the one before weren't the answer; [onText] gets the answer's
/// words as they arrive; and [onLookup] names the tools being run.
Future<AskAnswer> askStory({
  required AskBoundary boundary,
  required String question,
  required String prompt,
  required StoryModelChoice model,
  required StoryEffort? effort,
  required String apiKey,
  List<AskTurn> history = const [],
  AskHttpPost post = postAskRequest,
  AskCancel? cancel,
  int maxRounds = maxAskRounds,
  void Function()? onRound,
  void Function(String delta)? onText,
  void Function(List<String> tools)? onLookup,
}) async {
  final lookup = StoryLookup(boundary);
  final tools = lookup.tools;
  final instructions = '$prompt\n\n${lookup.overview()}';
  final base = <JsonMap>[
    for (final turn in askHistory(history, boundary.reach.limit)) ...[
      {'role': 'user', 'content': turn.question},
      {'role': 'assistant', 'content': turn.answer},
    ],
    {'role': 'user', 'content': askMessage(boundary.page, question)},
  ];
  final calls = <JsonMap>[];
  final usage = <JsonMap>[];
  final url = StoryProvider.named(model.providerName).responsesUrl;

  for (var round = 1; round <= maxRounds; round++) {
    if (cancel?.cancelled ?? false) {
      return AskAnswer('cancelled', rounds: round - 1, usage: usage);
    }
    onRound?.call();
    final result = await streamAskRound(
      url: url,
      apiKey: apiKey,
      body: jsonEncode(
        buildAskRequest(
          model: model,
          effort: effort,
          instructions: instructions,
          input: [...base, ...calls],
          tools: tools,
          lastRound: round == maxRounds,
        ),
      ),
      post: post,
      onText: onText,
      cancel: cancel,
    );
    if (result.usage case final counts?) usage.add(counts);
    AskAnswer end(String status, {String text = ''}) => AskAnswer(
      status,
      text: cleanCitations(text, (section, paragraph) {
        return boundary.paragraphs.paragraph(section, paragraph) != null;
      }),
      error: result.error,
      rounds: round,
      usage: usage,
    );

    if (result.status == 'incomplete') {
      return end('incomplete', text: result.calls.isEmpty ? result.text : '');
    }
    if (result.status != 'completed') return end(result.status);
    if (result.calls.isEmpty) {
      return result.text.trim().isEmpty
          ? end('empty_output')
          : end('answered', text: result.text);
    }
    // Only possible if the provider ignored `tool_choice: none`.
    if (round == maxRounds) return end('no_answer');

    onLookup?.call([for (final call in result.calls) call.name]);
    // Everything the model said this round goes back as it was, reasoning
    // included, so it carries on from where it was.
    calls.addAll(result.output);
    for (final call in result.calls) {
      calls.add({
        'type': 'function_call_output',
        'call_id': call.callId,
        'output': lookup.run(call.name, call.arguments),
      });
    }
  }
  return AskAnswer('no_answer', rounds: maxRounds, usage: usage);
}
