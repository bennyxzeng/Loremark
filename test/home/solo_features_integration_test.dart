import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/read_screen.dart';
import 'package:loremark/insights/reading_insights.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/search/passage_search.dart';
import 'package:loremark/search/search_sheet.dart';

import '../insights/fake_reading_insights.dart';
import '../search/fake_passage_search.dart';
import 'fake_epub_reader_service.dart';

void main() {
  testWidgets('search uses reading history and pauses dwell during its sheet', (
    tester,
  ) async {
    final service = FakeEpubReaderService();
    final insights = FakeReadingInsights(furthest: const ReaderPosition(4, 0));
    final hit = fakeHit(sectionIndex: 1);
    final search = FakePassageSearch(
      onSearch: (_) => SearchResults(hits: [hit], hiddenMatches: 0),
    );
    final store = FakeReadingPositionStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadScreen(
            book: Book(
              id: 'integration',
              title: 'Integration book',
              author: null,
              epubPath: 'unused.epub',
              coverPath: null,
              importedAt: DateTime(2026),
            ),
            readerService: service,
            openPositionStore: () async => store,
            openInsights: () async => insights,
            openSearch: () async => search,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final session = service.sessions.single;
    session.emit(const ReaderPosition(2, 0.2));
    await tester.pumpAndSettle();
    final hiddenBefore = insights.hiddenCalls;
    final shownBefore = insights.shownCalls;
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(insights.hiddenCalls, hiddenBefore + 1);
    await tester.enterText(find.byKey(const ValueKey('search-field')), 'cat');
    await tester.pump(searchDebounce);
    await tester.pump();
    // Readium percentages cannot establish text offsets within a section.
    expect(search.lastCutoff, const ReaderPosition(3, 1));
    await tester.tap(find.byKey(const ValueKey('search-hit-1-0')));
    await tester.pumpAndSettle();
    expect(insights.shownCalls, shownBefore + 1);
    expect(session.shownPassages, [hit.target]);
    session.emit(const ReaderPosition(1, 0.25));
    await tester.pumpAndSettle();
    expect(insights.causes.last, NavigationCause.searchJump);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('a contents jump ahead does not widen what search may see', (
    tester,
  ) async {
    final service = FakeEpubReaderService();
    // The reader read through chapter 1 and jumped to the last chapter.
    final insights = FakeReadingInsights(furthest: const ReaderPosition(1, 1));
    final search = FakePassageSearch();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadScreen(
            book: Book(
              id: 'jump',
              title: 'Jump book',
              author: null,
              epubPath: 'unused.epub',
              coverPath: null,
              importedAt: DateTime(2026),
            ),
            readerService: service,
            openPositionStore: () async => FakeReadingPositionStore(),
            openInsights: () async => insights,
            openSearch: () async => search,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    service.sessions.single.emit(const ReaderPosition(9, 0.5));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('search-field')), 'cat');
    await tester.pump(searchDebounce);
    await tester.pump();

    expect(search.lastCutoff, const ReaderPosition(1, 1));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
