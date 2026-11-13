import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/reader/reading_position_store.dart';
import 'package:loremark/reading/jump_confirmation.dart';
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
        await store.save(
          book,
          const ReaderPosition(12, 0.4, totalProgression: 0.6),
        );
        final tracker = await loadTracker(store, book);
        expect(tracker.furthest, const TextPosition(12, 0.4));
        expect(tracker.boundary, const TextPosition(12, 0.4));
        expect(tracker.boundaryTotal, 0.6);
        expect(tracker.currentTotal, 0.6);
        // Reopening at the saved page is not a jump.
        tracker.updatePosition(const TextPosition(12, 0.4));
        expect(tracker.pendingJump, isNull);
      },
    );

    test('saves that, so going back before reading on loses nothing', () async {
      await store.save(
        book,
        const ReaderPosition(12, 0.4, totalProgression: 0.6),
      );
      await loadTracker(store, book);
      await store.save(book, const ReaderPosition(2, 0, totalProgression: 0.1));
      final tracker = await loadTracker(store, book);
      expect(tracker.current, const TextPosition(2, 0));
      expect(tracker.furthest, const TextPosition(12, 0.4));
      expect(tracker.boundary, const TextPosition(12, 0.4));
      expect(tracker.boundaryTotal, 0.6);
      expect(tracker.currentTotal, 0.1);
    });

    test('keeps the saved boundary behind the position', () async {
      await store.save(
        book,
        const ReaderPosition(12, 0.4, totalProgression: 0.6),
      );
      await store.saveProgress(
        book,
        furthest: const TextPosition(12, 0.4),
        boundary: const TextPosition(3, 1),
        boundaryTotal: 0.2,
      );
      final tracker = await loadTracker(store, book);
      expect(tracker.current, const TextPosition(12, 0.4));
      expect(tracker.boundary, const TextPosition(3, 1));
      expect(tracker.boundaryTotal, 0.2);
      // A jump not counted as read still waits on the next open.
      expect(tracker.pendingJump, const TextPosition(12, 0.4));
    });
  });
}
