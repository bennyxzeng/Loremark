import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/recap_panel.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/epub_reader_service.dart';
import 'package:loremark/recap/recap_backend.dart';
import 'package:loremark/recap/recap_client.dart';
import 'package:loremark/recap/recap_controller.dart';
import 'package:loremark/recap/recap_source.dart';
import 'package:loremark/settings/ai_settings.dart';

final _book = Book(
  id: 'book-1',
  title: 'The Glass Harbor',
  author: null,
  epubPath: '/nowhere.epub',
  coverPath: null,
  importedAt: DateTime.utc(2026),
);

const _source = RecapSource(
  sectionTitle: 'Chapter 2: The Letter',
  sectionLabel: 'Chapter 2',
  partway: false,
  place: (finished: 2, paragraphsRead: 0, revision: 2),
  events: [
    RecapEvent(
      id: 'E1',
      chapter: 'Chapter 1',
      text: 'Mara arrives at the harbor.',
    ),
  ],
  characters: ['Mara'],
  openQuestions: [],
  recentText: 'Mara reads the letter by the quay.',
);

const _tar = PassageTarget(
  sectionIndex: 1,
  progression: 0.2,
  highlight: 'The harbor smelled of tar.',
);

const _recap = Recap(
  items: [
    RecapItem(
      title: 'Mara reaches the harbor.',
      summary: 'She comes to Glass Harbor looking for work.',
      chapter: 'Chapter 1',
      passages: [RecapPassage('The harbor smelled of tar.', target: _tar)],
    ),
    RecapItem(
      title: 'A letter changes hands.',
      summary: 'Elian gives Mara a letter he won’t explain.',
      chapter: 'Chapter 2: The Letter',
    ),
  ],
  stopsAt: 'the end of Chapter 2: The Letter',
  place: (finished: 2, paragraphsRead: 0, revision: 2),
);

/// Finds the reader at [start], answers with [answer], and keeps what was
/// asked for.
class _FakeBackend implements RecapBackend {
  _FakeBackend({
    this.start = const RecapCanStart(_source),
    this.answer = const RecapReady(_recap),
  });

  RecapStart start;
  RecapResult answer;
  Completer<void>? hold;
  int prepares = 0;
  final requests = <RecapSource>[];

  @override
  Future<RecapStart> prepare(Book book) async {
    prepares++;
    return start;
  }

  @override
  Future<RecapResult> recap(
    RecapSource source,
    AiCredentials credentials,
  ) async {
    requests.add(source);
    await hold?.future;
    return answer;
  }
}

void main() {
  late AiSettings settings;

  setUp(() async {
    settings = AiSettings(
      MemorySecretStore({
        'ai_onboarding_seen': 'true',
        'ai_provider': 'deepseek',
        'ai_api_key': 'sk-test',
      }),
    );
    await settings.load();
  });

  RecapController controllerFor(_FakeBackend backend) {
    final controller = RecapController(book: _book, backend: backend);
    addTearDown(controller.dispose);
    return controller;
  }

  /// The recap panel at the top of a scrolling list, as in the Ask tab.
  Future<void> pumpAsk(
    WidgetTester tester,
    RecapController controller, {
    bool active = true,
    VoidCallback? onBackToBook,
    ValueChanged<PassageTarget>? onOpenPassage,
    VoidCallback? onOpenStoryMap,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      AiSettingsScope(
        settings: settings,
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                RecapPanel(
                  controller: controller,
                  active: active,
                  onBackToBook: onBackToBook,
                  onOpenPassage: onOpenPassage,
                  onOpenStoryMap: onOpenStoryMap,
                ),
                const Text('The conversation'),
              ],
            ),
          ),
        ),
      ),
    );
    // While a recap is being written, its progress bar never settles.
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('shows where the recap stops before asking for one', (
    tester,
  ) async {
    final backend = _FakeBackend();
    await pumpAsk(tester, controllerFor(backend));

    expect(find.text('WHERE WE LEFT OFF'), findsOne);
    expect(find.text('RECAP UP TO'), findsOne);
    expect(find.text('The end of Chapter 2: The Letter'), findsOne);
    expect(find.text('Catch me up'), findsOne);
    expect(find.text('A 30-second read.'), findsOne);
    // The map goes past the reader, so there is nothing to update.
    expect(find.textContaining('Update your Story Map'), findsNothing);
    expect(backend.requests, isEmpty);
  });

  testWidgets('Catch me up shows the recap as numbered moments', (
    tester,
  ) async {
    final backend = _FakeBackend();
    await pumpAsk(tester, controllerFor(backend));

    await tester.tap(find.text('Catch me up'));
    await tester.pumpAndSettle();

    expect(backend.requests, [_source]);
    expect(find.text('Your story companion'), findsOne);
    expect(find.text('Up to the end of Chapter 2: The Letter.'), findsOne);
    expect(find.text('01'), findsOne);
    expect(find.text('Mara reaches the harbor.'), findsOne);
    expect(find.text('She comes to Glass Harbor looking for work.'), findsOne);
    expect(find.text('02'), findsOne);
    expect(find.text('A letter changes hands.'), findsOne);
    expect(find.text('New recap'), findsOne);
    expect(find.text('Catch me up'), findsNothing);
    // A follow-up goes in the chat below.
    expect(find.text('Questions about it? Ask below.'), findsOne);
  });

  testWidgets('View passage shows the book’s own words', (tester) async {
    final controller = controllerFor(_FakeBackend());
    await pumpAsk(tester, controller);
    await tester.tap(find.text('Catch me up'));
    await tester.pumpAndSettle();

    // Only a moment the Story Map quoted has a passage.
    expect(find.text('Chapter 1 · View passage'), findsOne);
    expect(find.text('Chapter 2: The Letter'), findsOne);

    await tester.tap(find.text('Chapter 1 · View passage'));
    await tester.pumpAndSettle();

    expect(find.text('The harbor smelled of tar.'), findsOne);
  });

  testWidgets('Read it in the book opens the book at the passage', (
    tester,
  ) async {
    final opened = <PassageTarget>[];
    await pumpAsk(
      tester,
      controllerFor(_FakeBackend()),
      onOpenPassage: opened.add,
    );
    await tester.tap(find.text('Catch me up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chapter 1 · View passage'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Read it in the book'));
    await tester.pumpAndSettle();

    expect(opened, [_tar]);
    // The passage sheet closes on the way.
    expect(find.text('The harbor smelled of tar.'), findsNothing);
  });

  testWidgets('a passage with nowhere to open has no button', (tester) async {
    const recap = Recap(
      items: [
        RecapItem(
          title: 'Mara reaches the harbor.',
          summary: 'She comes to Glass Harbor looking for work.',
          chapter: 'Chapter 1',
          passages: [RecapPassage('The harbor smelled of tar.')],
        ),
      ],
      stopsAt: 'the end of Chapter 2: The Letter',
      place: (finished: 2, paragraphsRead: 0, revision: 2),
    );
    await pumpAsk(
      tester,
      controllerFor(_FakeBackend(answer: const RecapReady(recap))),
      onOpenPassage: (_) {},
    );
    await tester.tap(find.text('Catch me up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chapter 1 · View passage'));
    await tester.pumpAndSettle();

    expect(find.text('The harbor smelled of tar.'), findsOne);
    expect(find.text('Read it in the book'), findsNothing);
  });

  testWidgets('Back to the book goes back to the Read tab', (tester) async {
    var back = 0;
    await pumpAsk(
      tester,
      controllerFor(_FakeBackend()),
      onBackToBook: () => back++,
    );
    await tester.tap(find.text('Catch me up'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Back to the book →'));

    expect(back, 1);
  });

  testWidgets('one press is one request, even if pressed again', (
    tester,
  ) async {
    final backend = _FakeBackend()..hold = Completer<void>();
    await pumpAsk(tester, controllerFor(backend));

    await tester.tap(find.text('Catch me up'));
    await tester.pump();
    expect(find.text('Writing your recap…'), findsOne);

    await tester.tap(find.text('Catch me up'));
    await tester.pump();
    expect(backend.requests, hasLength(1));

    backend.hold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Mara reaches the harbor.'), findsOne);
  });

  testWidgets('a recap started elsewhere shows here when it comes', (
    tester,
  ) async {
    // The Read tab's welcome-back card starts the recap, then opens this tab.
    final backend = _FakeBackend()..hold = Completer<void>();
    final controller = controllerFor(backend);
    await pumpAsk(tester, controller, active: false);
    await controller.prepare();
    unawaited(controller.write(settings.credentials!));

    await pumpAsk(tester, controller, settle: false);
    expect(find.text('Writing your recap…'), findsOne);
    expect(backend.prepares, 1);

    backend.hold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Mara reaches the harbor.'), findsOne);
  });

  testWidgets('a failed recap says why and offers to try again', (
    tester,
  ) async {
    final backend = _FakeBackend(
      answer: const RecapFailed(
        'DeepSeek rejected your API key. Check it in Settings.',
      ),
    );
    await pumpAsk(tester, controllerFor(backend));

    await tester.tap(find.text('Catch me up'));
    await tester.pumpAndSettle();

    expect(
      find.text('DeepSeek rejected your API key. Check it in Settings.'),
      findsOne,
    );
    expect(find.text('Try again'), findsOne);
  });

  testWidgets('before the reader has read any of the map, shows nothing', (
    tester,
  ) async {
    await pumpAsk(
      tester,
      controllerFor(_FakeBackend(start: const RecapNeedsReading())),
    );

    expect(find.text('WHERE WE LEFT OFF'), findsNothing);
    expect(find.text('Catch me up'), findsNothing);
    expect(find.text('The conversation'), findsOne);
  });

  testWidgets('without a Story Map, shows nothing', (tester) async {
    final backend = _FakeBackend(start: const RecapNeedsStoryMap());
    await pumpAsk(tester, controllerFor(backend));

    expect(find.text('WHERE WE LEFT OFF'), findsNothing);
    expect(find.text('Catch me up'), findsNothing);
    expect(backend.requests, isEmpty);
  });

  testWidgets('partway through a chapter, stops at the reader’s page', (
    tester,
  ) async {
    const source = RecapSource(
      sectionTitle: 'Chapter 3: The Storm',
      sectionLabel: 'Chapter 3',
      partway: true,
      place: (finished: 2, paragraphsRead: 7, revision: 2),
      events: [],
      characters: [],
      openQuestions: [],
      recentText: 'Rain on the quay.',
    );
    await pumpAsk(
      tester,
      controllerFor(_FakeBackend(start: const RecapCanStart(source))),
    );

    expect(find.text('Your page in Chapter 3: The Storm'), findsOne);
  });

  testWidgets('once the reader has read all the map holds, links to it', (
    tester,
  ) async {
    const source = RecapSource(
      sectionTitle: 'Chapter 2: The Letter',
      sectionLabel: 'Chapter 2',
      partway: false,
      place: (finished: 2, paragraphsRead: 0, revision: 2),
      events: [],
      characters: [],
      openQuestions: [],
      recentText: 'Mara reads the letter by the quay.',
      mapEndsHere: true,
    );
    var opened = 0;
    await pumpAsk(
      tester,
      controllerFor(_FakeBackend(start: const RecapCanStart(source))),
      onOpenStoryMap: () => opened++,
    );

    expect(find.text('Read further? Update your Story Map →'), findsOne);

    await tester.tap(find.text('Read further? Update your Story Map →'));
    expect(opened, 1);
  });

  testWidgets('a recap of another place isn’t shown', (tester) async {
    final backend = _FakeBackend();
    final controller = controllerFor(backend);
    await pumpAsk(tester, controller);
    await tester.tap(find.text('Catch me up'));
    await tester.pumpAndSettle();
    expect(find.text('Mara reaches the harbor.'), findsOne);

    // The reader turns back into chapter 2, then opens the tab again.
    backend.start = const RecapCanStart(
      RecapSource(
        sectionTitle: 'Chapter 2: The Letter',
        sectionLabel: 'Chapter 2',
        partway: true,
        place: (finished: 1, paragraphsRead: 3, revision: 2),
        events: [],
        characters: [],
        openQuestions: [],
        recentText: 'Mara opens the letter.',
      ),
    );
    await pumpAsk(tester, controller, active: false);
    await pumpAsk(tester, controller);

    expect(find.text('Mara reaches the harbor.'), findsNothing);
    expect(find.text('Your page in Chapter 2: The Letter'), findsOne);
    expect(find.text('Catch me up'), findsOne);
  });

  testWidgets('looks for the reader’s place again each time the tab opens', (
    tester,
  ) async {
    final backend = _FakeBackend();
    final controller = controllerFor(backend);

    await pumpAsk(tester, controller, active: false);
    expect(backend.prepares, 0);
    // Nothing shows until it knows where the reader is.
    expect(find.text('WHERE WE LEFT OFF'), findsNothing);

    await pumpAsk(tester, controller);
    expect(backend.prepares, 1);
    expect(find.text('Catch me up'), findsOne);

    await pumpAsk(tester, controller, active: false);
    await pumpAsk(tester, controller);
    expect(backend.prepares, 2);
  });
}
