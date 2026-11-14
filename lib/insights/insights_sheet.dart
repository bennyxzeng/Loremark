import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/loremark_theme.dart';
import 'reading_insights.dart';
import 'reading_time_text.dart';

/// Shows how the reader has been reading, and the switch for reading hints.
///
/// [timeLeft] is the estimate at the moment the sheet opens, or null while
/// the pace is still being learned.
Future<void> showInsightsSheet(
  BuildContext context, {
  required ReadingInsights insights,
  required TimeLeft? timeLeft,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    builder: (context) => InsightsSheet(insights: insights, timeLeft: timeLeft),
  );
}

/// Today, pace, time left, streak and the last two weeks at a glance.
class InsightsSheet extends StatefulWidget {
  const InsightsSheet({
    super.key,
    required this.insights,
    required this.timeLeft,
  });

  final ReadingInsights insights;
  final TimeLeft? timeLeft;

  @override
  State<InsightsSheet> createState() => _InsightsSheetState();
}

class _InsightsSheetState extends State<InsightsSheet> {
  /// Kept here so the switch moves at once, before the setting is written.
  late bool _hints = widget.insights.hintsEnabled;

  @override
  void initState() {
    super.initState();
    widget.insights.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(InsightsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.insights, widget.insights)) {
      oldWidget.insights.removeListener(_onChanged);
      widget.insights.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.insights.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() => _hints = widget.insights.hintsEnabled);

  Future<void> _setHints(bool enabled) async {
    setState(() => _hints = enabled);
    try {
      await widget.insights.setHintsEnabled(enabled);
    } on Object catch (error) {
      debugPrint('Could not save the reading hints setting: $error');
      if (mounted) {
        setState(() => _hints = widget.insights.hintsEnabled);
      }
    }
  }

  String _pace(InsightsSummary summary) {
    final rounded = (summary.unitsPerMinute / 10).round() * 10;
    final unit = summary.countsCharacters ? 'characters' : 'words';
    return '~$rounded $unit/min';
  }

  String _paceNote(InsightsSummary summary) => summary.paceIsPersonal
      ? 'Estimated from ${summary.paceSamples} page turns'
      : 'A typical pace until it learns yours';

  @override
  Widget build(BuildContext context) {
    final summary = widget.insights.summary;
    final timeLeft = widget.timeLeft;
    final days = summary.lastDays;
    final bestDay = days.isEmpty
        ? Duration.zero
        : days.map((day) => day.activeTime).reduce((a, b) => a > b ? a : b);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('READING INSIGHTS', style: kicker()),
          const SizedBox(height: 14),
          Wrap(
            spacing: 24,
            runSpacing: 16,
            children: [
              _Stat(
                label: 'TODAY',
                value: _shortTime(summary.today),
                // Today and the streak add up every book, so a book opened
                // for the first time can already show time.
                note: 'All books, idle time not counted',
              ),
              _Stat(
                label: 'PACE',
                value: _pace(summary),
                note: _paceNote(summary),
              ),
              _Stat(
                label: 'LEFT IN CHAPTER',
                value: timeLeft == null
                    ? '--'
                    : _shortTime(timeLeft.chapter, zero: 'Under a minute'),
                note: timeLeft == null ? 'Shown once your pace is known' : null,
              ),
              _Stat(
                label: 'LEFT IN BOOK',
                value: timeLeft == null
                    ? '--'
                    : _shortTime(timeLeft.book, zero: 'Under a minute'),
              ),
              _Stat(
                label: 'STREAK',
                value:
                    '${summary.streakDays} ${summary.streakDays == 1 ? 'day' : 'days'}',
                note: 'Best day: ${_shortTime(bestDay)}',
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('LAST 14 DAYS', style: kicker(color: LoremarkColors.muted)),
          const SizedBox(height: 10),
          DailyReadingChart(days: days),
          const SizedBox(height: 12),
          const Divider(),
          SwitchListTile(
            key: const ValueKey('hints-switch'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Reading hints',
              style: serif(15, color: LoremarkColors.readerTitle),
            ),
            subtitle: const Text(
              'Offer help when you keep rereading a passage. '
              'Everything stays on this device.',
              style: TextStyle(fontSize: 12, color: LoremarkColors.muted),
            ),
            value: _hints,
            onChanged: _setHints,
          ),
        ],
      ),
    );
  }
}

/// "0 min" for none, otherwise as [formatReadingTime].
String _shortTime(Duration time, {String zero = '0 min'}) =>
    time == Duration.zero ? zero : formatReadingTime(time);

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.note});

  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 160),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: kicker(color: LoremarkColors.muted)),
          const SizedBox(height: 4),
          Text(value, style: serif(20, color: LoremarkColors.readerTitle)),
          if (note case final note?)
            Text(
              note,
              style: const TextStyle(fontSize: 11, color: LoremarkColors.muted),
            ),
        ],
      ),
    );
  }
}

/// Minutes read on each of the last days, as bars with today highlighted.
class DailyReadingChart extends StatelessWidget {
  const DailyReadingChart({super.key, required this.days});

  /// Oldest first, today last.
  final List<DailyReading> days;

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _weekdayNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  String get _description {
    final parts = [
      for (final day in days)
        '${_weekdayNames[day.day.weekday - 1]} '
            '${(day.activeTime.inSeconds / 60).round()} min',
    ];
    return 'Reading time per day, last ${days.length} days: '
        '${parts.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _description,
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        key: const ValueKey('daily-chart'),
        height: 110,
        width: double.infinity,
        child: CustomPaint(
          painter: DailyReadingPainter(
            minutes: [for (final day in days) day.activeTime.inSeconds / 60],
            labels: [for (final day in days) _weekdays[day.day.weekday - 1]],
          ),
        ),
      ),
    );
  }
}

/// Draws [minutes] as rounded bars over a thin baseline, with [labels] under
/// them. The last bar is today's.
class DailyReadingPainter extends CustomPainter {
  DailyReadingPainter({required this.minutes, required this.labels});

  final List<double> minutes;
  final List<String> labels;

  /// The top of the scale: the next of 15, 30, 60 or 120 minutes above the
  /// biggest bar, then whole hours, so a quiet week doesn't look flat.
  static double scaleMax(Iterable<double> minutes) {
    final biggest = minutes.fold<double>(0, (a, b) => a > b ? a : b);
    for (final step in const [15.0, 30.0, 60.0, 120.0]) {
      if (biggest <= step) return step;
    }
    return (biggest / 60).ceil() * 60;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (minutes.isEmpty) return;
    const labelHeight = 16.0;
    final chartHeight = size.height - labelHeight;
    final max = scaleMax(minutes);
    final slot = size.width / minutes.length;
    final barWidth = slot * 0.6;

    final baseline = Paint()
      ..color = LoremarkColors.line
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, chartHeight),
      Offset(size.width, chartHeight),
      baseline,
    );

    for (var i = 0; i < minutes.length; i++) {
      final isToday = i == minutes.length - 1;
      final centre = slot * (i + 0.5);
      if (minutes[i] > 0) {
        // Even a short day gets a visible bar.
        final height = (minutes[i] / max * (chartHeight - 4)).clamp(
          3.0,
          chartHeight,
        );
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(
              centre - barWidth / 2,
              chartHeight - height,
              barWidth,
              height,
            ),
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          ),
          Paint()..color = isToday ? LoremarkColors.olive : LoremarkColors.gold,
        );
      }
      if (i < labels.length) {
        final text = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: TextStyle(
              fontSize: 10,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
              color: isToday ? LoremarkColors.olive : LoremarkColors.muted,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, Offset(centre - text.width / 2, chartHeight + 3));
        text.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(DailyReadingPainter oldDelegate) =>
      !listEquals(minutes, oldDelegate.minutes) ||
      !listEquals(labels, oldDelegate.labels);
}
