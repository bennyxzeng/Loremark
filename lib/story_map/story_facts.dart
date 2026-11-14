import 'package:flutter/material.dart';

import '../story_model/story_model.dart';
import '../story_model/story_snapshot.dart';

/// Opens a draggable bottom sheet, as used for character cards and guides.
Future<void> showFactSheet(
  BuildContext context, {
  required ScrollableWidgetBuilder builder,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: builder,
    ),
  );
}

/// A small heading above a group of facts.
class FactHeading extends StatelessWidget {
  const FactHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// One fact with optional detail, tags and the quotes that support it.
class FactTile extends StatelessWidget {
  const FactTile({
    super.key,
    required String this.text,
    required this.model,
    this.detail,
    this.tags = const [],
    this.evidence = const [],
  }) : textSpan = null;

  /// A fact whose line mixes plain words with links, such as [factLinkSpan].
  const FactTile.rich({
    super.key,
    required InlineSpan this.textSpan,
    required this.model,
    this.detail,
    this.tags = const [],
    this.evidence = const [],
  }) : text = null;

  final StoryModel model;
  final String? text;
  final InlineSpan? textSpan;
  final String? detail;
  final List<String> tags;
  final List<Evidence> evidence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final style = theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (textSpan case final span?)
            Text.rich(span, style: style)
          else
            Text(text!, style: style),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [for (final tag in tags) FactTag(tag)],
            ),
          ],
          if (detail != null) ...[
            SizedBox(height: tags.isEmpty ? 2 : 4),
            Text(detail!, style: muted),
          ],
          for (final quote in evidence) ...[
            const SizedBox(height: 2),
            Text(
              '${model.sectionById(quote.sectionId)?.label ?? quote.sectionId}'
              ' · ${quote.paragraphId}  “${quote.quote}”',
              style: muted?.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }
}

/// [name] as a link inside a fact's line, for [FactTile.rich].
WidgetSpan factLinkSpan(String name, VoidCallback onTap) => WidgetSpan(
  alignment: PlaceholderAlignment.baseline,
  baseline: TextBaseline.alphabetic,
  child: FactLink(name, onTap: onTap),
);

/// A name in a fact that opens what it names, styled so it reads as a link
/// next to the plain words around it.
class FactLink extends StatelessWidget {
  const FactLink(this.name, {super.key, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Semantics(
      link: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        // A WidgetSpan's child doesn't take the line's style, so the link
        // sets its own.
        child: Text(
          name,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: color,
            decoration: TextDecoration.underline,
            decorationColor: color,
          ),
        ),
      ),
    );
  }
}

/// A label on a fact, such as `past`, in a rounded box.
///
/// Most facts are `current` and `explicit`, so those stay quiet and the other
/// labels stand out.
class FactTag extends StatelessWidget {
  const FactTag(this.label, {super.key});

  final String label;

  bool get isDefault =>
      label == TemporalContext.current.name || label == Assertion.explicit.name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDefault
            ? colors.surfaceContainerHighest
            : colors.tertiaryContainer,
        border: Border.all(
          color: isDefault
              ? colors.outlineVariant
              : colors.tertiary.withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: isDefault ? colors.onSurface : colors.onTertiaryContainer,
          ),
        ),
      ),
    );
  }
}

/// The heading above changes that did [action]. The label guide says which
/// word the model uses for each.
String changeHeading(TransitionAction action) => switch (action) {
  TransitionAction.supersede => 'Replaced',
  TransitionAction.retract => 'Retracted',
  TransitionAction.resolve => 'Answered',
};

/// [changes] grouped by what they did, leaving out actions none of them did.
Map<TransitionAction, List<RecordTransition>> changesByAction(
  List<RecordTransition> changes,
) => {
  for (final action in TransitionAction.values)
    if (changes.any((change) => change.action == action))
      action: [
        for (final change in changes)
          if (change.action == action) change,
      ],
};

/// The answer to [question], or null while it is still open.
String? answerText(StoryQuestion question) => switch (question.resolution) {
  final resolution? =>
    'Answered: ${resolution.resolution ?? resolution.reason}',
  null => null,
};
