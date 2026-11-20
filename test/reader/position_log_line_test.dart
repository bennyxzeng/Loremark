import 'dart:convert';

import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/readium_reader_service.dart';

Locator _locator({Map<String, dynamic>? extra}) => Locator(
  href: 'OEBPS/ch3.xhtml',
  type: 'application/xhtml+xml',
  locations: Locations(progression: 0.25, additionalProperties: extra ?? {}),
);

void main() {
  group('positionLogLine', () {
    final now = DateTime.utc(2026, 11, 1, 12);
    const prefix = 'LOREMARK_POSITION ';

    test('prints section, progression and page numbers as one JSON line', () {
      final line = positionLogLine(
        _locator(extra: {'currentPage': 2, 'totalPages': 8}),
        4,
        now: now,
      );

      expect(line, startsWith(prefix));
      expect(line, isNot(contains('\n')));
      expect(jsonDecode(line!.substring(prefix.length)), {
        'section': 4,
        'progression': 0.25,
        'currentPage': 2,
        'totalPages': 8,
        'tUs': now.microsecondsSinceEpoch,
      });
    });

    test('adds where the page starts when the locator has it', () {
      const selector = r"[src='images\/010\.jpg']";
      final line = positionLogLine(
        Locator(
          href: 'OEBPS/ch3.xhtml',
          type: 'application/xhtml+xml',
          locations: Locations(
            progression: 0.25,
            cssSelector: selector,
            additionalProperties: {'currentPage': 2, 'totalPages': 8},
          ),
        ),
        4,
        now: now,
      );

      expect(
        jsonDecode(line!.substring(prefix.length))['cssSelector'],
        selector,
      );
    });

    test('skips the bare locator that has no page numbers', () {
      expect(positionLogLine(_locator(), 4, now: now), isNull);
      expect(
        positionLogLine(_locator(extra: {'currentPage': 2}), 4, now: now),
        isNull,
      );
    });

    test('keeps a null section for an href outside the spine', () {
      final line = positionLogLine(
        _locator(extra: {'currentPage': 0, 'totalPages': 1}),
        null,
        now: now,
      );

      expect(jsonDecode(line!.substring(prefix.length))['section'], isNull);
    });
  });
}
