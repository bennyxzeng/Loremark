import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/epub_sections.dart';
import 'package:loremark/recap/recap_source.dart';
import 'package:loremark/story_model/story_model.dart';

import '../story_model/story_model_fixture.dart';

const _spine = [
  SpineItem(path: 'OEBPS/title.xhtml', linear: true),
  SpineItem(path: 'OEBPS/ch1.xhtml', linear: true),
  SpineItem(path: 'OEBPS/ch2.xhtml', linear: true),
];

/// A section long enough to recap: a heading, then one sentence many times.
String _chapter(String heading, String sentence) =>
    '$heading\n\n${List.filled(30, sentence).join(' ')}';

final _texts = [
  'The Glass Harbor',
  _chapter('Chapter 1: Arrival', 'Mara walks along the quay.'),
  _chapter('Chapter 2: The Letter', 'Elian is secretly the harbor master.'),
];

void main() {
  group('without a Story Map', () {
    test('there is nothing to recap before a section is finished', () {
      expect(
        buildRecapSource(
          spine: _spine,
          sectionTexts: _texts,
          finishedSpineItems: 0,
        ),
        isNull,
      );
    });

    test('a title page alone is not worth a recap', () {
      expect(
        buildRecapSource(
          spine: _spine,
          sectionTexts: _texts,
          finishedSpineItems: 1,
        ),
        isNull,
      );
    });

    test('uses the end of the last finished chapter and nothing after', () {
      final source = buildRecapSource(
        spine: _spine,
        sectionTexts: _texts,
        finishedSpineItems: 2,
      )!;

      expect(source.cutoffLabel, 'Chapter 1: Arrival');
      expect(source.sectionText, contains('Mara walks along the quay.'));
      expect(source.hasStoryFacts, isFalse);
      expect(source.serialize(), isNot(contains('Elian')));
      expect(source.serialize(), contains('no Story Map has been built'));
    });

    test('steps over footnotes and short pages at the end', () {
      final spine = [
        ..._spine,
        const SpineItem(path: 'OEBPS/notes.xhtml', linear: false),
        const SpineItem(path: 'OEBPS/plate.xhtml', linear: true),
      ];
      final texts = [..._texts, _chapter('Notes', 'A footnote.'), 'Plate 3'];

      final source = buildRecapSource(
        spine: spine,
        sectionTexts: texts,
        finishedSpineItems: 5,
      )!;

      expect(source.cutoffLabel, 'Chapter 2: The Letter');
    });

    test('names a section without a heading by its number', () {
      final texts = [
        _texts[0],
        List.filled(40, 'Mara walks along the quay.').join(' '),
      ];

      final source = buildRecapSource(
        spine: _spine,
        sectionTexts: texts,
        finishedSpineItems: 2,
      )!;

      expect(source.cutoffLabel, 'Section 2');
    });
  });

  group('with a Story Map', () {
    test('only has facts up to the last finished story section', () {
      final source = buildRecapSource(
        spine: _spine,
        sectionTexts: _texts,
        finishedSpineItems: 2,
        model: storyModelFixture(),
        finishedStorySections: 1,
      )!;

      expect(source.hasStoryFacts, isTrue);
      expect(source.characters, contains('Mara'));
      expect(source.events.map((event) => event.line), [
        'E1 [Chapter 1] Mara arrives at the harbor.',
      ]);
      expect(source.events.single.quotes.map((quote) => quote.text), [
        'quote f013',
      ]);
      expect(source.openQuestions, ['Who is the stranger?']);
      // Chapter 2 adds Elian, renames Mara and reveals Captain Vell.
      final message = source.serialize();
      expect(message, contains('E1 [Chapter 1] Mara arrives at the harbor.'));
      for (final spoiler in ['Elian', 'Quinn', 'Vell', 'letter']) {
        expect(message, isNot(contains(spoiler)), reason: spoiler);
      }
    });

    test('knows what a later finished section revealed', () {
      final source = buildRecapSource(
        spine: _spine,
        sectionTexts: _texts,
        finishedSpineItems: 3,
        model: storyModelFixture(),
        finishedStorySections: 2,
      )!;

      expect(source.characters, contains('Elian'));
      expect(source.events.last.chapter, 'Chapter 2');
      expect(source.events.last.text, 'Elian hands Mara a letter.');
      expect(
        source.events.map((event) => event.text),
        contains('(remembered, from the past) Elian left home years ago.'),
      );
      // Each event has its own ID, in order, for the recap to point back to.
      expect(source.events.map((event) => event.id), [
        for (var i = 1; i <= source.events.length; i++) 'E$i',
      ]);
      // The stranger's question was answered in chapter 2.
      expect(source.openQuestions, ['Why did Elian leave?']);
    });

    test('a Story Map built past the reader adds nothing past them', () {
      // The map covers both chapters, but the reader finished only one.
      final source = buildRecapSource(
        spine: _spine,
        sectionTexts: _texts,
        finishedSpineItems: 2,
        model: storyModelFixture(),
        finishedStorySections: 1,
      )!;

      expect(source.characters, isNot(contains('Elian')));
    });

    test('uses the Story Map title for the finished chapter', () {
      final json = storyModelFixtureJson();
      for (final section in json['processed_sections'] as List) {
        final map = section as Map<String, dynamic>;
        map['href'] = map['section_id'] == 's1'
            ? 'OEBPS/ch1.xhtml'
            : 'OEBPS/ch2.xhtml';
      }
      final texts = [
        _texts[0],
        _chapter('I', 'Mara walks along the quay.'),
        _texts[2],
      ];

      final source = buildRecapSource(
        spine: _spine,
        sectionTexts: texts,
        finishedSpineItems: 2,
        model: StoryModel.fromJson(json),
        finishedStorySections: 1,
      )!;

      expect(source.cutoffLabel, 'Chapter 1: Arrival');
    });
  });

  group('passages', () {
    /// The fixture's model with this book's chapter files, and [quote] as the
    /// evidence for "Mara arrives at the harbor."
    StoryModel modelQuoting(String quote) {
      final json = storyModelFixtureJson();
      for (final section in json['processed_sections'] as List) {
        final map = section as Map<String, dynamic>;
        map['href'] = map['section_id'] == 's1'
            ? 'OEBPS/ch1.xhtml'
            : 'OEBPS/ch2.xhtml';
      }
      final records = json['records'] as Map<String, dynamic>;
      final arrival = (records['events'] as List).first as Map<String, dynamic>;
      final evidence = (arrival['evidence'] as List).single;
      (evidence as Map<String, dynamic>)['quote'] = quote;
      return StoryModel.fromJson(json);
    }

    /// The quote behind the one event a reader who finished chapter 1 knows.
    RecapQuote quoteAfterChapterOne(String quote, {List<String>? texts}) =>
        buildRecapSource(
          spine: _spine,
          sectionTexts: texts ?? _texts,
          finishedSpineItems: 2,
          model: modelQuoting(quote),
          finishedStorySections: 1,
        )!.events.single.quotes.single;

    test('a quote is found in the chapter it is from', () {
      final quote = quoteAfterChapterOne('Mara walks along the quay.');

      expect(quote.text, 'Mara walks along the quay.');
      expect(quote.target!.sectionIndex, 1);
      expect(quote.target!.highlight, contains('Mara walks along the quay.'));
    });

    test('never opens the book past the reader', () {
      // A real quote, but from chapter 2, which the reader hasn't finished.
      final quote = quoteAfterChapterOne(
        'Elian is secretly the harbor master.',
      );

      expect(quote.text, 'Elian is secretly the harbor master.');
      expect(quote.target, isNull);
    });

    test('straight quotes find curly ones', () {
      final texts = [
        _texts[0],
        _chapter('Chapter 1: Arrival', 'Mara’s boat is late again.'),
        _texts[2],
      ];

      final quote = quoteAfterChapterOne(
        "Mara's boat is late again.",
        texts: texts,
      );

      expect(quote.target!.sectionIndex, 1);
      expect(quote.target!.highlight, contains('Mara’s boat is late again.'));
    });

    test('a quote whose end the model changed is found by its start', () {
      final quote = quoteAfterChapterOne(
        'Mara walks along the quay. Mara walks along the pier.',
      );

      expect(quote.target!.sectionIndex, 1);
    });

    test('a quote that isn’t in the book has nowhere to open', () {
      expect(quoteAfterChapterOne('The sea was calm.').target, isNull);
    });
  });

  group('recapTail', () {
    test('keeps a short section whole', () {
      expect(recapTail('  Mara walks.  '), 'Mara walks.');
    });

    test('keeps only the end of a long section, starting at a word', () {
      final text = List.generate(5000, (i) => 'word$i').join(' ');

      final tail = recapTail(text);

      expect(tail.length, lessThanOrEqualTo(recapTextLimit));
      expect(tail, endsWith('word4999'));
      expect(tail, startsWith('word'));
    });

    test('cuts text without spaces too', () {
      final tail = recapTail('海' * 20000);

      expect(tail.length, lessThanOrEqualTo(recapTextLimit));
    });
  });

  group('sectionHeading', () {
    test('is the first line when it is short', () {
      expect(sectionHeading('\n\nChapter 3\n\nShe ran.'), 'Chapter 3');
    });

    test('is null when the first line is a paragraph', () {
      expect(sectionHeading('${'She ran. ' * 20}\n\nMore.'), isNull);
    });
  });
}
