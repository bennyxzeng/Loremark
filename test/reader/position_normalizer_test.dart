import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/epub_sections.dart';
import 'package:loremark/reader/position_normalizer.dart';
import 'package:loremark/reader/reader_position.dart';

List<SpineItem> spineOf(String shape) => [
  for (var i = 0; i < shape.length; i++)
    SpineItem(path: 'ch$i.xhtml', linear: shape[i] == 'L'),
];

void main() {
  // Sections 0 and 1 are linear, 2 and 3 are not, 4 and 5 are linear, 6 is not.
  final spine = spineOf('LLNNLLN');
  late PositionNormalizer normalizer;

  setUp(() => normalizer = PositionNormalizer(spine));

  group('normalize', () {
    test('reports the first position as it is', () {
      expect(normalizer.normalize(const ReaderPosition(1, 0.25)), [
        const ReaderPosition(1, 0.25),
      ]);
    });

    test('snaps a chapter end to exactly 1.0', () {
      final result = normalizer.normalize(
        const ReaderPosition(0, 1 - 1e-9, totalProgression: 0.9999),
      );

      expect(result.single.progression, 1.0);
      expect(result.single.totalProgression, 1.0);
    });

    test('snaps 0.9995 to 1.0 and leaves 0.998 alone', () {
      expect(
        normalizer.normalize(const ReaderPosition(0, 0.9995)).single,
        const ReaderPosition(0, 1.0),
      );
      expect(
        PositionNormalizer(spine)
            .normalize(const ReaderPosition(0, 0.998))
            .single,
        const ReaderPosition(0, 0.998),
      );
    });

    test('does not snap values near 0', () {
      expect(
        normalizer.normalize(const ReaderPosition(0, 0.0005)).single,
        const ReaderPosition(0, 0.0005),
      );
    });

    test('clamps out-of-range values into 0 to 1', () {
      expect(
        normalizer
            .normalize(const ReaderPosition(0, -0.5, totalProgression: 3))
            .single,
        const ReaderPosition(0, 0, totalProgression: 1),
      );
      expect(
        normalizer.normalize(const ReaderPosition(0, 7)).single,
        const ReaderPosition(0, 1),
      );
    });

    test('treats a NaN progression as the start', () {
      expect(
        normalizer.normalize(const ReaderPosition(0, double.nan)).single,
        const ReaderPosition(0, 0),
      );
    });

    test('suppresses a repeat of the last position', () {
      normalizer.normalize(const ReaderPosition(0, 0.5, totalProgression: 0.1));

      expect(
        normalizer.normalize(
          const ReaderPosition(0, 0.5, totalProgression: 0.1),
        ),
        isEmpty,
      );
    });

    test('suppresses a repeat that only matches after snapping', () {
      normalizer.normalize(const ReaderPosition(0, 1.0));

      expect(normalizer.normalize(const ReaderPosition(0, 0.9995)), isEmpty);
    });

    test('reports a change within the same section', () {
      normalizer.normalize(const ReaderPosition(0, 0.5));

      expect(normalizer.normalize(const ReaderPosition(0, 0.6)), [
        const ReaderPosition(0, 0.6),
      ]);
    });

    test('finishes the section when turning into the next one', () {
      normalizer.normalize(const ReaderPosition(0, 0.9, totalProgression: 0.2));

      expect(
        normalizer.normalize(
          const ReaderPosition(1, 0, totalProgression: 0.25),
        ),
        [
          const ReaderPosition(0, 1.0, totalProgression: 0.25),
          const ReaderPosition(1, 0, totalProgression: 0.25),
        ],
      );
    });

    test('finishes without a total when the renderer gives none', () {
      normalizer.normalize(const ReaderPosition(0, 0.9));

      expect(normalizer.normalize(const ReaderPosition(1, 0)), [
        const ReaderPosition(0, 1.0),
        const ReaderPosition(1, 0),
      ]);
    });

    test('does not finish the section when mayFinishPrevious is false', () {
      normalizer.normalize(const ReaderPosition(0, 0.4));

      expect(
        normalizer.normalize(
          const ReaderPosition(1, 0),
          mayFinishPrevious: false,
        ),
        [const ReaderPosition(1, 0)],
      );
    });

    test('still suppresses repeats when mayFinishPrevious is false', () {
      normalizer.normalize(const ReaderPosition(1, 0.5));

      expect(
        normalizer.normalize(
          const ReaderPosition(1, 0.5),
          mayFinishPrevious: false,
        ),
        isEmpty,
      );
    });

    test('finishes the section when turning across non-linear items', () {
      normalizer.normalize(const ReaderPosition(1, 0.8));

      expect(normalizer.normalize(const ReaderPosition(4, 0)), [
        const ReaderPosition(1, 1.0),
        const ReaderPosition(4, 0),
      ]);
    });

    test('does not finish a section that is already at 1.0', () {
      normalizer.normalize(const ReaderPosition(0, 1.0));

      expect(normalizer.normalize(const ReaderPosition(1, 0)), [
        const ReaderPosition(1, 0),
      ]);
    });

    test('adds no synthetic 1.0 for a jump over linear sections', () {
      normalizer.normalize(const ReaderPosition(0, 0.5));

      expect(normalizer.normalize(const ReaderPosition(5, 0.1)), [
        const ReaderPosition(5, 0.1),
      ]);
    });

    test(
      'adds no synthetic 1.0 when only some skipped items are non-linear',
      () {
        normalizer.normalize(const ReaderPosition(1, 0.5));

        // 2 and 3 are non-linear but 4 is linear.
        expect(normalizer.normalize(const ReaderPosition(5, 0)), [
          const ReaderPosition(5, 0),
        ]);
      },
    );

    test('adds no synthetic 1.0 when moving backwards', () {
      normalizer.normalize(const ReaderPosition(1, 0.5));

      expect(normalizer.normalize(const ReaderPosition(0, 0.9)), [
        const ReaderPosition(0, 0.9),
      ]);
      expect(normalizer.normalize(const ReaderPosition(0, 0.2)), [
        const ReaderPosition(0, 0.2),
      ]);
    });

    test('remembers only the reported position, not the synthetic one', () {
      normalizer.normalize(const ReaderPosition(0, 0.9));
      normalizer.normalize(const ReaderPosition(1, 0));

      // Going back to the end of section 0 is a plain backward move.
      expect(normalizer.normalize(const ReaderPosition(0, 1.0)), [
        const ReaderPosition(0, 1.0),
      ]);
    });

    test('adds no synthetic 1.0 when the spine is shorter than the jump', () {
      normalizer.normalize(const ReaderPosition(6, 0.5));

      expect(normalizer.normalize(const ReaderPosition(9, 0)), [
        const ReaderPosition(9, 0),
      ]);
    });
  });

  group('finish', () {
    test('reports the last linear section as finished', () {
      expect(normalizer.finish(), [
        const ReaderPosition(5, 1.0, totalProgression: 1.0),
      ]);
    });

    test(
      'finishes the earlier section when only non-linear items lie between',
      () {
        normalizer = PositionNormalizer(spineOf('LLLNNL'));
        normalizer.normalize(const ReaderPosition(2, 0.95));

        expect(normalizer.finish(), [
          const ReaderPosition(2, 1.0, totalProgression: 1.0),
          const ReaderPosition(5, 1.0, totalProgression: 1.0),
        ]);
      },
    );

    test('does not finish an earlier section with linear sections between', () {
      normalizer.normalize(const ReaderPosition(0, 0.5));

      expect(normalizer.finish(), [
        const ReaderPosition(5, 1.0, totalProgression: 1.0),
      ]);
    });

    test('does not add a synthetic 1.0 for a section already at 1.0', () {
      normalizer = PositionNormalizer(spineOf('LLNL'));
      normalizer.normalize(const ReaderPosition(1, 1.0));

      expect(normalizer.finish(), [
        const ReaderPosition(3, 1.0, totalProgression: 1.0),
      ]);
    });

    test('reports only the end when the reader is in the last section', () {
      normalizer.normalize(const ReaderPosition(5, 0.9, totalProgression: 0.9));

      expect(normalizer.finish(), [
        const ReaderPosition(5, 1.0, totalProgression: 1.0),
      ]);
    });

    test('reports nothing if the end was already reported', () {
      normalizer.normalize(const ReaderPosition(5, 1.0, totalProgression: 1.0));

      expect(normalizer.finish(), isEmpty);
    });

    test('reports nothing twice', () {
      normalizer.finish();

      expect(normalizer.finish(), isEmpty);
    });

    test('drops a repeat of the end reported by finish', () {
      normalizer.finish();

      expect(
        normalizer.normalize(
          const ReaderPosition(5, 0.9999, totalProgression: 1.0),
        ),
        isEmpty,
      );
    });

    test('reports nothing for an empty spine', () {
      expect(PositionNormalizer(const []).finish(), isEmpty);
    });

    test('reports nothing if every section is non-linear', () {
      expect(PositionNormalizer(spineOf('NN')).finish(), isEmpty);
    });
  });
}
