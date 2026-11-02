import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/epub_sections.dart';
import 'package:loremark/reader/readium_reader_service.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/search/search_index.dart';

import '../library/test_epub.dart';

String _page(String body) =>
    '<?xml version="1.0" encoding="utf-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title></head>'
    '<body>$body</body></html>';

/// The search index over the text of a one-chapter book with [body].
SearchIndex _indexOf(String body) {
  final bytes = buildEpub(
    chapters: [EpubChapter(id: 'c', fileName: 'c.xhtml', raw: _page(body))],
  );
  return SearchIndex.build(
    bookId: 'b',
    sectionTexts: sectionTextsFromBytes(bytes),
  );
}

Locator _withPhysicalPage(Object? value) => Locator(
  href: 'OEBPS/c.xhtml',
  type: 'application/xhtml+xml',
  locations: Locations(
    progression: 0.5,
    additionalProperties: {'physicalPage': ?value},
  ),
);

void main() {
  group('text blocks', () {
    test('are the innermost text-holding blocks in document order', () {
      final xhtml = _page(
        '<div><p>one</p><p>  </p><div><h2>two</h2></div></div>'
        '<p><img src="x.png"/></p><ul><li>three</li></ul>'
        '<blockquote><p>four</p></blockquote>',
      );
      final numbers = [
        for (var n = 0; n < 6; n++)
          if (textProgressionOfBlock(xhtml, n) != null) n,
      ];
      // one, two, three, four.
      expect(numbers, [0, 1, 2, 3]);
    });

    test('are not shifted by elements that hold no text', () {
      final plain = _page('<p>one</p><p>two</p><p>three</p>');
      // Readium adds empty elements to the page it shows.
      final decorated = _page(
        '<div id="decoration"></div><p>one</p><span></span><p>two</p>'
        '<p>three</p><div class="flutter-readium-spotlight"></div>',
      );
      for (var n = 0; n < 3; n++) {
        final inPlain = textProgressionOfBlock(plain, n)!;
        final inDecorated = textProgressionOfBlock(decorated, n)!;
        expect(inDecorated, inPlain);
      }
    });

    test('are null for a block that does not exist or markup that is bad', () {
      final xhtml = _page('<p>one</p><p>two</p>');
      expect(textProgressionOfBlock(xhtml, 2), isNull);
      expect(textProgressionOfBlock(xhtml, -1), isNull);
      expect(textProgressionOfBlock('<p>broken', 0), isNull);
      expect(textProgressionOfBlock(_page(''), 0), isNull);
    });
  });

  group('textProgressionOfBlock', () {
    const paragraphs = [
      'The harbor was quiet that morning.',
      'Gatsby waved from the end of the dock.',
      'Nobody on the shore waved back.',
      'Later the fog came in from the sea.',
    ];
    final body = [for (final p in paragraphs) '<p>$p</p>'].join();
    final index = _indexOf(body);
    final xhtml = _page(body);

    /// What search finds when the first block past the page is
    /// [firstBlockPastPage].
    List<String> visible(int firstBlockPastPage) {
      final cutoff = ReaderPosition(
        0,
        textProgressionOfBlock(xhtml, firstBlockPastPage)!,
      );
      final hits = index
          .search('harbor gatsby waved shore fog', cutoff: cutoff)
          .hits;
      return [for (final hit in hits) hit.passage.text]..sort();
    }

    test('shows every paragraph on the page, the last one too', () {
      expect(visible(2), ([paragraphs[0], paragraphs[1]])..sort());
    });

    test('hides the block that starts the next page and all after it', () {
      final shown = visible(2);
      expect(shown, isNot(contains(paragraphs[2])));
      expect(shown, isNot(contains(paragraphs[3])));
    });

    test('shows nothing when the first block is already past the page', () {
      expect(visible(0), isEmpty);
    });

    test('shows one more paragraph for each block the page covers', () {
      for (var n = 1; n < paragraphs.length; n++) {
        expect(visible(n), hasLength(n));
      }
    });

    test('never reaches the end of the section', () {
      for (var n = 0; n < paragraphs.length; n++) {
        expect(textProgressionOfBlock(xhtml, n)!, lessThan(1));
      }
    });
  });

  group('textProgressionOfBlock inside a paragraph', () {
    // One long paragraph whose last sentences are on the next page.
    const sentences = [
      'Gatsby waved from the end of the dock.',
      'The fog came in from the sea.',
      'Nobody on the shore waved back at all.',
    ];
    final paragraph = sentences.join(' ');
    final index = _indexOf('<p>$paragraph</p>');
    final xhtml = _page('<p>$paragraph</p>');

    /// What search finds when the page ends after [characters] characters of
    /// the paragraph, not counting whitespace.
    List<String> visible(int characters) {
      final progression = textProgressionOfBlock(
        xhtml,
        0,
        characters: characters,
      );
      if (progression == null) return const [];
      final hits = index
          .search('gatsby fog nobody', cutoff: ReaderPosition(0, progression))
          .hits;
      return [for (final hit in hits) hit.passage.text];
    }

    int nonSpace(String text) => text.replaceAll(RegExp(r'\s'), '').length;

    test('counts characters the way the page script does', () {
      // The page ends exactly after the first sentence.
      final first = nonSpace(sentences[0]);
      expect(
        textProgressionOfBlock(xhtml, 0, characters: first)!,
        greaterThan(textProgressionOfBlock(xhtml, 0, characters: first - 1)!),
      );
    });

    test('moves forward one character at a time', () {
      var previous = -1.0;
      for (var n = 0; n < nonSpace(paragraph); n++) {
        final at = textProgressionOfBlock(xhtml, 0, characters: n)!;
        expect(at, greaterThan(previous));
        previous = at;
      }
    });

    test('is null past the end of the block', () {
      expect(
        textProgressionOfBlock(xhtml, 0, characters: nonSpace(paragraph)),
        isNull,
      );
      expect(textProgressionOfBlock(xhtml, 0, characters: -1), isNull);
    });

    test('does not run on into the next block', () {
      final two = _page('<p>one</p><p>two</p>');
      expect(textProgressionOfBlock(two, 0, characters: 3), isNull);
      expect(textProgressionOfBlock(two, 0, characters: 2), isNotNull);
    });

    test('ignores whitespace and markup inside the block', () {
      final plain = _page('<p>Hello   there friend</p>');
      final marked = _page('<p>Hello <em>the</em>re\n   fri<b>end</b></p>');
      for (var n = 0; n < 15; n++) {
        expect(
          textProgressionOfBlock(marked, 0, characters: n),
          textProgressionOfBlock(plain, 0, characters: n),
        );
      }
    });

    test('skips the text the plain text leaves out', () {
      // Ruby readings are not in the plain text, so they are not counted.
      final withRuby = _page('<p>ab<ruby>c<rt>XX</rt></ruby>de</p>');
      final withoutRuby = _page('<p>abcde</p>');
      for (var n = 0; n < 5; n++) {
        expect(
          textProgressionOfBlock(withRuby, 0, characters: n),
          textProgressionOfBlock(withoutRuby, 0, characters: n),
        );
      }
    });

    test('lets search find what is on the page and nothing past it', () {
      // A long paragraph is cut into pieces, so this one is a single piece:
      // the page ends inside it, and the piece is hidden until it is read.
      expect(visible(nonSpace(sentences[0])), isEmpty);
    });
  });

  group('pageEnd', () {
    test('reads the block and characters the page script reports', () {
      expect(pageEnd(_withPhysicalPage('loremark-end:17:42')), (
        block: 17,
        characters: 42,
      ));
      expect(pageEnd(_withPhysicalPage('loremark-end:0:0')), (
        block: 0,
        characters: 0,
      ));
    });

    test('reads a marker without characters as the start of the block', () {
      expect(pageEnd(_withPhysicalPage('loremark-end:5')), (
        block: 5,
        characters: 0,
      ));
    });

    test('ignores a page without the marker', () {
      expect(pageEnd(_withPhysicalPage(null)), isNull);
      expect(pageEnd(_withPhysicalPage('iv')), isNull);
      expect(pageEnd(_withPhysicalPage(7)), isNull);
    });

    test('ignores a marker that is not numbers', () {
      expect(pageEnd(_withPhysicalPage('loremark-end:')), isNull);
      expect(pageEnd(_withPhysicalPage('loremark-end:x')), isNull);
      expect(pageEnd(_withPhysicalPage('loremark-end:3:y')), isNull);
      expect(pageEnd(_withPhysicalPage('loremark-end:-2')), isNull);
      expect(pageEnd(_withPhysicalPage('loremark-end:2:-1')), isNull);
      expect(pageEnd(_withPhysicalPage('loremark-end:1:2:3')), isNull);
    });
  });
}
