import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/decor.dart';
import '../theme/loremark_theme.dart';

/// Shows the [WelcomeBackCard] as a pop-up over the book, with the page
/// dimmed and blurred behind it, so the reader answers it before reading on.
///
/// Returns true if the reader chose **Catch me up**. Tapping outside the card
/// is the same as **Keep reading**.
Future<bool> showWelcomeBack(
  BuildContext context, {
  required String sectionTitle,
  required bool partway,
}) async {
  final catchUp = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Keep reading',
    barrierColor: LoremarkColors.ink.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: WelcomeBackCard(
              sectionTitle: sectionTitle,
              partway: partway,
              onCatchUp: () => Navigator.of(context).pop(true),
              onKeepReading: () => Navigator.of(context).pop(false),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final shown = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return AnimatedBuilder(
        animation: shown,
        // The book behind goes soft, so the card reads as the thing to answer
        // first.
        builder: (context, child) => BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 6 * shown.value,
            sigmaY: 6 * shown.value,
          ),
          child: child,
        ),
        child: FadeTransition(
          opacity: shown,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(shown),
            child: child,
          ),
        ),
      );
    },
  );
  return catchUp ?? false;
}

/// The companion's welcome back when a book opens: it offers a recap of where
/// the reader stopped (use case 1). [showWelcomeBack] shows it.
class WelcomeBackCard extends StatelessWidget {
  const WelcomeBackCard({
    super.key,
    required this.sectionTitle,
    required this.partway,
    required this.onCatchUp,
    required this.onKeepReading,
  });

  /// The section the recap would stop in, such as "Chapter 3: The Letter".
  final String sectionTitle;

  /// Whether the reader stopped partway through it, rather than at its end.
  final bool partway;

  /// Opens the recap. Null while one is being written.
  final VoidCallback? onCatchUp;

  /// Hides the card until the book is opened again.
  final VoidCallback onKeepReading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: LoremarkColors.welcomeBorder),
          gradient: const LinearGradient(
            colors: [LoremarkColors.welcomeStart, LoremarkColors.welcomeEnd],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            // The companion, fading into the card from the right.
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: 150,
              child: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Colors.transparent, Colors.black],
                  stops: [0, 0.55],
                ).createShader(bounds),
                blendMode: BlendMode.dstIn,
                child: Image.asset(
                  LoremarkArt.companionHeader,
                  fit: BoxFit.cover,
                  alignment: const Alignment(0.2, 0),
                  excludeFromSemantics: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 120, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'YOUR COMPANION IS HERE',
                    style: kicker(color: LoremarkColors.welcomeText),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Welcome back.',
                    style: serif(
                      26,
                      color: LoremarkColors.welcomeTitle,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    partway
                        ? 'Last time you stopped partway through '
                              '$sectionTitle. A little reminder before you '
                              'read on?'
                        : 'Last time you finished $sectionTitle. A little '
                              'reminder before you turn the page?',
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: LoremarkColors.welcomeText,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: onCatchUp,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Catch me up'),
                        SizedBox(width: 6),
                        Icon(Icons.north_east, size: 16),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onKeepReading,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: LoremarkColors.welcomeText,
                    ),
                    child: const Text('Keep reading'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
