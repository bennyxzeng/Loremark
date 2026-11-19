import 'package:flutter/material.dart';

import '../theme/loremark_theme.dart';

/// A small pill saying the reader skipped ahead, which asks again what to do
/// about it. Styled like the Story Map chip in the header, in the colors it
/// uses for something the reader can do something about.
///
/// It goes in the row of page buttons and is tappable their whole height, but
/// never taller, so it never pushes the page up.
class SkippedAheadButton extends StatelessWidget {
  const SkippedAheadButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const color = LoremarkColors.avatarText;
    return Semantics(
      button: true,
      label: 'Skipped ahead. Asks whether what you skipped counts as read.',
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        customBorder: const StadiumBorder(),
        child: SizedBox(
          height: kMinInteractiveDimension,
          child: Center(
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
              decoration: BoxDecoration(
                color: LoremarkColors.chip,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: LoremarkColors.chipBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.fast_forward, size: 13, color: color),
                  const SizedBox(width: 5),
                  Text('SKIPPED AHEAD', style: kicker(color: color, size: 9)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
