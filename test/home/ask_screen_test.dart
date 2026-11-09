import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/ask_screen.dart';
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
  cutoffLabel: 'Chapter 2: The Letter',
  events: [
    RecapEvent(
      id: 'E1',
      chapter: 'Chapter 1',
      text: 'Mara arrives at the harbor.',
    ),
  ],
  characters: ['Mara'],
  openQuestions: [],
  sectionText: 'Mara reads the letter by the quay.',
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
      quotes: [RecapQuote('The harbor smelled of tar.', target: _tar)],
    ),
    RecapItem(
      title: 'A letter changes hands.',
      summary: 'Elian gives Mara a letter he won’t explain.',
      chapter: 'Chapter 2: The Letter',
    ),
  ],
  cutoffLabel: 'Chapter 2: The Letter',
  usedStoryMap: true,
);

/// Gives [source] and [answer], and keeps what was asked for.
class _FakeBackend implements RecapBackend {
  _FakeBackend({this.source = _source, this.answer = const RecapReady(_recap)});

  RecapSource? source;
  RecapResult answer;
  Completer<void>? hold;
  int prepares = 0;
  final requests = <RecapSource>[];

  @override
  Future<RecapSource?> prepare(Book book) async {
    prepares++;
    return source;
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

  Future<void> pumpAsk(
    WidgetTester tester,
    RecapController controller, {
    bool active = true,
    VoidCallback? onBackToBook,
    ValueChanged<PassageTarget>? onOpenPassage,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      AiSettingsScope(
        settings: settings,
        child: MaterialApp(
          home: Scaffold(
            body: AskScreen(
              controller: controller,
              active: active,
              onBackToBook: onBackToBook,
              onOpenPassage: onOpenPassage,
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

    expect(find.text('Chapter 2: The Letter'), findsOne);
    expect(
      find.text('The Glass Harbor · Through Chapter 2: The Letter'),
      findsOne,
    );
    expect(find.text('Catch me up'), findsOne);
    expect(find.text('A 30-second read.'), findsOne);
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
    expect(find.text('01'), findsOne);
    expect(find.text('Mara reaches the harbor.'), findsOne);
    expect(find.text('She comes to Glass Harbor looking for work.'), findsOne);
    expect(find.text('02'), findsOne);
    expect(find.text('A letter changes hands.'), findsOne);
    expect(find.text('New recap'), findsOne);
    expect(find.text('Catch me up'), findsNothing);
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

    expect(find.text('“The harbor smelled of tar.”'), findsOne);
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
    expect(find.text('“The harbor smelled of tar.”'), findsNothing);
  });

  testWidgets('a quote that couldn’t be found in the book has no button', (
    tester,
  ) async {
    const recap = Recap(
      items: [
        RecapItem(
          title: 'Mara reaches the harbor.',
          summary: 'She comes to Glass Harbor looking for work.',
          chapter: 'Chapter 1',
          quotes: [RecapQuote('The harbor smelled of tar.')],
        ),
      ],
      cutoffLabel: 'Chapter 2: The Letter',
      usedStoryMap: true,
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

    expect(find.text('“The harbor smelled of tar.”'), findsOne);
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

  testWidgets('before the first chapter is finished, says to read on', (
    tester,
  ) async {
    await pumpAsk(tester, controllerFor(_FakeBackend(source: null)));

    expect(find.textContaining('Finish your first chapter'), findsOne);
    expect(find.text('Catch me up'), findsNothing);
  });

  testWidgets('without a Story Map, says what the recap is built from', (
    tester,
  ) async {
    const source = RecapSource(
      cutoffLabel: 'Chapter 1: Arrival',
      events: [],
      characters: [],
      openQuestions: [],
      sectionText: 'Mara walks along the quay.',
    );
    await pumpAsk(tester, controllerFor(_FakeBackend(source: source)));

    expect(find.textContaining('Build the Story Map'), findsOne);
  });

  testWidgets('looks for the reader’s place again each time the tab opens', (
    tester,
  ) async {
    final backend = _FakeBackend();
    final controller = controllerFor(backend);

    await pumpAsk(tester, controller, active: false);
    expect(backend.prepares, 0);

    await pumpAsk(tester, controller);
    expect(backend.prepares, 1);
    expect(find.text('Catch me up'), findsOne);

    await pumpAsk(tester, controller, active: false);
    await pumpAsk(tester, controller);
    expect(backend.prepares, 2);
  });
}
