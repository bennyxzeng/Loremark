import 'package:flutter/material.dart';

import '../theme/loremark_theme.dart';

/// Says the reader jumped past what they have read, with the way back and a
/// way to count what they skipped as read. Styled like the swipe hint.
class AheadBanner extends StatelessWidget {
  const AheadBanner({
    super.key,
    required this.onGoBack,
    required this.onCountAsRead,
  });

  final VoidCallback onGoBack;
  final VoidCallback onCountAsRead;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LoremarkColors.card,
      elevation: 3,
      shadowColor: LoremarkColors.ink.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: LoremarkColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: LoremarkColors.olive,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fast_forward,
                    size: 17,
                    color: LoremarkColors.onOlive,
                  ),
                ),
                const SizedBox(width: 12),
                const Flexible(
                  child: Text(
                    'You’re ahead of where you’ve read',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: LoremarkColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: onGoBack, child: const Text('Go back')),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: onCountAsRead,
                  child: const Text('Count as read'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
