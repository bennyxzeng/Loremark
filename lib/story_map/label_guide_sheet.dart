import 'package:flutter/material.dart';

import '../story_model/story_model.dart';
import 'story_facts.dart';

/// Opens the guide to the labels on a fact as a bottom sheet.
Future<void> showLabelGuide(BuildContext context) {
  return showFactSheet(
    context,
    builder: (context, scrollController) =>
        LabelGuideView(scrollController: scrollController),
  );
}

/// What each `temporal_context` and `assertion` label and each change heading
/// means, in the terms of the lab's `STORY_MODEL_FORMAT.md`.
class LabelGuideView extends StatelessWidget {
  const LabelGuideView({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      children: [
        Text('Label guide', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'The labels on a fact say when it holds and how we know it.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const FactHeading('When does it hold?'),
        for (final time in TemporalContext.values)
          _LabelRow(FactTag(time.name), switch (time) {
            TemporalContext.current => 'Part of the present story.',
            TemporalContext.past =>
              'Earlier than the present story: a memory, flashback or '
                  'backstory.',
            TemporalContext.future =>
              'Planned or predicted. It may not happen.',
            TemporalContext.hypothetical =>
              'Imagined: what would happen “if…”.',
            TemporalContext.unknown => 'The text doesn’t say when.',
          }),
        const FactHeading('How do we know?'),
        for (final assertion in Assertion.values)
          _LabelRow(FactTag(assertion.name), switch (assertion) {
            Assertion.explicit => 'The narration says it directly.',
            Assertion.reported =>
              'A character or in-world source says it. It may be false.',
            Assertion.inferred =>
              'Not said outright, but it follows from the text.',
          }),
        const FactHeading('What changed?'),
        for (final action in TransitionAction.values)
          _LabelRow(
            Text(
              changeHeading(action),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            '${_meaningOf(action)} Model label: ${action.name}.',
          ),
      ],
    );
  }
}

String _meaningOf(TransitionAction action) => switch (action) {
  TransitionAction.supersede => 'A new fact takes the place of an older one.',
  TransitionAction.retract => 'A later chapter shows an old fact was wrong.',
  TransitionAction.resolve => 'A later chapter answers an open question.',
};

class _LabelRow extends StatelessWidget {
  const _LabelRow(this.label, this.meaning);

  final Widget label;
  final String meaning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Align(alignment: Alignment.topLeft, child: label),
          ),
          Expanded(child: Text(meaning, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
