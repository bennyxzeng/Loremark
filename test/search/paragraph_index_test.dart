import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/search/paragraph_index.dart';

void main() {
  // Section 0: paragraphs at 0..11, 13..18 and 20..29.
  const first = 'Aaaa bbbb c\n\nDdddd\n\nEeee fff.';
  const second = 'Gggg.\n\nHhhh.';

  group('paragraphs', () {
    test('splits on blank lines, with ids in reading order', () {
      final index = ParagraphIndex([first, second]);
      expect(index.count, 5);
      expect(
        [for (var i = 0; i < 5; i++) index.textOf(i)],
        ['Aaaa bbbb c', 'Ddddd', 'Eeee fff.', 'Gggg.', 'Hhhh.'],
      );
      expect(
        [for (var i = 0; i < 5; i++) index.sectionOf(i)],
        [
          0, 0, 0, 1, 1, //
        ],
      );
      expect(
        [for (var i = 0; i < 5; i++) index.ordinalOf(i)],
        [
          0, 1, 2, 0, 1, //
        ],
      );
    });

    test('keeps single line breaks inside a paragraph', () {
      final index = ParagraphIndex(['one\ntwo\n\nthree']);
      expect(index.textOf(0), 'one\ntwo');
      expect(index.count, 2);
    });

    test('ignores empty paragraphs and surrounding whitespace', () {
      final index = ParagraphIndex(['\n\n  a  \n \n\n\n b \n\n']);
      expect(
        [for (var i = 0; i < index.count; i++) index.textOf(i)],
        ['a', 'b'],
      );
      expect(ParagraphIndex(['', '  ']).count, 0);
    });

    test('offsets locate the paragraph in the section text', () {
      final index = ParagraphIndex([first]);
      for (var i = 0; i < index.count; i++) {
        expect(
          first.substring(index.startOf(i), index.endOf(i)),
          index.textOf(i),
        );
      }
    });

    test('progression is the character offset over the section length', () {
      final index = ParagraphIndex([first]);
      expect(index.startProgression(1), 13 / first.length);
      expect(index.endProgression(1), 18 / first.length);
      final passage = index.passage(1);
      expect(passage.sectionIndex, 0);
      expect(passage.paragraphIndex, 1);
      expect(passage.text, 'Ddddd');
      expect(passage.start, ReaderPosition(0, 13 / first.length));
    });

    test('non-linear sections have no paragraphs', () {
      final index = ParagraphIndex(
        [first, 'Footnote text.', second],
        linear: [true, false, true],
      );
      expect(index.count, 5);
      expect(index.sectionOf(3), 2);
      expect(index.sectionTexts[1], '');
      expect(index.idOf(1, 0), isNull);
    });

    test('finds a paragraph by section and position', () {
      final index = ParagraphIndex([first, second]);
      expect(index.idOf(1, 1), 4);
      expect(index.idOf(1, 2), isNull);
      expect(index.idOf(5, 0), isNull);
    });
  });

  group('visibleCount', () {
    final index = ParagraphIndex([first, second, 'Zzzz.']);
    int visible(int section, double progression) =>
        index.visibleCount(ReaderPosition(section, progression));

    test('nothing before the start of the book', () {
      expect(visible(0, 0), 0);
    });

    test('a paragraph counts once it is fully passed', () {
      // The fractions land half a character in, so floating point can't
      // change the whole number they floor to.
      expect(visible(0, 10.5 / first.length), 0);
      expect(visible(0, 11.5 / first.length), 1);
      expect(visible(0, 17.5 / first.length), 1);
      expect(visible(0, 18.5 / first.length), 2);
    });

    test('rounds down, so a straddled paragraph is out', () {
      // 18.9 characters floors to 18: the paragraph ending at 18 is in, the
      // one ending at 29 is not.
      expect(visible(0, 18.9 / first.length), 2);
      expect(visible(0, 28.9 / first.length), 2);
    });

    test('a finished section shows all of it, a fresh one none', () {
      expect(visible(0, 1), 3);
      expect(visible(1, 0), 3);
      expect(visible(1, 1), 5);
      expect(visible(2, 0), 5);
      expect(visible(2, 1), 6);
    });

    test('earlier sections are fully visible whatever the progression', () {
      expect(visible(1, 0.0001), 3);
    });

    test('a position past the book shows everything', () {
      expect(visible(3, 0), 6);
      expect(visible(99, 0.5), 6);
    });

    test('a section without paragraphs adds none', () {
      final gap = ParagraphIndex(
        ['A.\n\nB.', 'footnote', 'C.'],
        linear: [true, false, true],
      );
      expect(gap.visibleCount(const ReaderPosition(1, 0.5)), 2);
      expect(gap.visibleCount(const ReaderPosition(1, 1)), 2);
      expect(gap.visibleCount(const ReaderPosition(2, 1)), 3);
    });

    test('is monotonic in the position', () {
      var previous = 0;
      for (var section = 0; section < 3; section++) {
        for (var step = 0; step <= 100; step++) {
          final count = visible(section, step / 100);
          expect(count, greaterThanOrEqualTo(previous));
          previous = count;
        }
      }
    });
  });

  test('visibleTextEnd stops at the last visible paragraph of the section', () {
    final index = ParagraphIndex([first, second]);
    expect(index.visibleTextEnd(0, 2), index.endOf(1));
    expect(index.visibleTextEnd(0, 4), index.endOf(2));
    expect(index.visibleTextEnd(3, 4), index.endOf(3));
  });
}
