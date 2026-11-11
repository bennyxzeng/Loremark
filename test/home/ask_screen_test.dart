import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/ask/ask_boundary.dart';
import 'package:loremark/ask/ask_controller.dart';
import 'package:loremark/ask/ask_history.dart';
import 'package:loremark/ask/ask_stream.dart';
import 'package:loremark/home/ask_screen.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/epub_reader_service.dart';
import 'package:loremark/reading/text_position.dart';
import 'package:loremark/settings/ai_lock.dart';
import 'package:loremark/settings/ai_settings.dart';
import 'package:loremark/settings/connection_status.dart';
import 'package:loremark/story_model/story_snapshot.dart';
import 'package:loremark/theme/loremark_theme.dart';

import '../ask/ask_test_support.dart';
import '../ask/fake_ask_backend.dart';
import '../story_model/story_model_fixture.dart';

/// The book's conversations in memory, by id.
class _MemoryHistory extends AskHistoryStore {
  _MemoryHistory([Map<String, List<AskExchange>>? saved])
    : saved = saved ?? {},
      super(Directory('unused'));

  final Map<String, List<AskExchange>> saved;

  @override
  Future<List<AskConversation>> list(String bookId) async => [
    for (final MapEntry(:key, :value) in saved.entries)
      if (value.isNotEmpty) AskConversation(key, value),
  ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<List<AskExchange>> load(String bookId, String id) async =>
      List.of(saved[id] ?? const []);

  @override
  Future<void> save(
    String bookId,
    String id,
    List<AskExchange> exchanges,
  ) async => saved[id] = List.of(exchanges);

  @override
  Future<void> delete(String bookId, String id) async => saved.remove(id);

  @override
  Future<void> deleteBook(String bookId) async => saved.clear();
}

AskExchange _exchange(String question, String answer) => AskExchange(
  question: question,
  answer: answer,
  limit: const TextPosition(1, 0),
  askedAt: DateTime.utc(2026),
);

void main() {
  final book = Book(
    id: 'book',
    title: 'The Glass Harbor',
    author: null,
    epubPath: 'book.epub',
    coverPath: null,
    importedAt: DateTime.utc(2026),
  );
  const page = AskPage('Mara looked out at the water.', TextPosition(2, 0.5));
  final model = storyModelFixture();
  final all = paragraphsOf(
    model.sections,
    count: 3,
    firstId: 1,
    textOf: (section, number) => 'Text of ${section.id} $number.',
  );
  const atChapterOne = AskReach(
    progress: StoryReadingProgress(1),
    limit: TextPosition(2, 0.5),
    page: page,
  );

  late FakeAskBackend backend;
  late List<String> openedMap;
  late List<PassageTarget> jumps;

  setUp(() {
    backend = FakeAskBackend(model: model, reach: atChapterOne, all: all);
    openedMap = [];
    jumps = [];
  });

  Future<AskController> pumpAsk(
    WidgetTester tester, {
    AskHttpPost? post,
    List<(int, String)> replies = const [],
    _MemoryHistory? history,
    ConnectionStatus? connection,
    ValueNotifier<bool>? active,
    DateTime Function()? now,
  }) async {
    final settings = AiSettings(
      MemorySecretStore({
        'ai_onboarding_seen': 'true',
        'ai_provider': 'openai',
        'ai_api_key': 'sk-test',
      }),
    );
    await settings.load();
    final controller = AskController(
      book: book,
      backend: backend,
      openHistory: () async => history ?? _MemoryHistory(),
      post: post ?? FakeAskProvider(replies).post,
      loadPrompt: () async => 'PROMPT',
      now: now,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      AiSettingsScope(
        settings: settings,
        child: ConnectionScope(
          status: connection ?? ConnectionStatus(),
          child: MaterialApp(
            theme: buildLoremarkTheme(),
            home: Scaffold(
              body: AiLock(
                feature: 'Ask',
                needsConnection: true,
                child: ValueListenableBuilder(
                  valueListenable: active ?? ValueNotifier(true),
                  builder: (context, active, _) => AskScreen(
                    controller: controller,
                    active: active,
                    onOpenStoryMap: () => openedMap.add('opened'),
                    onOpenPassage: (target) async => jumps.add(target),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> askQuestion(WidgetTester tester, String question) async {
    await tester.enterText(find.byKey(const ValueKey('ask-input')), question);
    await tester.pump();
    await tester.tap(find.byTooltip('Ask'));
    await tester.pumpAndSettle();
  }

  IconButton newConversation(WidgetTester tester) => tester.widget(
    find.ancestor(
      of: find.byIcon(Icons.add_comment_outlined),
      matching: find.byType(IconButton),
    ),
  );

  /// The passages a citation sheet marks as cited, top to bottom.
  List<String> highlighted(WidgetTester tester) => [
    for (final box in tester.widgetList<Container>(find.byType(Container)))
      if (box.decoration case BoxDecoration(color: LoremarkColors.noteQuote))
        (box.child! as Text).data!,
  ];

  String answer(String text) => sse([
    completed([message(text)]),
  ]);

  testWidgets('says what answers can use, before any question', (tester) async {
    await pumpAsk(tester);
    expect(
      find.text('Sees your recent pages · Story Map to Chapter 1: Arrival'),
      findsOne,
    );
    expect(find.text('Ask about what you’ve read.'), findsOne);
    expect(newConversation(tester).onPressed, isNull);
  });

  testWidgets('asks, and shows the answer with where it comes from', (
    tester,
  ) async {
    await pumpAsk(
      tester,
      replies: [(200, answer('Mara is a dock clerk [s1/p0001, page].'))],
    );
    await askQuestion(tester, 'Who is Mara?');

    expect(find.text('Who is Mara?'), findsOne);
    expect(find.textContaining('Mara is a dock clerk'), findsOne);
    expect(find.text('1'), findsOne);
    // An older kind of citation: the recent pages, with no line.
    expect(find.text('recent pages'), findsOne);
    expect(find.text('No passage cited.'), findsNothing);

    // The citation opens the paragraph, without moving the reader...
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    expect(find.text('Text of s1 1.'), findsOne);
    expect(find.text('Text of s1 2.'), findsOne);
    expect(find.text('Chapter 1: Arrival'), findsOne);
    expect(jumps, isEmpty);
    // ...until the reader asks to go there.
    await tester.tap(find.text('Open in book'));
    await tester.pumpAndSettle();
    expect(jumps.single.highlight, 'Text of s1 1.');
    expect(backend.placed.single.id, 'p0001');
    expect(find.text('Text of s1 2.'), findsNothing);
  });

  testWidgets('paragraphs next to each other are one citation', (tester) async {
    await pumpAsk(
      tester,
      replies: [
        (200, answer('Mara is a dock clerk [s1/p0001, s1/p0002, s1/p0003].')),
      ],
    );
    await askQuestion(tester, 'Who is Mara?');
    expect(find.text('1'), findsOne);
    expect(find.text('2'), findsNothing);
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    expect(highlighted(tester), [
      'Text of s1 1.',
      'Text of s1 2.',
      'Text of s1 3.',
    ]);
    await tester.tap(find.text('Open in book'));
    await tester.pumpAndSettle();
    expect(jumps.single.highlight, 'Text of s1 1.');
    expect(
      [for (final more in jumps.single.also) more.highlight],
      ['Text of s1 2.', 'Text of s1 3.'],
    );
    expect(backend.placed, hasLength(3));
  });

  testWidgets('a citation past where the reader is now can\'t be opened', (
    tester,
  ) async {
    final controller = await pumpAsk(
      tester,
      history: _MemoryHistory({
        'c1': [
          AskExchange(
            question: 'Later?',
            answer: 'Elian came [s2/p0001].',
            limit: const TextPosition(9, 0),
            askedAt: DateTime.utc(2026),
          ),
        ],
      }),
    );
    controller.open('c1');
    await tester.pumpAndSettle();
    expect(find.byTooltip('Past where you are now'), findsOne);
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    expect(find.text('Open in book'), findsNothing);
  });

  testWidgets('says so when an answer cites nothing', (tester) async {
    await pumpAsk(tester, replies: [(200, answer('Just words.'))]);
    await askQuestion(tester, 'Who?');
    expect(find.text('No passage cited.'), findsOne);
  });

  testWidgets('without a map, says the page is all it has', (tester) async {
    backend
      ..model = null
      ..reach = const AskReach(
        progress: StoryReadingProgress(0),
        limit: TextPosition(2, 0.5),
        page: page,
      );
    await pumpAsk(tester);
    expect(find.text('Sees your recent pages · No Story Map yet'), findsOne);
    expect(find.textContaining('Build a Story Map'), findsOne);
    await tester.tap(find.text('Story Map'));
    expect(openedMap, hasLength(1));
  });

  testWidgets('says when the reader is past what the map covers', (
    tester,
  ) async {
    backend.reach = const AskReach(
      progress: StoryReadingProgress(1),
      limit: TextPosition(4, 0.2),
      page: page,
      pastMap: true,
    );
    await pumpAsk(tester);
    expect(find.textContaining('past what the Story Map covers'), findsOne);
  });

  testWidgets('with nothing read, there is nothing to ask', (tester) async {
    backend
      ..model = null
      ..reach = AskReach.none;
    await pumpAsk(tester);
    expect(find.textContaining('Read a page first.'), findsOne);
    final input = tester.widget<TextField>(
      find.byKey(const ValueKey('ask-input')),
    );
    expect(input.enabled, isFalse);
  });

  testWidgets('a failed question can be tried again', (tester) async {
    await pumpAsk(
      tester,
      replies: [
        (401, '{"error":{"message":"bad key"}}'),
        (200, answer('Mara [s1/p0001].')),
      ],
    );
    await askQuestion(tester, 'Who?');
    expect(
      find.text('Your API key was rejected. Check it in Settings.'),
      findsOne,
    );
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mara'), findsWidgets);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('shows what it is doing, and can be stopped', (tester) async {
    final body = StreamController<String>();
    await pumpAsk(
      tester,
      post: (url, headers, sent) async =>
          AskHttpReply(200, body.stream, () => body.close()),
    );
    await askQuestion(tester, 'Who?');
    expect(find.text('Thinking…'), findsOne);
    expect(find.byTooltip('Stop'), findsOne);

    body.add(
      sse([
        {'type': 'response.output_text.delta', 'item_id': 'm', 'delta': 'Ma'},
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Ma'), findsWidgets);

    await tester.tap(find.byTooltip('Stop'));
    await tester.pumpAndSettle();
    expect(find.text('Stopped. Nothing was kept.'), findsOne);
    expect(find.byTooltip('Ask'), findsOne);
  });

  testWidgets('a question being written survives going offline', (
    tester,
  ) async {
    final connection = ConnectionStatus();
    await pumpAsk(tester, connection: connection);
    await tester.enterText(find.byKey(const ValueKey('ask-input')), 'Half a');

    connection.isOnline = false;
    await tester.pumpAndSettle();
    expect(find.text('Ask needs a connection'), findsOne);
    connection.isOnline = true;
    await tester.pumpAndSettle();

    final input = tester.widget<TextField>(
      find.byKey(const ValueKey('ask-input')),
    );
    expect(input.controller!.text, 'Half a');
  });

  group('recent pages', () {
    const fourLines = AskPage(
      'First line.\n\nSecond line.\n\nThird line.\n\nFourth line.',
      TextPosition(2, 0.5),
    );

    setUp(() {
      backend.reach = const AskReach(
        progress: StoryReadingProgress(1),
        limit: TextPosition(2, 0.5),
        page: fourLines,
      );
    });

    testWidgets('a line is numbered with the paragraphs, and opens', (
      tester,
    ) async {
      await pumpAsk(
        tester,
        replies: [(200, answer('Mara waited [page/2] by it [s1/p0001].'))],
      );
      await askQuestion(tester, 'What did Mara do?');
      expect(find.text('recent pages'), findsNothing);

      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();
      expect(find.text('RECENT PAGES'), findsOne);
      expect(find.textContaining('What Ask saw'), findsOne);
      expect(find.text('First line.'), findsOne);
      expect(find.text('Second line.'), findsOne);
      expect(find.text('Third line.'), findsOne);
      expect(find.text('Fourth line.'), findsNothing);
      expect(backend.pagesAsked.single, const TextPosition(2, 0.5));
      expect(jumps, isEmpty);

      await tester.tap(find.text('Open in book'));
      await tester.pumpAndSettle();
      expect(jumps.single.sectionIndex, 2);
      expect(jumps.single.highlight, 'Second line.');
      expect(find.text('RECENT PAGES'), findsNothing);

      // The paragraph is the next number.
      await tester.tap(find.text('2'));
      await tester.pumpAndSettle();
      expect(find.text('Chapter 1: Arrival'), findsOne);
    });

    testWidgets('lines next to each other are one citation', (tester) async {
      await pumpAsk(
        tester,
        replies: [(200, answer('Mara waited by it [page/3, page/2].'))],
      );
      await askQuestion(tester, 'What did Mara do?');
      expect(find.text('1'), findsOne);
      expect(find.text('2'), findsNothing);

      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();
      for (final line in fourLines.lines) {
        expect(find.text(line), findsOne);
      }
      expect(highlighted(tester), ['Second line.', 'Third line.']);
      await tester.tap(find.text('Open in book'));
      await tester.pumpAndSettle();
      // It goes to the first, and highlights both.
      expect(jumps.single.highlight, 'Second line.');
      expect(
        [for (final more in jumps.single.also) more.highlight],
        ['Third line.'],
      );
    });

    testWidgets('with no line, all of them show, ending at the page', (
      tester,
    ) async {
      final controller = await pumpAsk(
        tester,
        history: _MemoryHistory({
          'c1': [
            AskExchange(
              question: 'Where?',
              answer: 'By the water [page].',
              limit: const TextPosition(2, 0.5),
              askedAt: DateTime.utc(2026),
            ),
          ],
        }),
      );
      controller.open('c1');
      await tester.pumpAndSettle();
      await tester.tap(find.text('recent pages'));
      await tester.pumpAndSettle();
      for (final line in fourLines.lines) {
        expect(find.text(line), findsOne);
      }
      await tester.tap(find.text('Open in book'));
      await tester.pumpAndSettle();
      expect(jumps.single.highlight, 'Fourth line.');
    });

    testWidgets('can\'t be opened when the page end wasn\'t measured', (
      tester,
    ) async {
      final controller = await pumpAsk(
        tester,
        history: _MemoryHistory({
          'c1': [
            AskExchange(
              question: 'Where?',
              answer: 'By the water [page].',
              limit: const TextPosition(2, 0),
              askedAt: DateTime.utc(2026),
            ),
          ],
        }),
      );
      controller.open('c1');
      await tester.pumpAndSettle();
      await tester.tap(find.text('recent pages'));
      await tester.pumpAndSettle();
      expect(find.text('RECENT PAGES'), findsNothing);
      expect(backend.pagesAsked, isEmpty);
    });
  });

  group('conversations', () {
    testWidgets('a new one empties the thread; the old one is listed', (
      tester,
    ) async {
      await pumpAsk(tester, replies: [(200, answer('Mara.'))]);
      await askQuestion(tester, 'Who?');
      expect(find.text('Mara.'), findsOne);

      await tester.tap(find.byTooltip('New conversation'));
      await tester.pumpAndSettle();
      expect(find.text('Ask about what you’ve read.'), findsOne);
      expect(newConversation(tester).onPressed, isNull);

      await tester.tap(find.byTooltip('Conversations'));
      await tester.pumpAndSettle();
      expect(find.text('CONVERSATIONS'), findsOne);
      expect(find.text('Who?'), findsOne);
      expect(find.textContaining('· 1 question'), findsOne);
    });

    testWidgets('one opens from the list', (tester) async {
      await pumpAsk(
        tester,
        history: _MemoryHistory({
          'c1': [_exchange('Earlier?', 'Long ago.')],
          'c2': [_exchange('Other?', 'Elsewhere.')],
        }),
      );
      expect(find.text('Ask about what you’ve read.'), findsOne);
      await tester.tap(find.byTooltip('Conversations'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Earlier?'));
      await tester.pumpAndSettle();
      expect(find.text('CONVERSATIONS'), findsNothing);
      expect(find.text('Long ago.'), findsOne);
      expect(find.text('Elsewhere.'), findsNothing);
    });

    testWidgets('deleting one asks first', (tester) async {
      final history = _MemoryHistory({
        'c1': [_exchange('Who?', 'Mara.')],
      });
      final controller = await pumpAsk(tester, history: history);
      controller.open('c1');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Conversations'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete conversation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(history.saved, contains('c1'));

      await tester.tap(find.byTooltip('Delete conversation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(history.saved, isEmpty);
      expect(
        find.text('Conversations you have about this book are kept here.'),
        findsOne,
      );
      Navigator.of(tester.element(find.text('CONVERSATIONS'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Ask about what you’ve read.'), findsOne);
    });

    testWidgets('leaving the tab for five minutes means a new one', (
      tester,
    ) async {
      var clock = DateTime.utc(2026, 11, 9, 12);
      final active = ValueNotifier(true);
      await pumpAsk(
        tester,
        replies: [(200, answer('Mara.'))],
        active: active,
        now: () => clock,
      );
      await askQuestion(tester, 'Who?');

      active.value = false;
      await tester.pump();
      clock = clock.add(const Duration(minutes: 4));
      active.value = true;
      await tester.pumpAndSettle();
      expect(find.text('Mara.'), findsOne);

      active.value = false;
      await tester.pump();
      clock = clock.add(askIdleGap);
      active.value = true;
      await tester.pumpAndSettle();
      expect(find.text('Mara.'), findsNothing);
      expect(find.text('Ask about what you’ve read.'), findsOne);
    });
  });

  group('when a conversation was last added to', () {
    final now = DateTime(2026, 11, 9, 20, 30);

    test('today, the time', () {
      expect(conversationTime(DateTime(2026, 11, 9, 8, 5), now), 'Today 08:05');
    });

    test('this year, the date', () {
      expect(conversationTime(DateTime(2026, 11, 8, 23, 59), now), 'Nov 8');
      expect(conversationTime(DateTime(2026, 3, 2), now), 'Mar 2');
    });

    test('before, the year too', () {
      expect(conversationTime(DateTime(2025, 11, 9), now), 'Nov 9, 2025');
    });
  });
}
