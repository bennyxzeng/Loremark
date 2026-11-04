import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../story_model/story_model.dart';
import '../story_model/story_snapshot.dart';
import 'card_sounds.dart';
import 'character_card_view.dart';
import 'collectible_card.dart';

/// What the cards of one open book share: the sounds, and which reveals have
/// already played.
class CardSession {
  CardSession(this.sounds);

  final CardSounds sounds;
  final _played = <(String, String)>{};

  /// Whether opening [entityId] should play its reveal, which then counts as
  /// played. A character is revealed in the chapter that introduces them or
  /// shows who they really are, once per chapter.
  bool claimReveal(StorySnapshot snapshot, String entityId) {
    final id = snapshot.canonicalId(entityId);
    if (snapshot.model.entities[id]?.kind != EntityKind.character) return false;
    if (!snapshot.isNewEntity(id) && !snapshot.isRevealedEntity(id)) {
      return false;
    }
    return _played.add((id, snapshot.section.id));
  }
}

/// Opens the card for [entityId], limited to [snapshot].
///
/// Tapping a related entity on the card opens that entity's card on top, so
/// closing it returns to this one.
Future<void> showCharacterCard(
  BuildContext context,
  StorySnapshot snapshot,
  String entityId,
  CardSession session,
) {
  session.sounds.prepare();
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  final reveal = !reduceMotion && session.claimReveal(snapshot, entityId);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
    pageBuilder: (context, _, _) => CharacterCardScreen(
      snapshot: snapshot,
      entityId: entityId,
      session: session,
      reveal: reveal,
    ),
  );
}

/// When each beat of a reveal happens, in milliseconds. Cards with more stars
/// build up for longer.
class _RevealTimeline {
  _RevealTimeline(this.stars)
    : burstAt = chargeAt + (stars >= 4 ? 950 : 500),
      starGap = stars >= 4 ? 150 : 110;

  static const riseFrom = 120;
  static const riseUntil = 870;
  static const chargeAt = 880;
  static const flipTakes = 560;
  static const flashTakes = 550;

  final int stars;
  final int burstAt;
  final int starGap;

  bool get _high => stars >= 4;
  int get flipAt => burstAt + 90;
  int get starsAt => flipAt + flipTakes;
  int get end => starsAt + stars * starGap + 650;

  /// How many stars are lit at [ms].
  int litAt(double ms) => ms < starsAt
      ? 0
      : (((ms - starsAt) / starGap).floor() + 1).clamp(0, stars);

  late final List<(int, CardSound)> cues = [
    (chargeAt, _high ? CardSound.chargeLong : CardSound.chargeShort),
    (burstAt, _high ? CardSound.burstHigh : CardSound.burstLow),
    (flipAt, CardSound.flip),
    for (var i = 0; i < stars; i++)
      (starsAt + i * starGap, CardSound.star(i + 1)),
  ];
}

/// One card, on its own screen over the Story Map.
class CharacterCardScreen extends StatefulWidget {
  const CharacterCardScreen({
    super.key,
    required this.snapshot,
    required this.entityId,
    required this.session,
    required this.reveal,
  });

  final StorySnapshot snapshot;
  final String entityId;
  final CardSession session;

  /// Whether to open with the reveal rather than the card at rest.
  final bool reveal;

  @override
  State<CharacterCardScreen> createState() => _CharacterCardScreenState();
}

class _CharacterCardScreenState extends State<CharacterCardScreen>
    with TickerProviderStateMixin {
  /// Room above the open page for the buttons, which stay on the dimmed screen.
  static const _buttonsHeight = 48.0;

  /// The widest the open page gets, as for a bottom sheet.
  static const _pageMaxWidth = 640.0;

  /// The space below the resting card for the hint.
  static const _hintGap = 14.0;
  static const _hintHeight = 18.0;

  /// How far into opening the hint is gone by.
  static const _hintFadesBy = 0.15;

  late final _timeline = _RevealTimeline(
    widget.snapshot.starsOf(widget.entityId),
  );
  late final _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _timeline.end),
  );
  late bool _revealing = widget.reveal;
  var _nextCue = 0;

  /// The card turning over and then opening up into a page of details, in one
  /// motion that can play either way.
  late final _opening = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final _flip = _opening.drive(
    CurveTween(curve: const Interval(0, 0.55, curve: Curves.easeInOut)),
  );
  late final _grow = _opening.drive(
    CurveTween(curve: const Interval(0.5, 1, curve: Curves.easeInOutCubic)),
  );
  var _showsDetails = false;

  CardSounds get _sounds => widget.session.sounds;
  double get _ms => _controller.value * _timeline.end;

  @override
  void initState() {
    super.initState();
    if (!_revealing) return;
    _controller
      ..addListener(_playDueCues)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finishReveal();
      })
      ..forward();
  }

  void _playDueCues() {
    final cues = _timeline.cues;
    while (_nextCue < cues.length && cues[_nextCue].$1 <= _ms) {
      _sounds.play(cues[_nextCue].$2);
      _nextCue++;
    }
  }

  void _skipReveal() {
    _controller.stop();
    _sounds.stop();
    _finishReveal();
  }

  void _finishReveal() {
    if (mounted && _revealing) setState(() => _revealing = false);
  }

  void _setShowsDetails(bool shows) {
    if (shows == _showsDetails) return;
    setState(() => _showsDetails = shows);
    if (MediaQuery.disableAnimationsOf(context)) {
      _opening.value = shows ? 1 : 0;
      return;
    }
    _sounds.play(CardSound.flip);
    if (shows) {
      _opening.forward();
    } else {
      _opening.reverse();
    }
  }

  @override
  void dispose() {
    if (_revealing) _sounds.stop();
    _opening.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// The back of the card, which opens up into a page.
  ///
  /// The details are laid out at the size of the page from the start and only
  /// scaled down on the card, so that the text doesn't reflow as it grows.
  Widget _details(Color tier, Size pageSize) {
    return AnimatedBuilder(
      animation: _grow,
      builder: (context, child) {
        final grow = _grow.value;
        return Material(
          color: Theme.of(context).bottomSheetTheme.backgroundColor,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(lerpDouble(cardRadius, 28, grow)!),
              bottom: Radius.circular(lerpDouble(cardRadius, 0, grow)!),
            ),
            side: grow == 1
                ? BorderSide.none
                : BorderSide(color: tier, width: 3 * (1 - grow)),
          ),
          child: child,
        );
      },
      child: FittedBox(
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
        clipBehavior: Clip.hardEdge,
        child: SizedBox.fromSize(
          size: pageSize,
          child: CharacterCardView(
            snapshot: widget.snapshot,
            entityId: widget.entityId,
            onEntityTap: (id) =>
                showCharacterCard(context, widget.snapshot, id, widget.session),
          ),
        ),
      ),
    );
  }

  Widget _restingCard(Color tier, Size pageSize) {
    return CollectibleCard(
      flip: _flip,
      showsBack: _showsDetails,
      onTurnOver: () => _setShowsDetails(true),
      front: (sheen) => CardFront(
        snapshot: widget.snapshot,
        entityId: widget.entityId,
        sheen: sheen,
      ),
      back: _details(tier, pageSize),
    );
  }

  Widget _revealingCard(Color tier) {
    final timeline = _timeline;
    final front = widget.snapshot.revealOf(widget.entityId)?.formerName;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final ms = _ms;
        final rise = Curves.easeOutCubic.transform(
          ((ms - _RevealTimeline.riseFrom) /
                  (_RevealTimeline.riseUntil - _RevealTimeline.riseFrom))
              .clamp(0.0, 1.0),
        );
        final charging =
            ms >= _RevealTimeline.chargeAt && ms < timeline.burstAt;
        final flip = Curves.easeOutCubic.transform(
          ((ms - timeline.flipAt) / _RevealTimeline.flipTakes).clamp(0.0, 1.0),
        );
        return Opacity(
          opacity: 0.35 + 0.65 * rise,
          child: Transform.translate(
            offset: Offset(
              charging ? math.sin(ms / 12) : 0,
              60 * (1 - rise) + (charging ? math.cos(ms / 9) : 0),
            ),
            child: Transform.scale(
              scale: 0.72 + 0.28 * rise,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(cardRadius),
                  boxShadow: [
                    if (charging) BoxShadow(color: tier, blurRadius: 26),
                  ],
                ),
                child: CardFlip(
                  angle: flip * math.pi,
                  first: CardCover(title: front),
                  second: CardFront(
                    snapshot: widget.snapshot,
                    entityId: widget.entityId,
                    litStars: timeline.litAt(ms),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _controls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListenableBuilder(
          listenable: _sounds,
          builder: (context, _) => IconButton(
            color: Colors.white,
            icon: Icon(_sounds.enabled ? Icons.volume_up : Icons.volume_off),
            tooltip: _sounds.enabled
                ? 'Mute card sounds'
                : 'Unmute card sounds',
            onPressed: () => _sounds.enabled = !_sounds.enabled,
          ),
        ),
        IconButton(
          color: Colors.white,
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tier = cardTierColor(widget.snapshot.starsOf(widget.entityId));
    const hint = TextStyle(color: Colors.white70, fontSize: 13);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          if (widget.reveal)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _revealing ? 1 : 0,
                  duration: const Duration(milliseconds: 350),
                  child: CustomPaint(
                    painter: _RevealStagePainter(
                      controller: _controller,
                      timeline: _timeline,
                      tier: tier,
                    ),
                  ),
                ),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final screen = constraints.biggest;
              final safe = MediaQuery.paddingOf(context)
                  .deflateRect(Offset.zero & screen);
              final cardWidth = math.min(safe.width - 48, 340.0);
              final rest = Rect.fromCenter(
                center: safe.center.translate(0, -(_hintGap + _hintHeight) / 2),
                width: cardWidth,
                height: math.min(cardWidth * 1.5, safe.height - 120),
              );
              final pageWidth = math.min(screen.width, _pageMaxWidth);
              final page = Rect.fromLTRB(
                (screen.width - pageWidth) / 2,
                safe.top + _buttonsHeight,
                (screen.width + pageWidth) / 2,
                screen.height,
              );
              return AnimatedBuilder(
                animation: _opening,
                child: _revealing
                    ? _revealingCard(tier)
                    : _restingCard(tier, page.size),
                builder: (context, card) => Stack(
                  children: [
                    // The map behind recedes, so that the buttons stand clear.
                    if (_grow.value > 0)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: Colors.black.withValues(
                              alpha: 0.55 * _grow.value,
                            ),
                          ),
                        ),
                      ),
                    Positioned.fromRect(
                      rect: Rect.lerp(rest, page, _grow.value)!,
                      child: card!,
                    ),
                    if (_opening.value < _hintFadesBy)
                      Positioned(
                        top: rest.bottom + _hintGap,
                        left: 0,
                        right: 0,
                        child: Opacity(
                          opacity: 1 - _opening.value / _hintFadesBy,
                          child: Text(
                            _revealing
                                ? 'Tap to skip'
                                : 'Tap to flip · Drag to tilt',
                            textAlign: TextAlign.center,
                            style: hint,
                          ),
                        ),
                      ),
                    if (_grow.value > 0)
                      Positioned(
                        top: safe.top,
                        left: safe.left,
                        child: Opacity(
                          opacity: _grow.value,
                          child: IconButton(
                            color: Colors.white,
                            icon: const Icon(Icons.arrow_back),
                            tooltip: 'Back to card',
                            onPressed: () => _setShowsDetails(false),
                          ),
                        ),
                      ),
                    if (!_revealing)
                      Positioned(
                        top: safe.top,
                        right: screen.width - safe.right,
                        child: _controls(),
                      ),
                  ],
                ),
              );
            },
          ),
          if (_revealing) ...[
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => ColoredBox(
                    color: Colors.white.withValues(
                      alpha: _flashAt(_ms, _timeline),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Semantics(
                button: true,
                label: 'Skip the reveal',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _skipReveal,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// How bright the burst's flash is at [ms], by the card's stars.
double _flashAt(double ms, _RevealTimeline timeline) {
  const peak = [0.15, 0.3, 0.55, 0.75, 0.95];
  final since = ms - timeline.burstAt;
  if (since < 0 || since > _RevealTimeline.flashTakes) return 0;
  return peak[timeline.stars - 1] * (1 - since / _RevealTimeline.flashTakes);
}

/// The dark stage behind a reveal: rays once it starts charging, and sparks
/// from the burst. More stars mean stronger rays and more sparks.
class _RevealStagePainter extends CustomPainter {
  _RevealStagePainter({
    required this.controller,
    required this.timeline,
    required this.tier,
  }) : super(repaint: controller) {
    const counts = [14, 30, 60, 110, 190];
    final random = math.Random(timeline.stars);
    _sparks = [
      for (var i = 0; i < counts[timeline.stars - 1]; i++)
        (
          random.nextDouble() * math.pi * 2,
          90 + random.nextDouble() * (120 + timeline.stars * 90),
          1 + random.nextDouble() * 2.2,
        ),
    ];
  }

  static const _rayStrength = [0.08, 0.16, 0.3, 0.45, 0.7];
  static const _sparkLife = 1.2;

  final AnimationController controller;
  final _RevealTimeline timeline;
  final Color tier;

  /// Direction, speed in points per second, and radius.
  late final List<(double, double, double)> _sparks;

  @override
  void paint(Canvas canvas, Size size) {
    final ms = controller.value * timeline.end;
    final bounds = Offset.zero & size;
    final center = size.center(Offset.zero);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF2A241D), Color(0xFF14110E)],
          radius: 0.8,
        ).createShader(bounds),
    );
    _paintRays(canvas, size, center, ms);
    _paintSparks(canvas, center, ms);
  }

  void _paintRays(Canvas canvas, Size size, Offset center, double ms) {
    final fade = ((ms - _RevealTimeline.chargeAt) / 300).clamp(0.0, 1.0);
    if (fade == 0) return;
    final reach = size.longestSide;
    final turn = ms / 4000;
    final strength = _rayStrength[timeline.stars - 1] * fade;
    final ray = Paint()
      ..shader = RadialGradient(
        colors: [
          tier.withValues(alpha: strength),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: reach * 0.6));
    for (var degrees = 0; degrees < 360; degrees += 22) {
      final from = turn + degrees * math.pi / 180;
      final to = from + 7 * math.pi / 180;
      canvas.drawPath(
        Path()
          ..moveTo(center.dx, center.dy)
          ..lineTo(
            center.dx + reach * math.cos(from),
            center.dy + reach * math.sin(from),
          )
          ..lineTo(
            center.dx + reach * math.cos(to),
            center.dy + reach * math.sin(to),
          )
          ..close(),
        ray,
      );
    }
  }

  void _paintSparks(Canvas canvas, Offset center, double ms) {
    final seconds = (ms - timeline.burstAt) / 1000;
    if (seconds <= 0 || seconds >= _sparkLife) return;
    final paint = Paint()
      ..color = tier.withValues(alpha: 1 - seconds / _sparkLife);
    // Sparks slow down as they fly, and start to fall.
    final travel = (1 - math.exp(-seconds * 2.2)) / 2.2;
    final fall = 60 * seconds * seconds;
    for (final (direction, speed, radius) in _sparks) {
      canvas.drawCircle(
        center +
            Offset(
              math.cos(direction) * speed * travel,
              math.sin(direction) * speed * travel + fall,
            ),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RevealStagePainter oldDelegate) =>
      oldDelegate.tier != tier || oldDelegate.timeline != timeline;
}
