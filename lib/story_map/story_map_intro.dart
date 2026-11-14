import 'package:flutter/material.dart';

import '../theme/loremark_theme.dart';

/// A card at the top of the Story Map tab telling a new reader what Update
/// does, until they close it. Styled like the offline banner.
class StoryMapIntro extends StatelessWidget {
  const StoryMapIntro({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Material(
        color: LoremarkColors.card,
        elevation: 3,
        shadowColor: LoremarkColors.ink.withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: LoremarkColors.line),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                      Icons.hub_outlined,
                      size: 17,
                      color: LoremarkColors.onOlive,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(right: 32),
                          child: Text(
                            'Tap Update to build the Story Map',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: LoremarkColors.ink,
                            ),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Each update adds the next chapter to a map of the '
                          'characters. It uses your AI key and can take a '
                          'minute. Nothing past where you’ve read is shown.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: LoremarkColors.muted,
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
    );
  }
}
