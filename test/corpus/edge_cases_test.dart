import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/epub_sections.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/reader/toc_builder.dart';
import 'package:loremark/search/paragraph_index.dart';
import 'package:loremark/search/search_index.dart';

import '../library/test_epub.dart';

/// Awkward markup and text that real books contain, run through text
/// extraction, the page-end math, paragraph pieces, search and the section
/// builder. None of it may crash, hang, or open more text than it should.

String page(String body, {String head = '<title>t</title>'}) =>
    '<?xml version="1.0" encoding="utf-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml" '
    'xmlns:epub="http://www.idpf.org/2007/ops"><head>$head</head>'
    '<body>$body</body></html>';

/// The plain text of a one-chapter book whose page is [xhtml].
String textOf(String xhtml) {
  final bytes = buildEpub(
    chapters: [EpubChapter(id: 'c', fileName: 'c.xhtml', raw: xhtml)],
  );
  return sectionTextsFromBytes(bytes).single;
}

String withoutSpace(String text) => text.replaceAll(RegExp(r'\s'), '');

void main() {
  group('plain text', () {
    test('decodes entities, numeric references and comments', () {
      final text = textOf(
        page(
          '<p>Caf&eacute; &amp; cr&egrave;me&nbsp;br&ucirc;l&eacute;e '
          '&#x4e2d;&#25991; &mdash; <!-- hidden --> done</p>',
        ),
      );

      expect(text, contains('Café & crème'));
      expect(text, contains('中文'));
      expect(text, contains('—'));
      expect(text, isNot(contains('hidden')));
    });

    test('reads CDATA and ignores processing instructions', () {
      final text = textOf(
        page('<p><![CDATA[a < b && c]]></p><?php echo 1 ?><p>after</p>'),
      );

      expect(text, contains('a < b && c'));
      expect(text, contains('after'));
      expect(text, isNot(contains('echo')));
    });

    test('keeps text that is directly in the body', () {
      final text = textOf(page('Just some words<br/>and more words'));

      expect(text, contains('Just some words'));
      expect(text, contains('and more words'));
    });

    test('leaves out scripts, styles, svg text and ruby readings', () {
      final text = textOf(
        page(
          '<p>Visible<script>var secret = 1;</script><style>p{}</style>'
          '<svg xmlns="http://www.w3.org/2000/svg"><text>vector</text></svg>'
          '<ruby>漢<rp>(</rp><rt>kan</rt><rp>)</rp></ruby>字</p>',
        ),
      );

      expect(text, contains('Visible'));
      expect(text, contains('漢字'));
      for (final hidden in ['secret', 'p{}', 'vector', 'kan']) {
        expect(text, isNot(contains(hidden)), reason: hidden);
      }
    });

    test('survives a byte order mark and an odd declaration', () {
      final text = textOf('﻿${page('<p>hello bom</p>')}');

      expect(text, contains('hello bom'));
    });

    test('falls back to stripping tags for markup that is not XML', () {
      final text = textOf(
        '<html><body><p>first<br>second<p>third &amp; fourth'
        '<img src=x></body></html>',
      );

      expect(text, contains('first'));
      expect(text, contains('third & fourth'));
      expect(text, isNot(contains('<')));
    });

    test('is empty for a chapter with nothing in it', () {
      expect(textOf(page('')), isEmpty);
      expect(textOf(page('   \n  <p>  </p>  <p>&nbsp;</p>')).trim(), isEmpty);
      expect(textOf(page('<p><img src="x.png"/></p>')).trim(), isEmpty);
    });

    test('copes with elements nested four hundred deep', () {
      final open = '<div>' * 400;
      final close = '</div>' * 400;
      final text = textOf(page('$open<p>deep</p>$close'));

      expect(text.trim(), 'deep');
    });

    test('puts table cells, lists and quotes on their own lines', () {
      final text = textOf(
        page(
          '<table><tr><td>one</td><td>two</td></tr></table>'
          '<ul><li>alpha</li><li>beta</li></ul>'
          '<blockquote><p>quoted</p></blockquote>',
        ),
      );

      for (final word in ['one', 'two', 'alpha', 'beta', 'quoted']) {
        expect(text, contains(word));
      }
      expect(text, isNot(contains('onetwo')));
      expect(text, isNot(contains('alphabeta')));
    });
  });

  group('text blocks and page ends', () {
    test('are found with upper-case tags', () {
      final xhtml = page('<P>one</P><P>two</P>');

      expect(textProgressionOfBlock(xhtml, 1), isNotNull);
      // One past the last block ends the page with it; past that is nothing.
      expect(textProgressionOfBlock(xhtml, 2), 1);
      expect(textProgressionOfBlock(xhtml, 3), isNull);
    });

    test('are none in a chapter with text only in the body', () {
      final xhtml = page('Just some words<br/>and more');

      expect(textProgressionOfBlock(xhtml, 0), isNull);
    });

    test('are reported null, not wrong, for markup that is not XML', () {
      expect(textProgressionOfBlock('<p>one<p>two', 0), isNull);
      expect(textProgressionOfBlock('', 0), isNull);
      expect(textProgressionOfBlock('not markup at all', 0), isNull);
    });

    test('count a block holding only a non-breaking space as empty', () {
      final xhtml = page('<p>&nbsp;</p><p>real</p>');

      expect(textProgressionOfBlock(xhtml, 0), isNotNull);
      // One block, "real": block 1 is one past it.
      expect(textProgressionOfBlock(xhtml, 1), 1);
      expect(textProgressionOfBlock(xhtml, 2), isNull);
    });

    test('use the innermost block of nested ones', () {
      final xhtml = page(
        '<div><blockquote><p>inner</p></blockquote></div><p>after</p>',
      );
      final inner = textProgressionOfBlock(xhtml, 0)!;
      final after = textProgressionOfBlock(xhtml, 1)!;

      expect(inner, lessThan(after));
      expect(textProgressionOfBlock(xhtml, 2), 1);
      expect(textProgressionOfBlock(xhtml, 3), isNull);
    });

    test('never point past the end of the block they name', () {
      final xhtml = page('<p>abc</p><p>def</p>');

      expect(textProgressionOfBlock(xhtml, 0, characters: 2), isNotNull);
      expect(textProgressionOfBlock(xhtml, 0, characters: 3), isNull);
      expect(textProgressionOfBlock(xhtml, 0, characters: 4), isNull);
      expect(textProgressionOfBlock(xhtml, 0, characters: 1000000), isNull);
    });

    test('line up with the plain text when there are ruby readings', () {
      final xhtml = page('<p>前<ruby>漢<rt>かん</rt></ruby>字後</p>');
      final text = textOf(xhtml);
      // The plain text has no reading: 前漢字後.
      expect(withoutSpace(text), '前漢字後');
      final at = textProgressionOfBlock(xhtml, 0, characters: 2)!;

      expect((at * text.length).floor(), text.indexOf('字'));
    });

    test('line up when blocks sit among loose text and inline markup', () {
      final xhtml = page(
        'loose <b>bold</b> text<p>one <i>two</i> three</p>tail'
        '<div>x<p>deep</p>y</div>',
      );
      final text = textOf(xhtml);
      final p = textProgressionOfBlock(xhtml, 0, characters: 3)!;

      expect(
        text.substring((p * text.length).floor()),
        startsWith('two three'),
      );
    });

    test('are the same however the markup is spaced', () {
      final tight = page('<p>aaa</p><p>bbb</p><p>ccc</p>');
      final loose = page(
        '\n  <p>\n aaa \n</p>\n\n  <p> bbb </p>\n <p>ccc</p>\n',
      );
      final tightText = textOf(tight);
      final looseText = textOf(loose);

      for (var n = 0; n < 3; n++) {
        final a = textProgressionOfBlock(tight, n)!;
        final b = textProgressionOfBlock(loose, n)!;
        expect(
          tightText.substring((a * tightText.length).floor()),
          looseText.substring((b * looseText.length).floor()),
        );
      }
    });
  });

  group('paragraph pieces', () {
    final random = Random(7);

    String soup(int length) {
      const bits = [
        'word',
        'Mr.',
        'Dr.',
        '3.14',
        'U.S.A.',
        'e.g.',
        'ok!',
        'why?',
        '...',
        '"quoted."',
        "'single.'",
        '(paren.)',
        '[1]',
        'a—b',
        'x.y',
        'end.',
        '؟',
        '。',
        '！',
        'ça',
        'naïve',
        '日本語',
        ' ',
        'http://a.b/c.d',
      ];
      final out = StringBuffer();
      while (out.length < length) {
        out
          ..write(bits[random.nextInt(bits.length)])
          ..write(random.nextInt(9) == 0 ? '' : ' ');
      }
      return out.toString().trim();
    }

    test('lose and repeat nothing on random punctuation', () {
      for (var trial = 0; trial < 60; trial++) {
        final text = soup(300 + random.nextInt(4000));
        final index = ParagraphIndex([text]);
        final joined = StringBuffer();
        var previousEnd = -1;
        for (var id = 0; id < index.count; id++) {
          expect(index.startOf(id), greaterThanOrEqualTo(previousEnd));
          expect(index.endOf(id), greaterThan(index.startOf(id)));
          previousEnd = index.endOf(id);
          joined.write(index.textOf(id));
        }
        expect(
          withoutSpace(joined.toString()),
          withoutSpace(text),
          reason: text,
        );
      }
    });

    test('are bounded for ordinary punctuated text', () {
      final text = List.filled(
        400,
        'A sentence of some length goes here.',
      ).join(' ');
      final index = ParagraphIndex([text]);

      for (var id = 0; id < index.count; id++) {
        expect(index.textOf(id).length, lessThan(700));
      }
    });

    test('keep one very long unpunctuated paragraph whole', () {
      final text = List.filled(400000, 'word').join(' ');
      final index = ParagraphIndex([text]);

      expect(index.count, 1);
    });

    test('handle twenty thousand tiny paragraphs quickly', () {
      final text = List.generate(20000, (i) => 'Line $i.').join('\n\n');
      final watch = Stopwatch()..start();
      final index = ParagraphIndex([text]);

      expect(index.count, 20000);
      expect(watch.elapsedMilliseconds, lessThan(3000));
    });

    test('do not split decimals, initials or web addresses', () {
      final text = '${'x' * 300} 3.14159 is pi. ${'y' * 300}';
      final index = ParagraphIndex([text]);
      final pieces = [for (var i = 0; i < index.count; i++) index.textOf(i)];

      expect(pieces.any((piece) => piece.contains('3.14159')), isTrue);
    });
  });

  group('search', () {
    final index = SearchIndex.build(
      bookId: 'edge',
      sectionTexts: [
        'The harbor lay quiet. Gatsby waved from the dock.',
        'Later the fog came in.\n\nNobody waved back at Gatsby.',
      ],
    );
    const end = ReaderPosition(1, 1);

    test('survive strange queries without throwing', () {
      final queries = [
        '',
        ' ',
        '.*',
        '(((',
        '"unterminated',
        '"',
        '""',
        '\u0000',
        '🙂',
        'a' * 20000,
        '${'word ' * 3000}end',
        '+-~!',
        r'\d+',
        '<script>',
        "' OR 1=1 --",
        'Gatsby AND',
        '؟',
        '日本',
      ];
      for (final query in queries) {
        expect(
          () => index.search(query, cutoff: end),
          returnsNormally,
          reason: query,
        );
      }
    });

    test('show nothing at the start of the book', () {
      expect(
        index.search('Gatsby', cutoff: const ReaderPosition(0, 0)).hits,
        isEmpty,
      );
    });

    test('accept a cutoff past the last section', () {
      final results = index.search(
        'Gatsby',
        cutoff: const ReaderPosition(99, 1),
      );

      expect(results.hits, hasLength(2));
    });

    test('answer for a book with one section or none', () {
      final one = SearchIndex.build(bookId: 'a', sectionTexts: ['Just one.']);
      final none = SearchIndex.build(bookId: 'b', sectionTexts: const []);

      expect(() => one.search('one', cutoff: end), returnsNormally);
      expect(none.search('one', cutoff: end).hits, isEmpty);
    });

    test('find text in right-to-left and mixed scripts', () {
      final rtl = SearchIndex.build(
        bookId: 'rtl',
        sectionTexts: ['שלום עולם. זה ספר.\n\nمرحبا بالعالم. هذا كتاب.'],
      );

      expect(rtl.search('שלום', cutoff: end).hits, hasLength(1));
      expect(rtl.search('مرحبا', cutoff: end).hits, hasLength(1));
    });

    test(
      'keeps a hidden paragraph hidden at every character before its end',
      () {
        final text = 'First paragraph here.\n\nSecond secretword paragraph.';
        final book = SearchIndex.build(bookId: 's', sectionTexts: [text]);
        final secondEnd = text.length;

        for (var at = text.indexOf('Second'); at < secondEnd; at++) {
          final cutoff = ReaderPosition(0, (at + 0.25) / text.length);
          expect(
            book.search('secretword', cutoff: cutoff).hits,
            isEmpty,
            reason: 'at $at of $secondEnd',
          );
        }
        expect(
          book.search('secretword', cutoff: const ReaderPosition(0, 1)).hits,
          hasLength(1),
        );
      },
    );
  });

  group('sections without a table of contents', () {
    List<SpineItem> spine(int n) => [
      for (var i = 0; i < n; i++) SpineItem(path: 'c$i', linear: true),
    ];

    test('are empty for no text at all', () {
      expect(sectionsWithoutToc(['', '   ', '\n'], spine(3)), isEmpty);
    });

    test('are empty when every file is non-linear', () {
      final items = [const SpineItem(path: 'a', linear: false)];

      expect(
        sectionsWithoutToc([List.filled(20000, 'w').join(' ')], items),
        isEmpty,
      );
    });

    test('cope with a very long book', () {
      final text = List.filled(1200000, 'w').join(' ');
      final watch = Stopwatch()..start();
      final entries = sectionsWithoutToc([text], spine(1));

      expect(entries, hasLength(240));
      expect(watch.elapsedMilliseconds, lessThan(5000));
    });

    test('cope with a file of one huge word', () {
      final entries = sectionsWithoutToc(['x' * 5000000], spine(1));

      expect(entries, isEmpty);
    });
  });
}
