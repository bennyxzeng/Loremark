import 'package:flutter/material.dart';

import '../theme/decor.dart';
import '../theme/loremark_theme.dart';

/// A tab's heading over a short message, for when there is nothing to show.
///
/// With an [image], the companion illustrates the message; otherwise [icon]
/// does.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.label,
    required this.title,
    required this.icon,
    required this.message,
    this.image,
    this.top,
  });

  final String label;
  final String title;
  final IconData icon;
  final String message;
  final String? image;

  /// Shown above the heading, such as the Ask tab's recap.
  final Widget? top;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    return PaperBackground(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
        children: [
          ?top,
          Text(label, style: kicker()),
          const SizedBox(height: 9),
          Text(title, style: serif(29, height: 1.18)),
          const SizedBox(height: 28),
          if (image != null)
            Image.asset(image, height: 190, excludeFromSemantics: true)
          else
            Icon(icon, size: 40, color: LoremarkColors.line),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              color: LoremarkColors.card.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: LoremarkColors.line),
            ),
            child: Column(
              children: [
                Icon(icon, size: 20, color: LoremarkColors.gold),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: LoremarkColors.muted,
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
