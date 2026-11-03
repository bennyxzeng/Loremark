import 'package:flutter/material.dart';

import '../story_model/story_model.dart';
import 'character_graph_view.dart';
import 'story_facts.dart';

/// Opens the guide to reading the relationship graph as a bottom sheet.
///
/// The text is the same for every book, apart from [sectionLabel], the chapter
/// the graph is showing, so the guide can't spoil anything.
Future<void> showGraphGuide(
  BuildContext context, {
  required String sectionLabel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scrollController) => GraphGuideView(
        sectionLabel: sectionLabel,
        scrollController: scrollController,
      ),
    ),
  );
}

/// What the shapes and lines on the relationship graph mean, and how to use it.
class GraphGuideView extends StatelessWidget {
  const GraphGuideView({
    super.key,
    required this.sectionLabel,
    this.scrollController,
  });

  final String sectionLabel;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      children: [
        Text('Graph guide', style: Theme.of(context).textTheme.headlineSmall),
        const FactHeading('Nodes'),
        _LegendRow(
          sample: GraphLegendSample.node(EntityKind.character),
          title: EntityKind.character.name,
        ),
        _LegendRow(
          sample: GraphLegendSample.node(EntityKind.organization),
          title: EntityKind.organization.name,
          detail: 'Shown when the organization filter is on.',
        ),
        _LegendRow(
          sample: GraphLegendSample.node(EntityKind.location),
          title: EntityKind.location.name,
          detail: 'Shown when the location filter is on.',
        ),
        _LegendRow(
          sample: GraphLegendSample.node(EntityKind.character, isNew: true),
          title: 'New or revealed in $sectionLabel',
          detail:
              'Bold outline and name. Revealed means you learn who they '
              'really are.',
        ),
        const FactHeading('Lines'),
        const _LegendRow(
          sample: GraphLegendSample.edge(),
          title: 'Solid line',
          detail: 'A relationship not tagged past.',
        ),
        _LegendRow(
          sample: const GraphLegendSample.edge(isPast: true),
          title: TemporalContext.past.name,
          detail: 'Dashed line. Set in the past, though it may not have ended.',
        ),
        _LegendRow(
          sample: const GraphLegendSample.edge(isInferred: true),
          title: '${Assertion.inferred.name} or ${Assertion.reported.name}',
          detail:
              'Faded line. The text doesn’t state it directly. '
              'Lines new in this chapter aren’t faded.',
        ),
        _LegendRow(
          sample: const GraphLegendSample.edge(isNew: true),
          title: 'New in $sectionLabel',
          detail: 'Thick, colored line.',
        ),
        const _LegendRow(
          sample: GraphLegendSample.edge(isPast: true, isNew: true),
          title: 'Styles combine',
          detail: 'A thick, dashed line is a new relationship set in the past.',
        ),
        const _LegendRow(
          sample: GraphLegendSample.edge(label: 'member of'),
          title: 'Arrow',
          detail: 'Read along the arrow: A → member of → B.',
        ),
        const FactHeading('Using the graph'),
        const _Tip('Tap a name to open its card.'),
        const _Tip('Pinch to zoom, and drag to move around.'),
        const _Tip('Move the chapter slider back to see an earlier chapter.'),
        const _Tip(
          'Use the organization and location filters to show or hide those '
          'nodes.',
        ),
        const _Tip('Labels that don’t fit stay hidden. Zoom in to see them.'),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.sample, required this.title, this.detail});

  final GraphLegendSample sample;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          sample,
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                if (detail != null)
                  Text(
                    detail!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}
