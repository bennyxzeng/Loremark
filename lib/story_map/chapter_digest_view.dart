import 'package:flutter/material.dart';

import '../story_model/story_model.dart';
import '../story_model/story_snapshot.dart';
import 'story_facts.dart';

/// What the reader learned in the snapshot's section (UC5 step 5).
class ChapterDigestView extends StatelessWidget {
  const ChapterDigestView({
    super.key,
    required this.snapshot,
    required this.onEntityTap,
  });

  final StorySnapshot snapshot;
  final ValueChanged<String> onEntityTap;

  @override
  Widget build(BuildContext context) {
    final model = snapshot.model;
    final section = snapshot.section;
    final changes = [
      for (final transition in snapshot.transitions)
        if (transition.learnedInSectionId == section.id) transition,
    ];
    final newEntities = snapshot.knownEntities.where(
      (entity) => snapshot.isNewEntity(entity.id),
    );
    final newCharacters = [
      for (final entity in newEntities)
        if (entity.kind == EntityKind.character) entity.id,
    ];
    final newPlacesAndGroups = [
      for (final entity in newEntities)
        if (entity.kind != EntityKind.character) entity.id,
    ];
    final relationships = snapshot.relationships.where(snapshot.isNewRecord);
    final events = snapshot.events.where(snapshot.isNewRecord);
    final questions = snapshot.questions.where(
      (question) => snapshot.isNewRecord(question.record),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(
          'What’s new in ${section.title}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (changes.isNotEmpty) ...[
          const FactHeading('Changes'),
          for (final change in changes)
            FactTile(
              model: model,
              text: snapshot.describeTransition(change),
              detail: change.reason,
              evidence: change.evidence,
            ),
        ],
        if (newCharacters.isNotEmpty) ...[
          const FactHeading('New characters'),
          _chips(newCharacters),
        ],
        if (newPlacesAndGroups.isNotEmpty) ...[
          const FactHeading('New places and groups'),
          _chips(newPlacesAndGroups),
        ],
        if (relationships.isNotEmpty) ...[
          const FactHeading('New relationships'),
          for (final record in relationships)
            FactTile(
              model: model,
              text: snapshot.describe(record.payload),
              detail: record.payload.description,
              tags: [
                if (record.payload.temporalContext == TemporalContext.past)
                  'past',
                ...assertionTags(record.payload.assertion),
              ],
            ),
        ],
        if (events.isNotEmpty) ...[
          const FactHeading('Events'),
          for (final record in events)
            FactTile(
              model: model,
              text:
                  '${record.payload.narrativeOrder}. '
                  '${record.payload.description}',
              detail: _participants(record.payload),
              tags: [
                if (record.payload.temporalContext == TemporalContext.past)
                  'flashback',
                ...assertionTags(record.payload.assertion),
              ],
            ),
        ],
        if (questions.isNotEmpty) ...[
          const FactHeading('New open questions'),
          for (final question in questions)
            FactTile(
              model: model,
              text: question.record.payload.question,
              detail: answerText(question),
            ),
        ],
      ],
    );
  }

  Widget _chips(List<String> entityIds) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final id in entityIds)
        ActionChip(
          label: Text(snapshot.displayName(id)),
          onPressed: () => onEntityTap(id),
        ),
    ],
  );

  String? _participants(StoryEvent event) {
    final names = {
      for (final id in event.participantIds) snapshot.displayName(id),
    };
    final place = event.locationId == null
        ? null
        : snapshot.displayName(event.locationId!);
    final parts = [if (names.isNotEmpty) names.join(', '), ?place];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
