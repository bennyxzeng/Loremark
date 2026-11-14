import 'package:flutter/material.dart';

import '../library/book.dart';
import '../settings/connection_status.dart';
import '../story_map/story_map_backend.dart';
import '../story_map/story_map_status.dart';
import '../story_map/story_update_bar.dart';
import '../theme/loremark_theme.dart';
import 'offline_banner.dart';

/// The top of every tab: the open book, an offline chip while the device has
/// no network, and the Story Map's status. Tapping the book returns to the
/// library; tapping the status opens the Story Map.
class ReaderHeader extends StatelessWidget {
  const ReaderHeader({
    super.key,
    required this.book,
    required this.onOpenLibrary,
    this.storyMap,
    this.onOpenStoryMap,
    this.now = DateTime.now,
  });

  final Book book;
  final VoidCallback onOpenLibrary;

  /// The Story Map's update under way, and where the reader is next to the
  /// map. Left out, the header shows neither.
  final StoryMapStatusController? storyMap;
  final VoidCallback? onOpenStoryMap;

  /// The time now, for how long an update has run; tests replace it.
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final storyMap = this.storyMap;
    return Material(
      color: LoremarkColors.header,
      shape: const Border(bottom: BorderSide(color: Color(0xFFEDDFCD))),
      child: storyMap == null
          ? _row(context, null)
          : ListenableBuilder(
              listenable: storyMap,
              builder: (context, _) => _row(context, storyMap),
            ),
    );
  }

  Widget _row(BuildContext context, StoryMapStatusController? storyMap) {
    final status = storyMap == null ? null : _StoryMapState.of(storyMap);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: 'Library',
            child: InkWell(
              onTap: onOpenLibrary,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  14,
                  status == null ? 16 : 6,
                  14,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.chevron_left, color: LoremarkColors.muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CURRENTLY READING',
                            style: kicker(color: LoremarkColors.muted, size: 9),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            book.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!ConnectionScope.of(context).isOnline) ...[
                      // The Story Map's status needs its words more.
                      OfflineChip(compact: status != null),
                      if (status == null) const SizedBox(width: 10),
                    ],
                    // Until there is a status to show in its place.
                    if (status == null)
                      const Icon(
                        Icons.local_library_outlined,
                        color: LoremarkColors.muted,
                        size: 20,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _StoryMapChip(
              state: status,
              startedAt: storyMap!.updateStartedAt,
              step: storyMap.step,
              total: storyMap.total,
              onTap: onOpenStoryMap,
              now: now,
            ),
          ),
      ],
    );
  }
}

/// What the Story Map chip says, and how loudly.
enum _StoryMapState {
  updating('UPDATING', 'updating', _ChipColors.loud),
  cancelling('CANCELLING', 'cancelling an update', _ChipColors.loud),
  stopping(
    'STOPPING',
    'finishing this section, then stopping',
    _ChipColors.loud,
  ),
  inMap('IN MAP', 'this page is in the map', _ChipColors.calm),
  ahead('NEEDS UPDATE', 'needs an update to reach this page', _ChipColors.warm),
  before('NOT IN MAP', 'this page is before the map starts', _ChipColors.quiet),
  none('NO MAP YET', 'this book has none yet', _ChipColors.quiet);

  const _StoryMapState(this.label, this.spoken, this.colors);

  final String label;

  /// For screen readers, after "Story Map: ".
  final String spoken;
  final _ChipColors colors;

  /// What [storyMap] has to show, or null for nothing yet.
  static _StoryMapState? of(StoryMapStatusController storyMap) {
    if (storyMap.updateStartedAt != null) {
      if (storyMap.cancelling) return cancelling;
      return storyMap.stopping ? stopping : updating;
    }
    return switch (storyMap.coverage) {
      null => null,
      StoryCoverage.none => none,
      StoryCoverage.before => before,
      StoryCoverage.inMap => inMap,
      StoryCoverage.ahead => ahead,
    };
  }
}

class _ChipColors {
  const _ChipColors(this.fill, this.border, this.text);

  /// An update under way: filled, so it is plain that something is happening.
  static const loud = _ChipColors(
    LoremarkColors.olive,
    LoremarkColors.olive,
    LoremarkColors.onOlive,
  );
  static const calm = _ChipColors(
    LoremarkColors.boundary,
    LoremarkColors.boundary,
    LoremarkColors.olive,
  );

  /// Something the reader can do something about.
  static const warm = _ChipColors(
    LoremarkColors.chip,
    LoremarkColors.chipBorder,
    LoremarkColors.avatarText,
  );
  static const quiet = _ChipColors(
    LoremarkColors.header,
    LoremarkColors.line,
    LoremarkColors.muted,
  );

  final Color fill;
  final Color border;
  final Color text;
}

/// Screens narrower than this are too narrow for both the time and the count
/// of sections in the Story Map chip.
const _narrow = 360.0;

/// The Story Map's status at the end of the header, styled like the offline
/// chip. Its tap target is the header's full height.
class _StoryMapChip extends StatelessWidget {
  const _StoryMapChip({
    required this.state,
    required this.startedAt,
    required this.step,
    required this.total,
    required this.onTap,
    required this.now,
  });

  final _StoryMapState state;
  final DateTime? startedAt;

  /// Which of the [total] sections asked for is being added, counted from 0.
  final int step;
  final int total;
  final VoidCallback? onTap;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final colors = state.colors;
    final style = kicker(color: colors.text, size: 9);
    final startedAt = this.startedAt;
    // Which section is under way, when there are several. On a small phone
    // that leaves no room for the time, which the Story Map tab shows.
    final several = startedAt != null && total > 1;
    final showTime =
        startedAt != null &&
        !(several && MediaQuery.sizeOf(context).width < _narrow);
    final spokenStep = several ? ', section ${step + 1} of $total' : '';
    return Semantics(
      button: true,
      label: 'Story Map: ${state.spoken}$spokenStep. Opens the Story Map.',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
            decoration: BoxDecoration(
              color: colors.fill,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hub, size: 13, color: colors.text),
                const SizedBox(width: 5),
                Text(state.label, style: style),
                if (several) ...[
                  const SizedBox(width: 4),
                  Text(
                    '${step + 1}/$total',
                    style: style.copyWith(
                      letterSpacing: 0.4,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
                if (showTime) ...[
                  const SizedBox(width: 2),
                  StoryElapsedTime(
                    startedAt: startedAt,
                    now: now,
                    style: style.copyWith(letterSpacing: 0.4),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
