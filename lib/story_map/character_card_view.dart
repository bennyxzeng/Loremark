import 'package:flutter/material.dart';

import '../story_model/story_model.dart';
import '../story_model/story_snapshot.dart';
import 'story_facts.dart';

/// What the reader knows about one character (or place or group) so far.
class CharacterCardView extends StatelessWidget {
  const CharacterCardView({
    super.key,
    required this.snapshot,
    required this.entityId,
    required this.onEntityTap,
  });

  final StorySnapshot snapshot;
  final String entityId;

  /// Opens the card of a related entity.
  final ValueChanged<String> onEntityTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final model = snapshot.model;
    final entity = model.entities[snapshot.canonicalId(entityId)]!;
    final aliases = snapshot.aliasesOf(entityId);
    final changes = snapshot.transitionsOf(entityId);
    final attributes = snapshot.attributesOf(entityId);
    final relationships = snapshot.relationshipsOf(entityId);
    final events = snapshot.eventsOf(entityId);
    final questions = snapshot.questionsOf(entityId);

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
      children: [
        Text(
          snapshot.displayName(entityId),
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          '${entity.kind.name} · First seen in '
          '${snapshot.firstSeenSection(entityId).label}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (aliases.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Also known as ${aliases.join(', ')}'),
        ],
        for (final MapEntry(key: action, value: group) in changesByAction(
          changes,
        ).entries) ...[
          FactHeading('Changes: ${changeHeading(action)}'),
          for (final change in group)
            FactTile(
              model: model,
              text:
                  '${model.sectionById(change.learnedInSectionId)?.label}: '
                  '${snapshot.describeTransition(change)}',
              detail: change.reason,
            ),
        ],
        if (attributes.isNotEmpty) ...[
          const FactHeading('Details'),
          for (final record in attributes)
            FactTile(
              model: model,
              text: snapshot.describe(record.payload),
              tags: [record.payload.assertion.name],
              evidence: record.evidence,
            ),
        ],
        if (relationships.isNotEmpty) ...[
          const FactHeading('Relationships'),
          for (final record in relationships)
            FactTile(
              model: model,
              text: snapshot.describe(record.payload),
              detail: record.payload.description,
              tags: [
                record.payload.temporalContext.name,
                record.payload.assertion.name,
              ],
              onTap: () => onEntityTap(_otherEnd(record.payload)),
            ),
        ],
        if (events.isNotEmpty) ...[
          const FactHeading('Events'),
          for (final record in events)
            FactTile(
              model: model,
              text: record.payload.description,
              detail: model.sectionById(record.learnedInSectionId)?.label,
              tags: [
                record.payload.temporalContext.name,
                record.payload.assertion.name,
              ],
            ),
        ],
        if (questions.isNotEmpty) ...[
          const FactHeading('Open questions'),
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

  String _otherEnd(Relationship relationship) =>
      snapshot.canonicalId(relationship.sourceId) ==
          snapshot.canonicalId(entityId)
      ? relationship.targetId
      : relationship.sourceId;
}
