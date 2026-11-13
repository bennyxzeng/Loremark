import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/read_screen.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/reader_position.dart';

import 'fake_epub_reader_service.dart';

// Sending the Read tab to a position, as Go back after a jump does.
void main() {
  final book = Book(
    id: 'abc',
    title: 'The Glass Harbor',
    author: null,
    epubPath: 'glass.epub',
    coverPath: null,
    importedAt: DateTime(2026),
  );

  late FakeEpubReaderService readerService;
  late PositionJumpController jumps;

  setUp(() {
    readerService = FakeEpubReaderService();
    jumps = PositionJumpController();
  });

  Future<void> pumpRead(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadScreen(
            book: book,
            readerService: readerService,
            openPositionStore: () async => FakeReadingPositionStore(),
            positionJumps: jumps,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('goes to the position', (tester) async {
    await pumpRead(tester);

    await jumps.goTo(const ReaderPosition(2, 0.4));

    expect(readerService.sessions.single.goToPositionCalls, [
      const ReaderPosition(2, 0.4),
    ]);
  });

  testWidgets('does nothing once the screen is gone', (tester) async {
    await pumpRead(tester);
    final session = readerService.sessions.single;
    await tester.pumpWidget(const SizedBox());

    await jumps.goTo(const ReaderPosition(2, 0.4));

    expect(session.goToPositionCalls, isEmpty);
  });
}
