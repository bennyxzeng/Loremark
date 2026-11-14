import 'dart:convert';

import 'package:loremark/ask/ask_boundary.dart';
import 'package:loremark/ask/ask_stream.dart';
import 'package:loremark/reading/text_position.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/story_model/story_snapshot.dart';
import 'package:loremark/story_update/story_paragraphs.dart';

/// Paragraphs `p0000`... of each section, numbered from 1, each holding
/// [textOf] its section and number.
Map<String, List<StoryParagraph>> paragraphsOf(
  Iterable<StorySection> sections, {
  int count = 300,
  int firstId = 0,
  required String Function(StorySection section, int number) textOf,
}) => {
  for (final section in sections)
    section.id: [
      for (var i = 0; i < count; i++)
        StoryParagraph(
          sectionId: section.id,
          id: 'p${'${i + firstId}'.padLeft(4, '0')}',
          number: i + 1,
          text: textOf(section, i + 1),
        ),
    ],
};

/// What [model] lets a reader who has finished [finished] sections and read
/// [paragraphsRead] paragraphs of the next one see, as the app works it out:
/// the progress `readStoryProgress` would give, and the paragraphs
/// `readStoryParagraphs` would keep. [all] is every section's paragraphs.
AskBoundary boundaryAt(
  StoryModel model,
  Map<String, List<StoryParagraph>> all, {
  required int finished,
  int paragraphsRead = 0,
  AskPage? page,
  bool pastMap = false,
  TextPosition limit = const TextPosition(0, 0),
}) {
  final sections = model.sections;
  StoryReadingProgress progress;
  if (paragraphsRead > 0 && finished < sections.length) {
    final next = sections[finished];
    progress = StoryReadingProgress(
      finished,
      hiddenInNext: hiddenWithinSection(
        model,
        next,
        all[next.id]!,
        paragraphsRead: paragraphsRead,
      ),
      paragraphsReadInNext: paragraphsRead,
    );
  } else {
    progress = StoryReadingProgress(finished);
  }
  final visible = {
    for (final section in sections.take(progress.shown))
      section.id:
          section == sections[progress.shown - 1] &&
              progress.hiddenInNext != null
          ? all[section.id]!.take(paragraphsRead).toList()
          : all[section.id]!,
  };
  return AskBoundary(
    reach: AskReach(
      progress: progress,
      limit: limit,
      page: page,
      pastMap: pastMap,
    ),
    model: model,
    paragraphs: StoryParagraphs(visible),
  );
}

/// A server-sent event stream of [events], as a provider sends it.
String sse(List<Map<String, dynamic>> events) => [
  for (final event in events)
    'event: ${event['type']}\ndata: ${jsonEncode(event)}\n\n',
].join();

/// The last event of a reply whose output is [output].
Map<String, dynamic> completed(
  List<Map<String, dynamic>> output, {
  String status = 'completed',
}) => {
  'type': 'response.$status',
  'response': {
    'id': 'resp_1',
    'status': status,
    'output': output,
    'usage': {'input_tokens': 10, 'output_tokens': 5},
    if (status == 'incomplete')
      'incomplete_details': {'reason': 'max_output_tokens'},
  },
};

/// A final answer saying [text], as an output item.
Map<String, dynamic> message(String text, {String id = 'msg_1'}) => {
  'type': 'message',
  'id': id,
  'role': 'assistant',
  'status': 'completed',
  'content': [
    {'type': 'output_text', 'text': text},
  ],
};

/// A call to [name] with [arguments], as an output item.
Map<String, dynamic> functionCall(
  String name,
  Map<String, dynamic> arguments, {
  String callId = 'call_1',
}) => {
  'type': 'function_call',
  'id': 'fc_$callId',
  'call_id': callId,
  'name': name,
  'arguments': jsonEncode(arguments),
  'status': 'completed',
};

/// Answers each request with the next of [replies], keeping what was sent.
class FakeAskProvider {
  FakeAskProvider(this.replies);

  /// Each a status code and the body sent with it.
  final List<(int, String)> replies;
  final bodies = <Map<String, dynamic>>[];
  final urls = <Uri>[];
  final headers = <Map<String, String>>[];

  Future<AskHttpReply> post(
    Uri url,
    Map<String, String> sentHeaders,
    String body,
  ) async {
    urls.add(url);
    headers.add(sentHeaders);
    bodies.add(jsonDecode(body) as Map<String, dynamic>);
    final (status, text) = replies[bodies.length - 1];
    // In pieces, as a network delivers it, to test reassembly.
    final chunks = [
      for (var i = 0; i < text.length; i += 7)
        text.substring(i, i + 7 > text.length ? text.length : i + 7),
    ];
    return AskHttpReply(status, Stream.fromIterable(chunks));
  }
}

/// Every string anywhere in [json].
Iterable<String> stringsIn(Object? json) sync* {
  switch (json) {
    case String():
      yield json;
    case Map():
      for (final value in json.values) {
        yield* stringsIn(value);
      }
    case List():
      for (final value in json) {
        yield* stringsIn(value);
      }
  }
}
