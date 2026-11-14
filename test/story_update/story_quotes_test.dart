import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/story_update/story_book.dart';
import 'package:loremark/story_update/story_quotes.dart';

const _section = 'section-009';

/// A section of [texts], numbered p0001, p0002, ...
JsonMap _chapter(List<String> texts) => {
  'section_id': _section,
  'paragraphs': [
    for (final (i, text) in texts.indexed)
      {'id': 'p${'${i + 1}'.padLeft(4, '0')}', 'text': text},
  ],
};

/// An answer with one name record citing [quote] in [paragraph].
JsonMap _answer(
  String paragraph,
  String quote, {
  String section = _section,
}) => {
  'new_entities': <Object>[],
  'new_records': {
    'names': [
      {
        'local_id': 'new_record_001',
        'payload': {'entity_id': 'new_entity_001', 'text': 'Orla'},
        'evidence': [
          {'section_id': section, 'paragraph_id': paragraph, 'quote': quote},
        ],
      },
    ],
  },
  'transitions': <Object>[],
};

JsonMap _evidenceOf(Object? answer) =>
    ((((answer! as JsonMap)['new_records'] as JsonMap)['names'] as List)[0]
            as JsonMap)['evidence'][0]
        as JsonMap;

// Made up for these tests, after the slips seen in real runs.
const _story = [
  'The rain had not stopped for three days.',
  'Captain Orla Venn kept her squad in the old mill by the river.',
  'If we strike them near the north bridge, we can be home by dawn, she said.',
  'The two scout walkers carried rifles on their backs and lamps on their heads.',
  'On the card were the words ‘For my brave Tomas’ in faded ink.',
  'Tomas was the sort of pilot who’d flown for nine winters without a scratch.',
  'The convoy from Neuhäusen arrived at noon.',
  '“You really are a strange one, Orla,” Tomas laughed.',
];

void main() {
  final chapter = _chapter(_story);

  /// The evidence [quote] in [paragraph] becomes, and the one repair made.
  (JsonMap, QuoteRepair) repaired(String paragraph, String quote) {
    final (answer, repairs) = repairStoryQuotes(
      _answer(paragraph, quote),
      chapter,
    );
    expect(repairs, hasLength(1));
    return (_evidenceOf(answer), repairs.single);
  }

  void unrepaired(
    String paragraph,
    String quote, {
    JsonMap? within,
    String section = _section,
  }) {
    final answer = _answer(paragraph, quote, section: section);
    final (result, repairs) = repairStoryQuotes(answer, within ?? chapter);
    expect(repairs, isEmpty);
    expect(identical(result, answer), isTrue);
  }

  group('a quote that slipped is put back to the book’s text:', () {
    test('cited in the paragraph next to the one it’s in', () {
      final (evidence, repair) = repaired('p0003', 'Orla Venn kept her squad');
      expect(evidence['paragraph_id'], 'p0002');
      expect(evidence['quote'], 'Orla Venn kept her squad');
      expect(repair.kind, 'moved');
      expect(repair.distance, 0);
    });

    test('in several paragraphs, it goes to the nearest', () {
      final section = _chapter([
        'The bell rang twice.',
        'One.',
        'Two.',
        'Three.',
        'The bell rang twice.',
      ]);
      final (answer, _) = repairStoryQuotes(
        _answer('p0004', 'The bell rang twice.'),
        section,
      );
      expect(_evidenceOf(answer)['paragraph_id'], 'p0005');
    });

    test('a word left out', () {
      final (evidence, repair) = repaired(
        'p0003',
        'If we strike near the north bridge',
      );
      expect(evidence['quote'], 'If we strike them near the north bridge');
      expect(evidence['paragraph_id'], 'p0003');
      expect(repair.kind, 'snapped');
      expect(repair.distance, 5);
    });

    test('a word added before it', () {
      final (evidence, _) = repaired(
        'p0002',
        'and Captain Orla Venn kept her squad',
      );
      expect(evidence['quote'], 'Captain Orla Venn kept her squad');
    });

    test('a word changed', () {
      final (evidence, _) = repaired(
        'p0004',
        'carried rifles on its backs and lamps',
      );
      expect(evidence['quote'], 'carried rifles on their backs and lamps');
    });

    test('other quote marks', () {
      final (evidence, repair) = repaired('p0005', '“For my brave Tomas”');
      expect(evidence['quote'], '‘For my brave Tomas’');
      expect(repair.distance, 0);
    });

    test('other capitals', () {
      final (evidence, _) = repaired(
        'p0008',
        'you really are a strange one, Orla',
      );
      expect(evidence['quote'], 'You really are a strange one, Orla');
    });

    test('a garbled letter', () {
      final (evidence, _) = repaired(
        'p0007',
        'The convoy from Neuh盲usen arrived',
      );
      expect(evidence['quote'], 'The convoy from Neuhäusen arrived');
    });

    test('part of a word, which is made whole', () {
      final (evidence, _) = repaired(
        'p0006',
        'he’d flown for nine winters without a scratch',
      );
      expect(
        evidence['quote'],
        'who’d flown for nine winters without a scratch',
      );
    });

    test('in a paragraph near the cited one', () {
      final (evidence, repair) = repaired(
        'p0002',
        'If we strike near the north bridge',
      );
      expect(evidence['paragraph_id'], 'p0003');
      expect(evidence['quote'], 'If we strike them near the north bridge');
      expect(repair.fromParagraph, 'p0002');
      expect(repair.toParagraph, 'p0003');
    });

    test('in Chinese, without widening to a word', () {
      final section = _chapter(['小林在图书馆里读了一下午的书。']);
      final (answer, _) = repairStoryQuotes(
        _answer('p0001', '林在图书馆读了一下午的书'),
        section,
      );
      expect(_evidenceOf(answer)['quote'], '林在图书馆里读了一下午的书');
    });

    test('next to characters outside the Basic Multilingual Plane', () {
      final section = _chapter([
        'She sent 🙂 and then 🚀 to the whole crew at once.',
      ]);
      final (answer, _) = repairStoryQuotes(
        _answer('p0001', 'She sent 🙂 and 🚀 to the whole crew'),
        section,
      );
      expect(
        _evidenceOf(answer)['quote'],
        'She sent 🙂 and then 🚀 to the whole crew',
      );
    });

    test('in a transition too', () {
      final answer = _answer('p0001', 'The rain had not stopped')
        ..['transitions'] = [
          {
            'target_record_id': 'f000001',
            'evidence': [
              {
                'section_id': _section,
                'paragraph_id': 'p0001',
                'quote': 'Captain Orla Venn kept her squad',
              },
            ],
          },
        ];
      final (_, repairs) = repairStoryQuotes(answer, chapter);
      expect(repairs.single.path, 'transitions[0].evidence[0]');
    });
  });

  group('left for the validator:', () {
    test('a quote already in its paragraph', () {
      unrepaired('p0002', 'Captain Orla Venn');
    });

    test('a sentence that isn’t in the book', () {
      unrepaired('p0002', 'The dragon swallowed the moon whole.');
    });

    test('a quote that is a fifth or more different', () {
      unrepaired('p0002', 'Captain Orla Venn burned the old mill down');
    });

    test('a near quote more than two paragraphs away', () {
      unrepaired('p0007', 'If we strike near the north bridge');
    });

    test('a short quote that isn’t word for word', () {
      unrepaired('p0002', 'Orla Vemn');
    });

    test('evidence from another section', () {
      unrepaired('p0003', 'Orla Venn kept her squad', section: 'section-001');
    });

    test('a quote whose repair would be over 300 characters', () {
      // Made-up words unlike each other, so that no cheaper match lines up
      // one word with the next.
      final random = Random(7);
      final words = [
        for (var i = 0; i < 80; i++)
          String.fromCharCodes([
            for (var j = 0; j < 6; j++) 0x61 + random.nextInt(26),
          ]),
      ];
      final section = _chapter([words.join(' ')]);
      // The first 44 words are 307 characters; leaving one out makes 300.
      final quote = (words.take(44).toList()..removeAt(20)).join(' ');
      expect(quote.length, 300);
      unrepaired('p0001', quote, within: section);
    });

    test('evidence that isn’t shaped as the schema says', () {
      final answer = jsonDecode(
        jsonEncode(_answer('p0003', 'Orla Venn kept her squad')),
      ) as JsonMap;
      _evidenceOf(answer)['quote'] = 42;
      final (result, repairs) = repairStoryQuotes(answer, chapter);
      expect(repairs, isEmpty);
      expect(identical(result, answer), isTrue);
      expect(repairStoryQuotes('not an answer', chapter).$2, isEmpty);
    });
  });

  test('the model’s answer itself is left as it came', () {
    final answer = _answer('p0003', 'Orla Venn kept her squad');
    final before = jsonEncode(answer);
    final (result, _) = repairStoryQuotes(answer, chapter);
    expect(jsonEncode(answer), before);
    expect(identical(result, answer), isFalse);
  });

  test('a repair is a warning, and a correction per changed field', () {
    final (_, repair) = repaired('p0002', 'If we strike near the north bridge');
    expect(repair.path, 'new_records.names[0].evidence[0]');
    expect(repair.issue.severity, 'warning');
    expect(repair.issue.code, 'quote_repaired');
    expect(repair.issue.path, repair.path);
    final corrections = repair.corrections('2026-11-10T00:00:00Z');
    expect(
      [for (final c in corrections) c['path']],
      [
        'new_records.names[0].evidence[0].paragraph_id',
        'new_records.names[0].evidence[0].quote',
      ],
    );
    expect(corrections.last['from'], 'If we strike near the north bridge');
    expect(corrections.last['to'], 'If we strike them near the north bridge');
    expect(corrections.last['corrected_by'], storyQuoteRepairer);
  });
}
