import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reading/passage_extractor.dart';
import 'package:loremark/reading/text_position.dart';

List<String> makeBook(int sectionCount) =>
    List.generate(sectionCount, (i) => 'section $i');

void main() {
  final extractor = PassageExtractor(makeBook(5));

  test('never returns text past the boundary for any input', () {
    for (var bookSize = 0; bookSize <= 4; bookSize++) {
      final book = PassageExtractor(makeBook(bookSize));
      for (var section = 0; section <= 6; section++) {
        for (final progression in [0.0, 0.5, 1.0]) {
          final boundary = TextPosition(section, progression);
          for (var from = 0; from <= 6; from++) {
            final result = book.extract(boundary, fromSection: from);
            for (var i = 0; i < result.length; i++) {
              final index = from + i;
              final finished =
                  index < section || (index == section && progression == 1.0);
              final reason =
                  'book $bookSize, boundary $boundary, from $from, index $index';
              expect(finished, isTrue, reason: reason);
              expect(index, lessThan(bookSize), reason: reason);
              expect(result[i], 'section $index', reason: reason);
            }
          }
        }
      }
    }
  });

  test('empty book returns nothing', () {
    final empty = PassageExtractor([]);
    expect(empty.extract(const TextPosition(3, 1.0)), isEmpty);
    expect(empty.finishedSectionCount(const TextPosition(3, 1.0)), 0);
  });

  test('boundary inside the first section returns nothing', () {
    expect(extractor.extract(const TextPosition(0, 0.0)), isEmpty);
    expect(extractor.extract(const TextPosition(0, 0.5)), isEmpty);
  });

  test('boundary at the end of the first section returns it', () {
    expect(extractor.extract(const TextPosition(0, 1.0)), ['section 0']);
  });

  test('current unfinished section is left out', () {
    expect(extractor.extract(const TextPosition(3, 0.5)), [
      'section 0',
      'section 1',
      'section 2',
    ]);
    expect(extractor.finishedSectionCount(const TextPosition(3, 0.5)), 3);
  });

  test('boundary past the end of the book returns the whole book', () {
    expect(extractor.extract(const TextPosition(9, 0.5)), makeBook(5));
    expect(extractor.finishedSectionCount(const TextPosition(9, 0.5)), 5);
  });

  test('fromSection returns only the sections not processed yet', () {
    expect(extractor.extract(const TextPosition(4, 0.2), fromSection: 2), [
      'section 2',
      'section 3',
    ]);
  });

  test('fromSection at or past the boundary returns nothing', () {
    expect(
      extractor.extract(const TextPosition(3, 0.5), fromSection: 3),
      isEmpty,
    );
    expect(
      extractor.extract(const TextPosition(3, 0.5), fromSection: 10),
      isEmpty,
    );
  });
}
