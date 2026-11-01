import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/loremark_theme.dart';
import 'reading_insights.dart';

/// A gentle strip under the book text offering help after a
/// [ConfusionSignal].
///
/// It sits between the reader and the page controls instead of over the text
/// (no SnackBar or dialog), asks a question rather than diagnosing, and hides
/// itself after [autoHide]. [onDismiss] runs for the close button and for the
/// timeout alike, since both mean "not now". Taking an action runs [onAccept]
/// instead, which is not a dismissal.
class ReadingNudge extends StatefulWidget {
  const ReadingNudge({
    super.key,
    required this.signal,
    required this.onDismiss,
    this.onAccept,
    this.onOpenStoryMap,
    this.onSearchChapter,
    this.autoHide = const Duration(seconds: 12),
  });

  final ConfusionSignal signal;
  final VoidCallback onDismiss;

  /// Runs after the reader takes an action, to hide the strip. Defaults to
  /// [onDismiss] when null.
  final VoidCallback? onAccept;

  /// Opens the Story Map. The button is left out when this is null.
  final VoidCallback? onOpenStoryMap;

  /// Opens a search of the current chapter. The button is left out when this
  /// is null, e.g. when book search isn't available.
  final VoidCallback? onSearchChapter;

  final Duration autoHide;

  @override
  State<ReadingNudge> createState() => _ReadingNudgeState();
}

class _ReadingNudgeState extends State<ReadingNudge> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.autoHide, widget.onDismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Calm, a question or an offer: never "confused" or "struggling".
  String get _message => switch (widget.signal.kind) {
    ConfusionKind.reread => 'Rereading this part?',
    ConfusionKind.stall =>
      'This part may be dense. A refresher on the characters might help.',
    ConfusionKind.chapterBounce => 'Looking back at an earlier chapter?',
    ConfusionKind.searchBurst => 'Looking for something?',
  };

  /// Takes the action, then hides the strip: the reader has accepted it.
  VoidCallback _then(VoidCallback action) => () {
    action();
    (widget.onAccept ?? widget.onDismiss)();
  };

  @override
  Widget build(BuildContext context) {
    final openStoryMap = widget.onOpenStoryMap;
    final searchChapter = widget.onSearchChapter;
    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        key: const ValueKey('reading-nudge'),
        decoration: const BoxDecoration(
          color: LoremarkColors.panel,
          border: Border(top: BorderSide(color: LoremarkColors.line)),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 22, right: 6, top: 8, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _message,
                      style: serif(14, color: LoremarkColors.readerTitle),
                    ),
                    if (openStoryMap != null || searchChapter != null)
                      Wrap(
                        children: [
                          if (openStoryMap != null)
                            TextButton(
                              onPressed: _then(openStoryMap),
                              child: const Text("See who's who so far"),
                            ),
                          if (searchChapter != null)
                            TextButton(
                              onPressed: _then(searchChapter),
                              child: const Text('Search this chapter'),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Dismiss',
                color: LoremarkColors.muted,
                onPressed: widget.onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
