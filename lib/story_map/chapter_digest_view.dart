import 'package:flutter/material.dart';

import '../story_model/story_model.dart';
import '../story_model/story_snapshot.dart';
import 'story_facts.dart';

/// The kinds of fact [ChapterDigestView] shows, one page each.
enum _DigestPage {
  changes('Changes'),
  entities('Entities'),
  relationships('Relationships'),
  events('Events'),
  questions('Questions');

  const _DigestPage(this.label);

  final String label;
}

/// What the reader learned in the snapshot's section (UC5 step 5), one kind of
/// fact at a time.
class ChapterDigestView extends StatefulWidget {
  const ChapterDigestView({
    super.key,
    required this.snapshot,
    required this.onEntityTap,
    required this.onGuideTap,
  });

  final StorySnapshot snapshot;
  final ValueChanged<String> onEntityTap;
  final VoidCallback onGuideTap;

  @override
  State<ChapterDigestView> createState() => _ChapterDigestViewState();
}

class _ChapterDigestViewState extends State<ChapterDigestView> {
  /// The page the reader picked. It is kept while a chapter has nothing on it,
  /// so sliding back to a chapter that does returns to it.
  _DigestPage? _pickedPage;

  StorySnapshot get snapshot => widget.snapshot;

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
    final relationships = snapshot.relationships
        .where(snapshot.isNewRecord)
        .toList();
    final events = snapshot.events.where(snapshot.isNewRecord).toList();
    final questions = snapshot.questions
        .where((question) => snapshot.isNewRecord(question.record))
        .toList();

    final counts = {
      _DigestPage.changes: changes.length,
      _DigestPage.entities: newCharacters.length + newPlacesAndGroups.length,
      _DigestPage.relationships: relationships.length,
      _DigestPage.events: events.length,
      _DigestPage.questions: questions.length,
    };
    final pages = [
      for (final page in _DigestPage.values)
        if (counts[page]! > 0) page,
    ];

    List<Widget> factsOn(_DigestPage page) => switch (page) {
      _DigestPage.changes => [
        for (final MapEntry(key: action, value: group) in changesByAction(
          changes,
        ).entries) ...[
          FactHeading(changeHeading(action)),
          for (final change in group)
            FactTile(
              model: model,
              text: snapshot.describeTransition(change),
              detail: change.reason,
              evidence: change.evidence,
            ),
        ],
      ],
      _DigestPage.entities => [
        if (newCharacters.isNotEmpty) ...[
          const FactHeading('New characters'),
          _chips(newCharacters),
        ],
        if (newPlacesAndGroups.isNotEmpty) ...[
          const FactHeading('New locations and organizations'),
          _chips(newPlacesAndGroups),
        ],
      ],
      _DigestPage.relationships => [
        for (final record in relationships)
          FactTile(
            model: model,
            text: snapshot.describe(record.payload),
            detail: record.payload.description,
            tags: [
              record.payload.temporalContext.name,
              record.payload.assertion.name,
            ],
          ),
      ],
      _DigestPage.events => [
        for (final record in events)
          FactTile(
            model: model,
            text:
                '${record.payload.narrativeOrder}. '
                '${record.payload.description}',
            detail: _participants(record.payload),
            tags: [
              record.payload.temporalContext.name,
              record.payload.assertion.name,
            ],
          ),
      ],
      _DigestPage.questions => [
        for (final question in questions)
          FactTile(
            model: model,
            text: question.record.payload.question,
            detail: answerText(question),
          ),
      ],
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'What’s new in ${section.title}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.help_outline),
                tooltip: 'Label guide',
                onPressed: widget.onGuideTap,
              ),
            ],
          ),
        ),
        if (!section.quotesChecked)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              'The quotes in this chapter weren’t checked against the book, '
              'so one may not match its passage.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (pages.isEmpty)
          const Expanded(
            child: Center(child: Text('Nothing new in this chapter.')),
          )
        else ...[
          _pageBar(pages, counts),
          Expanded(
            child: ListView(
              // A new key starts a new page or chapter from the top.
              key: ValueKey((_currentPage(pages), section.id)),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: factsOn(_currentPage(pages)),
            ),
          ),
        ],
      ],
    );
  }

  _DigestPage _currentPage(List<_DigestPage> pages) =>
      pages.contains(_pickedPage) ? _pickedPage! : pages.first;

  Widget _pageBar(List<_DigestPage> pages, Map<_DigestPage, int> counts) {
    final current = _currentPage(pages);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        spacing: 8,
        children: [
          for (final page in pages)
            ChoiceChip(
              label: Text('${page.label} ${counts[page]}'),
              selected: page == current,
              showCheckmark: false,
              // The app's chip theme looks the same selected or not.
              selectedColor: colors.primary,
              labelStyle: page == current
                  ? theme.chipTheme.labelStyle?.copyWith(
                      color: colors.onPrimary,
                    )
                  : null,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => setState(() => _pickedPage = page),
            ),
        ],
      ),
    );
  }

  Widget _chips(List<String> entityIds) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final id in entityIds)
        ActionChip(
          label: Text(snapshot.displayName(id)),
          onPressed: () => widget.onEntityTap(id),
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
