import 'package:flutter/material.dart';

import '../story_update/story_updater.dart';
import '../theme/loremark_theme.dart';

/// A notification that slides in over the top of a book's tabs when a Story
/// Map update ends while the reader is on another tab. Styled like the offline
/// banner.
class StoryUpdateBanner extends StatelessWidget {
  const StoryUpdateBanner({
    super.key,
    required this.outcome,
    required this.visible,
    required this.onView,
    required this.onDismiss,
  });

  /// How the update ended, or null if none has. Kept after [visible] turns
  /// false, so the banner still has something to show as it slides away.
  final StoryUpdateOutcome? outcome;
  final bool visible;
  final VoidCallback onView;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final outcome = this.outcome;
    // Nothing has ended yet, so there's nothing to slide away either.
    if (outcome == null) return const SizedBox.shrink();
    final (title, detail) = outcome.committed
        ? (
            'Story Map updated',
            outcome.sectionTitle == null
                ? 'A section was added.'
                : 'Added ${outcome.sectionTitle}.',
          )
        : (
            'The Story Map update didn’t go through',
            'See the Story Map for why.',
          );
    return IgnorePointer(
      ignoring: !visible,
      // Gone for a screen reader too, though it stays to slide away.
      child: ExcludeSemantics(
        excluding: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, -1.2),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Semantics(
                liveRegion: true,
                child: Material(
                  color: LoremarkColors.card,
                  elevation: 3,
                  shadowColor: LoremarkColors.ink.withValues(alpha: 0.25),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: LoremarkColors.line),
                  ),
                  // The close button floats in the corner, as on the offline
                  // banner, so only the title has to keep clear of it.
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: const BoxDecoration(
                                color: LoremarkColors.olive,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.hub,
                                size: 17,
                                color: LoremarkColors.onOlive,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(right: 32),
                                    child: Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: LoremarkColors.ink,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    detail,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: LoremarkColors.muted,
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: onView,
                                      child: const Text('View'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton(
                          onPressed: onDismiss,
                          tooltip: 'Dismiss',
                          icon: const Icon(
                            Icons.close,
                            size: 18,
                            color: LoremarkColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
