import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/read_screen.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/epub_reader_service.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/theme/loremark_theme.dart';

import 'fake_epub_reader_service.dart';

// Opening the book at a passage a recap quotes, and going back.
void main() {
  final book = Book(
    id: 'abc',
    title: 'The Glass Harbor',
    author: null,
    epubPath: 'glass.epub',
    coverPath: null,
    importedAt: DateTime(2026),
  );

  const passage = PassageTarget(
    sectionIndex: 1,
    progression: 0.2,
    highlight: 'The harbor smelled of tar.',
  );
  const reading = ReaderPosition(4, 0.6);

  late FakeEpubReaderService readerService;
  late PassageJumpController jumps;

  setUp(() {
    readerService = FakeEpubReaderService();
    jumps = PassageJumpController();
  });

  /// Opens the book with the reader at [reading].
  Future<FakeEpubReaderSession> openBook(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLoremarkTheme(),
        home: Scaffold(
          body: ReadScreen(
            book: book,
            readerService: readerService,
            openPositionStore: () async => FakeReadingPositionStore(),
            passageJumps: jumps,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final session = readerService.sessions.single..emit(reading);
    await tester.pump();
    return session;
  }

  testWidgets('shows the passage and offers the way back', (tester) async {
    final session = await openBook(tester);

    await jumps.show(passage);
    await tester.pump();

    expect(session.shownPassages, [passage]);
    expect(find.text('Back to your page'), findsOne);
  });

  testWidgets('Back to your page returns to where the reader was', (
    tester,
  ) async {
    final session = await openBook(tester);
    await jumps.show(passage);
    await tester.pump();
    session.emit(const ReaderPosition(1, 0.2));
    await tester.pump();

    await tester.tap(find.text('Back to your page'));
    await tester.pumpAndSettle();

    expect(session.goToPositionCalls.last, reading);
    expect(session.clearHighlightCalls, 1);
    expect(find.text('Back to your page'), findsNothing);
  });

  testWidgets('a second jump still goes back to the first place', (
    tester,
  ) async {
    final session = await openBook(tester);
    await jumps.show(passage);
    await tester.pump();
    session.emit(const ReaderPosition(1, 0.2));
    await tester.pump();

    await jumps.show(passage);
    await tester.pump();
    await tester.tap(find.text('Back to your page'));
    await tester.pumpAndSettle();

    expect(session.goToPositionCalls.last, reading);
  });

  testWidgets('Stay here keeps the reader at the passage', (tester) async {
    final session = await openBook(tester);
    await jumps.show(passage);
    await tester.pump();

    await tester.tap(find.byTooltip('Stay here'));
    await tester.pumpAndSettle();

    expect(find.text('Back to your page'), findsNothing);
    expect(session.goToPositionCalls, isEmpty);
  });
}
