import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/ask/ask_boundary.dart';
import 'package:loremark/ask/ask_controller.dart';
import 'package:loremark/ask/ask_engine.dart';
import 'package:loremark/ask/ask_history.dart';
import 'package:loremark/ask/ask_stream.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reading/text_position.dart';
import 'package:loremark/settings/ai_settings.dart';
import 'package:loremark/story_model/story_snapshot.dart';
import 'package:loremark/story_update/story_model_choice.dart';

import '../story_model/story_model_fixture.dart';
import 'ask_test_support.dart';
import 'fake_ask_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final book = Book(
    id: 'book',
    title: 'The Glass Harbor',
    author: null,
    epubPath: 'book.epub',
    coverPath: null,
    importedAt: DateTime.utc(2026),
  );
  const credentials = AiCredentials(
    provider: AiProvider.openai,
    apiKey: 'sk-test',
  );
  const page = AskPage('Mara looked out at the water.', TextPosition(2, 0.5));
  final model = storyModelFixture();

  late Directory temp;
  late FakeAskBackend backend;
  late DateTime clock;

  setUp(() {
    clock = DateTime.utc(2026, 11, 9);
    temp = Directory.systemTemp.createTempSync('ask_controller_');
    backend = FakeAskBackend(
      model: model,
      reach: const AskReach(
        progress: StoryReadingProgress(1),
        limit: TextPosition(2, 0.5),
        page: page,
      ),
      all: paragraphsOf(
        model.sections,
        count: 3,
        firstId: 1,
        textOf: (section, number) => 'Text of ${section.id} $number.',
      ),
    );
  });
  tearDown(() => temp.deleteSync(recursive: true));

  AskController controllerWith(FakeAskProvider provider) => AskController(
    book: book,
    backend: backend,
    openHistory: () async => AskHistoryStore(temp),
    post: provider.post,
    loadPrompt: () async => 'PROMPT',
    now: () => clock,
  );

  AskExchange earlier(String question) => AskExchange(
    question: question,
    answer: 'Yes.',
    limit: const TextPosition(1, 0),
    askedAt: DateTime.utc(2026),
  );

  /// A controller whose answers arrive only when [body] gets them.
  AskController streaming(StreamController<String> body) => AskController(
    book: book,
    backend: backend,
    openHistory: () async => AskHistoryStore(temp),
    loadPrompt: () async => 'PROMPT',
    now: () => clock,
    post: (url, headers, sent) async =>
        AskHttpReply(200, body.stream, () => body.close()),
  );

  Future<void> ask(AskController controller, String question) => controller.ask(
    question,
    credentials: credentials,
    model: StoryModelChoice.gpt61Terra,
    effort: StoryEffort.high,
  );

  String answerWith(String text) => sse([
    completed([message(text)]),
  ]);

  test(
    'looks at where the reader is, and starts on a new conversation',
    () async {
      await AskHistoryStore(temp).save('book', 'c1', [earlier('Earlier?')]);
      final controller = controllerWith(FakeAskProvider([]));
      expect(controller.loaded, isFalse);
      await controller.refresh();
      expect(controller.loaded, isTrue);
      expect(controller.boundary!.sections.single.id, 's1');
      expect(controller.exchanges, isEmpty);
      expect(controller.conversationId, isNull);
      expect(controller.conversations.single.title, 'Earlier?');
      // Read once only, however often it looks again.
      await AskHistoryStore(temp).save('book', 'c2', [earlier('Later?')]);
      await controller.refresh();
      expect(controller.conversations, hasLength(1));
      expect(backend.reaches, 2);
    },
  );

  test('keeps an answer, with the reader\'s place, on the device', () async {
    final provider = FakeAskProvider([
      (200, answerWith('A clerk [s1/p0001].')),
    ]);
    final controller = controllerWith(provider);
    final stages = <AskStage?>[];
    controller.addListener(() => stages.add(controller.pending?.stage));

    await ask(controller, '  Who is Mara?  ');

    expect(controller.pending, isNull);
    final exchange = controller.exchanges.single;
    expect(exchange.question, 'Who is Mara?');
    expect(exchange.answer, 'A clerk [s1/p0001].');
    expect(exchange.limit, const TextPosition(2, 0.5));
    expect(stages, containsAllInOrder([AskStage.reading, AskStage.thinking]));
    final id = controller.conversationId!;
    final saved = await AskHistoryStore(temp).load('book', id);
    expect(saved.single.answer, 'A clerk [s1/p0001].');
    expect(controller.conversations.single.id, id);
  });

  test('sends the conversation so far with the next question', () async {
    final provider = FakeAskProvider([
      (200, answerWith('First.')),
      (200, answerWith('Second.')),
    ]);
    final controller = controllerWith(provider);
    await ask(controller, 'One?');
    await ask(controller, 'Two?');
    final input = jsonEncode(provider.bodies[1]['input']);
    expect(input, contains('One?'));
    expect(input, contains('First.'));
  });

  test('sends nothing when the map can\'t be read', () async {
    backend.error = const FileSystemException('gone');
    final provider = FakeAskProvider([]);
    final controller = controllerWith(provider);
    await ask(controller, 'Who?');
    expect(provider.bodies, isEmpty);
    expect(controller.pending!.stage, AskStage.failed);
    expect(controller.pending!.failure, contains('nothing was sent'));
  });

  test('sends nothing with nothing read to answer from', () async {
    backend.reach = AskReach.none;
    final provider = FakeAskProvider([]);
    final controller = controllerWith(provider);
    await ask(controller, 'Who?');
    expect(provider.bodies, isEmpty);
    expect(controller.pending!.failure, contains('Read a page first'));
  });

  test('a failure can be tried again, or put away', () async {
    final provider = FakeAskProvider([
      (429, '{"error":{"message":"slow down"}}'),
      (200, answerWith('Now.')),
    ]);
    final controller = controllerWith(provider);
    await ask(controller, 'Who?');
    expect(controller.pending!.failure, contains('limiting requests'));
    expect(controller.exchanges, isEmpty);

    await controller.retry(
      credentials: credentials,
      model: StoryModelChoice.gpt61Terra,
      effort: StoryEffort.high,
    );
    expect(provider.bodies, hasLength(2));
    expect(controller.exchanges.single.answer, 'Now.');

    final again = controllerWith(FakeAskProvider([(500, 'down')]));
    await ask(again, 'Who?');
    again.dismiss();
    expect(again.pending, isNull);
  });

  test('a cut-off answer is kept and marked', () async {
    final controller = controllerWith(
      FakeAskProvider([
        (
          200,
          sse([
            completed([message('Mara is')], status: 'incomplete'),
          ]),
        ),
      ]),
    );
    await ask(controller, 'Who?');
    expect(controller.exchanges.single.cutOff, isTrue);
  });

  test('stops when asked, keeping nothing', () async {
    final body = StreamController<String>();
    final controller = AskController(
      book: book,
      backend: backend,
      openHistory: () async => AskHistoryStore(temp),
      loadPrompt: () async => 'PROMPT',
      post: (url, headers, sent) async =>
          AskHttpReply(200, body.stream, () => body.close()),
    );
    final asking = ask(controller, 'Who?');
    body.add(
      sse([
        {'type': 'response.output_text.delta', 'item_id': 'm', 'delta': 'Ma'},
      ]),
    );
    await pumpEventQueue();
    expect(controller.busy, isTrue);
    expect(controller.pending!.text, 'Ma');
    controller.stop();
    await asking;
    expect(controller.busy, isFalse);
    expect(controller.pending!.failure, 'Stopped. Nothing was kept.');
    expect(controller.exchanges, isEmpty);
  });

  group('conversations', () {
    test('a new one sends nothing from the one before, which stays', () async {
      final provider = FakeAskProvider([
        (200, answerWith('First.')),
        (200, answerWith('Second.')),
      ]);
      final controller = controllerWith(provider);
      await ask(controller, 'One?');
      final first = controller.conversationId!;
      controller.startNew();
      expect(controller.exchanges, isEmpty);
      expect(controller.conversationId, isNull);

      clock = clock.add(const Duration(minutes: 1));
      await ask(controller, 'Two?');
      final input = jsonEncode(provider.bodies[1]['input']);
      expect(input, isNot(contains('One?')));
      expect(controller.conversationId, isNot(first));
      expect(
        [for (final c in controller.conversations) c.title],
        ['Two?', 'One?'],
      );
      expect(await AskHistoryStore(temp).list('book'), hasLength(2));
    });

    test('a saved one can be opened and carried on', () async {
      await AskHistoryStore(temp).save('book', 'c1', [earlier('Earlier?')]);
      await AskHistoryStore(temp).save('book', 'c2', [earlier('Other?')]);
      final provider = FakeAskProvider([(200, answerWith('Again.'))]);
      final controller = controllerWith(provider);
      await controller.refresh();
      controller.open('c1');
      expect(controller.conversationId, 'c1');
      expect(controller.exchanges.single.question, 'Earlier?');

      await ask(controller, 'And now?');
      final input = jsonEncode(provider.bodies.single['input']);
      expect(input, contains('Earlier?'));
      expect(input, isNot(contains('Other?')));
      final saved = await AskHistoryStore(temp).load('book', 'c1');
      expect([for (final e in saved) e.question], ['Earlier?', 'And now?']);
      expect(controller.conversations.first.id, 'c1');
    });

    test(
      'coming back within five minutes keeps it; later, starts anew',
      () async {
        final controller = controllerWith(
          FakeAskProvider([(200, answerWith('Yes.'))]),
        );
        await ask(controller, 'Who?');

        controller.leave();
        clock = clock.add(askIdleGap - const Duration(seconds: 1));
        await controller.refresh();
        expect(controller.exchanges, hasLength(1));

        // Away is counted from leaving, not from the question.
        controller.leave();
        clock = clock.add(askIdleGap);
        await controller.refresh();
        expect(controller.exchanges, isEmpty);
        expect(controller.conversations.single.title, 'Who?');

        // Looking again without leaving changes nothing.
        clock = clock.add(const Duration(hours: 1));
        await controller.refresh();
        expect(controller.conversationId, isNull);
      },
    );

    test('nothing switches while a question is under way', () async {
      await AskHistoryStore(temp).save('book', 'c1', [earlier('Earlier?')]);
      final body = StreamController<String>();
      final controller = streaming(body);
      await controller.refresh();
      controller.open('c1');
      final asking = ask(controller, 'More?');
      await pumpEventQueue();
      expect(controller.busy, isTrue);

      controller
        ..startNew()
        ..open('c2')
        ..leave();
      clock = clock.add(const Duration(hours: 1));
      await controller.refresh();
      await controller.deleteConversation('c1');
      expect(controller.conversationId, 'c1');
      expect(controller.exchanges, hasLength(1));

      body.add(answerWith('Yes.'));
      await body.close();
      await asking;
      final saved = await AskHistoryStore(temp).load('book', 'c1');
      expect(saved, hasLength(2));
    });

    test(
      'deleting the one shown starts a new one, on the device too',
      () async {
        await AskHistoryStore(temp).save('book', 'c1', [earlier('Earlier?')]);
        await AskHistoryStore(temp).save('book', 'c2', [earlier('Other?')]);
        final controller = controllerWith(FakeAskProvider([]));
        await controller.refresh();
        controller.open('c1');
        await controller.deleteConversation('c1');
        expect(controller.conversationId, isNull);
        expect(controller.exchanges, isEmpty);
        expect([for (final c in controller.conversations) c.id], ['c2']);
        expect(await AskHistoryStore(temp).load('book', 'c1'), isEmpty);

        await controller.deleteConversation('c2');
        expect(controller.conversations, isEmpty);
        expect(await AskHistoryStore(temp).list('book'), isEmpty);
      },
    );
  });

  test('says what went wrong in words a reader can act on', () {
    String said(String status, [String? category]) => describeAskFailure(
      AskAnswer(
        status,
        error: category == null ? null : {'category': category, 'message': 'm'},
      ),
    );
    expect(said('api_error', 'authentication'), contains('Settings'));
    expect(said('api_error', 'timeout'), contains('may still charge'));
    expect(said('refusal'), contains('declined'));
    expect(said('no_answer'), contains('no usable answer'));
  });
}
