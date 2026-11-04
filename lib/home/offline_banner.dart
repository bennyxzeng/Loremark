import 'package:flutter/material.dart';

import '../settings/connection_status.dart';
import '../theme/loremark_theme.dart';

/// A notification that slides in over the top of a book's tabs when the
/// device goes offline. The reader can dismiss it; the header's offline chip
/// stays as the reminder.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final status = ConnectionScope.of(context);
    final visible = status.showOfflineBanner;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -1.2),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Semantics(
              liveRegion: true,
              child: Material(
                color: LoremarkColors.card,
                elevation: 3,
                shadowColor: LoremarkColors.ink.withValues(alpha: 0.25),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: LoremarkColors.line),
                ),
                // The close button floats in the corner rather than taking a
                // column of the row, so only the title has to keep clear of
                // its tap target and the description runs to the edge.
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: const BoxDecoration(
                              color: LoremarkColors.olive,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.wifi_off,
                              size: 17,
                              color: LoremarkColors.onOlive,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(right: 32),
                                  child: Text(
                                    'You’re offline',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: LoremarkColors.ink,
                                    ),
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Story Map will not update, and Ask is not available until'
                                  ' the connection is restored. ',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: LoremarkColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        onPressed: status.dismissOfflineBanner,
                        tooltip: 'Dismiss',
                        icon: const Icon(
                          Icons.close,
                          size: 18,
                          color: LoremarkColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The header's small reminder that the device is offline.
class OfflineChip extends StatelessWidget {
  const OfflineChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: LoremarkColors.chip,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: LoremarkColors.chipBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, size: 13, color: LoremarkColors.chipText),
          const SizedBox(width: 5),
          Text(
            'OFFLINE',
            style: kicker(color: LoremarkColors.chipText, size: 9),
          ),
        ],
      ),
    );
  }
}
