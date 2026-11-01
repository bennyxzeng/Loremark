import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/read_screen.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/search/passage_search.dart';
import 'package:loremark/search/search_sheet.dart';
import 'package:loremark/theme/loremark_theme.dart';

import '../search/fake_passage_search.dart';
import 'fake_epub_reader_service.dart';

void main() {
  final book = Book(
    id: 'abc',
    title: 'The Glass Harbor',
    author: null,
    epubPath: 'glass.epub',
    coverPath: null,
    importedAt: DateTime(2026),
  );

  late FakeEpubReaderService service;
  late FakeReadingPositionStore store;
  late FakePassageSearch search;
  late int opens;

  setUp(() {
    service = FakeEpubReaderService();
    store = FakeReadingPositionStore();
    search = FakePassageSearch();
    opens = 0;
  });

  Future<PassageSearch> openFake() async {
    opens++;
    return search;
  }

  Widget screen({
    Future<PassageSearch> Function()? openSearch,
    ReaderPosition? Function()? furthestPosition,
    SearchSheetController? controller,
    bool showReader = true,
  }) => MaterialApp(
    theme: buildLoremarkTheme(),
    home: Scaffold(
      body: showReader
          ? ReadScreen(
              book: book,
              readerService: service,
              openPositionStore: () async => store,
              openSearch: openSearch,
              furthestPosition: furthestPosition,
              searchController: controller,
            )
          : const SizedBox(),
    ),
  );

  Future<FakeEpubReaderSession> openBook(
    WidgetTester tester, {
    Future<PassageSearch> Function()? openSearch,
    ReaderPosition? Function()? furthestPosition,
    SearchSheetController? controller,
  }) async {
    await tester.pumpWidget(
      screen(
        openSearch: openSearch ?? openFake,
        furthestPosition: furthestPosition,
        controller: controller,
      ),
    );
    await tester.pumpAndSettle();
    return service.sessions.single;
  }

  Future<void> emit(
    WidgetTester tester,
    FakeEpubReaderSession session,
    ReaderPosition position,
  ) async {
    session.emit(position);
    await tester.idle();
    await tester.pump();
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
  }

  /// Types [query] and waits out the debounce.
  Future<void> type(WidgetTester tester, String query) async {
    await tester.enterText(find.byKey(const ValueKey('search-field')), query);
    await tester.pump(searchDebounce);
    await tester.pump();
  }

  /// The background color of the highlighted parts of the snippet [text].
  List<String> highlightedParts(WidgetTester tester) {
    final parts = <String>[];
    for (final widget in tester.widgetList<RichText>(find.byType(RichText))) {
      widget.text.visitChildren((span) {
        if (span is TextSpan && span.style?.backgroundColor != null) {
          parts.add(span.text!);
        }
        return true;
      });
    }
    return parts;
  }

  group('search button', () {
    testWidgets('is disabled when the book has no search', (tester) async {
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.search),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('opens the sheet, focused on the field', (tester) async {
      await openBook(tester);

      await openSheet(tester);

      expect(find.text('SEARCH'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('search-field')),
      );
      expect(field.autofocus, isTrue);
      expect(find.textContaining('exact phrase'), findsOneWidget);
    });

    testWidgets('does not open the search until it is used', (tester) async {
      await openBook(tester);

      expect(opens, 0);
      await openSheet(tester);
      expect(opens, 1);
    });

    testWidgets('opens the search once per book however often it is used', (
      tester,
    ) async {
      await openBook(tester);

      await openSheet(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await openSheet(tester);

      expect(opens, 1);
    });
  });

  group('cutoff', () {
    testWidgets('is the current position when there is no furthest', (
      tester,
    ) async {
      final session = await openBook(tester);
      await emit(tester, session, const ReaderPosition(2, 0.5));
      await openSheet(tester);

      await type(tester, 'cat');

      expect(search.lastCutoff, const ReaderPosition(2, 0.5));
    });

    testWidgets('is the furthest position after turning back', (tester) async {
      final session = await openBook(
        tester,
        furthestPosition: () => const ReaderPosition(4, 0.2),
      );
      await emit(tester, session, const ReaderPosition(1, 0.9));
      await openSheet(tester);

      await type(tester, 'cat');

      expect(search.lastCutoff, const ReaderPosition(4, 0.2));
    });

    testWidgets('is the start of the book before any position', (tester) async {
      await openBook(tester);
      await openSheet(tester);

      await type(tester, 'cat');

      expect(search.lastCutoff, const ReaderPosition(0, 0));
    });

    testWidgets('names the chapter the reader has reached', (tester) async {
      final session = await openBook(tester);
      await emit(tester, session, const ReaderPosition(2, 0.5));
      await openSheet(tester);

      expect(
        find.text("Searching what you've read, up to Section 1.1"),
        findsOneWidget,
      );
    });

    testWidgets('without a chapter title, says what is searched', (
      tester,
    ) async {
      await openBook(tester);
      await openSheet(tester);

      expect(find.text("Searching what you've read"), findsOneWidget);
    });

    testWidgets('re-runs the query when the reader moves', (tester) async {
      final session = await openBook(tester);
      await emit(tester, session, const ReaderPosition(1, 0.5));
      await openSheet(tester);
      await type(tester, 'cat');
      expect(search.searches, hasLength(1));

      await emit(tester, session, const ReaderPosition(4, 0.1));

      expect(search.searches, hasLength(2));
      expect(search.lastCutoff, const ReaderPosition(4, 0.1));
      expect(search.searches.last.query, 'cat');
    });
  });

  group('typing', () {
    testWidgets('waits for a pause before searching', (tester) async {
      await openBook(tester);
      await openSheet(tester);

      await tester.enterText(find.byKey(const ValueKey('search-field')), 'c');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byKey(const ValueKey('search-field')), 'ca');
      await tester.pump(const Duration(milliseconds: 100));
      expect(search.searches, isEmpty);

      await tester.pump(const Duration(milliseconds: 100));

      expect(search.searches.map((s) => s.query), ['ca']);
    });

    testWidgets('an empty query searches nothing and clears the results', (
      tester,
    ) async {
      search.onSearch = (_) =>
          SearchResults(hits: [fakeHit(sectionIndex: 1)], hiddenMatches: 0);
      await openBook(tester);
      await openSheet(tester);
      await type(tester, 'cat');
      expect(find.byType(InkWell), findsWidgets);

      await type(tester, '  ');

      expect(search.searches, hasLength(1));
      expect(find.textContaining('The grey cat'), findsNothing);
    });
  });

  group('results', () {
    testWidgets('are grouped by chapter, with the match highlighted', (
      tester,
    ) async {
      search.onSearch = (_) => SearchResults(
        hits: [
          fakeHit(sectionIndex: 4, snippet: 'Chapter two cat here'),
          fakeHit(sectionIndex: 1, snippet: 'The grey cat sat'),
          fakeHit(
            sectionIndex: 1,
            paragraphIndex: 3,
            snippet: 'Another cat',
            matches: const [MatchSpan(8, 11)],
          ),
          // Before the first chapter, so it has no title.
          fakeHit(sectionIndex: 0, snippet: 'A cat on the cover'),
        ],
        hiddenMatches: 0,
      );
      await openBook(tester);
      await openSheet(tester);

      await type(tester, 'cat');

      final headings = [
        for (final key in [
          'search-chapter-Section 1',
          'search-chapter-Chapter One',
          'search-chapter-Chapter Two',
        ])
          tester.getTopLeft(find.byKey(ValueKey(key))).dy,
      ];
      expect(headings, orderedEquals([...headings]..sort()));
      // Both Chapter One hits sit under one heading.
      expect(
        find.byKey(const ValueKey('search-chapter-Chapter One')),
        findsOneWidget,
      );
      expect(find.text('CHAPTER ONE'), findsOneWidget);
      expect(find.text('SECTION 1'), findsOneWidget);
      expect(
        find.textContaining('The grey cat sat', findRichText: true),
        findsOneWidget,
      );
      expect(highlightedParts(tester), containsAll(['grey cat', 'cat']));
    });

    testWidgets('a section inside a chapter is listed under that chapter', (
      tester,
    ) async {
      search.onSearch = (_) =>
          SearchResults(hits: [fakeHit(sectionIndex: 3)], hiddenMatches: 0);
      await openBook(tester);
      await openSheet(tester);

      await type(tester, 'cat');

      // Section 3 comes after "Section 1.1" (2) and before "Chapter Two" (4).
      expect(find.text('SECTION 1.1'), findsOneWidget);
    });

    testWidgets('survive match spans that run past the snippet', (
      tester,
    ) async {
      search.onSearch = (_) => SearchResults(
        hits: [
          fakeHit(
            sectionIndex: 1,
            snippet: 'short',
            matches: const [MatchSpan(2, 99), MatchSpan(40, 50)],
          ),
        ],
        hiddenMatches: 0,
      );
      await openBook(tester);
      await openSheet(tester);

      await type(tester, 'sh');

      expect(tester.takeException(), isNull);
      expect(highlightedParts(tester), ['ort']);
    });

    testWidgets('tell how many matches are in chapters not yet reached', (
      tester,
    ) async {
      search.onSearch = (_) =>
          SearchResults(hits: [fakeHit(sectionIndex: 1)], hiddenMatches: 3);
      await openBook(tester);
      await openSheet(tester);

      await type(tester, 'cat');

      expect(
        find.text("3 more matches in chapters you haven't reached yet"),
        findsOneWidget,
      );
    });

    testWidgets('say "match" for exactly one hidden match', (tester) async {
      search.onSearch = (_) =>
          SearchResults(hits: [fakeHit(sectionIndex: 1)], hiddenMatches: 1);
      await openBook(tester);
      await openSheet(tester);

      await type(tester, 'cat');

      expect(
        find.text("1 more match in chapters you haven't reached yet"),
        findsOneWidget,
      );
    });

    testWidgets('show no footer without hidden matches', (tester) async {
      search.onSearch = (_) =>
          SearchResults(hits: [fakeHit(sectionIndex: 1)], hiddenMatches: 0);
      await openBook(tester);
      await openSheet(tester);

      await type(tester, 'cat');

      expect(find.byKey(const ValueKey('search-hidden')), findsNothing);
    });

    testWidgets('say so when nothing matches', (tester) async {
      await openBook(tester);
      await openSheet(tester);

      await type(tester, 'dragon');

      expect(
        find.text("No matches in what you've read so far"),
        findsOneWidget,
      );
    });

    testWidgets('still count hidden matches when nothing visible matches', (
      tester,
    ) async {
      search.onSearch = (_) => const SearchResults(hits: [], hiddenMatches: 2);
      await openBook(tester);
      await openSheet(tester);

      await type(tester, 'dragon');

      expect(find.byKey(const ValueKey('search-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('search-hidden')), findsOneWidget);
    });
  });

  group('failure', () {
    testWidgets('says search is unavailable and keeps the book open', (
      tester,
    ) async {
      final session = await openBook(
        tester,
        openSearch: () async => throw StateError('no index'),
      );

      await openSheet(tester);

      expect(find.byKey(const ValueKey('search-error')), findsOneWidget);
      expect(
        find.text("Search isn't available for this book right now."),
        findsOneWidget,
      );
      expect(session.closeCalls, 0);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Fake reader view'), findsOneWidget);
    });

    testWidgets('Try again opens the search afresh', (tester) async {
      var attempts = 0;
      await openBook(
        tester,
        openSearch: () async {
          attempts++;
          if (attempts == 1) throw StateError('no index');
          return search;
        },
      );
      await openSheet(tester);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      await type(tester, 'cat');

      expect(attempts, 2);
      expect(find.byKey(const ValueKey('search-error')), findsNothing);
      expect(search.searches, hasLength(1));
    });

    testWidgets('a search that throws shows a message, not a crash', (
      tester,
    ) async {
      search.onSearch = (_) => throw StateError('boom');
      await openBook(tester);
      await openSheet(tester);

      await type(tester, 'cat');

      expect(tester.takeException(), isNull);
      expect(
        find.text('Something went wrong with that search.'),
        findsOneWidget,
      );
    });
  });

  group('picking a hit', () {
    testWidgets('closes the sheet and shows the passage', (tester) async {
      final hit = fakeHit(sectionIndex: 1, highlight: 'grey cat');
      search.onSearch = (_) => SearchResults(hits: [hit], hiddenMatches: 0);
      final session = await openBook(tester);
      await openSheet(tester);
      await type(tester, 'cat');

      await tester.tap(find.byKey(const ValueKey('search-hit-1-0')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('search-field')), findsNothing);
      expect(session.shownPassages, [same(hit.target)]);
    });

    testWidgets('dismissing the sheet shows nothing', (tester) async {
      search.onSearch = (_) =>
          SearchResults(hits: [fakeHit(sectionIndex: 1)], hiddenMatches: 0);
      final session = await openBook(tester);
      await openSheet(tester);
      await type(tester, 'cat');

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(session.shownPassages, isEmpty);
    });

    testWidgets('keeps the highlight through page turns and reopening', (
      tester,
    ) async {
      search.onSearch = (_) =>
          SearchResults(hits: [fakeHit(sectionIndex: 1)], hiddenMatches: 0);
      final session = await openBook(tester);
      await openSheet(tester);
      await type(tester, 'cat');
      await tester.tap(find.byKey(const ValueKey('search-hit-1-0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Next page'));
      await emit(tester, session, const ReaderPosition(1, 0.5));
      await openSheet(tester);

      expect(session.clearHighlightCalls, 0);
    });

    testWidgets('clears the highlight when the screen goes away', (
      tester,
    ) async {
      search.onSearch = (_) =>
          SearchResults(hits: [fakeHit(sectionIndex: 1)], hiddenMatches: 0);
      final session = await openBook(tester);
      await openSheet(tester);
      await type(tester, 'cat');
      await tester.tap(find.byKey(const ValueKey('search-hit-1-0')));
      await tester.pumpAndSettle();

      await tester.pumpWidget(screen(showReader: false));
      await tester.pumpAndSettle();

      expect(session.clearHighlightCalls, 1);
      expect(session.closeCalls, 1);
    });

    testWidgets('does not touch the highlight if none was shown', (
      tester,
    ) async {
      final session = await openBook(tester);

      await tester.pumpWidget(screen(showReader: false));
      await tester.pumpAndSettle();

      expect(session.clearHighlightCalls, 0);
    });
  });

  group('SearchSheetController', () {
    testWidgets('opens the sheet with a query already searched', (
      tester,
    ) async {
      final controller = SearchSheetController();
      await openBook(tester, controller: controller);

      unawaited(controller.open(initialQuery: 'cat'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('search-field')),
      );
      expect(field.controller!.text, 'cat');
      expect(search.searches.map((s) => s.query), ['cat']);
    });

    testWidgets('does nothing once the screen is gone', (tester) async {
      final controller = SearchSheetController();
      await openBook(tester, controller: controller);
      await tester.pumpWidget(screen(showReader: false));

      await controller.open();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('search-field')), findsNothing);
    });
  });
}
