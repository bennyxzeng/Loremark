import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/reader/reading_position_store.dart';
import 'package:loremark/reading/jump_confirmation.dart';
import 'package:loremark/reading/reading_progress_tracker.dart';
import 'package:loremark/reading/text_position.dart';

void main() {
  group('loadTracker', () {
    const book = 'book1';
    late Directory temp;
    late ReadingPositionStore store;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('loremark_tracker_');
      store = ReadingPositionStore(temp);
    });

    tearDown(() => temp.delete(recursive: true));

    test('starts a new book at the beginning', () async {
      final tracker = await loadTracker(store, book);
      expect(tracker.current, const TextPosition(0, 0));
      expect(tracker.furthest, const TextPosition(0, 0));
      expect(tracker.boundary, const TextPosition(0, 0));
    });

    test(
      'counts a book read before the tracker as read up to its position',
      () async {
        await store.save(book, const ReaderPosition(12, 0.4));
        final tracker = await loadTracker(store, book);
        expect(tracker.furthest, const TextPosition(12, 0.4));
        expect(tracker.boundary, const TextPosition(12, 0.4));
        // Reopening at the saved page is not a jump.
        expect(
          tracker.updatePosition(const TextPosition(12, 0.4)),
          PositionUpdateResult.updated,
        );
      },
    );

    test('saves that, so going back before reading on loses nothing', () async {
      await store.save(book, const ReaderPosition(12, 0.4));
      await loadTracker(store, book);
      await store.save(book, const ReaderPosition(2, 0));
      final tracker = await loadTracker(store, book);
      expect(tracker.current, const TextPosition(2, 0));
      expect(tracker.furthest, const TextPosition(12, 0.4));
      expect(tracker.boundary, const TextPosition(12, 0.4));
    });

    test('keeps the saved boundary behind the position', () async {
      await store.save(book, const ReaderPosition(12, 0.4));
      await store.saveProgress(
        book,
        furthest: const TextPosition(12, 0.4),
        boundary: const TextPosition(3, 1),
      );
      final tracker = await loadTracker(store, book);
      expect(tracker.current, const TextPosition(12, 0.4));
      expect(tracker.boundary, const TextPosition(3, 1));
      // A jump not counted as read is asked about again on the next open.
      expect(
        tracker.updatePosition(const TextPosition(12, 0.4)),
        PositionUpdateResult.needsConfirmation,
      );
    });
  });

  group('confirmSkippedChapters', () {
    late JumpAnswer? answer;

    Future<void> ask(WidgetTester tester) async {
      answer = null;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  answer = await confirmSkippedChapters(context),
              child: const Text('Ask'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();
    }

    testWidgets('says what it is asking', (tester) async {
      await ask(tester);
      expect(find.text('You skipped ahead'), findsOne);
      expect(
        find.text(
          'Count what you skipped as read? Story Map and Ask only use what '
          'you’ve read.',
        ),
        findsOne,
      );
    });

    for (final (button, expected) in const [
      ('Count as read', JumpAnswer.countAsRead),
      ('Go back', JumpAnswer.goBack),
      ('Not yet', JumpAnswer.notYet),
    ]) {
      testWidgets('is ${expected.name} for $button', (tester) async {
        await ask(tester);
        await tester.tap(find.text(button));
        await tester.pumpAndSettle();
        expect(answer, expected);
      });
    }

    testWidgets('is notYet when closed without an answer', (tester) async {
      await ask(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('You skipped ahead'), findsNothing);
      expect(answer, JumpAnswer.notYet);
    });
  });
}
