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

  setUp(() {
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
    now: () => DateTime.utc(2026, 11, 9),
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

  test('looks at where the reader is, and reads the conversation', () async {
    await AskHistoryStore(temp).save('book', [
      AskExchange(
        question: 'Earlier?',
        answer: 'Yes.',
        limit: const TextPosition(1, 0),
        askedAt: DateTime.utc(2026),
      ),
    ]);
    final controller = controllerWith(FakeAskProvider([]));
    expect(controller.loaded, isFalse);
    await controller.refresh();
    expect(controller.loaded, isTrue);
    expect(controller.boundary!.sections.single.id, 's1');
    expect(controller.exchanges.single.question, 'Earlier?');
    // Read once only, however often it looks again.
    await controller.refresh();
    expect(controller.exchanges, hasLength(1));
    expect(backend.reaches, 2);
  });

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
    final saved = await AskHistoryStore(temp).load('book');
    expect(saved.single.answer, 'A clerk [s1/p0001].');
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

  test('clears the conversation, on the device too', () async {
    final controller = controllerWith(
      FakeAskProvider([(200, answerWith('Yes.'))]),
    );
    await ask(controller, 'Who?');
    await controller.clear();
    expect(controller.exchanges, isEmpty);
    expect(await AskHistoryStore(temp).load('book'), isEmpty);
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
