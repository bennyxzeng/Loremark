import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/story_model/story_snapshot.dart';

import 'story_model_fixture.dart';

void main() {
  final model = storyModelFixture();
  final chapter1 = StorySnapshot(model, model.sections[0]);
  final chapter2 = StorySnapshot(model, model.sections[1]);

  List<String> ids(Iterable<StoryRecord> records) => [
    for (final record in records) record.id,
  ];

  test('sorts sections into reading order', () {
    expect([for (final s in model.sections) s.id], ['s1', 's2']);
    expect(model.sections[1].label, 'Chapter 2');
  });

  test('rejects other schema versions', () {
    expect(
      () => StoryModel.fromJson({
        ...storyModelFixtureJson(),
        'schema_version': '1.0',
      }),
      throwsFormatException,
    );
  });

  group('at chapter 1', () {
    test('hides entities and facts first learned in chapter 2', () {
      expect(
        [for (final e in chapter1.knownEntities) e.id],
        ['c001', 'c002', 'g001'],
      );
      expect(ids(chapter1.relationships), ['f010', 'f011']);
      expect(ids(chapter1.events), ['f013']);
      expect(chapter1.transitions, isEmpty);
    });

    test('uses names as they were then', () {
      expect(chapter1.displayName('c001'), 'Mara');
      expect(chapter1.aliasesOf('c001'), ['the harbor girl']);
      expect(chapter1.displayName('c002'), 'the stranger');
    });

    test('keeps facts a later chapter withdraws', () {
      expect(ids(chapter1.attributesOf('c001')), ['f008', 'f009']);
    });

    test('keeps questions a later chapter answers open', () {
      final [question] = chapter1.questionsOf('c002');
      expect(question.resolution, isNull);
    });
  });

  group('at chapter 2', () {
    test('applies the rename', () {
      expect(chapter2.displayName('c001'), 'Mara Quinn');
      expect(chapter2.aliasesOf('c001'), ['the harbor girl']);
      final rename = chapter2
          .transitionsOf('c001')
          .singleWhere((t) => t.action == TransitionAction.supersede);
      expect(chapter2.describeTransition(rename), 'Mara → Mara Quinn');
    });

    test('drops a retracted fact', () {
      expect(ids(chapter2.attributesOf('c001')), ['f008']);
    });

    test('answers a resolved question', () {
      final [question] = chapter2.questionsOf('c002');
      expect(question.resolution?.resolution, 'He is Captain Vell.');
    });

    test('merges entities with a revealed identity', () {
      expect(chapter2.canonicalId('c004'), 'c002');
      expect(chapter2.membersOf('c004'), ['c002', 'c004']);
      expect(chapter2.aliasesOf('c002'), ['Captain Vell']);
      expect([
        for (final e in chapter2.knownEntities) e.id,
      ], isNot(contains('c004')));
      expect(chapter1.canonicalId('c004'), 'c004');
    });

    test('marks what is new in the chapter', () {
      expect(
        [
          for (final e in chapter2.knownEntities)
            if (chapter2.isNewEntity(e.id)) e.id,
        ],
        ['c003'],
      );
      expect(ids(chapter2.relationships.where(chapter2.isNewRecord)), ['f012']);
      expect(ids(chapter2.events.where(chapter2.isNewRecord)), [
        'f015',
        'f014',
      ]);
      expect(chapter2.firstSeenSection('c001').id, 's1');
    });

    group('reveals', () {
      StorySnapshot chapter2Of(void Function(Map<String, dynamic>) change) {
        final json = storyModelFixtureJson();
        change(json['records'] as Map<String, dynamic>);
        final model = StoryModel.fromJson(json);
        return StorySnapshot(model, model.sections[1]);
      }

      Map<String, dynamic> payloadOf(List<dynamic> records, String id) =>
          (records.cast<Map<String, dynamic>>().singleWhere(
                (record) => record['id'] == id,
              ))['payload']
              as Map<String, dynamic>;

      test('an explicit identity link reveals who both sides are', () {
        expect(chapter2.isRevealedEntity('c002'), isTrue);
        expect(chapter2.isRevealedEntity('c004'), isTrue);
        expect(chapter2.revealOf('c002')?.note, 'also Captain Vell');
        expect(chapter2.revealOf('c002')?.formerName, isNull);
      });

      test('an inferred identity link reveals nothing', () {
        final snapshot = chapter2Of((records) {
          payloadOf(records['identity_links'] as List, 'f018')['assertion'] =
              'inferred';
        });

        expect(snapshot.isRevealedEntity('c002'), isFalse);
      });

      test('a name spelled out in full reveals nothing', () {
        expect(chapter2.displayName('c001'), 'Mara Quinn');
        expect(chapter2.isRevealedEntity('c001'), isFalse);
      });

      test('an unrelated new name is a reveal', () {
        final snapshot = chapter2Of((records) {
          payloadOf(records['names'] as List, 'f006')['text'] = 'Captain Rowe';
        });

        expect(snapshot.isRevealedEntity('c001'), isTrue);
        expect(snapshot.revealOf('c001')?.note, 'was Mara');
        expect(snapshot.revealOf('c001')?.formerName, 'Mara');
      });

      test('an entity nothing happened to is not revealed', () {
        expect(chapter2.isRevealedEntity('c003'), isFalse);
      });

      test('nothing is revealed before the chapter that reveals it', () {
        final snapshot = chapter1;

        expect(snapshot.isRevealedEntity('c002'), isFalse);
        expect(snapshot.isRevealedEntity('c001'), isFalse);
      });
    });

    group('stars', () {
      StorySnapshot withFacts(int count) {
        final json = storyModelFixtureJson();
        final records = json['records'] as Map<String, dynamic>;
        (json['entities'] as List).add(<String, dynamic>{
          'id': 'c009',
          'kind': 'character',
          'introduced_revision': 2,
        });
        (records['attributes'] as List).addAll(<Map<String, dynamic>>[
          for (var i = 0; i < count; i++)
            <String, dynamic>{
              'id': 'extra$i',
              'introduced_revision': 2,
              'learned_in_section_id': 's2',
              'legacy_id': null,
              'payload': <String, dynamic>{
                'entity_id': 'c009',
                'label': 'detail_$i',
                'value': 'fact $i',
                'assertion': 'explicit',
                'attributed_to_id': null,
              },
              'evidence': <Map<String, dynamic>>[],
            },
        ]);
        final model = StoryModel.fromJson(json);
        return StorySnapshot(model, model.sections[1]);
      }

      test('follow how many facts are known', () {
        const expected = {
          0: 1,
          1: 1,
          2: 2,
          5: 2,
          6: 3,
          14: 3,
          15: 4,
          29: 4,
          30: 5,
          60: 5,
        };
        for (final MapEntry(key: facts, value: stars) in expected.entries) {
          expect(withFacts(facts).starsOf('c009'), stars, reason: '$facts');
        }
      });

      test('count only what the chapter has reached', () {
        expect(chapter1.starsOf('c001'), 2);
        expect(chapter2.starsOf('c001'), 3);
      });
    });

    test('describes relationships with current names', () {
      final [relationship] = chapter2.relationshipsOf('c003');
      expect(
        chapter2.describe(relationship.payload),
        'Elian sibling of Mara Quinn',
      );
    });
  });
}
