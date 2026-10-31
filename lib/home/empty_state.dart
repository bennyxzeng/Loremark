import 'package:flutter/material.dart';

import '../theme/loremark_theme.dart';

/// A tab's heading over a short message, for when there is nothing to show.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.label,
    required this.title,
    required this.icon,
    required this.message,
  });

  final String label;
  final String title;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
      children: [
        Text(label, style: kicker()),
        const SizedBox(height: 9),
        Text(title, style: serif(29, height: 1.18)),
        const SizedBox(height: 40),
        Icon(icon, size: 40, color: LoremarkColors.line),
        const SizedBox(height: 12),
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
    );
  }
}
