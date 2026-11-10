import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../theme/loremark_theme.dart';

/// Whether the reader has seen the swipe hint, kept as an empty file whose
/// presence means they have. Shared by every book.
class SwipeHintFlag {
  const SwipeHintFlag();

  Future<bool> seen() async => (await _seenFile()).exists();

  Future<void> markSeen() async {
    await (await _seenFile()).create(recursive: true);
  }
}

Future<File> _seenFile() async {
  final support = await getApplicationSupportDirectory();
  return File('${support.path}/swipe_hint_seen');
}

/// Shows [child] with a hint to swipe sideways to turn pages, until the reader
/// first swipes sideways or taps the hint. After that it never shows again.
class SwipeHint extends StatefulWidget {
  const SwipeHint({
    super.key,
    required this.child,
    this.flag = const SwipeHintFlag(),
  });

  final Widget child;

  /// Where the hint is remembered as seen; tests replace the device's.
  final SwipeHintFlag flag;

  @override
  State<SwipeHint> createState() => _SwipeHintState();
}

class _SwipeHintState extends State<SwipeHint> {
  /// How far sideways a finger has to move to count as a swipe.
  static const _swipeDistance = 40.0;

  /// Starts hidden, so a reader who has seen it doesn't see it flash while
  /// the flag is read.
  bool _visible = false;

  /// The finger that may be swiping, and where it went down.
  int? _pointer;
  Offset? _downAt;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final seen = await widget.flag.seen();
      if (mounted && !seen) setState(() => _visible = true);
    } on Object {
      // Leave it hidden rather than show it every time.
    }
  }

  /// Hides the hint now, and for good once that is saved. If saving fails,
  /// it shows again next time.
  Future<void> _dismiss() async {
    if (!_visible) return;
    setState(() => _visible = false);
    try {
      await widget.flag.markSeen();
    } on Object {
      // Nothing else depends on it.
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointer = event.pointer;
    _downAt = event.position;
  }

  void _onPointerUp(PointerUpEvent event) {
    final downAt = _downAt;
    if (event.pointer != _pointer || downAt == null) return;
    final delta = event.position - downAt;
    // Scrolling up or down is the mistake the hint is for, so only a sideways
    // move counts.
    if (delta.dx.abs() > _swipeDistance && delta.dx.abs() > delta.dy.abs()) {
      unawaited(_dismiss());
    }
  }

  @override
  Widget build(BuildContext context) {
    // A Listener sees the swipe without taking it from the page under it.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_visible)
            Positioned(
              left: 12,
              right: 12,
              // Above the page buttons, so they stay usable.
              bottom: 60,
              child: Center(
                child: _HintCard(onTap: () => unawaited(_dismiss())),
              ),
            ),
        ],
      ),
    );
  }
}

/// The hint itself, styled like the offline banner.
class _HintCard extends StatelessWidget {
  const _HintCard({required this.onTap});

  final VoidCallback onTap;

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
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          child: Row(
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
                  Icons.swipe,
                  size: 17,
                  color: LoremarkColors.onOlive,
                ),
              ),
              const SizedBox(width: 12),
              const Flexible(
                child: Text(
                  'Swipe left or right to turn pages',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: LoremarkColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.close, size: 18, color: LoremarkColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
