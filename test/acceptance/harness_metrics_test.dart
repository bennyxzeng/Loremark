import 'package:flutter_test/flutter_test.dart';

import '../../tool/acceptance/metrics.dart';

PagePosition _at(int section, int page, {int pages = 10}) =>
    PagePosition(section: section, page: page, pages: pages);

void main() {
  group('pageDistance', () {
    test('is the page difference inside one section, in either order', () {
      expect(pageDistance(_at(2, 4), _at(2, 4)), 0);
      expect(pageDistance(_at(2, 4), _at(2, 5)), 1);
      expect(pageDistance(_at(2, 5), _at(2, 4)), 1);
      expect(pageDistance(_at(2, 1), _at(2, 8)), 7);
    });

    test('counts turns through the boundary of neighbouring sections', () {
      // Last page of section 2 to the first page of section 3: one turn.
      expect(pageDistance(_at(2, 9), _at(3, 0, pages: 6)), 1);
      // Second to last page to the second page of the next section: three.
      expect(pageDistance(_at(2, 8), _at(3, 1, pages: 6)), 3);
      // Backwards is the same distance.
      expect(pageDistance(_at(3, 1, pages: 6), _at(2, 8)), 3);
    });

    test('cannot compare far-apart sections', () {
      expect(pageDistance(_at(2, 4), _at(4, 4)), isNull);
      expect(pageDistance(_at(9, 0), _at(1, 0)), isNull);
    });

    test('reports a repaginated section as not comparable', () {
      expect(pageDistance(_at(2, 4), _at(2, 4, pages: 11)), isNull);
    });
  });

  group('PagePosition.fromProgression', () {
    test('puts a saved page start back on its page', () {
      for (var pages = 1; pages <= 40; pages++) {
        for (var page = 0; page < pages; page++) {
          final p = PagePosition.fromProgression(
            section: 1,
            progression: page / pages,
            pages: pages,
          );
          expect(p.page, page, reason: 'page $page of $pages');
        }
      }
    });

    test('clamps the finished section to its last page', () {
      final p = PagePosition.fromProgression(
        section: 1,
        progression: 1.0,
        pages: 18,
      );

      expect(p.page, 17);
      expect(p.isLastPage, isTrue);
    });

    test('clamps an out-of-range progression', () {
      expect(
        PagePosition.fromProgression(
          section: 0,
          progression: -0.2,
          pages: 5,
        ).page,
        0,
      );
    });
  });

  group('parsePositionLines', () {
    const line =
        '1762000000.123  4242  4260 I flutter : LOREMARK_POSITION '
        '{"section":3,"progression":0.25,"currentPage":2,"totalPages":8,"tUs":5}';

    test('reads the app line out of logcat noise, in order', () {
      final log = [
        '1762000000.001  1  1 I ActivityManager: Start proc',
        line,
        '1762000000.200  4242  4260 I flutter : unrelated output',
        line.replaceAll('"currentPage":2', '"currentPage":3'),
      ].join('\n');

      final positions = parsePositionLines(log);

      expect(positions, hasLength(2));
      expect(positions.first.section, 3);
      expect(positions.first.page, 2);
      expect(positions.first.pages, 8);
      expect(positions.first.progression, 0.25);
      expect(positions.last.page, 3);
    });

    test('skips lines with broken or incomplete JSON', () {
      final log = [
        'I flutter : LOREMARK_POSITION {"section":3,',
        'I flutter : LOREMARK_POSITION not json',
        'I flutter : LOREMARK_POSITION {"section":3}',
        'I flutter : LOREMARK_POSITION []',
        line,
      ].join('\n');

      expect(parsePositionLines(log), hasLength(1));
    });

    test('handles CRLF line endings', () {
      expect(parsePositionLines('$line\r\n$line\r\n'), hasLength(2));
    });
  });
}
