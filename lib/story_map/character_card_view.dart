import 'package:flutter/material.dart';

import '../story_model/story_model.dart';
import '../story_model/story_snapshot.dart';
import 'story_facts.dart';

/// Opens the card for [entityId] as a bottom sheet, limited to [snapshot].
///
/// Tapping a related entity on the card opens that entity's card on top, so
/// closing it returns to this one.
Future<void> showCharacterCard(
  BuildContext context,
  StorySnapshot snapshot,
  String entityId,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scrollController) => CharacterCardView(
        snapshot: snapshot,
        entityId: entityId,
        scrollController: scrollController,
      ),
    ),
  );
}

/// What the reader knows about one character (or place or group) so far.
class CharacterCardView extends StatelessWidget {
  const CharacterCardView({
    super.key,
    required this.snapshot,
    required this.entityId,
    this.scrollController,
  });

  final StorySnapshot snapshot;
  final String entityId;
  final ScrollController? scrollController;

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
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      children: [
        Text(
          snapshot.displayName(entityId),
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          '${entityKindLabel(entity.kind)} · First seen in '
          '${snapshot.firstSeenSection(entityId).label}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (aliases.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Also known as ${aliases.join(', ')}'),
        ],
        if (changes.isNotEmpty) ...[
          const FactHeading('Changes'),
          for (final change in changes)
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
              tags: assertionTags(record.payload.assertion),
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
                if (record.payload.temporalContext == TemporalContext.past)
                  'past',
                ...assertionTags(record.payload.assertion),
              ],
              onTap: () => showCharacterCard(
                context,
                snapshot,
                _otherEnd(record.payload),
              ),
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
                if (record.payload.temporalContext == TemporalContext.past)
                  'flashback',
                ...assertionTags(record.payload.assertion),
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
