import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/epub_sections.dart';

import '../library/test_epub.dart';

void main() {
  const chapters = [
    EpubChapter(
      id: 'ch1',
      fileName: 'Chapter 1.xhtml',
      body: '<h1>One</h1><p>Alpha beta</p>',
    ),
    EpubChapter(
      id: 'notes',
      fileName: 'notes.xhtml',
      body: '<p>Footnote text</p>',
      linear: false,
    ),
    EpubChapter(id: 'ch2', fileName: 'text/ch2.xhtml', body: '<p>Omega</p>'),
  ];

  List<String> texts(List<EpubChapter> chapters) =>
      sectionTextsFromBytes(buildEpub(chapters: chapters));

  String textOf(String body) =>
      texts([EpubChapter(id: 'c', fileName: 'c.xhtml', body: body)]).single;

  group('spineFromBytes', () {
    test('lists the items in spine order with resolved paths', () {
      final spine = spineFromBytes(buildEpub(chapters: chapters));

      expect(spine.map((item) => item.path), [
        'OEBPS/Chapter 1.xhtml',
        'OEBPS/notes.xhtml',
        'OEBPS/text/ch2.xhtml',
      ]);
    });

    test('includes non-linear items and flags them', () {
      final spine = spineFromBytes(buildEpub(chapters: chapters));

      expect(spine.map((item) => item.linear), [true, false, true]);
    });

    test('keeps an itemref missing from the manifest as an empty item', () {
      final spine = spineFromBytes(
        buildEpub(
          chapters: const [
            EpubChapter(id: 'a', fileName: 'a.xhtml'),
            EpubChapter(
              id: 'ghost',
              fileName: 'ghost.xhtml',
              inManifest: false,
            ),
            EpubChapter(id: 'b', fileName: 'b.xhtml'),
          ],
        ),
      );

      expect(spine.map((item) => item.path), [
        'OEBPS/a.xhtml',
        '',
        'OEBPS/b.xhtml',
      ]);
    });

    test('throws a FormatException for a file that is not an EPUB', () {
      expect(
        () => spineFromBytes(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });
  });

  group('sectionTextsFromBytes', () {
    test('returns the text of each item in spine order', () {
      expect(texts(chapters), ['One\n\nAlpha beta', 'Footnote text', 'Omega']);
    });

    test('separates paragraphs with a blank line', () {
      expect(
        textOf('<h2>Title</h2><p>First</p><div>Second</div><p>Third</p>'),
        'Title\n\nFirst\n\nSecond\n\nThird',
      );
    });

    test('puts line breaks and list items on their own lines', () {
      expect(
        textOf('<p>one<br/>two</p><ul><li>a</li><li>b</li></ul>'),
        'one\ntwo\n\na\nb',
      );
    });

    test('collapses whitespace inside a paragraph and trims', () {
      expect(
        textOf('\n  <p>  A   <b>bold</b>\n\t word,  <i>x</i>y </p>\n'),
        'A bold word, xy',
      );
    });

    test('decodes HTML entities', () {
      expect(
        textOf('<p>Fish&nbsp;&amp;&nbsp;chips &mdash; &eacute;&hellip;</p>'),
        'Fish & chips — é…',
      );
    });

    test('skips scripts, styles, images and the head', () {
      expect(
        textOf(
          '<style>p { color: red }</style><script>var x = 1;</script>'
          '<p>Seen<img src="a.png" alt="Not text"/></p>'
          '<svg><title>Not text</title></svg>',
        ),
        'Seen',
      );
    });

    test('skips ruby readings', () {
      expect(
        textOf('<p><ruby>漢字<rp>(</rp><rt>かんじ</rt><rp>)</rp></ruby></p>'),
        '漢字',
      );
    });

    test('is empty for a page without text', () {
      expect(textOf('<p> </p><img src="a.png"/>'), '');
    });

    test('keeps the order when a chapter file is missing', () {
      expect(
        texts(const [
          EpubChapter(id: 'a', fileName: 'a.xhtml', body: '<p>A</p>'),
          EpubChapter(id: 'b', fileName: 'b.xhtml', inArchive: false),
          EpubChapter(id: 'c', fileName: 'c.xhtml', body: '<p>C</p>'),
        ]),
        ['A', '', 'C'],
      );
    });

    test('is empty for an itemref missing from the manifest', () {
      expect(
        texts(const [
          EpubChapter(id: 'a', fileName: 'a.xhtml', body: '<p>A</p>'),
          EpubChapter(id: 'g', fileName: 'g.xhtml', inManifest: false),
          EpubChapter(id: 'c', fileName: 'c.xhtml', body: '<p>C</p>'),
        ]),
        ['A', '', 'C'],
      );
    });

    test('strips tags from a chapter that is not well-formed', () {
      expect(
        texts(const [
          EpubChapter(
            id: 'a',
            fileName: 'a.xhtml',
            raw:
                '<html><head><title>T</title></head><body><p>Broken <b>tag</p>'
                '<script>var x;</script><p>&nbsp;Next&amp;</p></body>',
          ),
          EpubChapter(id: 'b', fileName: 'b.xhtml', body: '<p>B</p>'),
        ]),
        ['Broken tag\n\nNext&', 'B'],
      );
    });

    test('throws a FormatException for a file that is not an EPUB', () {
      expect(
        () => sectionTextsFromBytes(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });

    test('throws a FormatException for a zip without a package', () {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('readme.txt', [104, 105]));
      expect(
        () => sectionTextsFromBytes(ZipEncoder().encodeBytes(archive)),
        throwsFormatException,
      );
    });
  });

  group('spineIndexOf', () {
    final spine = spineFromBytes(buildEpub(chapters: chapters));

    test('matches the archive path', () {
      expect(spineIndexOf(spine, 'OEBPS/text/ch2.xhtml'), 2);
    });

    test('ignores a fragment, a query and a leading slash', () {
      expect(spineIndexOf(spine, 'OEBPS/notes.xhtml#fn1'), 1);
      expect(spineIndexOf(spine, 'OEBPS/notes.xhtml?x=1#fn1'), 1);
      expect(spineIndexOf(spine, '/OEBPS/notes.xhtml'), 1);
    });

    test('decodes percent-encoding', () {
      expect(spineIndexOf(spine, 'OEBPS/Chapter%201.xhtml'), 0);
      expect(spineIndexOf(spine, '/OEBPS/Chapter%201.xhtml#top'), 0);
      expect(spineIndexOf(spine, 'OEBPS/Chapter 1.xhtml'), 0);
    });

    test('returns null when nothing matches', () {
      expect(spineIndexOf(spine, 'OEBPS/other.xhtml'), isNull);
      expect(spineIndexOf(spine, ''), isNull);
      expect(spineIndexOf(spine, '#top'), isNull);
      expect(spineIndexOf(spine, '100%'), isNull);
    });

    test('does not match an item missing from the manifest', () {
      final broken = spineFromBytes(
        buildEpub(
          chapters: const [
            EpubChapter(id: 'g', fileName: 'g.xhtml', inManifest: false),
          ],
        ),
      );

      expect(spineIndexOf(broken, ''), isNull);
      expect(spineIndexOf(broken, '/'), isNull);
    });
  });

  test('a reported href finds the text of its section', () {
    const book = [
      EpubChapter(id: 'a', fileName: 'Chapter 1.xhtml', body: '<p>Ant</p>'),
      EpubChapter(
        id: 'b',
        fileName: 'more notes.xhtml',
        body: '<p>Bee</p>',
        linear: false,
      ),
      EpubChapter(
        id: 'c',
        fileName: 'text/Chapter 3.xhtml',
        body: '<p>Cat</p>',
      ),
      EpubChapter(id: 'd', fileName: 'd.xhtml', inArchive: false),
      EpubChapter(id: 'e', fileName: 'e.xhtml', body: '<p>Eel</p>'),
    ];
    final bytes = buildEpub(chapters: book);
    final spine = spineFromBytes(bytes);
    final sections = sectionTextsFromBytes(bytes);
    final reported = {
      'Ant': '/OEBPS/Chapter%201.xhtml#intro',
      'Bee': 'OEBPS/more%20notes.xhtml',
      'Cat': 'OEBPS/text/Chapter%203.xhtml?x=1',
      'Eel': '/OEBPS/e.xhtml',
    };

    expect(sections, hasLength(spine.length));
    for (final MapEntry(key: text, value: href) in reported.entries) {
      final index = spineIndexOf(spine, href);
      expect(index, isNotNull, reason: href);
      expect(sections[index!], contains(text), reason: href);
    }
  });

  group('from a file', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('loremark_sections_');
      path = '${dir.path}/book.epub';
      File(path).writeAsBytesSync(buildEpub(chapters: chapters));
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('readSpine reads the spine', () async {
      final spine = await readSpine(path);

      expect(spine.map((item) => item.linear), [true, false, true]);
      expect(spine.first.path, 'OEBPS/Chapter 1.xhtml');
    });

    test('readSectionTexts reads the texts', () async {
      expect(await readSectionTexts(path), [
        'One\n\nAlpha beta',
        'Footnote text',
        'Omega',
      ]);
    });

    test('reading a file that is not an EPUB throws', () async {
      File(path).writeAsBytesSync([1, 2, 3]);

      await expectLater(readSpine(path), throwsFormatException);
      await expectLater(readSectionTexts(path), throwsFormatException);
    });
  });
}
