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

  group('partway through a section', () {
    final section = model.sections[1];

    test('with nothing hidden, is the end of the section', () {
      final partial = StorySnapshot(model, section, hidden: const {});
      expect(
        ids(partial.relationships),
        ids(StorySnapshot(model, section).relationships),
      );
      expect(partial.transitions, hasLength(chapter2.transitions.length));
    });

    test('leaves out what is hidden everywhere it would show', () {
      final partial = StorySnapshot(
        model,
        section,
        hidden: {
          for (final record in model.allRecords)
            if (record.learnedInSectionId == section.id) record.id,
        },
      );
      expect(ids(partial.relationships), isNot(contains('f012')));
      expect(ids(partial.events), isNot(contains('f014')));
      expect(partial.knownEntities.map((e) => e.id), isNot(contains('c003')));
      expect(partial.isNewRecord(model.recordsById['f012']!), isFalse);
    });

    test('a hidden change leaves the old fact standing', () {
      final partial = StorySnapshot(
        model,
        section,
        hidden: const {'t001', 'f006'},
      );
      expect(partial.displayName('c001'), 'Mara');
      expect(chapter2.displayName('c001'), 'Mara Quinn');
      expect(partial.transitions.map((t) => t.id), isNot(contains('t001')));
    });

    test('an open question stays open until its answer is reached', () {
      final partial = StorySnapshot(model, section, hidden: const {'t003'});
      final question = partial.questions.firstWhere(
        (item) => item.record.id == 'f016',
      );
      expect(question.resolution, isNull);
    });

    test('a hidden question isn\'t asked', () {
      final partial = StorySnapshot(model, section, hidden: const {'f017'});
      expect(
        partial.questions.map((item) => item.record.id),
        isNot(contains('f017')),
      );
    });
  });

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

    test('describes relationships with current names', () {
      final [relationship] = chapter2.relationshipsOf('c003');
      expect(
        chapter2.describe(relationship.payload),
        'Elian sibling of Mara Quinn',
      );
    });
  });
}
