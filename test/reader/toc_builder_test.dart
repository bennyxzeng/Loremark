import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/epub_sections.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/reader/toc_builder.dart';

String words(int n) => List.filled(n, 'word').join(' ');

List<SpineItem> spineOf(int count, {Set<int> nonLinear = const {}}) => [
  for (var i = 0; i < count; i++)
    SpineItem(path: 'c$i.xhtml', linear: !nonLinear.contains(i)),
];

void main() {
  group('readingUnits', () {
    test('counts words split by whitespace', () {
      expect(readingUnits('one two  three\nfour\tfive'), 5);
      expect(readingUnits(''), 0);
      expect(readingUnits('   \n  '), 0);
    });

    test('counts each Chinese, Japanese or Korean character as 0.6', () {
      expect(readingUnits('你好世界你好世界你好'), closeTo(6, 1e-9));
      expect(readingUnits('こんにちは'), closeTo(3, 1e-9));
      expect(readingUnits('한국어'), closeTo(1.8, 1e-9));
    });

    test('adds words and characters in mixed text', () {
      expect(readingUnits('hello 世界 world'), closeTo(3.2, 1e-9));
    });
  });

  group('sectionsWithoutToc', () {
    test('is empty for a book too short to cut', () {
      expect(sectionsWithoutToc([words(100)], spineOf(1)), isEmpty);
      expect(sectionsWithoutToc([words(7400)], spineOf(1)), isEmpty);
      expect(sectionsWithoutToc(const [], const []), isEmpty);
    });

    test('is empty when the book has no text', () {
      expect(sectionsWithoutToc(['', ' '], spineOf(2)), isEmpty);
    });

    test('cuts a long file by the share of its words', () {
      final entries = sectionsWithoutToc([words(12000)], spineOf(1));

      expect(entries.map((e) => e.title), ['Section 1', 'Section 2']);
      expect(entries[0].position, const ReaderPosition(0, 0));
      expect(entries[1].position!.sectionIndex, 0);
      expect(entries[1].position!.progression, closeTo(0.5, 1e-9));
    });

    test('moves a cut that is near a file start to that start', () {
      // Four files of 3,000 words: the cut at 6,000 is the start of file 2.
      final entries = sectionsWithoutToc([
        for (var i = 0; i < 4; i++) words(3000),
      ], spineOf(4));

      expect(entries.map((e) => e.position), [
        const ReaderPosition(0, 0),
        const ReaderPosition(2, 0),
      ]);
    });

    test('keeps a cut inside a file when no start is close', () {
      // 100 + 11,900: the cut at 6,000 is mid-file, far from both starts.
      final entries = sectionsWithoutToc([
        words(100),
        words(11900),
      ], spineOf(2));

      expect(entries[1].position!.sectionIndex, 1);
      expect(entries[1].position!.progression, closeTo(5900 / 11900, 1e-6));
    });

    test('starts at the first file that has text', () {
      final entries = sectionsWithoutToc([
        '',
        words(500),
        words(11500),
      ], spineOf(3));

      expect(entries.first.position!.sectionIndex, 1);
    });

    test('leaves out files the reader does not turn through', () {
      final entries = sectionsWithoutToc([
        words(6000),
        words(50000),
        words(6000),
      ], spineOf(3, nonLinear: {1}));

      expect(entries, hasLength(2));
      expect(entries.map((e) => e.sectionIndex), isNot(contains(1)));
    });

    test('makes about one section for every 5,000 words', () {
      for (final total in [10000, 25000, 100000, 580000]) {
        final entries = sectionsWithoutToc([words(total)], spineOf(1));
        expect(
          entries.length,
          (total / wordsPerSection).round(),
          reason: '$total',
        );
      }
    });

    test('makes sections of similar length', () {
      final entries = sectionsWithoutToc([words(52000)], spineOf(1));
      final shares = [for (final e in entries) e.position!.progression, 1.0];
      for (var i = 1; i < shares.length; i++) {
        final length = (shares[i] - shares[i - 1]) * 52000;
        expect(length, inInclusiveRange(4500, 5500));
      }
    });

    test('puts sections in reading order, each after the one before', () {
      final entries = sectionsWithoutToc([
        words(900),
        words(30000),
        words(20),
        words(40000),
      ], spineOf(4));

      for (var i = 1; i < entries.length; i++) {
        final before = entries[i - 1].position!;
        final after = entries[i].position!;
        final later =
            after.sectionIndex > before.sectionIndex ||
            (after.sectionIndex == before.sectionIndex &&
                after.progression > before.progression);
        expect(later, isTrue, reason: '$before then $after');
      }
    });

    test('numbers sections from 1 and points them at their file', () {
      final entries = sectionsWithoutToc([words(30000)], spineOf(1));

      for (var i = 0; i < entries.length; i++) {
        expect(entries[i].title, 'Section ${i + 1}');
        expect(entries[i].href, isEmpty);
        expect(entries[i].isSynthetic, isTrue);
        expect(entries[i].sectionIndex, entries[i].position!.sectionIndex);
        expect(entries[i].depth, 0);
      }
    });

    test('sizes Chinese text by characters', () {
      // 20,000 characters is about 12,000 words, two sections.
      final entries = sectionsWithoutToc(['汉' * 20000], spineOf(1));

      expect(entries, hasLength(2));
    });

    test('never lands on the end of a file', () {
      final entries = sectionsWithoutToc([words(99999)], spineOf(1));

      for (final e in entries) {
        expect(e.position!.progression, lessThan(1));
      }
    });

    test('takes another section length', () {
      final entries = sectionsWithoutToc(
        [words(1000)],
        spineOf(1),
        wordsPerSection: 100,
      );

      expect(entries, hasLength(10));
    });

    test('needs one text for every spine item', () {
      expect(
        () => sectionsWithoutToc([words(10)], spineOf(2)),
        throwsArgumentError,
      );
      expect(
        () => sectionsWithoutToc([words(10)], spineOf(1), wordsPerSection: 0),
        throwsArgumentError,
      );
    });

    test('copes with a thousand files', () {
      final entries = sectionsWithoutToc([
        for (var i = 0; i < 1000; i++) words(300),
      ], spineOf(1000));

      expect(entries, hasLength(60));
    });
  });
}
