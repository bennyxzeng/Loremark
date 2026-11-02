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

    test('describes relationships with current names', () {
      final [relationship] = chapter2.relationshipsOf('c003');
      expect(
        chapter2.describe(relationship.payload),
        'Elian sibling of Mara Quinn',
      );
    });
  });
}
