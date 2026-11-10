import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/ask/ask_boundary.dart';
import 'package:loremark/ask/ask_engine.dart';
import 'package:loremark/ask/ask_stream.dart';
import 'package:loremark/reading/text_position.dart';
import 'package:loremark/story_model/story_snapshot.dart';
import 'package:loremark/story_update/story_model_choice.dart';

import '../acceptance/synthetic_story_model.dart';
import '../story_model/story_model_fixture.dart';
import 'ask_test_support.dart';

void main() {
  final model = storyModelFixture();
  final all = paragraphsOf(
    model.sections,
    count: 3,
    firstId: 1,
    textOf: (section, number) => 'Text of ${section.id} paragraph $number.',
  );
  const page = AskPage('Mara looked out at the water.', TextPosition(2, 0.5));
  final boundary = boundaryAt(
    model,
    all,
    finished: 1,
    page: page,
    limit: const TextPosition(2, 0.5),
  );

  Future<AskAnswer> ask(
    FakeAskProvider provider, {
    AskBoundary? at,
    List<AskTurn> history = const [],
    StoryModelChoice choice = StoryModelChoice.gpt61Terra,
    int maxRounds = maxAskRounds,
    AskCancel? cancel,
    List<String>? text,
    List<List<String>>? lookups,
    void Function()? onRound,
  }) => askStory(
    boundary: at ?? boundary,
    question: 'Who is Mara?',
    prompt: 'PROMPT',
    model: choice,
    effort: StoryEffort.high,
    apiKey: 'sk-secret',
    history: history,
    post: provider.post,
    maxRounds: maxRounds,
    cancel: cancel,
    onText: text?.add,
    onLookup: lookups?.add,
    onRound: onRound,
  );

  group('a question', () {
    test('looks things up, then answers with what it found', () async {
      final provider = FakeAskProvider([
        (
          200,
          sse([
            completed([
              {'type': 'reasoning', 'id': 'rs_1', 'encrypted_content': 'x'},
              functionCall('get_entity', {'entity_id': 'c001'}),
            ]),
          ]),
        ),
        (
          200,
          sse([
            {
              'type': 'response.output_item.added',
              'item': {'type': 'message', 'id': 'msg_1'},
            },
            {
              'type': 'response.output_text.delta',
              'item_id': 'msg_1',
              'delta': 'Mara is a dock clerk ',
            },
            {
              'type': 'response.output_text.delta',
              'item_id': 'msg_1',
              'delta': '[s1/p0001].',
            },
            completed([message('Mara is a dock clerk [s1/p0001].')]),
          ]),
        ),
      ]);
      final text = <String>[];
      final lookups = <List<String>>[];
      final answer = await ask(provider, text: text, lookups: lookups);

      expect(answer.status, 'answered');
      expect(answer.text, 'Mara is a dock clerk [s1/p0001].');
      expect(answer.rounds, 2);
      expect(answer.usage, hasLength(2));
      expect(text.join(), 'Mara is a dock clerk [s1/p0001].');
      expect(lookups, [
        ['get_entity'],
      ]);

      final first = provider.bodies[0];
      expect(first['model'], 'gpt-6.1-terra');
      expect(first['stream'], isTrue);
      expect(first['tool_choice'], 'auto');
      expect(first['reasoning'], {'effort': 'high'});
      final input = first['input'] as List;
      expect((input[0] as Map)['role'], 'system');
      expect((input[0] as Map)['content'], startsWith('PROMPT\n\nSTORY MAP'));
      expect((input.last as Map)['content'], contains(page.text));
      expect(
        (input.last as Map)['content'],
        endsWith('QUESTION:\nWho is Mara?'),
      );

      // The second carries the first's output back, and the lookup's answer.
      final second = provider.bodies[1]['input'] as List;
      expect(second.length, input.length + 3);
      expect((second[input.length] as Map)['type'], 'reasoning');
      expect((second[input.length + 1] as Map)['type'], 'function_call');
      final output = second.last as Map;
      expect(output['type'], 'function_call_output');
      expect(output['call_id'], 'call_1');
      expect(output['output'], contains('dock clerk'));
    });

    test('drops a citation of a paragraph it wasn\'t given', () async {
      final provider = FakeAskProvider([
        (
          200,
          sse([
            completed([
              message(
                'Mara works there [s1/p0001, s2/p0001]. Later [s9/p0003].',
              ),
            ]),
          ]),
        ),
      ]);
      final answer = await ask(provider);
      expect(answer.text, 'Mara works there [s1/p0001]. Later.');
    });

    test('words said before a lookup aren\'t shown as the answer', () async {
      final provider = FakeAskProvider([
        (
          200,
          sse([
            {
              'type': 'response.output_item.added',
              'item': {'type': 'message', 'id': 'c', 'phase': 'commentary'},
            },
            {
              'type': 'response.output_text.delta',
              'item_id': 'c',
              'delta': 'Let me check.',
            },
            completed([
              functionCall('find_facts', {'query': 'Mara'}),
            ]),
          ]),
        ),
        (
          200,
          sse([
            completed([message('Done.')]),
          ]),
        ),
      ]);
      final text = <String>[];
      var rounds = 0;
      await ask(provider, text: text, onRound: () => rounds++);
      expect(text, isNot(contains('Let me check.')));
      expect(rounds, 2);
    });

    test('the last request must answer', () async {
      final call = sse([
        completed([
          functionCall('find_facts', {'query': 'Mara'}),
        ]),
      ]);
      final provider = FakeAskProvider([(200, call), (200, call)]);
      final answer = await ask(provider, maxRounds: 2);
      expect(provider.bodies[0]['tool_choice'], 'auto');
      expect(provider.bodies[1]['tool_choice'], 'none');
      // Still sent, so the start of the request stays the same.
      expect(provider.bodies[1]['tools'], provider.bodies[0]['tools']);
      expect(answer.status, 'no_answer');
    });

    test('with nothing in the map, it answers from the page alone', () async {
      final provider = FakeAskProvider([
        (
          200,
          sse([
            completed([message('From the page [page].')]),
          ]),
        ),
      ]);
      final answer = await ask(
        provider,
        at: AskBoundary(
          reach: const AskReach(
            progress: StoryReadingProgress(0),
            limit: TextPosition(2, 0.5),
            page: page,
          ),
        ),
      );
      expect(answer.text, 'From the page [page].');
      expect(provider.bodies.single.containsKey('tools'), isFalse);
    });

    test('OpenAI is told to store nothing; DeepSeek isn\'t sent it', () async {
      Future<Map<String, dynamic>> bodyFor(StoryModelChoice choice) async {
        final provider = FakeAskProvider([
          (
            200,
            sse([
              completed([message('Hi.')]),
            ]),
          ),
        ]);
        await ask(provider, choice: choice);
        return provider.bodies.single;
      }

      final openai = await bodyFor(StoryModelChoice.gpt61Sol);
      expect(openai['store'], isFalse);
      expect(openai['include'], ['reasoning.encrypted_content']);
      final deepseek = await bodyFor(StoryModelChoice.deepseekFlash);
      expect(deepseek.containsKey('store'), isFalse);
      expect(deepseek.containsKey('include'), isFalse);
    });

    test('goes to the provider\'s Responses API with the key', () async {
      final provider = FakeAskProvider([
        (
          200,
          sse([
            completed([message('Hi.')]),
          ]),
        ),
      ]);
      await ask(provider, choice: StoryModelChoice.deepseekFlash);
      expect(
        provider.urls.single.toString(),
        'https://api.deepseek.com/responses',
      );
      expect(provider.headers.single['authorization'], 'Bearer sk-secret');
    });
  });

  group('ends', () {
    Future<AskAnswer> one(int status, String body) =>
        ask(FakeAskProvider([(status, body)]));

    test('with the provider\'s refusal, without the key', () async {
      final answer = await one(
        401,
        jsonEncode({
          'error': {'message': 'Incorrect API key sk-secret'},
        }),
      );
      expect(answer.status, 'api_error');
      expect(answer.error!['category'], 'authentication');
      expect('${answer.error}', isNot(contains('sk-secret')));
    });

    test('when the reply stops before its last event', () async {
      final answer = await one(
        200,
        sse([
          {
            'type': 'response.output_text.delta',
            'item_id': 'm',
            'delta': 'Mara',
          },
        ]),
      );
      expect(answer.status, 'api_error');
      expect(answer.error!['category'], 'network');
    });

    test('cut off, keeping what it said', () async {
      final answer = await one(
        200,
        sse([
          completed([message('Mara is')], status: 'incomplete'),
        ]),
      );
      expect(answer.status, 'incomplete');
      expect(answer.text, 'Mara is');
    });

    test('failed, or refused', () async {
      expect(
        (await one(200, sse([completed([], status: 'failed')]))).status,
        'failed',
      );
      final refused = await one(
        200,
        sse([
          completed([
            {
              'type': 'message',
              'content': [
                {'type': 'refusal', 'refusal': 'No.'},
              ],
            },
          ]),
        ]),
      );
      expect(refused.status, 'refusal');
      expect(
        (await one(
          200,
          sse([
            {'type': 'error', 'message': 'bad sk-secret'},
          ]),
        )).error!['message'],
        'bad [API key removed]',
      );
    });

    test('with nothing said', () async {
      expect((await one(200, sse([completed([])]))).status, 'empty_output');
    });

    test('when the reader stops it', () async {
      final cancel = AskCancel();
      final controller = StreamController<String>();
      final answer = askStory(
        boundary: boundary,
        question: 'Who?',
        prompt: 'P',
        model: StoryModelChoice.gpt61Terra,
        effort: null,
        apiKey: 'k',
        cancel: cancel,
        post: (url, headers, body) async =>
            AskHttpReply(200, controller.stream, () => controller.close()),
      );
      controller.add(
        sse([
          {'type': 'response.output_text.delta', 'item_id': 'm', 'delta': 'M'},
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      cancel.cancel();
      expect((await answer).status, 'cancelled');
    });
  });

  testWidgets('gives up on a reply that goes quiet', (tester) async {
    final body = StreamController<String>();
    var closed = false;
    AskAnswer? answer;
    unawaited(
      askStory(
        boundary: boundary,
        question: 'Who?',
        prompt: 'P',
        model: StoryModelChoice.gpt61Terra,
        effort: null,
        apiKey: 'k',
        post: (url, headers, sent) async => AskHttpReply(200, body.stream, () {
          if (closed) return;
          closed = true;
          unawaited(body.close());
        }),
      ).then((value) => answer = value),
    );
    await tester.pump();
    body.add(
      sse([
        {'type': 'response.output_text.delta', 'item_id': 'm', 'delta': 'M'},
      ]),
    );
    // Words keep it going...
    await tester.pump(askIdleTimeout - const Duration(seconds: 1));
    expect(answer, isNull);
    body.add(
      sse([
        {'type': 'response.output_text.delta', 'item_id': 'm', 'delta': 'a'},
      ]),
    );
    await tester.pump(askIdleTimeout - const Duration(seconds: 1));
    expect(answer, isNull);
    // ...and silence ends it.
    await tester.pump(const Duration(seconds: 2));
    expect(answer!.status, 'api_error');
    expect(answer!.error!['category'], 'timeout');
  });

  group('history', () {
    AskTurn turn(String question, TextPosition limit) =>
        AskTurn(question: question, answer: 'A to $question', limit: limit);

    test('leaves out questions asked further on', () {
      final kept = askHistory([
        turn('early', const TextPosition(1, 0.2)),
        turn('later', const TextPosition(3, 0.1)),
        turn('same page', const TextPosition(2, 0.5)),
      ], const TextPosition(2, 0.5));
      expect([for (final t in kept) t.question], ['early', 'same page']);
    });

    test('keeps only the latest', () {
      final kept = askHistory([
        for (var i = 0; i < 15; i++) turn('q$i', const TextPosition(0, 0)),
      ], const TextPosition(1, 0));
      expect(kept, hasLength(maxAskHistory));
      expect(kept.first.question, 'q5');
    });

    test('is sent before the new question', () async {
      final provider = FakeAskProvider([
        (
          200,
          sse([
            completed([message('Hi.')]),
          ]),
        ),
      ]);
      await ask(
        provider,
        history: [
          turn('before', const TextPosition(1, 0)),
          turn('after', const TextPosition(4, 0)),
        ],
      );
      final input = provider.bodies.single['input'] as List;
      expect(
        [for (final item in input.skip(1)) (item as Map)['role']],
        ['user', 'assistant', 'user'],
      );
      expect(jsonEncode(input), isNot(contains('A to after')));
    });
  });

  // A model that asks for everything there is, with every id in the book,
  // must still be sent nothing the reader hasn't read.
  test('no request holds anything past the reader', () async {
    final synthetic = generateSyntheticStoryModel(
      const SyntheticStoryModelSpec(
        seed: 5,
        sections: 10,
        characters: 40,
        records: 400,
      ),
    ).model;
    final everything = paragraphsOf(
      synthetic.sections,
      textOf: (section, number) => 'Quote ${syntheticTag(section.order)}',
    );
    for (final (finished, read) in [(0, 30), (3, 0), (4, 120), (9, 299)]) {
      final at = boundaryAt(
        synthetic,
        everything,
        finished: finished,
        paragraphsRead: read,
      );
      var call = 0;
      Map<String, dynamic> next(String name, Map<String, dynamic> args) =>
          functionCall(name, args, callId: 'call_${call++}');
      final provider = FakeAskProvider([
        (
          200,
          sse([
            completed([
              for (final id in synthetic.entities.keys)
                next('get_entity', {'entity_id': id}),
              for (final section in synthetic.sections) ...[
                next('get_chapter', {'section_id': section.id}),
                next('find_facts', {
                  'query': '${syntheticTag(section.order)} quote',
                }),
                next('read_paragraphs', {
                  'refs': [
                    for (final n in [0, 29, 30, 119, 120, 299])
                      '${section.id}/p${'$n'.padLeft(4, '0')}',
                  ],
                  'context': 3,
                }),
              ],
            ]),
          ]),
        ),
        (
          200,
          sse([
            completed([message('Done.')]),
          ]),
        ),
      ]);
      await ask(provider, at: at);
      // What the app put in: messages and lookups' answers. The model's own
      // calls go back as it wrote them, and it asked about later sections.
      final sent = [
        for (final body in provider.bodies)
          for (final item in (body['input'] as List).cast<Map>())
            if (item['type'] != 'function_call') ...stringsIn(item),
      ].expand(sectionTagsIn).toList();
      expect(sent, isNotEmpty);
      for (final order in sent) {
        expect(
          order,
          lessThanOrEqualTo(at.progress.shown),
          reason: 'at $finished+$read',
        );
      }
    }
  });
}
