import 'package:flutter/foundation.dart';
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

  group('the last page of a section', () {
    Locations pages(int current, int total, double? progression) => Locations(
      progression: progression,
      additionalProperties: {'currentPage': current, 'totalPages': total},
    );

    // Values from the Android emulator, a book read right to left: Readium
    // numbers the pages of a file backwards, 113 of 114 first, then 112.
    test('a right-to-left file is not finished on its first page', () {
      expect(isLastPage(pages(113, 114, 0.0)), isFalse);
      expect(isLastPage(pages(112, 114, 0.00876395003167696)), isFalse);
      expect(isLastPage(pages(111, 114, 0.01755226693091183)), isFalse);
      expect(pageIndexOf(pages(113, 114, 0.0)), 0);
      expect(pageIndexOf(pages(112, 114, 0.00876395003167696)), 1);
    });

    test('a right-to-left file is finished on its last page, which is 0', () {
      expect(isLastPage(pages(0, 114, 113 / 114)), isTrue);
      expect(isLastPage(pages(1, 114, 112 / 114)), isFalse);
    });

    test('a right-to-left position keeps the page start until the end', () {
      Locator rtl(int current, double progression) => Locator(
        href: 'OEBPS/ch1.xhtml',
        type: _xhtml,
        locations: pages(current, 114, progression),
      );

      expect(
        positionFromLocator(rtl(113, 0.0), _indexOf),
        const ReaderPosition(1, 0.0),
      );
      expect(
        positionFromLocator(rtl(50, 63 / 114), _indexOf),
        ReaderPosition(1, 63 / 114),
      );
      expect(
        positionFromLocator(rtl(0, 113 / 114), _indexOf),
        const ReaderPosition(1, 1.0),
      );
    });

    // Values from the same device for a book read left to right.
    test('a left-to-right file is as before', () {
      expect(isLastPage(pages(0, 5, 0.0)), isFalse);
      expect(isLastPage(pages(1, 5, 0.19970359392367543)), isFalse);
      expect(isLastPage(pages(3, 5, 0.6000370507595406)), isFalse);
      expect(isLastPage(pages(4, 5, 0.8)), isTrue);
      expect(pageIndexOf(pages(1, 5, 0.19970359392367543)), 1);
    });

    test('a one-page file is finished on its only page either way', () {
      expect(isLastPage(pages(0, 1, 0.0)), isTrue);
      expect(isLastPage(pages(0, 1, null)), isTrue);
    });

    test('without a progression the page number is taken as it is', () {
      expect(isLastPage(pages(4, 5, null)), isTrue);
      expect(isLastPage(pages(3, 5, null)), isFalse);
      expect(pageIndexOf(pages(2, 5, null)), 2);
    });

    test('is not known without page numbers', () {
      expect(isLastPage(const Locations(progression: 0.9)), isFalse);
      expect(isLastPage(null), isFalse);
      expect(pageIndexOf(const Locations(progression: 0.9)), isNull);
      expect(pageIndexOf(pages(0, 0, 0.5)), isNull);
      expect(isLastPage(pages(0, 0, 0.5)), isFalse);
    });

    test('is right for every page of files of 1 to 200 pages, both ways', () {
      for (var total = 1; total <= 200; total++) {
        for (var page = 0; page < total; page++) {
          // The progression is a little off the exact page start, as seen.
          for (final noise in [-0.3, 0.0, 0.3]) {
            final progression = ((page + noise) / total).clamp(0.0, 1.0);
            final ltr = pages(page, total, progression);
            final rtl = pages(total - 1 - page, total, progression);
            final last = page == total - 1;
            final why = 'page $page of $total, noise $noise';
            expect(isLastPage(ltr), last, reason: 'left to right, $why');
            expect(isLastPage(rtl), last, reason: 'right to left, $why');
          }
        }
      }
    });

    group('on iOS', () {
      // iOS numbers the pages of a file from 1: 1 to 5 for a 5-page file.
      setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
      tearDown(() => debugDefaultTargetPlatformOverride = null);

      test('the second to last page is not finished', () {
        final locator = Locator(
          href: 'OEBPS/ch1.xhtml',
          type: _xhtml,
          locations: pages(4, 5, 0.6),
        );

        expect(isLastPage(pages(4, 5, 0.6)), isFalse);
        expect(
          positionFromLocator(locator, _indexOf),
          const ReaderPosition(1, 0.6),
        );
      });

      test('the last page is finished', () {
        expect(isLastPage(pages(5, 5, 0.8)), isTrue);
        expect(isLastPage(pages(1, 1, 0.0)), isTrue);
      });

      test('page numbers are counted from 0, as on Android', () {
        expect(pageIndexOf(pages(1, 5, 0.0)), 0);
        expect(pageIndexOf(pages(2, 5, 0.2)), 1);
        expect(pageIndexOf(pages(3, 5, null)), 2);
      });

      test('is right for every page of files of 1 to 200 pages', () {
        for (var total = 1; total <= 200; total++) {
          for (var page = 0; page < total; page++) {
            for (final noise in [-0.3, 0.0, 0.3]) {
              final progression = ((page + noise) / total).clamp(0.0, 1.0);
              expect(
                isLastPage(pages(page + 1, total, progression)),
                page == total - 1,
                reason: 'page $page of $total, noise $noise',
              );
            }
          }
        }
      });
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
