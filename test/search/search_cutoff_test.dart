import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/search/search_cutoff.dart';
import 'package:loremark/search/search_index.dart';

void main() {
  test('renderer percentages never reveal text in an unfinished section', () {
    // Image-heavy and reflowed pages need not align with text percentages.
    final index = SearchIndex.build(
      bookId: 'image-heavy',
      sectionTexts: ['Known harbor.', 'Secret harbor.'],
    );
    for (final fraction in [0.0, 0.1, 0.5, 0.999999]) {
      final cutoff = completedSectionCutoff(
        current: ReaderPosition(1, fraction),
      );
      expect(cutoff, const ReaderPosition(0, 1));
      expect(
        index.search('harbor', cutoff: cutoff).hits.map((h) => h.passage.text),
        ['Known harbor.'],
      );
    }
    final complete = completedSectionCutoff(
      current: const ReaderPosition(1, 1),
    );
    expect(index.search('harbor', cutoff: complete).hits, hasLength(2));
    expect(
      completedSectionCutoff(current: const ReaderPosition(0, 0.99)),
      const ReaderPosition(0, 0),
    );
    expect(
      completedSectionCutoff(
        current: const ReaderPosition(0, 0.5),
        furthest: const ReaderPosition(2, 0.4),
      ),
      const ReaderPosition(1, 1),
    );
  });

  group('searchCutoff', () {
    test('is the start of the book with no position', () {
      expect(searchCutoff(), const ReaderPosition(0, 0));
    });

    test('is the current position when nothing else is known', () {
      const current = ReaderPosition(2, 0.5);

      expect(searchCutoff(current: current), current);
    });

    test('is the furthest position when there is no current one', () {
      const furthest = ReaderPosition(3, 0.1);

      expect(searchCutoff(furthest: furthest), furthest);
    });

    test('takes the furthest when the reader turned back', () {
      const current = ReaderPosition(1, 0.9);
      const furthest = ReaderPosition(4, 0.2);

      expect(searchCutoff(current: current, furthest: furthest), furthest);
    });

    test('takes the current position when it is past the furthest', () {
      const current = ReaderPosition(4, 0.3);
      const furthest = ReaderPosition(4, 0.2);

      expect(searchCutoff(current: current, furthest: furthest), current);
    });

    test('compares the section before the progression', () {
      const current = ReaderPosition(2, 0.1);
      const furthest = ReaderPosition(1, 1);

      expect(searchCutoff(current: current, furthest: furthest), current);
    });

    test('keeps the current position on a tie', () {
      const current = ReaderPosition(2, 0.5, totalProgression: 0.4);
      const furthest = ReaderPosition(2, 0.5);

      expect(searchCutoff(current: current, furthest: furthest), current);
    });
  });
}
