import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/story_update/story_book.dart';
import 'package:loremark/story_update/story_section_kind.dart';
import 'package:loremark/story_update/story_updater.dart';

/// What [title]'s section looks like with nothing but its title and a page of
/// text to go on.
StorySectionKind _byTitle(String title) =>
    classifyStorySection(title: title, textChars: 5000, imageCount: 0);

/// A book that says what its parts are in each way EPUB has.
Uint8List _bookWithSemantics() {
  String page(String title, String body, {String bodyAttributes = ''}) =>
      '<html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>$title</title>'
      '</head><body$bodyAttributes>$body</body></html>';
  String words(String text) => '<p>$text Some words of the story.</p>';
  const documents = [
    'map',
    'one',
    'plates',
    'two',
    'notes',
    'last',
    'printing',
    'thanks',
    'more',
    'ads',
  ];
  final files = {
    'META-INF/container.xml':
        '<container version="1.0" '
        'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
        '<rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles></container>',
    'OEBPS/content.opf':
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title>Marked</dc:title></metadata><manifest>'
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
        'properties="nav"/>'
        '${[for (final name in documents) '<item id="$name" href="$name.xhtml" media-type="application/xhtml+xml"/>'].join()}'
        '</manifest><spine>'
        '${[for (final name in documents) '<itemref idref="$name"${name == 'notes' ? ' linear="no"' : ''}/>'].join()}'
        '</spine><guide>'
        '<reference type="acknowledgements" href="thanks.xhtml" title="T"/>'
        '</guide></package>',
    'OEBPS/nav.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>n</title></head>'
        '<body><nav epub:type="toc"><ol>'
        '<li><a href="map.xhtml">The Known World</a></li>'
        '<li><a href="one.xhtml">One</a></li>'
        '<li><a href="plates.xhtml">Pictures</a></li>'
        // Its title says afterword, but the document says chapter.
        '<li><a href="two.xhtml">后记</a></li>'
        '<li><a href="notes.xhtml">Names</a></li>'
        '<li><a href="last.xhtml">Last Words</a></li>'
        '<li><a href="printing.xhtml">Printing</a></li>'
        '<li><a href="thanks.xhtml">With Gratitude</a></li>'
        '<li><a href="more.xhtml">More</a></li>'
        '<li><a href="ads.xhtml">Chapter 99</a></li>'
        '</ol></nav>'
        '<nav epub:type="landmarks"><ol>'
        // An anchor no section starts at, inside the first chapter.
        '<li><a epub:type="bodymatter" href="one.xhtml#start">Start</a></li>'
        '<li><a epub:type="backmatter" href="more.xhtml">More</a></li>'
        '</ol></nav></body></html>',
    'OEBPS/map.xhtml': page('The Known World', words('Here be dragons.')),
    'OEBPS/one.xhtml': page(
      'One',
      '<h1>One</h1><p id="start">It began.</p>${words('More.')}',
    ),
    'OEBPS/plates.xhtml': page(
      'Pictures',
      '<p>Pictures</p><img src="a.jpg"/><img src="b.jpg"/><img src="c.jpg"/>',
    ),
    'OEBPS/two.xhtml': page(
      '后记',
      '<section epub:type="chapter">${words('The story goes on.')}</section>',
    ),
    'OEBPS/notes.xhtml': page('Names', words('A list of names.')),
    'OEBPS/last.xhtml': page(
      'Last Words',
      words('Thank you for reading.'),
      bodyAttributes: ' epub:type="afterword"',
    ),
    'OEBPS/printing.xhtml': page(
      'Printing',
      '<section role="doc-colophon">${words('Set in a typeface.')}</section>',
    ),
    'OEBPS/thanks.xhtml': page('With Gratitude', words('To everyone.')),
    'OEBPS/more.xhtml': page('More', words('Other books.')),
    'OEBPS/ads.xhtml': page('Chapter 99', words('A preview.')),
  };
  final archive = Archive();
  files.forEach((name, text) {
    archive.addFile(ArchiveFile.string(name, text));
  });
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  group('by title', () {
    test('finds illustrations', () {
      for (final title in [
        '插图',
        '插圖',
        '彩页',
        '口絵',
        'Illustrations',
        'Color Inserts',
      ]) {
        expect(_byTitle(title), StorySectionKind.illustrations, reason: title);
      }
    });

    test('finds afterwords', () {
      for (final title in [
        '后记',
        '後記',
        '译后记',
        'あとがき',
        'Afterword',
        'Afterword: On Writing',
        'Translator’s Note',
        "Author's Note",
      ]) {
        expect(_byTitle(title), StorySectionKind.afterword, reason: title);
      }
    });

    test('finds front matter', () {
      for (final title in [
        'Front Matter',
        'Epigraph',
        'Table of Contents',
        'Copyright',
        '目录',
        '版权信息',
        '内容简介',
      ]) {
        expect(_byTitle(title), StorySectionKind.frontMatter, reason: title);
      }
    });

    test('finds back matter', () {
      for (final title in [
        'Back Matter',
        'About the Author',
        'Acknowledgments',
        '作者简介',
      ]) {
        expect(_byTitle(title), StorySectionKind.backMatter, reason: title);
      }
    });

    test('leaves the story as it is', () {
      for (final title in [
        '序章',
        '尾声',
        '终章',
        '番外',
        'Animate购入特典小说',
        '5年3班 佐伯沙弥香',
        'Prologue',
        'Epilogue: The Bloodstained Queen',
        'Interlude: The Headless Reaper',
        'Chapter 3: To Your Gallant Visage',
        // Where the word isn't the start of an English title.
        'Under Cover',
        'The Contents of the Box',
      ]) {
        expect(_byTitle(title), StorySectionKind.story, reason: title);
      }
    });
  });

  group('by its text', () {
    test('a little text around pictures is illustrations', () {
      // Volume 2's 插图 of 终将成为你: a blurb, and twelve pictures.
      expect(
        classifyStorySection(title: 'Gallery?', textChars: 279, imageCount: 12),
        StorySectionKind.illustrations,
      );
      expect(
        classifyStorySection(title: 'Untitled', textChars: 40, imageCount: 1),
        StorySectionKind.illustrations,
      );
    });

    test('a chapter with a picture is still the story', () {
      expect(
        classifyStorySection(title: 'Two', textChars: 3446, imageCount: 1),
        StorySectionKind.story,
      );
      expect(
        classifyStorySection(title: 'Two', textChars: 306, imageCount: 2),
        StorySectionKind.story,
      );
    });
  });

  group('by what the book says', () {
    test('comes before the title', () {
      expect(
        classifyStorySection(
          title: '后记',
          textChars: 5000,
          imageCount: 0,
          types: {'chapter'},
        ),
        StorySectionKind.story,
      );
      expect(
        classifyStorySection(
          title: 'Chapter 9',
          textChars: 5000,
          imageCount: 0,
          types: {'afterword'},
        ),
        StorySectionKind.afterword,
      );
    });

    test('front or back matter wins over chapter', () {
      expect(
        classifyStorySection(
          title: 'x',
          textChars: 5000,
          imageCount: 0,
          types: {'chapter', 'backmatter'},
        ),
        StorySectionKind.backMatter,
      );
    });

    test('the body\'s bounds only take sections out of the story', () {
      StorySectionKind at(int order, {String title = 'x', int images = 0}) =>
          classifyStorySection(
            title: title,
            textChars: 200,
            imageCount: images,
            order: order,
            bodyStart: 3,
            backStart: 8,
          );
      expect(at(2), StorySectionKind.frontMatter);
      expect(at(3), StorySectionKind.story);
      expect(at(5, title: '插图'), StorySectionKind.illustrations);
      expect(at(5, images: 4), StorySectionKind.illustrations);
      expect(at(8), StorySectionKind.backMatter);
    });

    test('bodymatter on every document says nothing more', () {
      expect(
        classifyStorySection(
          title: '插图',
          textChars: 5000,
          imageCount: 0,
          types: {'bodymatter'},
        ),
        StorySectionKind.illustrations,
      );
    });

    test('outside the reading order is supplementary', () {
      expect(
        classifyStorySection(
          title: 'Notes',
          textChars: 5000,
          imageCount: 0,
          linear: false,
        ),
        StorySectionKind.supplementary,
      );
    });
  });

  group('a book', () {
    late Directory temp;
    late String epub;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('story_kind_');
      epub = '${temp.path}/marked.epub';
      File(epub).writeAsBytesSync(_bookWithSemantics());
    });
    tearDown(() => temp.deleteSync(recursive: true));

    test('that says what its parts are is taken at its word', () {
      final book = StoryBook.open(File(epub).readAsBytesSync());
      final kinds = {
        for (final section in book.sections)
          section.title: book.kindOf(section, book.extract(section)),
      };
      expect(kinds, {
        // Before the landmark where the body starts.
        'The Known World': StorySectionKind.frontMatter,
        'One': StorySectionKind.story,
        'Pictures': StorySectionKind.illustrations,
        '后记': StorySectionKind.story,
        'Names': StorySectionKind.supplementary,
        'Last Words': StorySectionKind.afterword,
        'Printing': StorySectionKind.backMatter,
        // From the EPUB 2 guide.
        'With Gratitude': StorySectionKind.backMatter,
        // From the landmark where the back matter starts.
        'More': StorySectionKind.backMatter,
        'Chapter 99': StorySectionKind.backMatter,
      });
      expect(book.bodyStartOrder, 2);
      expect(book.backStartOrder, 9);
    });

    test('suggests starting where its story does', () {
      final status = inspectStoryUpdate(epub, '${temp.path}/store');
      expect(status.suggestedStart, 'section-002');
      expect(
        status.choices.map((choice) => choice.kind).toSet(),
        containsAll(StorySectionKind.values),
      );
    });

    test('says what a section that can\'t be cut looks like', () {
      final book = StoryBook.open(File(epub).readAsBytesSync());
      final pictures = book.sections.firstWhere((s) => s.title == 'Pictures');
      expect(book.kindOf(pictures, null), StorySectionKind.story);
      final illustrations = StoryBookSection(
        title: '插图',
        href: pictures.href,
        fragment: null,
        spineIndex: pictures.spineIndex,
        inToc: true,
        problem: 'Two entries start at the same place',
      )..order = pictures.order;
      expect(book.kindOf(illustrations, null), StorySectionKind.illustrations);
    });

    test('keeps its sections as they were', () {
      // The lab cuts the same sections, so nothing here moves them.
      final book = StoryBook.open(File(epub).readAsBytesSync());
      expect(book.sections.map((section) => section.sectionId), [
        for (var i = 1; i <= 10; i++) 'section-${'$i'.padLeft(3, '0')}',
      ]);
    });
  });

  test(
    'the sample book\'s front and back are found by their titles',
    () {
      final book = StoryBook.open(
        File('sample_epub/86v1_chapters.epub').readAsBytesSync(),
      );
      final kinds = [
        for (final section in book.sections)
          (section.title, book.kindOf(section, book.extract(section))),
      ];
      expect(kinds.where((kind) => kind.$2 != StorySectionKind.story), [
        ('Front Matter', StorySectionKind.frontMatter),
        ('Epigraph', StorySectionKind.frontMatter),
        ('Afterword', StorySectionKind.afterword),
        ('Back Matter', StorySectionKind.backMatter),
      ]);
      final story = [
        for (final (title, kind) in kinds)
          if (kind == StorySectionKind.story) title,
      ];
      expect(story, hasLength(14));
      expect(story.first, startsWith('Coquelicots'));
      expect(story.last, 'Epilogue II: Reboot');
    },
    tags: 'corpus',
    skip: File('sample_epub/86v1_chapters.epub').existsSync()
        ? false
        : 'needs the sample book',
  );
}
