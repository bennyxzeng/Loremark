import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/read_screen.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/epub_reader_service.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/theme/loremark_theme.dart';

import 'fake_epub_reader_service.dart';

void main() {
  Book makeBook({String id = 'abc', String path = 'glass.epub'}) => Book(
    id: id,
    title: 'The Glass Harbor',
    author: null,
    epubPath: path,
    coverPath: null,
    importedAt: DateTime(2026),
  );

  final book = makeBook();

  late FakeEpubReaderService service;
  late FakeReadingPositionStore store;

  setUp(() {
    service = FakeEpubReaderService();
    store = FakeReadingPositionStore();
  });

  Widget screen({
    Book? forBook,
    Future<FakeReadingPositionStore> Function()? openStore,
    ValueChanged<ReaderPosition>? onPositionChanged,
  }) => MaterialApp(
    theme: buildLoremarkTheme(),
    home: Scaffold(
      body: ReadScreen(
        book: forBook ?? book,
        readerService: service,
        openPositionStore: openStore ?? () async => store,
        onPositionChanged: onPositionChanged,
      ),
    ),
  );

  /// Pumps the screen until the reader view is showing.
  Future<FakeEpubReaderSession> openBook(
    WidgetTester tester, {
    ValueChanged<ReaderPosition>? onPositionChanged,
  }) async {
    await tester.pumpWidget(screen(onPositionChanged: onPositionChanged));
    await tester.pumpAndSettle();
    return service.sessions.single;
  }

  Future<void> emit(
    WidgetTester tester,
    FakeEpubReaderSession session,
    ReaderPosition position,
  ) async {
    session.emit(position);
    // Let the stream deliver the event before the frame that shows it.
    await tester.idle();
    await tester.pump();
  }

  String chapterTitle(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('chapter-title'))).data!;

  String progressLabel(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('progress-label'))).data!;

  group('opening', () {
    testWidgets('shows the loading text, then the reader view', (tester) async {
      service.gate = Completer<void>();
      await tester.pumpWidget(screen());

      expect(find.text('Opening book…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      service.gate!.complete();
      await tester.pumpAndSettle();

      expect(find.text('Opening book…'), findsNothing);
      expect(find.text('Fake reader view'), findsOneWidget);
      expect(service.openedPaths, ['glass.epub']);
    });

    testWidgets('opens at the saved position', (tester) async {
      const saved = ReaderPosition(2, 0.4, totalProgression: 0.3);
      store = FakeReadingPositionStore(positions: {'abc': saved});

      final session = await openBook(tester);

      expect(session.builtViews, [saved]);
    });

    testWidgets('opens at the start when nothing is saved', (tester) async {
      final session = await openBook(tester);

      expect(session.builtViews, [null]);
    });

    testWidgets('opens at the start when the store fails to open', (
      tester,
    ) async {
      await tester.pumpWidget(
        screen(openStore: () async => throw const FormatException('no store')),
      );
      await tester.pumpAndSettle();
      final session = service.sessions.single;

      expect(find.text('Fake reader view'), findsOneWidget);
      expect(session.builtViews, [null]);

      await emit(tester, session, const ReaderPosition(1, 0.1));
      expect(store.saves, isEmpty);
    });

    testWidgets('opens at the start when the store fails to load', (
      tester,
    ) async {
      store = FakeReadingPositionStore(loadError: const FormatException('bad'));

      final session = await openBook(tester);

      expect(find.text('Fake reader view'), findsOneWidget);
      expect(session.builtViews, [null]);

      // The store itself opened, so later positions are still saved.
      const position = ReaderPosition(1, 0.1);
      await emit(tester, session, position);
      expect(store.saves, [('abc', position)]);
    });

    testWidgets('reopens when the book changes', (tester) async {
      final first = await openBook(tester);

      await tester.pumpWidget(
        screen(
          forBook: makeBook(id: 'xyz', path: 'other.epub'),
        ),
      );
      await tester.pumpAndSettle();

      expect(first.closeCalls, 1);
      expect(service.openedPaths, ['glass.epub', 'other.epub']);
      expect(service.sessions, hasLength(2));
      expect(find.text('Fake reader view'), findsOneWidget);
    });

    testWidgets('shows only the newest book when the book changes mid-open', (
      tester,
    ) async {
      // The first book is slow, so the second finishes opening before it.
      service.pathGates['glass.epub'] = Completer<void>();
      await tester.pumpWidget(screen());
      await tester.pumpWidget(
        screen(
          forBook: makeBook(id: 'xyz', path: 'other.epub'),
        ),
      );
      await tester.pumpAndSettle();
      final second = service.sessions.single;
      expect(second.epubPath, 'other.epub');
      expect(find.text('Fake reader view'), findsOneWidget);

      service.pathGates['glass.epub']!.complete();
      await tester.pumpAndSettle();

      final first = service.sessions.singleWhere(
        (session) => session.epubPath == 'glass.epub',
      );
      expect(first.closeCalls, 1);
      expect(first.builtViews, isEmpty);
      expect(first.hasListener, isFalse);
      expect(second.closeCalls, 0);
      expect(second.builtViews, hasLength(1));
      expect(second.hasListener, isTrue);
      expect(find.text('Fake reader view'), findsOneWidget);
    });
  });

  group('positions', () {
    testWidgets('saves each position and passes it on', (tester) async {
      final reported = <ReaderPosition>[];
      final session = await openBook(tester, onPositionChanged: reported.add);
      const first = ReaderPosition(1, 0.2, totalProgression: 0.1);
      const second = ReaderPosition(1, 0.6, totalProgression: 0.2);

      await emit(tester, session, first);
      await emit(tester, session, second);

      expect(store.saves, [('abc', first), ('abc', second)]);
      expect(reported, [first, second]);
    });

    testWidgets('keeps reading when a save fails', (tester) async {
      store.saveError = const FormatException('disk full');
      final session = await openBook(tester);

      await emit(tester, session, const ReaderPosition(4, 0.0));

      expect(tester.takeException(), isNull);
      expect(chapterTitle(tester), 'Chapter Two');
    });

    testWidgets('the chapter title follows the position', (tester) async {
      final session = await openBook(tester);
      expect(chapterTitle(tester), 'The Glass Harbor');

      await emit(tester, session, const ReaderPosition(0, 0.5));
      expect(chapterTitle(tester), 'The Glass Harbor');

      await emit(tester, session, const ReaderPosition(1, 0.0));
      expect(chapterTitle(tester), 'Chapter One');

      await emit(tester, session, const ReaderPosition(3, 0.5));
      expect(chapterTitle(tester), 'Section 1.1');

      await emit(tester, session, const ReaderPosition(5, 1.0));
      expect(chapterTitle(tester), 'Chapter Two');
    });

    testWidgets('shows how far through the book the reader is', (tester) async {
      final session = await openBook(tester);
      expect(progressLabel(tester), '');

      await emit(
        tester,
        session,
        const ReaderPosition(1, 0, totalProgression: 0.42),
      );
      expect(progressLabel(tester), '42%');

      await emit(
        tester,
        session,
        const ReaderPosition(5, 1, totalProgression: 1),
      );
      expect(progressLabel(tester), '100%');

      await emit(
        tester,
        session,
        const ReaderPosition(5, 1, totalProgression: 0.998),
      );
      expect(progressLabel(tester), '99%');

      await emit(tester, session, const ReaderPosition(5, 1));
      expect(progressLabel(tester), '');
    });

    testWidgets('builds the reader view once however much it moves', (
      tester,
    ) async {
      final session = await openBook(tester);

      for (var i = 0; i < 20; i++) {
        await emit(tester, session, ReaderPosition(i % 6, i / 20));
      }

      expect(session.builtViews, hasLength(1));
    });
  });

  group('controls', () {
    testWidgets('the page buttons turn the page', (tester) async {
      final session = await openBook(tester);

      await tester.tap(find.byTooltip('Next page'));
      await tester.tap(find.byTooltip('Next page'));
      await tester.tap(find.byTooltip('Previous page'));

      expect(session.forwardCalls, 2);
      expect(session.backwardCalls, 1);
    });

    testWidgets('lists the contents, indented, without unlinked entries', (
      tester,
    ) async {
      await openBook(tester);

      await tester.tap(find.byTooltip('Contents'));
      await tester.pumpAndSettle();

      expect(find.text('Chapter One'), findsOneWidget);
      expect(find.text('Section 1.1'), findsOneWidget);
      expect(find.text('Chapter Two'), findsOneWidget);
      expect(find.text('Online Notes'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Section 1.1')).dx,
        greaterThan(tester.getTopLeft(find.text('Chapter One')).dx),
      );
    });

    testWidgets('highlights the current chapter', (tester) async {
      final session = await openBook(tester);
      await emit(tester, session, const ReaderPosition(3, 0.5));

      await tester.tap(find.byTooltip('Contents'));
      await tester.pumpAndSettle();

      bool selected(String title) => tester
          .widget<ListTile>(find.widgetWithText(ListTile, title))
          .selected;
      expect(selected('Section 1.1'), isTrue);
      expect(selected('Chapter One'), isFalse);
      expect(selected('Chapter Two'), isFalse);
    });

    testWidgets('tapping a chapter goes there and closes the sheet', (
      tester,
    ) async {
      final session = await openBook(tester);

      await tester.tap(find.byTooltip('Contents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chapter Two'));
      await tester.pumpAndSettle();

      expect(session.goToCalls.map((entry) => entry.title), ['Chapter Two']);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('dismissing the sheet goes nowhere', (tester) async {
      final session = await openBook(tester);

      await tester.tap(find.byTooltip('Contents'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(session.goToCalls, isEmpty);
    });

    testWidgets('disables Contents when the book has none', (tester) async {
      service = FakeEpubReaderService(toc: const []);
      await openBook(tester);

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.toc),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('errors', () {
    testWidgets('says the file is missing', (tester) async {
      service.error = const EpubOpenException(EpubOpenFailure.missingFile);
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      expect(find.textContaining('file is missing'), findsOneWidget);
      expect(find.textContaining('import it again'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Fake reader view'), findsNothing);
    });

    testWidgets("says the file isn't an EPUB", (tester) async {
      service.error = const EpubOpenException(EpubOpenFailure.unreadable);
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      expect(
        find.textContaining("couldn't be opened as an EPUB"),
        findsOneWidget,
      );
    });

    testWidgets('gives a generic message for anything else', (tester) async {
      service.error = StateError('boom');
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't open this book"), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
    });

    testWidgets('Try again opens the book', (tester) async {
      service.error = const EpubOpenException(EpubOpenFailure.missingFile);
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      service.error = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(service.openedPaths, ['glass.epub', 'glass.epub']);
      expect(find.text('Fake reader view'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });
  });

  group('closing', () {
    testWidgets('disposing closes the session', (tester) async {
      final session = await openBook(tester);
      expect(session.hasListener, isTrue);

      await tester.pumpWidget(const SizedBox());

      expect(session.closeCalls, 1);
    });

    testWidgets('closes a session that opens after disposal', (tester) async {
      service.gate = Completer<void>();
      await tester.pumpWidget(screen());
      await tester.pumpWidget(const SizedBox());

      service.gate!.complete();
      await tester.pump();

      final session = service.sessions.single;
      expect(session.closeCalls, 1);
      expect(session.builtViews, isEmpty);
    });
  });
}
