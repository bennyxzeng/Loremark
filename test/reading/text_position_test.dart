import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reading/text_position.dart';

void main() {
  group('compareTo', () {
    test('earlier section is before later section', () {
      expect(const TextPosition(1, 0.9) < const TextPosition(2, 0.1), isTrue);
    });

    test('same section compares by progression', () {
      expect(const TextPosition(3, 0.2) < const TextPosition(3, 0.5), isTrue);
      expect(const TextPosition(3, 0.5) > const TextPosition(3, 0.2), isTrue);
    });

    test('<= and >= include equal positions', () {
      const a = TextPosition(3, 0.5);
      expect(a <= const TextPosition(3, 0.5), isTrue);
      expect(a >= const TextPosition(3, 0.5), isTrue);
      expect(a <= const TextPosition(3, 0.4), isFalse);
      expect(a >= const TextPosition(3, 0.6), isFalse);
    });

    test('sorts a list in reading order', () {
      final positions = [
        const TextPosition(2, 0.0),
        const TextPosition(0, 0.5),
        const TextPosition(2, 0.3),
        const TextPosition(1, 1.0),
      ]..sort();
      expect(positions, [
        const TextPosition(0, 0.5),
        const TextPosition(1, 1.0),
        const TextPosition(2, 0.0),
        const TextPosition(2, 0.3),
      ]);
    });
  });

  test('equal positions are equal and have the same hashCode', () {
    const a = TextPosition(4, 0.25);
    const b = TextPosition(4, 0.25);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.compareTo(b), 0);
  });

  group('json', () {
    test('round trip through a JSON string keeps the exact position', () {
      const position = TextPosition(12, 0.3333333333333333);
      final decoded = jsonDecode(jsonEncode(position.toJson()));
      expect(TextPosition.fromJson(decoded), position);
    });

    test('accepts an int progression', () {
      expect(
        TextPosition.fromJson({'sectionIndex': 2, 'progression': 1}),
        const TextPosition(2, 1.0),
      );
    });

    test('throws FormatException on invalid data', () {
      final invalid = <Map<String, dynamic>>[
        {},
        {'sectionIndex': 1},
        {'sectionIndex': '1', 'progression': 0.5},
        {'sectionIndex': 1.5, 'progression': 0.5},
        {'sectionIndex': -1, 'progression': 0.5},
        {'sectionIndex': 1, 'progression': -0.1},
        {'sectionIndex': 1, 'progression': 1.1},
      ];
      for (final json in invalid) {
        expect(
          () => TextPosition.fromJson(json),
          throwsFormatException,
          reason: '$json',
        );
      }
    });
  });
}
