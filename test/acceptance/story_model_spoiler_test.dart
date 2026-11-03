import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/story_model/story_snapshot.dart';

import 'synthetic_story_model.dart';

// Spoiler audit for the story model (spec: "nothing past the cutoff is
// retrieved or shown"). For every section of the bundled demo model and of
// seeded synthetic models, it builds the snapshot a reader at that section
// sees and checks, through `StorySnapshot`'s public API only, that:
//
// - every record, transition, entity, relationship and question shown was
//   learned at or before the section, and cites evidence at or before it;
// - nothing a reached transition supersedes or retracts is shown as active;
// - an entity first introduced later never appears, not even as a member of
//   an identity group, and groups only join entities by reached, still-active
//   explicit links;
// - no text shown (names, descriptions, transition summaries) was learned
//   later. The synthetic models tag each text with its section to prove this.
//
// The expected sets are recomputed here straight from the raw model, so this
// is a second opinion on `StorySnapshot`, not a copy of its code.

void main() {
  group('bundled demo model', () {
    final model = StoryModel.fromJson(
      jsonDecode(File('assets/story_models/86v1.json').readAsStringSync())
          as Map<String, dynamic>,
    );

    test('is well formed', () {
      expect(modelProblems(model), isEmpty);
    });

    test('shows nothing past the reader in any section', () {
      for (final section in model.sections) {
        expect(
          auditSnapshot(StorySnapshot(model, section)),
          isEmpty,
          reason: 'section ${section.id}',
        );
      }
    });
  });

  group('synthetic models', () {
    const specs = {
      'default': SyntheticStoryModelSpec(),
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
      'long book, few facts per chapter': SyntheticStoryModelSpec(
        seed: 3,
        sections: 90,
        characters: 150,
        locations: 15,
        organizations: 8,
        records: 700,
        transitionRate: 0.2,
        identityLinks: 25,
      ),
      'heavy supersede chains': SyntheticStoryModelSpec(
        seed: 4,
        sections: 25,
        characters: 60,
        locations: 6,
        organizations: 4,
        records: 900,
        transitionRate: 0.9,
        identityLinks: 20,
      ),
      'no identity links': SyntheticStoryModelSpec(
        seed: 5,
        sections: 30,
        records: 800,
        identityLinks: 0,
      ),
    };

    for (final MapEntry(key: name, value: spec) in specs.entries) {
      group(name, () {
        final generated = generateSyntheticStoryModel(spec);
        final model = generated.model;

        test('is well formed and covers every kind of change', () {
          expect(modelProblems(model), isEmpty);
          expect(model.sections, hasLength(spec.sections));
          final actions = {for (final t in model.transitions) t.action};
          expect(actions, TransitionAction.values.toSet());
          // The generator's own ground truth matches what the records say.
          expect(generated.introducedIn, firstMentions(model));
        });

        test('shows nothing past the reader in any section', () {
          for (final section in model.sections) {
            final problems = auditSnapshot(StorySnapshot(model, section));
            expect(problems, isEmpty, reason: 'section ${section.id}');
          }
        });
      });
    }

    test('identity links merge entities only once revealed', () {
      // At least one explicit link must be revealed late enough that the
      // merge is visibly absent before it, or the audit proves nothing.
      final model = generateSyntheticStoryModel(
        const SyntheticStoryModelSpec(seed: 6, identityLinks: 20),
      ).model;
      var mergedLate = 0;
      final last = StorySnapshot(model, model.sections.last);
      for (final entity in last.knownEntities) {
        final members = last.membersOf(entity.id);
        if (members.length < 2) continue;
        final first = model.sections.first;
        if (StorySnapshot(model, first).membersOf(entity.id).length <
            members.length) {
          mergedLate++;
        }
      }
      expect(mergedLate, greaterThan(0));
    });
  });

  // The audit must be able to fail. These feed it models with a leak planted
  // in the data, which StorySnapshot passes through faithfully.
  group('audit catches planted leaks', () {
    Map<String, dynamic> json() => generateSyntheticStoryModel(
      const SyntheticStoryModelSpec(sections: 6, records: 500),
    ).json;

    Map<String, dynamic> firstRecord(
      Map<String, dynamic> json,
      String collection,
      String section,
    ) => ((json['records'] as Map)[collection] as List).cast<Map>().firstWhere(
      (r) => r['learned_in_section_id'] == section,
    ) as Map<String, dynamic>;

    List<String> auditAt(Map<String, dynamic> json, String sectionId) {
      final model = StoryModel.fromJson(json);
      return auditSnapshot(StorySnapshot(model, model.sectionById(sectionId)!));
    }

    test('evidence from a later section', () {
      final data = json();
      final record = firstRecord(data, 'attributes', 's002');
      (record['evidence'] as List).add({
        'section_id': 's005',
        'paragraph_id': 'p0001',
        'quote': 'Quote ${syntheticTag(5)}',
      });
      expect(auditAt(data, 's002'), isNotEmpty);
      expect(auditAt(data, 's005'), isEmpty);
    });

    test('a transition that replaces a fact with one from a later section', () {
      final data = json();
      final replacement = firstRecord(data, 'attributes', 's005');
      final target = firstRecord(data, 'attributes', 's001');
      (data['transitions'] as List).add({
        'id': 't999999',
        'introduced_revision': 2,
        'learned_in_section_id': 's002',
        'target_record_id': target['id'],
        'action': 'supersede',
        'replacement_record_id': replacement['id'],
        'resolution': null,
        'reason': 'Reason ${syntheticTag(2)}',
        'evidence': <Map<String, dynamic>>[],
      });
      expect(auditAt(data, 's002'), isNotEmpty);
    });

    test('a transition that cites a later section', () {
      final data = json();
      final target = firstRecord(data, 'attributes', 's001');
      (data['transitions'] as List).add({
        'id': 't999999',
        'introduced_revision': 2,
        'learned_in_section_id': 's002',
        'target_record_id': target['id'],
        'action': 'retract',
        'replacement_record_id': null,
        'resolution': null,
        'reason': 'Reason ${syntheticTag(2)}',
        'evidence': [
          {
            'section_id': 's004',
            'paragraph_id': 'p0001',
            'quote': 'Quote ${syntheticTag(4)}',
          },
        ],
      });
      expect(auditAt(data, 's002'), isNotEmpty);
      expect(auditAt(data, 's004'), isEmpty);
    });

    test('a fact that a reached transition retracts', () {
      // Not a leak in the data but in the view: if a snapshot ignored the
      // transition, the audit has to notice the fact is still shown. The
      // audit's own bookkeeping is checked by retracting a fact and making
      // sure the clean model is accepted either side of it.
      final data = json();
      final target = firstRecord(data, 'attributes', 's001');
      (data['transitions'] as List).add({
        'id': 't999998',
        'introduced_revision': 3,
        'learned_in_section_id': 's003',
        'target_record_id': target['id'],
        'action': 'retract',
        'replacement_record_id': null,
        'resolution': null,
        'reason': 'Reason ${syntheticTag(3)}',
        'evidence': <Map<String, dynamic>>[],
      });
      expect(auditAt(data, 's002'), isEmpty);
      expect(auditAt(data, 's003'), isEmpty);
    });
  });
}

int _order(StoryModel model, String sectionId) =>
    model.sectionById(sectionId)?.order ?? -1;

/// Problems in the model's own data that would make a snapshot's output wrong
/// no matter how correct the snapshot is.
List<String> modelProblems(StoryModel model) {
  final problems = <String>[];
  final seen = <String>{};
  for (final record in model.allRecords) {
    if (!seen.add(record.id)) problems.add('duplicate record ${record.id}');
    final learned = _order(model, record.learnedInSectionId);
    if (learned < 0) problems.add('${record.id} learned in unknown section');
    for (final evidence in record.evidence) {
      final cited = _order(model, evidence.sectionId);
      if (cited < 0 || cited > learned) {
        problems.add(
          '${record.id} learned in ${record.learnedInSectionId} cites '
          '${evidence.sectionId}',
        );
      }
    }
    for (final id in record.payload.entityIds) {
      if (!model.entities.containsKey(id)) {
        problems.add('${record.id} mentions unknown entity $id');
      }
    }
  }
  final targeted = <String>{};
  for (final t in model.transitions) {
    final learned = _order(model, t.learnedInSectionId);
    if (learned < 0) problems.add('${t.id} learned in unknown section');
    if (!targeted.add(t.targetRecordId)) {
      problems.add('${t.targetRecordId} is the target of two transitions');
    }
    final target = model.recordsById[t.targetRecordId];
    if (target == null) {
      problems.add('${t.id} targets unknown ${t.targetRecordId}');
    } else if (_order(model, target.learnedInSectionId) > learned) {
      problems.add('${t.id} changes ${target.id} before it was learned');
    }
    final replacementId = t.replacementRecordId;
    if (replacementId != null) {
      final replacement = model.recordsById[replacementId];
      if (replacement == null) {
        problems.add('${t.id} replaces with unknown $replacementId');
      } else if (_order(model, replacement.learnedInSectionId) > learned) {
        problems.add('${t.id} is replaced by a later record $replacementId');
      }
    }
    for (final evidence in t.evidence) {
      final cited = _order(model, evidence.sectionId);
      if (cited < 0 || cited > learned) {
        problems.add('${t.id} cites ${evidence.sectionId}');
      }
    }
  }
  return problems;
}

/// For each entity, the first section order whose records mention it.
Map<String, int> firstMentions(StoryModel model) {
  final first = <String, int>{};
  for (final record in model.allRecords) {
    final order = _order(model, record.learnedInSectionId);
    for (final id in record.payload.entityIds) {
      if (order < (first[id] ?? 1 << 30)) first[id] = order;
    }
  }
  return first;
}

/// Everything that [snapshot] shows but should not, as readable messages.
///
/// Empty when the snapshot is a faithful view of what a reader who has
/// finished [StorySnapshot.section] knows.
List<String> auditSnapshot(StorySnapshot snapshot) {
  final model = snapshot.model;
  final cutoff = snapshot.section.order;
  final problems = <String>[];
  void fail(String message) => problems.add('at s$cutoff: $message');

  bool reached(String sectionId) {
    final order = _order(model, sectionId);
    return order >= 0 && order <= cutoff;
  }

  // What the raw data says the reader has reached.
  final reachedTransitions = [
    for (final t in model.transitions)
      if (reached(t.learnedInSectionId)) t,
  ];
  final targeted = {for (final t in reachedTransitions) t.targetRecordId: t};
  final first = firstMentions(model);
  final seenEntities = {
    for (final MapEntry(:key, :value) in first.entries)
      if (value <= cutoff) key,
  };

  // Identity groups: union-find over links that are reached, not withdrawn,
  // explicit and between two different entities of the same kind.
  final parent = <String, String>{};
  String find(String id) {
    var root = id;
    while ((parent[root] ??= root) != root) {
      root = parent[root]!;
    }
    return root;
  }

  for (final record in model.identityLinks) {
    final link = record.payload;
    final left = model.entities[link.leftEntityId];
    final right = model.entities[link.rightEntityId];
    if (reached(record.learnedInSectionId) &&
        !targeted.containsKey(record.id) &&
        link.assertion == Assertion.explicit &&
        left != null &&
        right != null &&
        left.id != right.id &&
        left.kind == right.kind) {
      parent[find(left.id)] = find(right.id);
    }
  }
  String group(String id) => find(id);
  bool sameGroup(String a, String b) => group(a) == group(b);

  // Text shown to the reader must come from reached sections.
  void checkText(String what, String text) {
    for (final order in sectionTagsIn(text)) {
      if (order > cutoff) fail('$what shows text from s$order: "$text"');
    }
  }

  // Entities.
  final known = snapshot.knownEntities;
  final knownIds = [for (final e in known) e.id];
  if (knownIds.toSet().length != knownIds.length) {
    fail('knownEntities lists an entity twice');
  }
  final covered = <String>{};
  for (final id in knownIds) {
    final members = snapshot.membersOf(id);
    for (final member in members) {
      if (!seenEntities.contains(member)) {
        fail('entity $member (first in s${first[member]}) appears in $id');
      }
      if (!covered.add(member)) fail('$member is in two known entities');
      if (!sameGroup(member, id)) {
        fail('$member is merged into $id without a reached explicit link');
      }
    }
    final expectedFirst = [for (final m in members) first[m] ?? 1 << 30]
        .reduce((a, b) => a < b ? a : b);
    if (snapshot.firstSeenOrder(id) != expectedFirst) {
      fail(
        'firstSeenOrder($id) is ${snapshot.firstSeenOrder(id)}, '
        'expected $expectedFirst',
      );
    }
  }
  for (final id in seenEntities) {
    if (!covered.contains(id)) fail('met entity $id is not shown');
  }
  for (final id in model.entities.keys) {
    if (seenEntities.contains(id)) continue;
    if (snapshot.firstSeenOrder(id) != null) fail('$id is seen too early');
    if (snapshot.membersOf(id).length != 1) fail('$id is merged too early');
  }
  var previousOrder = 0;
  for (final id in knownIds) {
    final order = snapshot.firstSeenOrder(id)!;
    if (order < previousOrder) fail('knownEntities is out of order at $id');
    previousOrder = order;
  }

  // Records shown must be reached, cited from reached sections, and active.
  void checkRecord(StoryRecord record, String where) {
    if (!reached(record.learnedInSectionId)) {
      fail('$where shows ${record.id} learned in ${record.learnedInSectionId}');
    }
    for (final evidence in record.evidence) {
      if (!reached(evidence.sectionId)) {
        fail('$where shows ${record.id} citing ${evidence.sectionId}');
      }
      checkText('evidence of ${record.id}', evidence.quote);
    }
    checkText(record.id, snapshot.describe(record.payload));
  }

  void checkActive(StoryRecord record, String where) {
    checkRecord(record, where);
    if (targeted.containsKey(record.id)) {
      fail(
        '$where shows ${record.id} as active after '
        '${targeted[record.id]!.action.name} in '
        '${targeted[record.id]!.learnedInSectionId}',
      );
    }
    if (!snapshot.isActive(record)) fail('$where shows inactive ${record.id}');
  }

  Set<String> ids(Iterable<StoryRecord> records) => {
    for (final r in records) r.id,
  };

  Set<String> expectedActive(Iterable<StoryRecord> records) => {
    for (final r in records)
      if (reached(r.learnedInSectionId) && !targeted.containsKey(r.id)) r.id,
  };

  void compare(String what, Set<String> actual, Set<String> expected) {
    final extra = actual.difference(expected);
    final missing = expected.difference(actual);
    if (extra.isNotEmpty) fail('$what shows $extra that should be hidden');
    if (missing.isNotEmpty) fail('$what hides $missing that should show');
  }

  for (final r in snapshot.relationships) {
    checkActive(r, 'relationships');
  }
  for (final r in snapshot.events) {
    checkActive(r, 'events');
  }
  compare('relationships', ids(snapshot.relationships), {
    for (final r in model.relationships)
      if (reached(r.learnedInSectionId) &&
          !targeted.containsKey(r.id) &&
          !sameGroup(r.payload.sourceId, r.payload.targetId))
        r.id,
  });
  compare('events', ids(snapshot.events), expectedActive(model.events));

  // Questions: open, or answered by a reached resolve, never withdrawn.
  final expectedQuestions = <String>{};
  for (final r in model.uncertainties) {
    if (!reached(r.learnedInSectionId)) continue;
    final t = targeted[r.id];
    if (t == null || t.action == TransitionAction.resolve) {
      expectedQuestions.add(r.id);
    }
  }
  compare('questions', {
    for (final q in snapshot.questions) q.record.id,
  }, expectedQuestions);
  void checkQuestion(StoryQuestion question) {
    checkRecord(question.record, 'questions');
    final resolution = question.resolution;
    final t = targeted[question.record.id];
    if (resolution == null) {
      if (t != null) {
        fail('${question.record.id} is open but was ${t.action.name}d');
      }
    } else {
      if (!reached(resolution.learnedInSectionId)) {
        fail('${question.record.id} is answered by a later transition');
      }
      if (resolution.action != TransitionAction.resolve ||
          resolution.targetRecordId != question.record.id) {
        fail('${question.record.id} has the wrong resolution');
      }
      checkText('resolution', resolution.resolution ?? '');
      checkText('resolution', snapshot.describeTransition(resolution));
    }
  }

  snapshot.questions.forEach(checkQuestion);

  // Transitions.
  void checkTransition(RecordTransition t, String where) {
    if (!reached(t.learnedInSectionId)) {
      fail('$where shows ${t.id} learned in ${t.learnedInSectionId}');
    }
    for (final evidence in t.evidence) {
      if (!reached(evidence.sectionId)) {
        fail('$where shows ${t.id} citing ${evidence.sectionId}');
      }
      checkText('evidence of ${t.id}', evidence.quote);
    }
    final target = model.recordsById[t.targetRecordId];
    if (target != null && !reached(target.learnedInSectionId)) {
      fail('$where shows ${t.id} changing a fact not learned yet');
    }
    final replacementId = t.replacementRecordId;
    if (replacementId != null &&
        !reached(model.recordsById[replacementId]!.learnedInSectionId)) {
      fail('$where shows ${t.id} with a replacement not learned yet');
    }
    checkText(t.id, snapshot.describeTransition(t));
    checkText(t.id, t.reason);
  }

  compare(
    'transitions',
    {for (final t in snapshot.transitions) t.id},
    {for (final t in reachedTransitions) t.id},
  );
  for (final t in snapshot.transitions) {
    checkTransition(t, 'transitions');
  }

  // Per-entity views, which a character card is built from.
  for (final id in knownIds) {
    final name = snapshot.displayName(id);
    checkText('displayName($id)', name);
    for (final alias in snapshot.aliasesOf(id)) {
      checkText('aliasesOf($id)', alias);
    }

    final attributes = snapshot.attributesOf(id);
    for (final r in attributes) {
      checkActive(r, 'attributesOf($id)');
    }
    compare(
      'attributesOf($id)',
      ids(attributes),
      expectedActive([
        for (final r in model.attributes)
          if (sameGroup(r.payload.entityId, id)) r,
      ]),
    );

    final relationships = snapshot.relationshipsOf(id);
    for (final r in relationships) {
      checkActive(r, 'relationshipsOf($id)');
    }
    compare(
      'relationshipsOf($id)',
      ids(relationships),
      ids(
        snapshot.relationships.where(
          (r) =>
              sameGroup(r.payload.sourceId, id) ||
              sameGroup(r.payload.targetId, id),
        ),
      ),
    );

    final events = snapshot.eventsOf(id);
    for (final r in events) {
      checkActive(r, 'eventsOf($id)');
    }
    compare(
      'eventsOf($id)',
      ids(events),
      expectedActive([
        for (final r in model.events)
          if (r.payload.entityIds.any((e) => sameGroup(e, id))) r,
      ]),
    );

    final questions = snapshot.questionsOf(id);
    questions.forEach(checkQuestion);
    compare(
      'questionsOf($id)',
      {for (final q in questions) q.record.id},
      {
        for (final q in snapshot.questions)
          if (q.record.payload.entityIds.any((e) => sameGroup(e, id)))
            q.record.id,
      },
    );

    for (final t in snapshot.transitionsOf(id)) {
      checkTransition(t, 'transitionsOf($id)');
    }
    if (snapshot.isNewEntity(id) != (snapshot.firstSeenOrder(id) == cutoff)) {
      fail('isNewEntity($id) disagrees with firstSeenOrder');
    }
    if (snapshot.firstSeenSection(id).order > cutoff) {
      fail('firstSeenSection($id) is after the cutoff');
    }
  }
  return problems;
}
