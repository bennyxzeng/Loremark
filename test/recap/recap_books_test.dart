import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' hide TextPosition;
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/ask/ask_controller.dart';
import 'package:loremark/ask/ask_history.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/epub_sections.dart';
import 'package:loremark/reader/page_end.dart';
import 'package:loremark/reader/page_start.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/reader/reading_position_store.dart';
import 'package:loremark/reading/text_position.dart';
import 'package:loremark/recap/recap_backend.dart';
import 'package:loremark/settings/ai_activity.dart';
import 'package:loremark/settings/ai_settings.dart';
import 'package:loremark/story_map/story_map_backend.dart';
import 'package:loremark/story_update/story_api_client.dart';
import 'package:loremark/story_update/story_book.dart';
import 'package:loremark/story_update/story_model_choice.dart';

import '../ask/ask_test_support.dart';
import '../story_update/golden.dart';

// Two books in the library, each with its own Story Map, place and recap,
// through the real device backends with only the provider stood in for.
//
// Both books are the same EPUB under different ids, so nothing but the id can
// keep them apart: whatever one book's recap gets, it can only have got through
// that book's own files.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  final delta = (readValidationGolden()['first'] as JsonMap)['candidate'];
  final epub = File('$goldenDir/story.epub');

  Book bookNamed(String id, String title) => Book(
    id: id,
    title: title,
    author: null,
    epubPath: epub.path,
    coverPath: null,
    importedAt: DateTime.utc(2026),
  );

  final harbor = bookNamed('a' * 64, 'The Glass Harbor');
  final storm = bookNamed('b' * 64, 'The Storm Road');

  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('recap_books_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => temp.path,
        );
  });
  tearDownAll(() => temp.deleteSync(recursive: true));

  final storyMap = DeviceStoryMapBackend(
    activity: AiActivity(),
    post: (url, headers, body) async => StoryHttpResponse(
      200,
      jsonEncode({
        'status': 'completed',
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': jsonEncode(delta)},
            ],
          },
        ],
      }),
    ),
  );
  final recaps = DeviceRecapBackend(storyMap: storyMap);

  Future<void> buildMap(Book book) async {
    final status = await storyMap.inspect(book);
    final batch = await storyMap.update(
      book,
      credentials: const AiCredentials(
        provider: AiProvider.deepseek,
        apiKey: 'sk-test',
      ),
      model: StoryModelChoice.deepseekFlash,
      effort: StoryEffort.low,
      checkQuotes: false,
      sections: [
        status.pickable.firstWhere((s) => s.sectionId == 'section-002'),
      ],
    );
    expect((await batch.done).last.status, 'committed');
  }

  test('each book keeps its own map, place, recap and conversations', () async {
    // Only the first book has a map yet: the second has no recap to offer.
    await buildMap(harbor);
    expect(await storyMap.loadModel(harbor), isNotNull);
    expect(await storyMap.loadModel(storm), isNull);
    expect(await recaps.prepare(storm), isA<RecapNeedsStoryMap>());

    await buildMap(storm);

    // The first book is read partway into Chapter 1: its page ends five
    // characters into the sixth paragraph.
    final positions = await ReadingPositionStore.open();
    await positions.save(harbor.id, const ReaderPosition(1, 0.5));
    await positions.savePageStart(
      harbor.id,
      const PageStart(1, ':root > :nth-child(2) > :nth-child(3)'),
    );
    final chapter1 = (await readSectionMarkup(epub.path, 'OEBPS/ch1.xhtml'))!;
    final end = textProgressionOfBlock(chapter1, 5, characters: 5)!;
    await positions.savePageEnd(harbor.id, PageEnd(1, 5, end));
    // The second is read past Chapter 1, into Chapter 2.
    await positions.save(storm.id, const ReaderPosition(2, 0.3));

    // Each is where it was left.
    expect(await positions.load(harbor.id), const ReaderPosition(1, 0.5));
    expect(await positions.load(storm.id), const ReaderPosition(2, 0.3));
    expect(await positions.loadPageStart(storm.id), isNull);
    expect(await positions.loadPageEnd(storm.id), isNull);

    // The welcome back names each book's own place.
    final harborStop = (await recaps.prepare(harbor)) as RecapCanStart;
    final stormStop = (await recaps.prepare(storm)) as RecapCanStart;
    expect(harborStop.stop.sectionTitle, 'Chapter 1: The Signal');
    expect(harborStop.stop.partway, isTrue);
    expect(stormStop.stop.sectionTitle, 'Chapter 1: The Signal');
    expect(stormStop.stop.partway, isFalse);

    // Catch me up in each book sends that book's pages and nothing else.
    final provider = FakeAskProvider([
      (
        200,
        sse([
          completed([message('Harbor recap.')]),
        ]),
      ),
      (
        200,
        sse([
          completed([message('Storm recap.')]),
        ]),
      ),
    ]);
    final history = AskHistoryStore(Directory('${temp.path}/chats_root'));
    AskController askFor(Book book) => AskController(
      book: book,
      backend: storyMap,
      activity: AiActivity(),
      openHistory: () async => history,
      post: provider.post,
      loadPrompt: () async => 'PROMPT',
      loadRecapPrompt: () async => 'RECAP PROMPT',
    );
    final harborAsk = askFor(harbor);
    final stormAsk = askFor(storm);
    addTearDown(harborAsk.dispose);
    addTearDown(stormAsk.dispose);

    const credentials = AiCredentials(
      provider: AiProvider.openai,
      apiKey: 'sk-test',
    );
    Future<void> catchUp(AskController ask) => ask.catchUp(
      credentials: credentials,
      model: StoryModelChoice.gpt61Terra,
      effort: StoryEffort.high,
    );
    await catchUp(harborAsk);
    await catchUp(stormAsk);

    final harborSent = jsonEncode(provider.bodies[0]);
    final stormSent = jsonEncode(provider.bodies[1]);
    // The first book's page, up to where it ends, and nothing further on.
    expect(harborSent, contains('CHAPTER 1 THE SIGNAL'));
    expect(harborSent, isNot(contains('hunt down the Grey Fox')));
    expect(harborSent, isNot(contains('CHAPTER 2 THE STORM')));
    expect(harborSent, isNot(contains('doesn\'t cover')));
    // The second book has no page end saved, so its page can't be measured,
    // and it is past its map. The first book's page and place don't stand in.
    expect(stormSent, contains('RECENT_PAGES: not available'));
    expect(stormSent, contains('doesn\'t cover'));
    expect(stormSent, isNot(contains('CHAPTER 1 THE SIGNAL')));
    expect(stormSent, isNot(contains('No one')));

    // Each answer reads only as far as its own book.
    expect(harborAsk.exchanges.single.answer, 'Harbor recap.');
    expect(harborAsk.exchanges.single.limit, TextPosition(1, end));
    expect(stormAsk.exchanges.single.answer, 'Storm recap.');
    expect(stormAsk.exchanges.single.limit.sectionIndex, 2);

    // And each recap is kept with its own book's conversations.
    final harborSaved = await history.list(harbor.id);
    final stormSaved = await history.list(storm.id);
    expect(harborSaved, hasLength(1));
    expect(stormSaved, hasLength(1));
    expect(harborSaved.single.exchanges.single.question, askRecapQuestion);
    expect(harborSaved.single.exchanges.single.answer, 'Harbor recap.');
    expect(stormSaved.single.exchanges.single.answer, 'Storm recap.');

    // Reading on in one book moves only that book's place.
    await positions.save(storm.id, const ReaderPosition(1, 0.2));
    final harborAgain = (await recaps.prepare(harbor)) as RecapCanStart;
    expect(harborAgain.stop.partway, isTrue);
    expect(await positions.load(harbor.id), const ReaderPosition(1, 0.5));
    expect(await recaps.prepare(storm), isA<RecapNeedsReading>());
  });
}
