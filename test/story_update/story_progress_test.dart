import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/story_update/story_api_client.dart';
import 'package:loremark/story_update/story_book.dart';
import 'package:loremark/story_update/story_model_choice.dart';
import 'package:loremark/story_update/story_paragraphs.dart';
import 'package:loremark/story_update/story_updater.dart';

import 'golden.dart';

String _page(String body) =>
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title></head>'
    '<body>$body</body></html>';

/// One chapter in a file of its own, then two sharing a file.
Uint8List _epub() {
  final files = {
    'META-INF/container.xml':
        '<container version="1.0" '
        'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
        '<rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles></container>',
    'OEBPS/content.opf':
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title>Places</dc:title></metadata><manifest>'
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
        'properties="nav"/>'
        '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>'
        '</manifest><spine><itemref idref="a"/><itemref idref="b"/>'
        '</spine></package>',
    'OEBPS/nav.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>n</title></head>'
        '<body><nav epub:type="toc"><ol>'
        '<li><a href="a.xhtml">Chapter 1</a></li>'
        '<li><a href="b.xhtml#two">Chapter 2</a></li>'
        '<li><a href="b.xhtml#three">Chapter 3</a></li>'
        '</ol></nav></body></html>',
    'OEBPS/a.xhtml': _page(
      '<h1>Chapter 1</h1><p>Alpha</p>'
      '<p>Beta <span>inside</span> more</p><p>Gamma</p>',
    ),
    'OEBPS/b.xhtml': _page(
      '<h1 id="two">Chapter 2</h1><p>Delta</p>'
      '<h1 id="three">Chapter 3</h1><p>Epsilon</p><p>Zeta</p>',
    ),
  };
  final archive = Archive();
  files.forEach((name, text) {
    archive.addFile(ArchiveFile.string(name, text));
  });
  return ZipEncoder().encodeBytes(archive);
}

String _child(int n) => ':root > :nth-child(2) > :nth-child($n)';

/// Paragraphs `p0001`... of `s2`, each holding `quote <number>`.
List<StoryParagraph> _paragraphs(int count) => [
  for (var i = 1; i <= count; i++)
    StoryParagraph(
      sectionId: 's2',
      id: 'p${'$i'.padLeft(4, '0')}',
      number: i,
      text: 'Words before quote $i.',
    ),
];

JsonMap _cite(int paragraph, {String? quote, String section = 's2'}) => {
  'section_id': section,
  'paragraph_id': 'p${'$paragraph'.padLeft(4, '0')}',
  'quote': quote ?? 'quote $paragraph',
};

JsonMap _record(
  String id,
  JsonMap payload,
  List<JsonMap> evidence, {
  String section = 's2',
}) => {
  'id': id,
  'learned_in_section_id': section,
  'payload': payload,
  'evidence': evidence,
};

JsonMap _name(String entity, [String text = 'Someone']) => {
  'entity_id': entity,
  'text': text,
};

JsonMap _attribute(String entity, {String assertion = 'explicit'}) => {
  'entity_id': entity,
  'label': 'role',
  'value': 'clerk',
  'assertion': assertion,
  'attributed_to_id': null,
};

StoryModel _model({
  List<JsonMap> names = const [],
  List<JsonMap> aliases = const [],
  List<JsonMap> attributes = const [],
  List<JsonMap> transitions = const [],
}) => StoryModel.fromJson({
  'schema_version': '2.0',
  'book': {'title': 'T'},
  'revision': {'number': 2},
  'processed_sections': [
    for (final (id, order) in const [('s1', 1), ('s2', 2)])
      {
        'section_id': id,
        'section_order': order,
        'chapter_number': order,
        'title': id,
      },
  ],
  'entities': <Object>[],
  'records': {
    'names': names,
    'aliases': aliases,
    'attributes': attributes,
    'relationships': <Object>[],
    'events': <Object>[],
    'uncertainties': <Object>[],
    'identity_links': <Object>[],
  },
  'transitions': transitions,
});

/// What of `s2` is hidden after each of its first [count] paragraphs.
List<Set<String>> _hiddenAfterEach(StoryModel model, int count) => [
  for (var read = 0; read <= count; read++)
    hiddenWithinSection(
      model,
      model.sectionById('s2')!,
      _paragraphs(count),
      paragraphsRead: read,
    ),
];

void main() {
  group('paragraphsBefore', () {
    final book = StoryBook.open(_epub());
    StoryBookSection section(String title) =>
        book.sections.firstWhere((s) => s.title == title);
    final one = section('Chapter 1');
    final two = section('Chapter 2');
    final three = section('Chapter 3');

    test('counts the paragraphs before the first element on the page', () {
      expect(book.paragraphsBefore(one, _child(1)), 0);
      expect(book.paragraphsBefore(one, _child(2)), 1);
      expect(book.paragraphsBefore(one, _child(4)), 3);
    });

    test('leaves out the paragraph an inline element is in', () {
      expect(book.paragraphsBefore(one, '${_child(3)} > span'), 2);
    });

    test('sorts out sections that share a document', () {
      // The first paragraph of chapter 3 is on the page.
      expect(book.paragraphsBefore(two, _child(4)), 2);
      expect(book.paragraphsBefore(three, _child(4)), 1);
      // Still in chapter 2: none of chapter 3 has been read.
      expect(book.paragraphsBefore(two, _child(2)), 1);
      expect(book.paragraphsBefore(three, _child(2)), 0);
    });

    test('says so when it can\'t place the element', () {
      expect(book.paragraphsBefore(one, ':root > :nth-child(9)'), isNull);
      expect(book.paragraphsBefore(one, 'p:not(.x)'), isNull);
      expect(book.paragraphsBefore(one, 'head'), isNull);
      // The body has no place among its own paragraphs.
      expect(book.paragraphsBefore(one, 'body'), isNull);
    });

    test('agrees with what is extracted', () {
      final extracted = book.extract(one)['paragraphs'] as List;
      expect(extracted, hasLength(4));
      expect(book.paragraphsBefore(one, _child(4)), extracted.length - 1);
    });

    // Where a page ends, by the text block the page script names: the first
    // one not wholly on the page.
    test('by block, counts the paragraphs before the block past the page', () {
      for (var block = 0; block < 4; block++) {
        expect(
          book.paragraphsBeforeBlock(one, block),
          book.paragraphsBefore(one, _child(block + 1)),
          reason: 'block $block',
        );
      }
    });

    test('by block, sorts out sections that share a document', () {
      // Chapter 2, Delta, Chapter 3, Epsilon, Zeta.
      expect(book.paragraphsBeforeBlock(two, 3), 2);
      expect(book.paragraphsBeforeBlock(three, 3), 1);
      expect(book.paragraphsBeforeBlock(two, 1), 1);
      expect(book.paragraphsBeforeBlock(three, 1), 0);
    });

    test('by block, says so when there is no such block', () {
      expect(book.paragraphsBeforeBlock(one, 4), isNull);
      expect(book.paragraphsBeforeBlock(one, -1), isNull);
    });
  });

  group('hiddenWithinSection', () {
    test('a fact is known once its paragraph is read', () {
      final hidden = _hiddenAfterEach(
        _model(
          attributes: [
            _record('a', _attribute('e'), [_cite(2)]),
          ],
        ),
        3,
      );
      expect(hidden[1], {'a'});
      expect(hidden[2], isEmpty);
      expect(hidden[3], isEmpty);
    });

    test('a misplaced quote counts where it really is', () {
      final hidden = _hiddenAfterEach(
        _model(
          attributes: [
            _record('a', _attribute('e'), [_cite(1, quote: 'quote 3')]),
          ],
        ),
        4,
      );
      expect(hidden[2], {'a'});
      expect(hidden[3], isEmpty);
    });

    test('a quote in several paragraphs counts at the last', () {
      final model = _model(
        attributes: [
          _record('a', _attribute('e'), [_cite(99, quote: 'Words before')]),
        ],
      );
      final hidden = _hiddenAfterEach(model, 3);
      expect(hidden[2], {'a'});
      expect(hidden[3], isEmpty);
    });

    test('a quote that is nowhere waits for the end of the section', () {
      final hidden = _hiddenAfterEach(
        _model(
          attributes: [
            _record('a', _attribute('e'), [_cite(1, quote: 'not in the book')]),
          ],
        ),
        3,
      );
      expect(hidden[3], {'a'});
    });

    test('a fact is known at its last citation, a name at its first', () {
      final hidden = _hiddenAfterEach(
        _model(
          names: [
            _record('n', _name('e'), [_cite(1), _cite(4)]),
          ],
          attributes: [
            _record('a', _attribute('e'), [_cite(1), _cite(4)]),
          ],
        ),
        5,
      );
      expect(hidden[1], {'a'});
      expect(hidden[3], {'a'});
      expect(hidden[4], isEmpty);
    });

    test('an inferred fact waits for the end of the section', () {
      final hidden = _hiddenAfterEach(
        _model(
          attributes: [
            _record('a', _attribute('e', assertion: 'inferred'), [_cite(1)]),
          ],
        ),
        3,
      );
      expect(hidden[3], {'a'});
    });

    test('a fact waits for the first name of what it mentions', () {
      final hidden = _hiddenAfterEach(
        _model(
          names: [
            _record('n', _name('e'), [_cite(5)]),
          ],
          attributes: [
            _record('a', _attribute('e'), [_cite(2)]),
          ],
        ),
        6,
      );
      expect(hidden[4], {'n', 'a'});
      expect(hidden[5], isEmpty);
    });

    test('an alias is a name to show it by', () {
      final hidden = _hiddenAfterEach(
        _model(
          names: [
            _record('n', _name('e'), [_cite(5)]),
          ],
          aliases: [
            _record('l', _name('e', 'Nickname'), [_cite(2)]),
          ],
          attributes: [
            _record('a', _attribute('e'), [_cite(3)]),
          ],
        ),
        6,
      );
      expect(hidden[3], {'n'});
    });

    test('a name from an earlier section is already known', () {
      final hidden = _hiddenAfterEach(
        _model(
          names: [
            _record('old', _name('e'), [
              _cite(1, section: 's1'),
            ], section: 's1'),
            _record('n', _name('e', 'Full Name'), [_cite(5)]),
          ],
          attributes: [
            _record('a', _attribute('e'), [_cite(2)]),
          ],
        ),
        6,
      );
      expect(hidden[2], {'n'});
    });

    JsonMap transition(int paragraph, String? replacement) => {
      'id': 't',
      'learned_in_section_id': 's2',
      'target_record_id': 'old',
      'action': 'supersede',
      'replacement_record_id': replacement,
      'resolution': null,
      'reason': 'r',
      'evidence': [_cite(paragraph)],
    };

    List<JsonMap> withReplacement(int paragraph) => [
      _record('old', _attribute('e'), [_cite(1, section: 's1')], section: 's1'),
      _record('new', _attribute('e'), [_cite(paragraph)]),
    ];

    final named = [
      _record('n', _name('e'), [_cite(1, section: 's1')], section: 's1'),
    ];

    test('a replacement waits for the change it comes with', () {
      final hidden = _hiddenAfterEach(
        _model(
          names: named,
          attributes: withReplacement(2),
          transitions: [transition(4, 'new')],
        ),
        5,
      );
      expect(hidden[3], {'new', 't'});
      expect(hidden[4], isEmpty);
    });

    test('a change waits for the replacement it comes with', () {
      final hidden = _hiddenAfterEach(
        _model(
          names: named,
          attributes: withReplacement(4),
          transitions: [transition(2, 'new')],
        ),
        5,
      );
      expect(hidden[3], {'new', 't'});
      expect(hidden[4], isEmpty);
    });

    test('leaves other sections alone', () {
      final hidden = _hiddenAfterEach(
        _model(
          attributes: [
            _record('a', _attribute('e'), [
              _cite(9, section: 's1'),
            ], section: 's1'),
          ],
        ),
        2,
      );
      expect(hidden[0], isEmpty);
    });
  });

  group('readStoryProgress', () {
    const epub = '$goldenDir/story.epub';
    late Directory temp;
    late String storePath;

    setUp(() async {
      temp = Directory.systemTemp.createTempSync('story_progress_');
      storePath = '${temp.path}/store';
      final golden = readValidationGolden();
      final delta = (golden['first'] as JsonMap)['candidate'];
      final outcome = await StoryUpdater.run(
        StoryUpdateRequest(
          epubPath: epub,
          storePath: storePath,
          model: StoryModelChoice.deepseekFlash,
          effort: StoryEffort.high,
          checkQuotes: false,
          prompt: File('assets/story_update/$updatePromptName')
              .readAsStringSync(),
          schemaText: File('assets/story_update/story_delta.schema.json')
              .readAsStringSync(),
          sectionId: 'section-002',
        ),
        bookId: 'progress',
        apiKey: 'sk-test',
        post: (url, headers, body) async => StoryHttpResponse(
          200,
          jsonEncode({
            'status': 'completed',
            'output': [
              {
                'type': 'message',
                'content': [
                  {'type': 'output_text', 'text': jsonEncode(delta)},
                ],
              },
            ],
          }),
        ),
      );
      expect(outcome.status, 'committed', reason: '${outcome.issues}');
    });
    tearDown(() => temp.deleteSync(recursive: true));

    int paragraphCount() =>
        ((readStoryModel(storePath)!['processed_sections'] as List).single
                as JsonMap)['paragraph_count']
            as int;

    test('partway through, keeps back what is ahead', () {
      final progress = readStoryProgress(
        storePath,
        epub,
        finished: 0,
        sectionsOnPage: const ['section-002'],
        cssSelector: _child(3),
      );
      expect(progress.finished, 0);
      expect(progress.hiddenInNext, isNotNull);
      expect(progress.paragraphsReadInNext, greaterThan(0));
      expect(progress.shown, 1);
    });

    test('keeps back less the further the reader gets', () {
      Set<String> hiddenAt(int child) =>
          readStoryProgress(
            storePath,
            epub,
            finished: 0,
            sectionsOnPage: const ['section-002'],
            cssSelector: _child(child),
          ).hiddenInNext ??
          const {};
      expect(hiddenAt(paragraphCount()).difference(hiddenAt(2)), isEmpty);
    });

    // Chapter 1's file is a heading and eight paragraphs, one block each, so
    // the page ending at block n starts the same as one starting at child n+1.
    test('to the end of the page, takes everything wholly on it', () {
      for (var block = 1; block <= 8; block++) {
        final toEnd = readStoryProgressToPageEnd(
          storePath,
          epub,
          finished: 0,
          sectionsOnPage: const ['section-002'],
          endBlock: block,
        );
        final fromStart = readStoryProgress(
          storePath,
          epub,
          finished: 0,
          sectionsOnPage: const ['section-002'],
          cssSelector: _child(block + 1),
        );
        expect(toEnd.paragraphsReadInNext, block, reason: 'block $block');
        expect(toEnd.paragraphsReadInNext, fromStart.paragraphsReadInNext);
        expect(toEnd.hiddenInNext, fromStart.hiddenInNext);
      }
    });

    test('to the end of a page past the first block, shows none of it', () {
      final progress = readStoryProgressToPageEnd(
        storePath,
        epub,
        finished: 0,
        sectionsOnPage: const ['section-002'],
        endBlock: 0,
      );
      expect(progress.shown, 0);
    });

    test('a page end that names no block leaves it at position alone', () {
      final progress = readStoryProgressToPageEnd(
        storePath,
        epub,
        finished: 0,
        sectionsOnPage: const ['section-002'],
        endBlock: 99,
      );
      expect(progress.shown, 0);
      expect(progress.hiddenInNext, isNull);
    });

    test('on the first paragraph, shows nothing of the section', () {
      final progress = readStoryProgress(
        storePath,
        epub,
        finished: 0,
        sectionsOnPage: const ['section-002'],
        cssSelector: _child(1),
      );
      expect(progress.hiddenInNext, isNull);
      expect(progress.shown, 0);
    });

    test('adds what position alone can\'t tell is finished', () {
      // The next section's first element, in a document of its own, can't be
      // found here, so a selector past this one's end stands in for it.
      final progress = readStoryProgress(
        storePath,
        epub,
        finished: 3,
        sectionsOnPage: const [],
        cssSelector: _child(1),
      );
      expect(progress.finished, 3);
    });

    for (final (what, selector) in const [
      ('can\'t be found', ':root > :nth-child(9)'),
      ('can\'t be read', 'p:not(.x)'),
    ]) {
      test('a selector that $what leaves it at position alone', () {
        final progress = readStoryProgress(
          storePath,
          epub,
          finished: 0,
          sectionsOnPage: const ['section-002'],
          cssSelector: selector,
        );
        expect(progress.finished, 0);
        expect(progress.hiddenInNext, isNull);
      });
    }

    test('the wrong EPUB leaves it at position alone', () {
      final progress = readStoryProgress(
        storePath,
        '$goldenDir/nav_order.epub',
        finished: 0,
        sectionsOnPage: const ['section-002'],
        cssSelector: _child(3),
      );
      expect(progress.hiddenInNext, isNull);
    });

    test('a store that isn\'t there leaves it at position alone', () {
      final progress = readStoryProgress(
        '${temp.path}/none',
        epub,
        finished: 2,
        sectionsOnPage: const ['section-002'],
        cssSelector: _child(3),
      );
      expect(progress.finished, 2);
      expect(progress.hiddenInNext, isNull);
    });
  });
}
