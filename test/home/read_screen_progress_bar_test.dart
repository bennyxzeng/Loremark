import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/read_screen.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/reader_position.dart';

import 'fake_epub_reader_service.dart';

// The bar another screen puts by the page count, as the book screen does with
// how much of the book counts as read.
void main() {
  final book = Book(
    id: 'abc',
    title: 'The Glass Harbor',
    author: null,
    epubPath: 'glass.epub',
    coverPath: null,
    importedAt: DateTime(2026),
  );
  const bar = ValueKey('bar');
  const label = ValueKey('progress-label');

  testWidgets('goes left of how far through the book the reader is', (
    tester,
  ) async {
    final readerService = FakeEpubReaderService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadScreen(
            book: book,
            readerService: readerService,
            openPositionStore: () async => FakeReadingPositionStore(),
            progressBar: const SizedBox(key: bar, height: 4),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    readerService.sessions.single.emit(
      const ReaderPosition(2, 0.5, totalProgression: 0.42),
    );
    await tester.pumpAndSettle();

    expect(find.text('42%'), findsOne);
    expect(
      tester.getTopRight(find.byKey(bar)).dx,
      lessThanOrEqualTo(tester.getTopLeft(find.byKey(label)).dx),
    );
    expect(tester.getSize(find.byKey(bar)).width, greaterThan(100));
  });
}
