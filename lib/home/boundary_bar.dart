import 'package:flutter/material.dart';

import '../theme/loremark_theme.dart';

/// How much of the book counts as read, filled up to the boundary, with a
/// marker where the reader is. After a jump past the boundary the marker is
/// green and the stretch skipped between them is tinted.
class BoundaryBar extends StatelessWidget {
  const BoundaryBar({
    super.key,
    required this.boundary,
    required this.current,
    required this.ahead,
  });

  /// How far into the whole book the boundary is, or null if unknown.
  final double? boundary;

  /// How far into the whole book the reader is, or null if unknown.
  final double? current;

  /// Whether the reader jumped past the boundary and is still there.
  final bool ahead;

  static const _barHeight = 4.0;
  static const _markerSize = 12.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _markerSize,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          double x(double fraction) => fraction.clamp(0.0, 1.0) * width;
          final boundary = this.boundary;
          final current = this.current;
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              _bar(width, LoremarkColors.line),
              if (boundary != null)
                _bar(
                  x(boundary),
                  LoremarkColors.olive,
                  key: const ValueKey('boundary-fill'),
                ),
              if (ahead && boundary != null && current != null)
                Positioned(
                  left: x(boundary),
                  child: _bar(
                    // Readium's totals aren't ours to promise are in order.
                    (x(current) - x(boundary)).clamp(0.0, width),
                    LoremarkColors.safeDot.withValues(alpha: 0.35),
                    key: const ValueKey('skipped'),
                  ),
                ),
              if (current != null)
                Positioned(
                  // Kept whole at either end of the bar.
                  left: (x(current) - _markerSize / 2).clamp(
                    0.0,
                    width - _markerSize,
                  ),
                  child: Container(
                    key: const ValueKey('reader-marker'),
                    width: _markerSize,
                    height: _markerSize,
                    decoration: BoxDecoration(
                      color: ahead
                          ? LoremarkColors.safeDot
                          : LoremarkColors.ink,
                      shape: BoxShape.circle,
                      // Sets the marker off the fill when it is inside it.
                      border: Border.all(color: LoremarkColors.paper, width: 2),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _bar(double width, Color color, {Key? key}) => Container(
    key: key,
    width: width,
    height: _barHeight,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(_barHeight / 2),
    ),
  );
}
