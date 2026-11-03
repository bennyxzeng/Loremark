import 'package:flutter/material.dart';

import 'loremark_theme.dart';

/// Illustrations of the Loremark companion, cropped and compressed for the
/// app from the originals in `assets/images/`.
abstract final class LoremarkArt {
  static const libraryHeader = 'assets/app/library_header.webp';
  static const companionHeader = 'assets/app/companion_header.webp';
  static const avatar = 'assets/app/companion_avatar.webp';

  /// Chibi poses, cut out on transparent backgrounds.
  static const chibiReading = 'assets/app/chibi_reading.webp';
  static const chibiPondering = 'assets/app/chibi_pondering.webp';
  static const chibiHush = 'assets/app/chibi_hush.webp';
}

/// Warm paper with soft light: a gold glow from the top corner and a faint
/// olive one from the bottom, like a sunlit reading room.
class PaperBackground extends StatelessWidget {
  const PaperBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: LoremarkColors.paper),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(1.1, -1.05),
            radius: 1.25,
            colors: [
              LoremarkColors.gold.withValues(alpha: 0.16),
              LoremarkColors.gold.withValues(alpha: 0),
            ],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-1.2, 1.15),
              radius: 1.1,
              colors: [
                LoremarkColors.olive.withValues(alpha: 0.09),
                LoremarkColors.olive.withValues(alpha: 0),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// An illustration that fades into the paper at its bottom edge.
class FadedIllustration extends StatelessWidget {
  const FadedIllustration({
    super.key,
    required this.asset,
    required this.height,
    this.alignment = Alignment.center,
  });

  final String asset;
  final double height;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0, 0.62, 1],
        ).createShader(bounds),
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          alignment: alignment,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
