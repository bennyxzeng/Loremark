import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'companion_art.dart';
import 'companion_director.dart';

/// The Loremark companion, animated like a pixel game character: she breathes
/// and blinks, thinks with a raised hand, and says an answer as it arrives,
/// hopping on each open mouth.
///
/// She keeps still while [active] is false, as when her tab is hidden, and
/// when the system asks for less motion.
class CompanionSprite extends StatefulWidget {
  const CompanionSprite({
    super.key,
    required this.frame,
    required this.height,
    this.mood = CompanionMood.idle,
    this.speech = '',
    this.citations = 0,
    this.active = true,
    this.greet = false,
  });

  final CompanionFrame frame;
  final double height;
  final CompanionMood mood;

  /// What she's saying so far, while [mood] is talking. She says what's added
  /// to it.
  final String speech;

  /// How many citations [speech] has; she points when one is added.
  final int citations;

  final bool active;

  /// Whether she raises a finger soon after appearing.
  final bool greet;

  @override
  State<CompanionSprite> createState() => _CompanionSpriteState();
}

class _CompanionSpriteState extends State<CompanionSprite> {
  late final CompanionDirector _director = CompanionDirector();
  final _clock = Stopwatch();
  Timer? _timer;
  bool _animating = false;

  CompanionArt? _art;
  ui.Image? _image;
  CompanionPose? _imagePose;
  CompanionFrame? _imageFrame;

  @override
  void initState() {
    super.initState();
    _director.setMood(widget.mood, Duration.zero);
    CompanionArt.load().then(
      (art) {
        if (!mounted) return;
        setState(() {
          _art = art;
          _picture();
        });
      },
      onError: (Object error) {
        debugPrint('Could not load the companion: $error');
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate();
  }

  @override
  void didUpdateWidget(CompanionSprite oldWidget) {
    super.didUpdateWidget(oldWidget);
    final now = _clock.elapsed;
    _director.setMood(widget.mood, now);
    final said = oldWidget.speech;
    final saying = widget.speech;
    if (widget.mood == CompanionMood.talking && saying.length > said.length) {
      _director.hear(saying.substring(said.length), now);
    }
    if (widget.citations > oldWidget.citations) _director.emphasize(now);
    _animate();
    _changed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _image?.dispose();
    super.dispose();
  }

  /// Starts or stops animating, as [CompanionSprite.active] and the system's
  /// motion setting say.
  void _animate() {
    final animate = widget.active && !MediaQuery.disableAnimationsOf(context);
    if (animate == _animating) return;
    _animating = animate;
    if (animate) {
      _clock
        ..reset()
        ..start();
      _director.start(Duration.zero, greet: widget.greet);
    } else {
      _clock.stop();
      _director.stop();
    }
    _changed();
  }

  /// After the director was told something: shows its pose and waits for the
  /// next change. Called while building, so it doesn't call setState.
  void _changed() {
    _director.advance(_clock.elapsed);
    _picture();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    final next = _director.nextChange;
    if (!_animating || next == null) return;
    final wait = next - _clock.elapsed;
    _timer = Timer(wait.isNegative ? Duration.zero : wait, _tick);
  }

  void _tick() {
    if (!mounted) return;
    setState(() {
      _director.advance(_clock.elapsed);
      _picture();
    });
    _schedule();
  }

  /// Pastes a new picture if the pose or frame needs one.
  void _picture() {
    final art = _art;
    if (art == null) return;
    final pose = _director.pose;
    final frame = widget.frame;
    final shown = _imagePose;
    if (_image != null &&
        frame == _imageFrame &&
        shown != null &&
        shown.looksLike(pose)) {
      return;
    }
    _image?.dispose();
    _image = art.picture(pose, frame);
    _imagePose = pose;
    _imageFrame = frame;
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.height;
    final art = _art;
    final width = art == null ? height : height * art.aspectRatio(widget.frame);
    final image = _image;
    if (image == null) return SizedBox(width: width, height: height);

    // Whole device pixels, so she moves in steps like a pixel game sprite.
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final hop = (_director.pose.hop * height / 100 * ratio).round() / ratio;
    Widget picture = RawImage(
      image: image,
      width: width,
      height: height,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
    if (widget.frame == CompanionFrame.bust) {
      // Her hair and sleeves are cut off at the bottom; fade them out.
      picture = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0, 0.7, 1],
        ).createShader(bounds),
        child: picture,
      );
    }
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: Transform.translate(offset: Offset(0, -hop), child: picture),
      ),
    );
  }
}
