import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/ask/ask_boundary.dart';
import 'package:loremark/ask/ask_controller.dart';
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

// The welcome back's Catch me up (use case 1): a recap asked in Ask, in a
// conversation of its own that the reader can carry on.
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
    clock = DateTime.utc(2026, 11, 10);
    temp = Directory.systemTemp.createTempSync('ask_recap_');
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

  AskController controllerWith(AskHttpPost post) => AskController(
    book: book,
    backend: backend,
    openHistory: () async => AskHistoryStore(temp),
    post: post,
    loadPrompt: () async => 'ASK PROMPT',
    loadRecapPrompt: () async => 'RECAP PROMPT',
    now: () => clock,
  );

  Future<void> ask(AskController controller, String question) => controller.ask(
    question,
    credentials: credentials,
    model: StoryModelChoice.gpt61Terra,
    effort: StoryEffort.high,
  );

  Future<void> catchUp(AskController controller) => controller.catchUp(
    credentials: credentials,
    model: StoryModelChoice.gpt61Terra,
    effort: StoryEffort.high,
  );

  String answerWith(String text) => sse([
    completed([message(text)]),
  ]);

  /// The system instructions request [index] was sent with.
  String instructionsOf(FakeAskProvider provider, int index) {
    final input = provider.bodies[index]['input'] as List;
    return (input.first as Map)['content'] as String;
  }

  test('starts a new conversation, asked with the recap prompt', () async {
    final provider = FakeAskProvider([
      (200, answerWith('Earlier answer.')),
      (200, answerWith('1. Mara arrives. She comes to the harbor [page/1].')),
    ]);
    final controller = controllerWith(provider.post);
    await ask(controller, 'Who is Mara?');
    final earlier = controller.conversationId;
    // A conversation's ID comes from when it started.
    clock = clock.add(const Duration(minutes: 1));

    await catchUp(controller);

    expect(instructionsOf(provider, 1), startsWith('RECAP PROMPT'));
    // Nothing from the conversation before goes with it.
    expect(
      jsonEncode(provider.bodies[1]['input']),
      isNot(contains('Who is Mara?')),
    );
    final recap = controller.exchanges.single;
    expect(recap.question, askRecapQuestion);
    expect(recap.answer, startsWith('1. Mara arrives.'));
    // A conversation of its own, kept with the book's others.
    expect(controller.conversationId, isNot(earlier));
    expect(controller.conversations, hasLength(2));
    final saved = await AskHistoryStore(temp)
        .load('book', controller.conversationId!);
    expect(saved.single.question, askRecapQuestion);
  });

  test('a follow-up uses Ask\'s own prompt, and sees the recap', () async {
    final provider = FakeAskProvider([
      (200, answerWith('1. Mara arrives. She comes to the harbor.')),
      (200, answerWith('She is a clerk.')),
    ]);
    final controller = controllerWith(provider.post);
    await catchUp(controller);

    await ask(controller, 'Who is she again?');

    expect(instructionsOf(provider, 1), startsWith('ASK PROMPT'));
    final input = jsonEncode(provider.bodies[1]['input']);
    expect(input, contains(askRecapQuestion));
    expect(input, contains('Mara arrives.'));
    expect(controller.exchanges, hasLength(2));
  });

  test('a recap that failed is tried again as a recap', () async {
    final provider = FakeAskProvider([
      (500, 'down'),
      (200, answerWith('1. Mara arrives.')),
    ]);
    final controller = controllerWith(provider.post);
    await catchUp(controller);
    expect(controller.pending!.failure, isNotNull);
    expect(controller.pending!.recap, isTrue);

    await controller.retry(
      credentials: credentials,
      model: StoryModelChoice.gpt61Terra,
      effort: StoryEffort.high,
    );

    expect(instructionsOf(provider, 1), startsWith('RECAP PROMPT'));
    expect(controller.exchanges.single.question, askRecapQuestion);
  });

  test('with nothing read, nothing is sent', () async {
    backend.reach = AskReach.none;
    final provider = FakeAskProvider([]);
    final controller = controllerWith(provider.post);

    await catchUp(controller);

    expect(provider.bodies, isEmpty);
    expect(controller.pending!.question, askRecapQuestion);
    expect(controller.pending!.failure, contains('Read a page first'));
  });

  test('does nothing while a question is under way', () async {
    final body = StreamController<String>();
    final controller = controllerWith(
      (url, headers, sent) async =>
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

    await catchUp(controller);

    expect(controller.pending!.question, 'Who?');
    controller.stop();
    await asking;
  });
}
