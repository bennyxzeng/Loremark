import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reading/reading_progress_tracker.dart';
import 'package:loremark/reading/text_position.dart';

void main() {
  late ReadingProgressTracker tracker;

  setUp(() {
    tracker = ReadingProgressTracker();
    tracker.updatePosition(const TextPosition(5, 0.5));
    tracker.confirmJump();
  });

  test('new tracker starts at the beginning of the book', () {
    final fresh = ReadingProgressTracker();
    expect(fresh.current, const TextPosition(0, 0));
    expect(fresh.furthest, const TextPosition(0, 0));
    expect(fresh.boundary, const TextPosition(0, 0));
    expect(fresh.pendingJump, isNull);
  });

  test('resume picks up where the book was left', () {
    final resumed = ReadingProgressTracker.resume(
      current: const TextPosition(4, 0.75),
      furthest: const TextPosition(9, 0.25),
      boundary: const TextPosition(5, 0.5),
    );
    expect(resumed.current, const TextPosition(4, 0.75));
    expect(resumed.furthest, const TextPosition(9, 0.25));
    expect(resumed.boundary, const TextPosition(5, 0.5));
    expect(resumed.pendingJump, isNull);
    expect(
      resumed.updatePosition(const TextPosition(8, 0)),
      PositionUpdateResult.needsConfirmation,
    );
  });

  test('small step forward moves the boundary', () {
    final result = tracker.updatePosition(const TextPosition(7, 0.9));
    expect(result, PositionUpdateResult.updated);
    expect(tracker.current, const TextPosition(7, 0.9));
    expect(tracker.furthest, const TextPosition(7, 0.9));
    expect(tracker.boundary, const TextPosition(7, 0.9));
  });

  test('going back keeps furthest and boundary', () {
    final result = tracker.updatePosition(const TextPosition(2, 0.1));
    expect(result, PositionUpdateResult.updated);
    expect(tracker.current, const TextPosition(2, 0.1));
    expect(tracker.furthest, const TextPosition(5, 0.5));
    expect(tracker.boundary, const TextPosition(5, 0.5));
  });

  test('big jump needs confirmation and keeps the boundary', () {
    final result = tracker.updatePosition(const TextPosition(8, 0.0));
    expect(result, PositionUpdateResult.needsConfirmation);
    expect(tracker.current, const TextPosition(8, 0.0));
    expect(tracker.furthest, const TextPosition(8, 0.0));
    expect(tracker.boundary, const TextPosition(5, 0.5));
    expect(tracker.pendingJump, const TextPosition(8, 0.0));
  });

  test('confirmJump moves the boundary to the pending jump', () {
    tracker.updatePosition(const TextPosition(8, 0.0));
    tracker.confirmJump();
    expect(tracker.boundary, const TextPosition(8, 0.0));
    expect(tracker.pendingJump, isNull);
  });

  test('reading on in the section of an unconfirmed jump does not ask '
      'again', () {
    tracker.updatePosition(const TextPosition(8, 0.0));
    for (final position in const [TextPosition(8, 0.4), TextPosition(8, 0.9)]) {
      expect(tracker.updatePosition(position), PositionUpdateResult.updated);
      expect(tracker.pendingJump, position);
    }
    expect(tracker.boundary, const TextPosition(5, 0.5));
  });

  test('reading on into the next section after an unconfirmed jump asks '
      'once more', () {
    tracker.updatePosition(const TextPosition(8, 0.0));
    expect(
      tracker.updatePosition(const TextPosition(9, 0.1)),
      PositionUpdateResult.needsConfirmation,
    );
    expect(
      tracker.updatePosition(const TextPosition(9, 0.5)),
      PositionUpdateResult.updated,
    );
    expect(tracker.boundary, const TextPosition(5, 0.5));
    tracker.confirmJump();
    expect(tracker.boundary, const TextPosition(9, 0.5));
  });

  test('going back a section from an unconfirmed jump and on again does not '
      'ask again', () {
    tracker.updatePosition(const TextPosition(9, 0.0));
    tracker.updatePosition(const TextPosition(8, 0.5));
    expect(
      tracker.updatePosition(const TextPosition(9, 0.2)),
      PositionUpdateResult.updated,
    );
  });

  test('confirmJump after reading on uses the latest pending position', () {
    tracker.updatePosition(const TextPosition(8, 0.0));
    tracker.updatePosition(const TextPosition(9, 0.3));
    tracker.confirmJump();
    expect(tracker.boundary, const TextPosition(9, 0.3));
  });

  test('another big jump from the pending jump asks again', () {
    tracker.updatePosition(const TextPosition(8, 0.0));
    final result = tracker.updatePosition(const TextPosition(11, 0.0));
    expect(result, PositionUpdateResult.needsConfirmation);
    expect(tracker.pendingJump, const TextPosition(11, 0.0));
  });

  test('big jump back from the pending jump asks again', () {
    tracker.updatePosition(const TextPosition(20, 0.0));
    final result = tracker.updatePosition(const TextPosition(9, 0.0));
    expect(result, PositionUpdateResult.needsConfirmation);
    expect(tracker.pendingJump, const TextPosition(9, 0.0));
  });

  test('going back after an unconfirmed jump drops it', () {
    tracker.updatePosition(const TextPosition(8, 0.0));
    tracker.updatePosition(const TextPosition(6, 0.0));
    expect(tracker.pendingJump, isNull);
    expect(tracker.boundary, const TextPosition(6, 0.0));
    tracker.confirmJump();
    expect(tracker.boundary, const TextPosition(6, 0.0));
  });

  group('jumpedFrom', () {
    test('is where the reader was just before the jump', () {
      tracker.updatePosition(const TextPosition(2, 0.1));
      tracker.updatePosition(const TextPosition(8, 0.0));
      expect(tracker.jumpedFrom, const TextPosition(2, 0.1));
    });

    test('stays before the first jump while asked again', () {
      tracker.updatePosition(const TextPosition(8, 0.0));
      // Not yet, then reading on into the next section asks again.
      tracker.updatePosition(const TextPosition(9, 0.1));
      expect(tracker.jumpedFrom, const TextPosition(5, 0.5));
      // And when jumping on, then far back.
      tracker.updatePosition(const TextPosition(20, 0.0));
      tracker.updatePosition(const TextPosition(12, 0.0));
      expect(tracker.jumpedFrom, const TextPosition(5, 0.5));
    });

    test('is the boundary when the reader was past it', () {
      final reopened = ReadingProgressTracker.resume(
        current: const TextPosition(12, 0.4),
        furthest: const TextPosition(12, 0.4),
        boundary: const TextPosition(3, 1),
      );
      reopened.updatePosition(const TextPosition(12, 0.4));
      expect(reopened.jumpedFrom, const TextPosition(3, 1));
    });
  });

  test('confirmJump without a pending jump does nothing', () {
    tracker.confirmJump();
    expect(tracker.boundary, const TextPosition(5, 0.5));
  });

  test('maxJumpSections changes the threshold', () {
    final strict = ReadingProgressTracker(maxJumpSections: 0);
    expect(
      strict.updatePosition(const TextPosition(0, 0.2)),
      PositionUpdateResult.updated,
    );
    expect(
      strict.updatePosition(const TextPosition(1, 0.0)),
      PositionUpdateResult.needsConfirmation,
    );
  });

  group('within one section', () {
    // The living doc's example: page 54 to page 87, here of a 120-page
    // chapter.
    const pages = 120;
    const page54 = TextPosition(3, 54 / pages);
    const page87 = TextPosition(3, 87 / pages);
    late ReadingProgressTracker chapter;

    setUp(() {
      chapter = ReadingProgressTracker.resume(
        current: page54,
        furthest: page54,
        boundary: page54,
      );
    });

    test('turning one page moves the boundary', () {
      const page55 = TextPosition(3, 55 / pages);
      expect(
        chapter.updatePosition(page55, sectionPages: pages),
        PositionUpdateResult.updated,
      );
      expect(chapter.boundary, page55);
    });

    test('turning two pages at once moves the boundary', () {
      const page56 = TextPosition(3, 56 / pages);
      expect(
        chapter.updatePosition(page56, sectionPages: pages),
        PositionUpdateResult.updated,
      );
      expect(chapter.boundary, page56);
    });

    test('a jump of ten pages moves the boundary', () {
      const page64 = TextPosition(3, 64 / pages);
      expect(
        chapter.updatePosition(page64, sectionPages: pages),
        PositionUpdateResult.updated,
      );
      expect(chapter.boundary, page64);
    });

    test('a jump of eleven pages needs confirmation', () {
      expect(
        chapter.updatePosition(
          const TextPosition(3, 65 / pages),
          sectionPages: pages,
        ),
        PositionUpdateResult.needsConfirmation,
      );
      expect(chapter.boundary, page54);
    });

    test('flipping one page at a time while Readium skips reports never '
        'asks', () {
      // Pages the emulator reported while flipping through a 67-page section
      // one page at a time: some reports were dropped, up to three in a row.
      const total = 67;
      const reported = [
        0, 1, 3, 6, 7, 9, 11, 13, 15, 16, 18, 22, 24, 26, 27, 29, 31, //
        33, 35, 36, 38, 40, 42, 44, 45, 47, 49, 51, 53, 55, 57, 59, 61, //
        63, 64, 66,
      ];
      final flipping = ReadingProgressTracker.resume(
        current: const TextPosition(3, 0),
        furthest: const TextPosition(3, 0),
        boundary: const TextPosition(3, 0),
      );
      for (final page in reported) {
        // The last page reports 1.0.
        final progression = page == total - 1 ? 1.0 : page / total;
        expect(
          flipping.updatePosition(
            TextPosition(3, progression),
            sectionPages: total,
          ),
          PositionUpdateResult.updated,
          reason: 'page $page',
        );
      }
      expect(flipping.boundary, const TextPosition(3, 1.0));
    });

    test('a jump of 33 pages needs confirmation', () {
      expect(
        chapter.updatePosition(page87, sectionPages: pages),
        PositionUpdateResult.needsConfirmation,
      );
      expect(chapter.boundary, page54);
      expect(chapter.pendingJump, page87);
    });

    test('the last page, reported as 1.0, counts from where it starts', () {
      // From the emulator log: the first page of 11, then the last page, the
      // reports between them dropped. Ten pages, not eleven.
      final short = ReadingProgressTracker.resume(
        current: const TextPosition(3, 0),
        furthest: const TextPosition(3, 0),
        boundary: const TextPosition(3, 0),
      );
      expect(
        short.updatePosition(const TextPosition(3, 1.0), sectionPages: 11),
        PositionUpdateResult.updated,
      );
    });

    test('after Not yet, reading on nearby does not ask again', () {
      chapter.updatePosition(page87, sectionPages: pages);
      for (final page in [88, 89, 95]) {
        expect(
          chapter.updatePosition(
            TextPosition(3, page / pages),
            sectionPages: pages,
          ),
          PositionUpdateResult.updated,
        );
      }
      expect(chapter.boundary, page54);
    });

    test('after Not yet, reading on into the next section asks once more', () {
      chapter.updatePosition(page87, sectionPages: pages);
      expect(
        chapter.updatePosition(const TextPosition(3, 1.0), sectionPages: pages),
        PositionUpdateResult.updated,
      );
      // Only one section past the boundary, but past an unconfirmed jump.
      expect(
        chapter.updatePosition(const TextPosition(4, 0), sectionPages: 30),
        PositionUpdateResult.needsConfirmation,
      );
      expect(
        chapter.updatePosition(const TextPosition(4, 0.1), sectionPages: 30),
        PositionUpdateResult.updated,
      );
      expect(chapter.boundary, page54);
      chapter.confirmJump();
      expect(chapter.boundary, const TextPosition(4, 0.1));
    });

    group('without a page count', () {
      test('up to 0.3 of the section moves the boundary', () {
        expect(
          chapter.updatePosition(const TextPosition(3, 0.65)),
          PositionUpdateResult.updated,
        );
      });

      test('more than 0.3 of the section needs confirmation', () {
        expect(
          chapter.updatePosition(const TextPosition(3, 0.9)),
          PositionUpdateResult.needsConfirmation,
        );
      });
    });
  });

  group('json', () {
    test('round trip keeps current, furthest and boundary', () {
      tracker.updatePosition(const TextPosition(9, 0.25));
      tracker.updatePosition(const TextPosition(4, 0.75));
      final decoded = jsonDecode(jsonEncode(tracker.toJson()));
      final loaded = ReadingProgressTracker.fromJson(decoded);
      expect(loaded.current, const TextPosition(4, 0.75));
      expect(loaded.furthest, const TextPosition(9, 0.25));
      expect(loaded.boundary, const TextPosition(5, 0.5));
      expect(loaded.pendingJump, isNull);
    });

    test('throws FormatException when a position is missing or invalid', () {
      final valid = tracker.toJson();
      expect(
        () => ReadingProgressTracker.fromJson({...valid}..remove('boundary')),
        throwsFormatException,
      );
      expect(
        () => ReadingProgressTracker.fromJson({
          ...valid,
          'current': {'sectionIndex': -1, 'progression': 0},
        }),
        throwsFormatException,
      );
    });
  });
}
