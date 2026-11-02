import 'package:flutter/material.dart';

import '../story_model/story_model.dart';
import '../story_model/story_snapshot.dart';

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
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

/// One fact with optional detail, tags and the quotes that support it.
class FactTile extends StatelessWidget {
  const FactTile({
    super.key,
    required this.model,
    required this.text,
    this.detail,
    this.tags = const [],
    this.evidence = const [],
    this.onTap,
  });

  final StoryModel model;
  final String text;
  final String? detail;
  final List<String> tags;
  final List<Evidence> evidence;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final tile = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: text),
                for (final tag in tags)
                  TextSpan(
                    text: '  $tag',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
              ],
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: onTap == null ? null : theme.colorScheme.primary,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 2),
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
    return onTap == null ? tile : InkWell(onTap: onTap, child: tile);
  }
}

/// Tags that flag facts the text does not state directly.
List<String> assertionTags(Assertion assertion) => switch (assertion) {
  Assertion.explicit => const [],
  Assertion.reported => const ['reported'],
  Assertion.inferred => const ['inferred'],
};

/// The answer to [question], or null while it is still open.
String? answerText(StoryQuestion question) => switch (question.resolution) {
  final resolution? =>
    'Answered: ${resolution.resolution ?? resolution.reason}',
  null => null,
};

/// A label for the kind of an entity, such as "Character".
String entityKindLabel(EntityKind kind) => switch (kind) {
  EntityKind.character => 'Character',
  EntityKind.location => 'Place',
  EntityKind.organization => 'Group',
};
