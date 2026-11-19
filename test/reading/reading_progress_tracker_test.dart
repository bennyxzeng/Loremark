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
    tracker.updatePosition(const TextPosition(5, 0.7));
    expect(tracker.current, const TextPosition(5, 0.7));
    expect(tracker.furthest, const TextPosition(5, 0.7));
    expect(tracker.boundary, const TextPosition(5, 0.7));
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
    tracker.updatePosition(const TextPosition(5, 0.6));
    expect(tracker.pendingJump, isNull);
    expect(tracker.boundary, const TextPosition(5, 0.6));
    tracker.confirmJump();
    expect(tracker.boundary, const TextPosition(5, 0.6));
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

  group('into the next section', () {
    // Section 3 has 20 pages, section 4 has 30.
    ReadingProgressTracker from(TextPosition boundary) =>
        ReadingProgressTracker.resume(
          current: boundary,
          furthest: boundary,
          boundary: boundary,
        );

    test('from the last page moves the boundary', () {
      final reading = from(const TextPosition(3, 15 / 20));
      reading.updatePosition(const TextPosition(3, 1.0), sectionPages: 20);
      reading.updatePosition(const TextPosition(4, 0), sectionPages: 30);
      expect(reading.pendingJump, isNull);
      expect(reading.boundary, const TextPosition(4, 0));
    });

    test('with the reports of the last pages dropped moves the boundary', () {
      final reading = from(const TextPosition(3, 10 / 20));
      reading.updatePosition(const TextPosition(3, 17 / 20), sectionPages: 20);
      reading.updatePosition(const TextPosition(4, 1 / 30), sectionPages: 30);
      expect(reading.pendingJump, isNull);
    });

    test('from the middle of a chapter is a jump', () {
      final reading = from(const TextPosition(3, 0));
      reading.updatePosition(const TextPosition(3, 5 / 20), sectionPages: 20);
      reading.updatePosition(const TextPosition(4, 0), sectionPages: 30);
      expect(reading.pendingJump, const TextPosition(4, 0));
      expect(reading.boundary, const TextPosition(3, 5 / 20));
    });

    test('two sections on is a jump, even from the last page', () {
      final reading = from(const TextPosition(3, 1.0));
      reading.updatePosition(const TextPosition(5, 0), sectionPages: 30);
      expect(reading.pendingJump, const TextPosition(5, 0));
    });

    test('after Count as read is still counted in pages', () {
      final reading = from(const TextPosition(3, 0));
      reading.updatePosition(const TextPosition(3, 12 / 20), sectionPages: 20);
      reading.confirmJump();
      // Eight pages on. By its share of the section, 0.4 of it was left,
      // which would be a jump.
      reading.updatePosition(const TextPosition(4, 0), sectionPages: 30);
      expect(reading.pendingJump, isNull);
    });

    group('without a page count', () {
      test('from near the end moves the boundary', () {
        final reading = from(const TextPosition(3, 0.9));
        reading.updatePosition(const TextPosition(4, 0.1));
        expect(reading.boundary, const TextPosition(4, 0.1));
      });

      test('from the middle is a jump', () {
        final reading = from(const TextPosition(3, 0.5));
        reading.updatePosition(const TextPosition(4, 0));
        expect(reading.pendingJump, const TextPosition(4, 0));
      });
    });
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

  group('flipping fast', () {
    // Section 3 has 40 pages, the reader is on page 10 of it.
    const pages = 40;
    TextPosition page(int index) => TextPosition(3, index / pages);
    const fast = Duration(seconds: 1);
    const slow = Duration(seconds: 40);
    late ReadingProgressTracker flipping;
    late DateTime clock;

    setUp(() {
      flipping = ReadingProgressTracker.resume(
        current: page(10),
        furthest: page(10),
        boundary: page(10),
      );
      clock = DateTime(2026, 11, 19, 20);
    });

    void turnTo(int index, {required Duration after}) {
      clock = clock.add(after);
      flipping.updatePosition(
        page(index),
        sectionPages: pages,
        totalProgression: index / 100,
        at: clock,
      );
    }

    /// Reads page 10, then flips through pages 11 to 15 on to 16.
    void flipToPage16() {
      turnTo(11, after: slow);
      for (var index = 12; index <= 16; index++) {
        turnTo(index, after: fast);
      }
    }

    test('five pages past the boundary are a jump from where it began', () {
      flipToPage16();
      expect(flipping.boundary, page(11));
      expect(flipping.boundaryTotal, 0.11);
      expect(flipping.pendingJump, page(16));
      expect(flipping.jumpedFrom, page(11));
      expect(flipping.flippedAhead, isTrue);
    });

    test('four pages, then one read, count as read, and the count starts '
        'over', () {
      turnTo(11, after: slow);
      for (var index = 12; index <= 15; index++) {
        turnTo(index, after: fast);
      }
      turnTo(16, after: slow);
      expect(flipping.boundary, page(16));
      expect(flipping.pendingJump, isNull);

      for (var index = 17; index <= 20; index++) {
        turnTo(index, after: fast);
      }
      expect(flipping.boundary, page(20));
      expect(flipping.pendingJump, isNull);
    });

    test('a page every two seconds is reading', () {
      for (var index = 11; index <= 30; index++) {
        turnTo(index, after: const Duration(seconds: 2));
      }
      expect(flipping.boundary, page(30));
      expect(flipping.pendingJump, isNull);
    });

    test('back and forth over read pages doesn’t count them', () {
      turnTo(11, after: slow);
      for (final index in const [12, 13, 12, 11, 12, 13, 14]) {
        turnTo(index, after: fast);
      }
      // Only 12, 13 and 14 were new.
      expect(flipping.boundary, page(14));
      expect(flipping.pendingJump, isNull);
    });

    test('going back doesn’t end the flipping', () {
      turnTo(11, after: slow);
      for (final index in const [12, 13, 14, 13, 14, 15, 16]) {
        turnTo(index, after: fast);
      }
      expect(flipping.boundary, page(11));
      expect(flipping.pendingJump, page(16));
    });

    test('pages Readium didn’t report count too', () {
      turnTo(11, after: slow);
      turnTo(13, after: fast);
      turnTo(15, after: fast);
      expect(flipping.pendingJump, isNull);
      turnTo(17, after: fast);
      expect(flipping.boundary, page(11));
      expect(flipping.pendingJump, page(17));
    });

    test('a step without a page count is one page', () {
      flipping.updatePosition(const TextPosition(3, 0.26), at: clock);
      for (final progression in const [0.27, 0.28, 0.29, 0.30]) {
        clock = clock.add(fast);
        flipping.updatePosition(TextPosition(3, progression), at: clock);
      }
      expect(flipping.pendingJump, isNull);
      clock = clock.add(fast);
      flipping.updatePosition(const TextPosition(3, 0.31), at: clock);
      expect(flipping.boundary, const TextPosition(3, 0.26));
      expect(flipping.pendingJump, const TextPosition(3, 0.31));
    });

    test('into the next section counts the pages left in this one', () {
      flipping = ReadingProgressTracker.resume(
        current: page(36),
        furthest: page(36),
        boundary: page(36),
      );
      // Read, so the boundary's page count is known.
      turnTo(37, after: slow);
      turnTo(38, after: fast);
      turnTo(pages, after: fast);
      for (final index in const [0, 1]) {
        clock = clock.add(fast);
        flipping.updatePosition(
          TextPosition(4, index / 30),
          sectionPages: 30,
          at: clock,
        );
      }
      expect(flipping.pendingJump, isNull);
      clock = clock.add(fast);
      flipping.updatePosition(
        const TextPosition(4, 2 / 30),
        sectionPages: 30,
        at: clock,
      );
      expect(flipping.boundary, page(37));
      expect(flipping.pendingJump, const TextPosition(4, 2 / 30));
    });

    test('reading a page back from where it got to still waits', () {
      flipToPage16();
      turnTo(15, after: slow);
      expect(flipping.boundary, page(11));
      expect(flipping.pendingJump, page(15));
      expect(flipping.flippedAhead, isTrue);
    });

    test('going back to where it began drops the jump', () {
      flipToPage16();
      turnTo(11, after: fast);
      expect(flipping.pendingJump, isNull);
      expect(flipping.flippedAhead, isFalse);
      expect(flipping.boundary, page(11));
    });

    test('after Count as read, counts from the reader', () {
      flipToPage16();
      flipping.confirmJump();
      expect(flipping.boundary, page(16));
      expect(flipping.flippedAhead, isFalse);

      for (var index = 17; index <= 20; index++) {
        turnTo(index, after: fast);
      }
      expect(flipping.pendingJump, isNull);
      turnTo(21, after: fast);
      expect(flipping.boundary, page(16));
      expect(flipping.pendingJump, page(21));
    });

    test('a jump while flipping is asked about, not flipping', () {
      turnTo(11, after: slow);
      turnTo(12, after: fast);
      turnTo(30, after: fast);
      expect(flipping.boundary, page(12));
      expect(flipping.pendingJump, page(30));
      expect(flipping.flippedAhead, isFalse);
    });

    test('without the time nothing is flipping', () {
      for (var index = 11; index <= 30; index++) {
        flipping.updatePosition(page(index), sectionPages: pages);
      }
      expect(flipping.boundary, page(30));
      expect(flipping.pendingJump, isNull);
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
      totals.updatePosition(const TextPosition(5, 0.6), totalProgression: 0.35);
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
      totals.updatePosition(const TextPosition(5, 0.6));
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
