import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../story_model/story_snapshot.dart';
import '../theme/loremark_theme.dart';

/// The rim and accent color of a card with [stars] stars.
Color cardTierColor(int stars) => const [
  Color(0xFFA79B8E),
  Color(0xFF7DB497),
  Color(0xFF6FA3DC),
  Color(0xFFAE86E8),
  Color(0xFFE8B64A),
][stars - 1];

const _cardDark = Color(0xFF1B1712);
const _cardText = Color(0xFFF6EEDF);
const _cardMuted = Color(0xFFCFC3B2);
const cardRadius = 16.0;

/// The light on a card that is being moved.
///
/// [at] is where it falls, from (0, 0) to (1, 1). [amount] is how much of it
/// there is, from 0 to 1, so that it can fade rather than switch off.
typedef CardSheen = ({Offset at, double amount});

/// [lit] of the five stars of a card, lit from the left.
class CardStars extends StatelessWidget {
  const CardStars({
    super.key,
    required this.stars,
    required this.lit,
    required this.color,
  });

  final int stars;
  final int lit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$stars of 5 stars',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 5; i++)
            Icon(
              Icons.star,
              size: 22,
              color: i < lit ? color : Colors.white.withValues(alpha: 0.18),
            ),
        ],
      ),
    );
  }
}

/// The face of a card: who this is and how much the reader knows so far.
///
/// Everything comes from [snapshot], so it never shows more than the chapter
/// the reader has reached.
class CardFront extends StatelessWidget {
  const CardFront({
    super.key,
    required this.snapshot,
    required this.entityId,
    this.litStars,
    this.sheen,
  });

  final StorySnapshot snapshot;
  final String entityId;

  /// How many stars are lit, if not all of them yet.
  final int? litStars;

  /// The light on the card, if any. It only catches the light as it is moved.
  final CardSheen? sheen;

  String? get _strap {
    if (snapshot.revealOf(entityId) case final reveal?) {
      return 'Revealed · ${reveal.note}';
    }
    return snapshot.isNewEntity(entityId) ? 'First appearance' : null;
  }

  @override
  Widget build(BuildContext context) {
    final stars = snapshot.starsOf(entityId);
    final tier = cardTierColor(stars);
    final kind = snapshot.model.entities[snapshot.canonicalId(entityId)]!.kind;
    final attributes = snapshot.attributesOf(entityId).take(2);
    final aliases = snapshot.aliasesOf(entityId).take(2);
    final strap = _strap;
    final small = kicker(color: _cardMuted, size: 11);

    return ClipRRect(
      borderRadius: BorderRadius.circular(cardRadius),
      child: CustomPaint(
        painter: _CardFacePainter(tier),
        foregroundPainter: _FoilPainter(sheen: sheen, stars: stars),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: tier, width: 3),
            borderRadius: BorderRadius.circular(cardRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(kind.name.toUpperCase(), style: small),
                    Text(snapshot.section.label.toUpperCase(), style: small),
                  ],
                ),
                Expanded(
                  // Never scrolls. It only clips an unusually long card.
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 36),
                        Text(
                          snapshot.displayName(entityId),
                          style: serif(
                            30,
                            color: _cardText,
                            height: 1.12,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        CardStars(
                          stars: stars,
                          lit: litStars ?? stars,
                          color: tier,
                        ),
                        const SizedBox(height: 16),
                        Divider(height: 1, color: tier.withValues(alpha: 0.6)),
                        const SizedBox(height: 12),
                        for (final record in attributes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text:
                                        '${readableLabel(record.payload.label)}  ',
                                    style: TextStyle(
                                      color: tier,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  TextSpan(text: record.payload.value),
                                ],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _cardText,
                                fontSize: 14,
                                height: 1.3,
                              ),
                            ),
                          ),
                        if (aliases.isNotEmpty)
                          Text(
                            'Also ${aliases.join(', ')}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _cardMuted,
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (strap != null)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: tier,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Text(
                        strap,
                        style: const TextStyle(
                          color: _cardDark,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The back of a card before it turns over.
class CardCover extends StatelessWidget {
  const CardCover({super.key, this.title});

  /// The name the reader knows this card by, if any.
  final String? title;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(cardRadius),
      child: CustomPaint(
        painter: const _CardCoverPainter(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF5A4E3F), width: 3),
            borderRadius: BorderRadius.circular(cardRadius),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '?',
                  style: serif(
                    64,
                    color: const Color(0xFF8C7D69),
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    title ?? 'Unknown',
                    textAlign: TextAlign.center,
                    style: serif(
                      18,
                      color: const Color(0xFFD9CDBB),
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows [first] at angle 0 and [second] at angle pi, turning between them.
class CardFlip extends StatelessWidget {
  const CardFlip({
    super.key,
    required this.angle,
    required this.first,
    required this.second,
  });

  final double angle;
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    final showsSecond = math.cos(angle) < 0;
    // Flat once it has turned all the way, so that it is plain to read.
    final turned = angle == math.pi;
    return Transform(
      alignment: Alignment.center,
      transform: turned ? Matrix4.identity() : (_perspective()..rotateY(angle)),
      child: showsSecond
          ? Transform(
              alignment: Alignment.center,
              transform: turned
                  ? Matrix4.identity()
                  : Matrix4.rotationY(math.pi),
              child: second,
            )
          : first,
    );
  }
}

Matrix4 _perspective() => Matrix4.identity()..setEntry(3, 2, 0.001);

/// A card to pick up: drag to tilt it and catch the foil, tap to turn it over.
class CollectibleCard extends StatefulWidget {
  const CollectibleCard({
    super.key,
    required this.flip,
    required this.showsBack,
    required this.onTurnOver,
    required this.front,
    required this.back,
  });

  /// How far the card has turned over, from 0 to 1.
  final Animation<double> flip;

  /// Whether the card is showing [back], or on its way there. Only the front
  /// can be picked up, so that the back is free to scroll.
  final bool showsBack;

  /// Called when the reader taps the front.
  final VoidCallback onTurnOver;

  /// Built from the light on the card, if any. See [CardFront.sheen].
  final Widget Function(CardSheen? sheen) front;
  final Widget back;

  @override
  State<CollectibleCard> createState() => _CollectibleCardState();
}

class _CollectibleCardState extends State<CollectibleCard> {
  /// How closely the card follows the finger.
  static const _follow = Duration(milliseconds: 60);

  /// How quickly the card catches the light once it is picked up.
  static const _catch = Duration(milliseconds: 220);

  /// How long the card takes to level out and lose the light once let go.
  static const _settle = Duration(milliseconds: 600);

  /// Where the reader is pressing, from (0, 0) to (1, 1).
  Offset? _press;

  void _aim(Offset position) {
    if (MediaQuery.disableAnimationsOf(context)) return;
    final size = context.size!;
    setState(() {
      _press = Offset(
        (position.dx / size.width).clamp(0, 1),
        (position.dy / size.height).clamp(0, 1),
      );
    });
  }

  void _release() => setState(() => _press = null);

  @override
  Widget build(BuildContext context) {
    final press = _press;
    final showsBack = widget.showsBack;
    return Semantics(
      button: !showsBack,
      label: showsBack ? null : 'Turn over for details',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: showsBack ? null : widget.onTurnOver,
        onPanStart: showsBack ? null : (d) => _aim(d.localPosition),
        onPanUpdate: showsBack ? null : (d) => _aim(d.localPosition),
        onPanEnd: showsBack ? null : (_) => _release(),
        onPanCancel: showsBack ? null : _release,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: press == null ? 0 : 1),
          duration: press == null ? _settle : _catch,
          curve: Curves.easeOut,
          builder: (context, light, _) => TweenAnimationBuilder<Offset>(
            tween: Tween(
              end: press == null
                  ? Offset.zero
                  : Offset(press.dx * 2 - 1, press.dy * 2 - 1),
            ),
            duration: press == null ? _settle : _follow,
            curve: Curves.easeOutCubic,
            builder: (context, tilt, _) => Transform(
              alignment: Alignment.center,
              // The side being pressed dips away from the reader.
              transform: tilt == Offset.zero
                  ? Matrix4.identity()
                  : (_perspective()
                      ..rotateX(tilt.dy * 0.24)
                      ..rotateY(-tilt.dx * 0.3)),
              child: AnimatedBuilder(
                animation: widget.flip,
                builder: (context, _) => CardFlip(
                  angle: widget.flip.value * math.pi,
                  // The light moves with the card, so the two settle as one.
                  first: widget.front(
                    light == 0
                        ? null
                        : (
                            at: Offset((tilt.dx + 1) / 2, (tilt.dy + 1) / 2),
                            amount: light,
                          ),
                  ),
                  second: widget.back,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A dark ground lit from the top, with faint rays.
class _CardFacePainter extends CustomPainter {
  const _CardFacePainter(this.tier);

  final Color tier;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final top = Offset(size.width / 2, 0);
    canvas.drawRect(bounds, Paint()..color = _cardDark);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.topCenter,
          radius: 1.0,
          colors: [Color.lerp(tier, _cardDark, 0.5)!, _cardDark],
        ).createShader(bounds),
    );
    final reach = size.longestSide * 1.4;
    final ray = Paint()..color = Colors.white.withValues(alpha: 0.035);
    for (var degrees = 0; degrees < 180; degrees += 10) {
      final from = degrees * math.pi / 180;
      final to = (degrees + 5) * math.pi / 180;
      canvas.drawPath(
        Path()
          ..moveTo(top.dx, top.dy)
          ..lineTo(top.dx + reach * math.cos(from), reach * math.sin(from))
          ..lineTo(top.dx + reach * math.cos(to), reach * math.sin(to))
          ..close(),
        ray,
      );
    }
  }

  @override
  bool shouldRepaint(_CardFacePainter oldDelegate) => oldDelegate.tier != tier;
}

/// A wide, soft pool of light with the foil's colors in it. Every card has a
/// glossy shine; higher tiers show more color.
class _FoilPainter extends CustomPainter {
  const _FoilPainter({required this.sheen, required this.stars});

  static const _foil = [0.0, 0.1, 0.2, 0.32, 0.45];
  static const _glare = 0.08;

  /// A bell-shaped falloff, which leaves no visible edge.
  static const _falloffStops = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0];
  static const _falloff = [1.0, 0.85, 0.53, 0.24, 0.07, 0.0];

  static const _foilColors = [
    Color(0xFF6FE3F5),
    Color(0xFFB39DF2),
    Color(0xFFEE82EE),
    Color(0xFFF7DE6A),
    Color(0xFF8BEFC0),
  ];

  final CardSheen? sheen;
  final int stars;

  @override
  void paint(Canvas canvas, Size size) {
    final light = sheen;
    if (light == null) return;
    final bounds = Offset.zero & size;
    final center = Alignment(light.at.dx * 2 - 1, light.at.dy * 2 - 1);
    Shader pool(double strength) => RadialGradient(
      center: center,
      radius: 1.25,
      stops: _falloffStops,
      colors: [
        for (final part in _falloff)
          Colors.white.withValues(alpha: part * strength),
      ],
    ).createShader(bounds);

    final foil = _foil[stars - 1] * light.amount;
    if (foil > 0) {
      // The colors drift more slowly than the light, as if under the surface.
      final drift = (light.at.dx + light.at.dy - 1) * 0.5;
      canvas.saveLayer(
        bounds,
        Paint()
          ..blendMode = BlendMode.screen
          ..color = Colors.white.withValues(alpha: foil),
      );
      canvas.drawRect(
        bounds,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment(-0.7 - drift, -0.7 - drift),
            end: Alignment(0.7 - drift, 0.7 - drift),
            tileMode: TileMode.mirror,
            colors: _foilColors,
          ).createShader(bounds),
      );
      canvas.drawRect(
        bounds,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = pool(1),
      );
      canvas.restore();
    }
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = pool(_glare * light.amount),
    );
  }

  @override
  bool shouldRepaint(_FoilPainter oldDelegate) =>
      oldDelegate.sheen != sheen || oldDelegate.stars != stars;
}

/// Diagonal stripes on the back of a card.
class _CardCoverPainter extends CustomPainter {
  const _CardCoverPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF231E18),
    );
    final stripe = Paint()
      ..color = const Color(0xFF2C261E)
      ..strokeWidth = 10;
    for (var x = -size.height; x < size.width; x += 28) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        stripe,
      );
    }
  }

  @override
  bool shouldRepaint(_CardCoverPainter oldDelegate) => false;
}
