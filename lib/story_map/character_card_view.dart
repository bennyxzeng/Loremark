import 'dart:math' as math;

import 'package:flutter/material.dart';

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
  return showFactSheet(
    context,
    builder: (context, scrollController) => CharacterCardView(
      snapshot: snapshot,
      entityId: entityId,
      scrollController: scrollController,
    ),
  );
}

/// The kinds of fact a card shows, one page each, in the order of their chips.
enum _CardPage {
  details('Details'),
  relationships('Relationships'),
  events('Events'),
  questions('Questions'),
  changes('Changes');

  const _CardPage(this.label);

  final String label;
}

/// What the reader knows about one character (or place or group) so far, one
/// kind of fact at a time.
class CharacterCardView extends StatefulWidget {
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
  State<CharacterCardView> createState() => _CharacterCardViewState();
}

class _CharacterCardViewState extends State<CharacterCardView> {
  /// The page the reader picked; until then, the first one with facts.
  _CardPage? _pickedPage;

  ScrollController? _ownController;
  final _headerKey = GlobalKey();

  StorySnapshot get snapshot => widget.snapshot;
  String get entityId => widget.entityId;

  ScrollController get _controller =>
      widget.scrollController ?? (_ownController ??= ScrollController());

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final model = snapshot.model;
    final entity = model.entities[snapshot.canonicalId(entityId)]!;
    final aliases = snapshot.aliasesOf(entityId);
    final attributes = snapshot.attributesOf(entityId);
    final relationships = snapshot.relationshipsOf(entityId);
    final events = snapshot.eventsOf(entityId);
    final questions = snapshot.questionsOf(entityId);
    final changes = snapshot.transitionsOf(entityId);

    final counts = {
      _CardPage.details: attributes.length,
      _CardPage.relationships: relationships.length,
      _CardPage.events: events.length,
      _CardPage.questions: questions.length,
      _CardPage.changes: changes.length,
    };
    final pages = [
      for (final page in _CardPage.values)
        if (counts[page]! > 0) page,
    ];
    final current = pages.contains(_pickedPage)
        ? _pickedPage!
        : pages.firstOrNull;

    List<Widget> factsOn(_CardPage page) => switch (page) {
      _CardPage.details => [
        for (final record in attributes)
          FactTile(
            model: model,
            text: snapshot.describe(record.payload),
            tags: [record.payload.assertion.name],
            evidence: record.evidence,
          ),
      ],
      _CardPage.relationships => [
        for (final record in relationships)
          FactTile.rich(
            model: model,
            textSpan: TextSpan(
              children: [
                _nameSpan(record.payload.sourceId),
                TextSpan(text: ' ${readableLabel(record.payload.label)} '),
                _nameSpan(record.payload.targetId),
              ],
            ),
            detail: record.payload.description,
            tags: [
              record.payload.temporalContext.name,
              record.payload.assertion.name,
            ],
          ),
      ],
      _CardPage.events => [
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
      _CardPage.questions => [
        for (final question in questions)
          FactTile(
            model: model,
            text: question.record.payload.question,
            detail: answerText(question),
          ),
      ],
      _CardPage.changes => [
        for (final MapEntry(key: action, value: group) in changesByAction(
          changes,
        ).entries) ...[
          FactHeading(changeHeading(action)),
          for (final change in group)
            FactTile(
              model: model,
              text:
                  '${model.sectionById(change.learnedInSectionId)?.label}: '
                  '${snapshot.describeTransition(change)}',
              detail: change.reason,
            ),
        ],
      ],
    };

    return CustomScrollView(
      controller: _controller,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            key: _headerKey,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
              ],
            ),
          ),
        ),
        if (current != null) ...[
          // Pinned, so another kind is a tap away however far down the
          // reader is. It covers the facts scrolling under it.
          PinnedHeaderSliver(
            child: ColoredBox(
              color:
                  theme.bottomSheetTheme.backgroundColor ??
                  theme.colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: FactPageBar(
                  pages: pages,
                  current: current,
                  label: (page) => '${page.label} ${counts[page]}',
                  onSelected: _pick,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            sliver: SliverList.list(children: factsOn(current)),
          ),
        ],
      ],
    );
  }

  /// Shows [page]. If the reader is past the header, so the bar is pinned at
  /// the top, the page starts right under the bar.
  void _pick(_CardPage page) {
    setState(() => _pickedPage = page);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final header = _headerKey.currentContext?.findRenderObject();
      if (header is! RenderBox || !_controller.hasClients) return;
      final position = _controller.position;
      final top = math.min(header.size.height, position.maxScrollExtent);
      if (position.pixels > top) _controller.jumpTo(top);
    });
  }

  /// [id]'s name in a relationship: a link to its card, or plain text when
  /// it is this card's own entity, as that card is already open.
  InlineSpan _nameSpan(String id) {
    final name = snapshot.displayName(id);
    return snapshot.canonicalId(id) == snapshot.canonicalId(entityId)
        ? TextSpan(text: name)
        : factLinkSpan(name, () => showCharacterCard(context, snapshot, id));
  }
}
