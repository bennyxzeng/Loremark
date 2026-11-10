import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/ask/ask_boundary.dart';
import 'package:loremark/ask/story_lookup.dart';
import 'package:loremark/reading/text_position.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/story_update/story_paragraphs.dart';

import '../acceptance/synthetic_story_model.dart';
import '../story_model/story_model_fixture.dart';
import 'ask_test_support.dart';

void main() {
  group('on a small book', () {
    final model = storyModelFixture();
    final all = paragraphsOf(
      model.sections,
      count: 3,
      firstId: 1,
      textOf: (section, number) =>
          'Text of ${section.id} paragraph $number, quote f0.',
    );
    StoryLookup at(int finished, {bool pastMap = false}) => StoryLookup(
      boundaryAt(model, all, finished: finished, pastMap: pastMap),
    );
    String run(StoryLookup lookup, String tool, Map<String, Object?> args) =>
        lookup.run(tool, jsonEncode(args));

    test('the overview names only what the reader has reached', () {
      final overview = at(1).overview();
      expect(overview, contains('s1 · Chapter 1: Arrival'));
      expect(overview, isNot(contains('s2')));
      expect(overview, contains('c001 · character · Mara'));
      expect(overview, isNot(contains('Elian')));
      expect(overview, isNot(contains('Captain Vell')));
      expect(overview, isNot(contains('The Glass Harbor')));
    });

    test('a later chapter brings its names in', () {
      final overview = at(2).overview();
      expect(overview, contains('Mara Quinn'));
      expect(overview, contains('Elian'));
    });

    test('an entity not met yet looks like one that doesn\'t exist', () {
      final lookup = at(1);
      final later = run(lookup, 'get_entity', {'entity_id': 'c003'});
      final none = run(lookup, 'get_entity', {'entity_id': 'c999'});
      expect(later, startsWith('Not available: c003.'));
      expect(later.replaceAll('c003', 'X'), none.replaceAll('c999', 'X'));
    });

    test('an entity card holds what is known, with the paragraphs cited', () {
      final card = run(at(1), 'get_entity', {'entity_id': 'c001'});
      expect(card, contains('Mara'));
      expect(card, contains('role: dock clerk | s1/p0001'));
      expect(card, contains('age: sixteen'));
      expect(card, contains('Mara arrives at the harbor.'));
      expect(card, isNot(contains('letter')));
    });

    test('changes from a later chapter show once it is reached', () {
      final card = run(at(2), 'get_entity', {'entity_id': 'c001'});
      // Not among the details any more, only as what changed.
      expect(card, isNot(contains('age: sixteen |')));
      expect(card, contains('No longer holds: age: sixteen'));
      expect(card, contains('How facts changed:'));
      expect(card, contains('retract'));
    });

    test('a chapter not reached is not available', () {
      final lookup = at(1);
      expect(
        run(lookup, 'get_chapter', {'section_id': 's2'}),
        startsWith('Not available: s2.'),
      );
      final chapter = run(lookup, 'get_chapter', {'section_id': 's1'});
      expect(chapter, contains('Mara arrives at the harbor.'));
      expect(chapter, contains('Open question: Who is the stranger?'));
    });

    test('an answered question says where it was answered', () {
      final chapter = run(at(2), 'get_chapter', {'section_id': 's1'});
      expect(chapter, contains('answered in s2: He is Captain Vell.'));
    });

    test('finds facts by any of the words', () {
      final found = run(at(1), 'find_facts', {'query': 'harbor nothing'});
      expect(found, contains('Mara arrives at the harbor.'));
      expect(found, contains('Harbor Guild'));
      expect(
        run(at(1), 'find_facts', {'query': 'letter'}),
        startsWith('Nothing the reader has learned mentions those words'),
      );
    });

    test('reads only paragraphs that have been read', () {
      final text = run(at(1), 'read_paragraphs', {
        'refs': ['s1/p0002', 's2/p0001', 'nonsense'],
        'context': 1,
      });
      expect(text, contains('[s1/p0001] Text of s1 paragraph 1'));
      expect(text, contains('[s1/p0003] Text of s1 paragraph 3'));
      expect(text, isNot(contains('[s2/')));
      expect(text, contains('Not available: s2/p0001, nonsense'));
    });

    test('mistakes come back as text the model can read', () {
      final lookup = at(1);
      expect(lookup.run('get_entity', 'not json'), contains('JSON object'));
      expect(lookup.run('nope', '{}'), contains('no tool called "nope"'));
      expect(run(lookup, 'get_entity', {'entity_id': 3}), contains('as text'));
      expect(run(lookup, 'read_paragraphs', {'refs': []}), contains('refs'));
    });

    test('says when the reader is in a part the map doesn\'t cover', () {
      expect(at(1, pastMap: true).overview(), contains('doesn\'t cover'));
      expect(at(1).overview(), isNot(contains('doesn\'t cover')));
    });

    test('with nothing reached, there are no tools, only the page', () {
      final lookup = at(0);
      expect(lookup.tools, isEmpty);
      expect(lookup.overview(), contains('The current page is all you have'));
      expect(lookup.run('get_entity', '{"entity_id":"c001"}'), contains('no'));
      final noMap = StoryLookup(AskBoundary(reach: AskReach.none));
      expect(noMap.overview(), contains('no Story Map yet'));
    });

    test('marks chapters the map skipped', () {
      final json = storyModelFixtureJson();
      for (final section in json['processed_sections'] as List) {
        if (section['section_id'] == 's2') section['section_order'] = 4;
      }
      final skipping = StoryModel.fromJson(json);
      final lookup = StoryLookup(
        boundaryAt(
          skipping,
          paragraphsOf(
            skipping.sections,
            count: 3,
            firstId: 1,
            textOf: (section, number) => 'x',
          ),
          finished: 2,
        ),
      );
      expect(lookup.overview(), contains('leaves out'));
    });
  });

  test('cuts a long answer at a line, and says so', () {
    final long = List.filled(2000, 'a line of text').join('\n');
    final cut = capLookup(long);
    expect(cut.length, lessThan(maxLookupChars + 100));
    expect(cut, endsWith('fewer references.]'));
    expect(capLookup('short'), 'short');
  });

  test('offers four strict tools', () {
    final model = storyModelFixture();
    final lookup = StoryLookup(
      boundaryAt(
        model,
        paragraphsOf(model.sections, textOf: (section, number) => 'x'),
        finished: 1,
      ),
    );
    expect(
      [for (final tool in lookup.tools) tool['name']],
      ['find_facts', 'get_entity', 'get_chapter', 'read_paragraphs'],
    );
    for (final tool in lookup.tools) {
      final parameters = tool['parameters'] as Map;
      expect(tool['strict'], isTrue);
      expect(parameters['additionalProperties'], isFalse);
      expect(
        parameters['required'],
        (parameters['properties'] as Map).keys.toList(),
      );
    }
  });

  // Every lookup, with every id there is, at points through seeded books: none
  // may say anything learned past the reader. Text carries the section it was
  // learned in as a tag like {s012}, and paragraphs hold their own.
  group('shows nothing past the reader', () {
    const specs = {
      'short book, many reveals': SyntheticStoryModelSpec(
        seed: 2,
        sections: 8,
        characters: 40,
        locations: 4,
        organizations: 3,
        records: 300,
        transitionRate: 0.5,
        identityLinks: 12,
      ),
      'a longer one': SyntheticStoryModelSpec(
        seed: 7,
        sections: 16,
        characters: 60,
        records: 600,
      ),
    };
    for (final MapEntry(key: name, value: spec) in specs.entries) {
      test(name, () {
        final model = generateSyntheticStoryModel(spec).model;
        final all = paragraphsOf(
          model.sections,
          textOf: (section, number) => 'Quote ${syntheticTag(section.order)}',
        );
        // So the checks below can't pass by seeing nothing.
        var sawHidden = false;
        var sawTags = 0;
        for (var finished = 0; finished < model.sections.length; finished++) {
          for (final read in [0, 1, 40, 150, 299]) {
            final boundary = boundaryAt(
              model,
              all,
              finished: finished,
              paragraphsRead: read,
            );
            final lookup = StoryLookup(boundary);
            final outputs = [
              lookup.overview(),
              for (final id in model.entities.keys)
                lookup.run('get_entity', jsonEncode({'entity_id': id})),
              for (final section in model.sections)
                lookup.run(
                  'get_chapter',
                  jsonEncode({'section_id': section.id}),
                ),
              for (final section in model.sections)
                lookup.run(
                  'find_facts',
                  jsonEncode({'query': '${syntheticTag(section.order)} quote'}),
                ),
              for (final section in model.sections)
                lookup.run(
                  'read_paragraphs',
                  jsonEncode({
                    'refs': [
                      for (final n in [0, 1, 40, 41, 150, 151, 298, 299])
                        '${section.id}/p${'$n'.padLeft(4, '0')}',
                    ],
                    'context': 3,
                  }),
                ),
            ];
            final reached = boundary.progress.shown;
            final hidden = boundary.progress.hiddenInNext ?? const <String>{};
            final reason = '$name at $finished+$read';
            for (final output in outputs) {
              for (final order in sectionTagsIn(output)) {
                sawTags++;
                expect(order, lessThanOrEqualTo(reached), reason: reason);
              }
              for (final id in hidden) {
                expect(
                  RegExp('\\b$id\\b').hasMatch(output),
                  isFalse,
                  reason: '$reason shows $id',
                );
              }
              _expectRefsRead(output, boundary.paragraphs, reason);
            }
            if (hidden.isNotEmpty) sawHidden = true;
          }
        }
        expect(sawHidden, isTrue);
        expect(sawTags, greaterThan(1000));
      });
    }
  });

  test('the overview keeps a long cast to the most mentioned', () {
    final model = generateSyntheticStoryModel(
      const SyntheticStoryModelSpec(sections: 4, characters: 500, records: 900),
    ).model;
    final lookup = StoryLookup(
      boundaryAt(
        model,
        paragraphsOf(model.sections, textOf: (section, number) => 'x'),
        finished: 4,
      ),
    );
    final overview = lookup.overview();
    final listed = RegExp(
      r'^- [clg]\d+ · ',
      multiLine: true,
    ).allMatches(overview).length;
    if (lookup.boundary.snapshot!.knownEntities.length > maxOverviewEntities) {
      expect(listed, maxOverviewEntities);
      expect(overview, contains('more not listed'));
    }
    expect(lookup.boundary.reach.limit, const TextPosition(0, 0));
  });
}

/// Every paragraph reference in [output] is one the reader has read.
void _expectRefsRead(String output, StoryParagraphs read, String reason) {
  for (final match in RegExp(r'(s\d{3})/(p\d{4})').allMatches(output)) {
    if (output.substring(0, match.start).endsWith('Not available: ') ||
        _inNotAvailable(output, match.start)) {
      continue;
    }
    expect(
      read.paragraph(match[1]!, match[2]!),
      isNotNull,
      reason: '$reason cites ${match[0]}',
    );
  }
}

bool _inNotAvailable(String output, int at) {
  final line = output.lastIndexOf('\n', at) + 1;
  return output.startsWith('Not available', line);
}
