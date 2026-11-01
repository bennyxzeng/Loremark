import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/reader_position.dart';

void main() {
  group('JSON', () {
    test('round trips a position with a total', () {
      const position = ReaderPosition(3, 0.25, totalProgression: 0.4);

      final decoded = ReaderPosition.fromJson(
        jsonDecode(jsonEncode(position.toJson())) as Map<String, dynamic>,
      );

      expect(decoded, position);
    });

    test('round trips a position without a total', () {
      const position = ReaderPosition(0, 1.0);

      final json = jsonDecode(jsonEncode(position.toJson()));

      expect(json, {'sectionIndex': 0, 'progression': 1.0});
      expect(ReaderPosition.fromJson(json as Map<String, dynamic>), position);
    });

    test('reads whole numbers as doubles', () {
      final position = ReaderPosition.fromJson({
        'sectionIndex': 2,
        'progression': 1,
        'totalProgression': 0,
      });

      expect(position, const ReaderPosition(2, 1.0, totalProgression: 0.0));
    });

    test('accepts the ends of the range', () {
      expect(
        ReaderPosition.fromJson({'sectionIndex': 0, 'progression': 0.0}),
        const ReaderPosition(0, 0),
      );
      expect(
        ReaderPosition.fromJson({
          'sectionIndex': 0,
          'progression': 1.0,
          'totalProgression': 1.0,
        }),
        const ReaderPosition(0, 1, totalProgression: 1),
      );
    });
  });

  group('validation', () {
    void rejects(String name, Map<String, dynamic> json) {
      test('rejects $name', () {
        expect(() => ReaderPosition.fromJson(json), throwsFormatException);
      });
    }

    rejects('an empty map', {});
    rejects('a missing section index', {'progression': 0.5});
    rejects('a missing progression', {'sectionIndex': 1});
    rejects('a negative section index', {
      'sectionIndex': -1,
      'progression': 0.5,
    });
    rejects('a fractional section index', {
      'sectionIndex': 1.5,
      'progression': 0.5,
    });
    rejects('a string section index', {
      'sectionIndex': '1',
      'progression': 0.5,
    });
    rejects('a string progression', {'sectionIndex': 1, 'progression': '0.5'});
    rejects('a progression below 0', {'sectionIndex': 1, 'progression': -0.1});
    rejects('a progression above 1', {'sectionIndex': 1, 'progression': 1.1});
    rejects('a NaN progression', {
      'sectionIndex': 1,
      'progression': double.nan,
    });
    rejects('a total below 0', {
      'sectionIndex': 1,
      'progression': 0.5,
      'totalProgression': -0.1,
    });
    rejects('a total above 1', {
      'sectionIndex': 1,
      'progression': 0.5,
      'totalProgression': 2,
    });
    rejects('a non-numeric total', {
      'sectionIndex': 1,
      'progression': 0.5,
      'totalProgression': 'half',
    });
  });

  group('equality', () {
    test('equal positions are equal and share a hash code', () {
      const a = ReaderPosition(1, 0.5, totalProgression: 0.2);
      const b = ReaderPosition(1, 0.5, totalProgression: 0.2);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('any differing field makes positions unequal', () {
      const base = ReaderPosition(1, 0.5, totalProgression: 0.2);

      expect(base, isNot(const ReaderPosition(2, 0.5, totalProgression: 0.2)));
      expect(base, isNot(const ReaderPosition(1, 0.6, totalProgression: 0.2)));
      expect(base, isNot(const ReaderPosition(1, 0.5, totalProgression: 0.3)));
      expect(base, isNot(const ReaderPosition(1, 0.5)));
    });
  });
}
