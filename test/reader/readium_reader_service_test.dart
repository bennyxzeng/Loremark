import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/epub_reader_service.dart';
import 'package:loremark/reader/epub_sections.dart';
import 'package:loremark/reader/readium_reader_service.dart';
import 'package:loremark/reader/reader_position.dart';

const _xhtml = 'application/xhtml+xml';

/// Hrefs as Readium reports them for the Android probe book: relative to the
/// archive root, percent-encoded, section links without a fragment.
const _hrefs = [
  'OEBPS/cover.xhtml',
  'OEBPS/ch1.xhtml',
  'OEBPS/Chap%20ter%203%20%C3%A9.xhtml',
];

/// A stand-in for `spineIndexOf` that knows exactly [_hrefs], so these tests
/// cover the adapter's mapping on its own.
int? _indexOf(String href) {
  final path = href.split('#').first;
  final index = _hrefs.indexOf(path);
  return index == -1 ? null : index;
}

Locator _locator(String href, {double? progression, double? total}) => Locator(
  href: href,
  type: _xhtml,
  locations: Locations(progression: progression, totalProgression: total),
);

void main() {
  group('positionFromLocator', () {
    test('maps section, progression and totalProgression', () {
      final position = positionFromLocator(
        _locator('OEBPS/ch1.xhtml', progression: 0.4, total: 0.25),
        _indexOf,
      );

      expect(position, const ReaderPosition(1, 0.4, totalProgression: 0.25));
    });

    test('keeps a percent-encoded href as Readium reports it', () {
      final position = positionFromLocator(
        _locator('OEBPS/Chap%20ter%203%20%C3%A9.xhtml', progression: 0.5),
        _indexOf,
      );

      expect(position?.sectionIndex, 2);
    });

    test('defaults a missing progression to 0 and leaves total null', () {
      final position = positionFromLocator(
        Locator(href: 'OEBPS/cover.xhtml', type: _xhtml),
        _indexOf,
      );

      expect(position, const ReaderPosition(0, 0));
    });

    test('drops a locator whose href is not in the spine', () {
      final position = positionFromLocator(
        _locator('OEBPS/notes.xhtml', progression: 0.1),
        _indexOf,
      );

      expect(position, isNull);
    });

    // Values from the Android emulator: a 3-page section reports page starts
    // 0.0, 0.333 and 0.666, with a zero-based currentPage.
    Locator paged(int currentPage, double progression) => Locator(
      href: 'OEBPS/ch1.xhtml',
      type: _xhtml,
      locations: Locations(
        progression: progression,
        additionalProperties: {'currentPage': currentPage, 'totalPages': 3},
      ),
    );

    test('reports the last page of a section as exactly 1.0', () {
      expect(
        positionFromLocator(paged(2, 0.6664607782581841), _indexOf),
        const ReaderPosition(1, 1.0),
      );
    });

    test('keeps the page start on earlier pages', () {
      expect(
        positionFromLocator(paged(1, 0.3329215565163681), _indexOf),
        const ReaderPosition(1, 0.3329215565163681),
      );
    });

    test('a one-page section is finished on its only page', () {
      final locator = Locator(
        href: 'OEBPS/cover.xhtml',
        type: _xhtml,
        locations: Locations(
          progression: 0,
          additionalProperties: {'currentPage': 0, 'totalPages': 1},
        ),
      );

      expect(positionFromLocator(locator, _indexOf)?.progression, 1.0);
    });
  });

  group('tocEntriesFromLinks', () {
    test('flattens a nested table of contents with depth', () {
      final entries = tocEntriesFromLinks([
        Link(href: 'OEBPS/cover.xhtml', title: 'Cover'),
        Link(
          href: 'OEBPS/ch1.xhtml',
          title: 'Part one',
          children: [
            Link(
              href: 'OEBPS/ch1.xhtml#s1',
              title: 'Section',
              children: [
                Link(href: 'OEBPS/ch1.xhtml#s1a', title: 'Subsection'),
              ],
            ),
            Link(href: 'OEBPS/Chap%20ter%203%20%C3%A9.xhtml', title: 'Next'),
          ],
        ),
      ], _indexOf);

      expect(entries.map((e) => (e.title, e.depth, e.sectionIndex)), [
        ('Cover', 0, 0),
        ('Part one', 0, 1),
        ('Section', 1, 1),
        ('Subsection', 2, 1),
        ('Next', 1, 2),
      ]);
    });

    test('keeps the href as written, with its fragment', () {
      final entries = tocEntriesFromLinks([
        Link(href: 'OEBPS/ch1.xhtml#pgepubid00004', title: 'Letter 2'),
      ], _indexOf);

      expect(entries.single.href, 'OEBPS/ch1.xhtml#pgepubid00004');
      expect(entries.single.sectionIndex, 1);
    });

    test('gives an entry outside the spine a null sectionIndex', () {
      final entries = tocEntriesFromLinks([
        Link(href: 'OEBPS/endnotes.xhtml', title: 'Notes'),
      ], _indexOf);

      expect(entries.single.sectionIndex, isNull);
    });

    test('uses an empty title when the link has none', () {
      final entries = tocEntriesFromLinks([
        Link(href: 'OEBPS/ch1.xhtml'),
      ], _indexOf);

      expect(entries.single.title, '');
    });

    test('is empty for an empty table of contents', () {
      expect(tocEntriesFromLinks(const [], _indexOf), isEmpty);
    });
  });

  group('locatorFromPosition', () {
    final readingOrder = [
      for (final href in _hrefs) Link(href: href, type: _xhtml),
    ];

    test('points at the reading-order link of the section', () {
      final locator = locatorFromPosition(
        const ReaderPosition(2, 0.5, totalProgression: 0.7),
        readingOrder,
        _indexOf,
      );

      expect(locator?.href, 'OEBPS/Chap%20ter%203%20%C3%A9.xhtml');
      expect(locator?.type, _xhtml);
      expect(locator?.locations?.progression, 0.5);
      expect(locator?.locations?.totalProgression, 0.7);
    });

    test('is null for a section missing from the reading order', () {
      // Non-linear spine items are not in Readium's reading order.
      final locator = locatorFromPosition(
        const ReaderPosition(5, 0.5),
        readingOrder,
        _indexOf,
      );

      expect(locator, isNull);
    });

    test('round-trips through positionFromLocator', () {
      const positions = [
        ReaderPosition(0, 0),
        ReaderPosition(1, 0.4, totalProgression: 0.25),
        ReaderPosition(2, 1, totalProgression: 1),
      ];

      for (final position in positions) {
        final locator = locatorFromPosition(position, readingOrder, _indexOf);

        expect(positionFromLocator(locator!, _indexOf), position);
      }
    });

    test('survives the JSON the plugin sends to the native view', () {
      const position = ReaderPosition(2, 0.5, totalProgression: 0.7);
      final locator = locatorFromPosition(position, readingOrder, _indexOf);

      final decoded = Locator.fromJson(locator!.toJson());

      expect(positionFromLocator(decoded!, _indexOf), position);
    });
  });

  group('locatorForPassage', () {
    final readingOrder = [
      for (final href in _hrefs) Link(href: href, type: _xhtml),
    ];
    const target = PassageTarget(
      sectionIndex: 2,
      progression: 0.25,
      highlight: 'a grey cat',
      before: 'There was ',
      after: ' on the wall',
    );

    test('carries the href, progression and text quote', () {
      final locator = locatorForPassage(target, readingOrder, _indexOf);

      expect(locator?.href, 'OEBPS/Chap%20ter%203%20%C3%A9.xhtml');
      expect(locator?.type, _xhtml);
      expect(locator?.locations?.progression, 0.25);
      expect(locator?.text?.highlight, 'a grey cat');
      expect(locator?.text?.before, 'There was ');
      expect(locator?.text?.after, ' on the wall');
    });

    test('keeps the quote through the JSON sent to the native view', () {
      final locator = locatorForPassage(target, readingOrder, _indexOf);

      final decoded = Locator.fromJson(locator!.toJson());

      expect(decoded?.text?.highlight, 'a grey cat');
      expect(decoded?.text?.before, 'There was ');
      expect(decoded?.locations?.progression, 0.25);
    });

    test('is null for a section missing from the reading order', () {
      final locator = locatorForPassage(
        const PassageTarget(sectionIndex: 5, progression: 0.5, highlight: 'x'),
        readingOrder,
        _indexOf,
      );

      expect(locator, isNull);
    });
  });

  group('passageHighlightStyle', () {
    test('always has a tint, which Android needs to draw anything', () {
      expect(passageHighlightStyle.tint, isNotNull);
      expect(passageHighlightStyle.toJson()['tint'], isA<String>());
    });
  });

  // These use the real `spineIndexOf`, so they pass once it is implemented.
  group('with the real spineIndexOf', () {
    const spine = [
      SpineItem(path: 'OEBPS/cover.xhtml', linear: true),
      SpineItem(path: 'OEBPS/ch1.xhtml', linear: true),
      SpineItem(path: 'OEBPS/Chap ter 3 é.xhtml', linear: true),
    ];
    int? indexOf(String href) => spineIndexOf(spine, href);

    test('maps hrefs with a slash, fragment and percent-encoding', () {
      final entries = tocEntriesFromLinks([
        Link(href: '/OEBPS/ch1.xhtml', title: 'Slash'),
        Link(href: 'OEBPS/ch1.xhtml#frag', title: 'Fragment'),
        Link(href: 'OEBPS/Chap%20ter%203%20%C3%A9.xhtml', title: 'Encoded'),
        Link(href: 'OEBPS/elsewhere.xhtml', title: 'Outside'),
      ], indexOf);

      expect(entries.map((e) => e.sectionIndex), [1, 1, 2, null]);
    });

    test('maps a percent-encoded locator and restores it', () {
      final readingOrder = [
        Link(href: 'OEBPS/Chap%20ter%203%20%C3%A9.xhtml', type: _xhtml),
      ];
      final position = positionFromLocator(
        _locator('OEBPS/Chap%20ter%203%20%C3%A9.xhtml', progression: 0.5),
        indexOf,
      );

      final locator = locatorFromPosition(position!, readingOrder, indexOf);

      expect(position.sectionIndex, 2);
      expect(locator?.href, 'OEBPS/Chap%20ter%203%20%C3%A9.xhtml');
    });
  });

  test('ReadiumReaderService reports a missing file without native code', () {
    expect(
      () => const ReadiumReaderService().open('/no/such/book.epub'),
      throwsA(
        isA<EpubOpenException>().having(
          (e) => e.failure,
          'failure',
          EpubOpenFailure.missingFile,
        ),
      ),
    );
  });
}
