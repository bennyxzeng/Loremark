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
    resumed.updatePosition(const TextPosition(8, 0));
    expect(resumed.pendingJump, const TextPosition(8, 0));
  });

  test('resume past the boundary leaves the jump waiting', () {
    final resumed = ReadingProgressTracker.resume(
      current: const TextPosition(12, 0.4),
      furthest: const TextPosition(12, 0.4),
      boundary: const TextPosition(3, 1),
    );
    expect(resumed.pendingJump, const TextPosition(12, 0.4));
    expect(resumed.jumpedFrom, const TextPosition(3, 1));
    // Opening at the saved page keeps it waiting.
    resumed.updatePosition(const TextPosition(12, 0.4));
    expect(resumed.pendingJump, const TextPosition(12, 0.4));
    expect(resumed.boundary, const TextPosition(3, 1));
  });

  test('small step forward moves the boundary', () {
    tracker.updatePosition(const TextPosition(7, 0.9));
    expect(tracker.current, const TextPosition(7, 0.9));
    expect(tracker.furthest, const TextPosition(7, 0.9));
    expect(tracker.boundary, const TextPosition(7, 0.9));
    expect(tracker.pendingJump, isNull);
  });

  test('going back keeps furthest and boundary', () {
    tracker.updatePosition(const TextPosition(2, 0.1));
    expect(tracker.current, const TextPosition(2, 0.1));
    expect(tracker.furthest, const TextPosition(5, 0.5));
    expect(tracker.boundary, const TextPosition(5, 0.5));
    expect(tracker.pendingJump, isNull);
  });

  test('big jump keeps the boundary and waits', () {
    tracker.updatePosition(const TextPosition(8, 0.0));
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

  test('reading on after a jump keeps it waiting, into the next sections '
      'too', () {
    tracker.updatePosition(const TextPosition(8, 0.0));
    for (final position in const [
      TextPosition(8, 0.4),
      TextPosition(9, 0.1),
      TextPosition(10, 0.5),
    ]) {
      tracker.updatePosition(position);
      expect(tracker.pendingJump, position);
    }
    expect(tracker.boundary, const TextPosition(5, 0.5));
  });

  test('confirmJump after reading on uses the latest pending position', () {
    tracker.updatePosition(const TextPosition(8, 0.0));
    tracker.updatePosition(const TextPosition(9, 0.3));
    tracker.confirmJump();
    expect(tracker.boundary, const TextPosition(9, 0.3));
  });

  test('a big jump back from a waiting jump still waits', () {
    tracker.updatePosition(const TextPosition(20, 0.0));
    tracker.updatePosition(const TextPosition(9, 0.0));
    expect(tracker.pendingJump, const TextPosition(9, 0.0));
    expect(tracker.boundary, const TextPosition(5, 0.5));
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

    test('stays before the jump while the reader moves on', () {
      for (final position in const [
        TextPosition(8, 0.0),
        TextPosition(9, 0.1),
        TextPosition(20, 0.0),
        TextPosition(12, 0.0),
      ]) {
        tracker.updatePosition(position);
      }
      expect(tracker.jumpedFrom, const TextPosition(5, 0.5));
    });
  });

  test('confirmJump without a pending jump does nothing', () {
    tracker.confirmJump();
    expect(tracker.boundary, const TextPosition(5, 0.5));
  });

  test('maxJumpSections changes the threshold', () {
    final strict = ReadingProgressTracker(maxJumpSections: 0);
    strict.updatePosition(const TextPosition(0, 0.2));
    expect(strict.pendingJump, isNull);
    strict.updatePosition(const TextPosition(1, 0.0));
    expect(strict.pendingJump, const TextPosition(1, 0.0));
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
      chapter.updatePosition(page55, sectionPages: pages);
      expect(chapter.boundary, page55);
      expect(chapter.pendingJump, isNull);
    });

    test('turning two pages at once moves the boundary', () {
      const page56 = TextPosition(3, 56 / pages);
      chapter.updatePosition(page56, sectionPages: pages);
      expect(chapter.boundary, page56);
    });

    test('a jump of ten pages moves the boundary', () {
      const page64 = TextPosition(3, 64 / pages);
      chapter.updatePosition(page64, sectionPages: pages);
      expect(chapter.boundary, page64);
      expect(chapter.pendingJump, isNull);
    });

    test('a jump of eleven pages waits', () {
      const page65 = TextPosition(3, 65 / pages);
      chapter.updatePosition(page65, sectionPages: pages);
      expect(chapter.boundary, page54);
      expect(chapter.pendingJump, page65);
    });

    test('flipping one page at a time while Readium skips reports is never a '
        'jump', () {
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
        flipping.updatePosition(
          TextPosition(3, progression),
          sectionPages: total,
        );
        expect(flipping.pendingJump, isNull, reason: 'page $page');
      }
      expect(flipping.boundary, const TextPosition(3, 1.0));
    });

    test('a jump of 33 pages waits', () {
      chapter.updatePosition(page87, sectionPages: pages);
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
      short.updatePosition(const TextPosition(3, 1.0), sectionPages: 11);
      expect(short.pendingJump, isNull);
    });

    test('reading on after a jump keeps it waiting, into the next section '
        'too', () {
      chapter.updatePosition(page87, sectionPages: pages);
      for (final (position, sectionPages) in const [
        (TextPosition(3, 88 / pages), pages),
        (TextPosition(3, 95 / pages), pages),
        (TextPosition(3, 1.0), pages),
        // Only one section past the boundary, but past the jump.
        (TextPosition(4, 0), 30),
        (TextPosition(4, 0.1), 30),
      ]) {
        chapter.updatePosition(position, sectionPages: sectionPages);
        expect(chapter.pendingJump, position);
      }
      expect(chapter.boundary, page54);
      chapter.confirmJump();
      expect(chapter.boundary, const TextPosition(4, 0.1));
    });

    group('without a page count', () {
      test('up to 0.3 of the section moves the boundary', () {
        chapter.updatePosition(const TextPosition(3, 0.65));
        expect(chapter.boundary, const TextPosition(3, 0.65));
        expect(chapter.pendingJump, isNull);
      });

      test('more than 0.3 of the section waits', () {
        chapter.updatePosition(const TextPosition(3, 0.9));
        expect(chapter.pendingJump, const TextPosition(3, 0.9));
      });
    });
  });

  group('how far into the book', () {
    late ReadingProgressTracker totals;

    setUp(() {
      totals = ReadingProgressTracker.resume(
        current: const TextPosition(5, 0.5),
        furthest: const TextPosition(5, 0.5),
        boundary: const TextPosition(5, 0.5),
        currentTotal: 0.3,
        boundaryTotal: 0.3,
      );
    });

    test('the boundary takes the total of where it moves to', () {
      totals.updatePosition(const TextPosition(6, 0.1), totalProgression: 0.35);
      expect(totals.boundaryTotal, 0.35);
      expect(totals.currentTotal, 0.35);
    });

    test('going back keeps the boundary\'s total', () {
      totals.updatePosition(const TextPosition(2, 0.1), totalProgression: 0.1);
      expect(totals.boundaryTotal, 0.3);
      expect(totals.currentTotal, 0.1);
    });

    test('a jump keeps the boundary\'s total until it counts as read', () {
      totals.updatePosition(const TextPosition(8, 0), totalProgression: 0.5);
      totals.updatePosition(const TextPosition(9, 0.2), totalProgression: 0.55);
      expect(totals.boundaryTotal, 0.3);
      totals.confirmJump();
      expect(totals.boundaryTotal, 0.55);
    });

    test('is unknown where the reader didn\'t say', () {
      totals.updatePosition(const TextPosition(6, 0.1));
      expect(totals.boundaryTotal, isNull);
      expect(totals.currentTotal, isNull);
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

    test('a tracker saved past the boundary loads with the jump waiting', () {
      tracker.updatePosition(const TextPosition(9, 0.25));
      final decoded = jsonDecode(jsonEncode(tracker.toJson()));
      final loaded = ReadingProgressTracker.fromJson(decoded);
      expect(loaded.pendingJump, const TextPosition(9, 0.25));
      expect(loaded.jumpedFrom, const TextPosition(5, 0.5));
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
