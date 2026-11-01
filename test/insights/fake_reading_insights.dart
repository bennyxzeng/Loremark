import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:loremark/insights/reading_insights.dart';
import 'package:loremark/reader/reader_position.dart';

/// Reading insights that remember how they were called and show whatever the
/// test sets, so widget tests need no log files or clock.
class FakeReadingInsights extends ChangeNotifier implements ReadingInsights {
  FakeReadingInsights({
    this.timeLeftValue,
    InsightsSummary? summary,
    this.hintsEnabled = true,
    this.furthest,
  }) : summary = summary ?? emptySummary();

  /// No reading yet: the default pace, no streak, 14 empty days ending today.
  static InsightsSummary emptySummary({DateTime? today}) {
    final end = today ?? DateTime(2026, 11, 1);
    return InsightsSummary(
      today: Duration.zero,
      unitsPerMinute: 230,
      paceSamples: 0,
      paceIsPersonal: false,
      countsCharacters: false,
      streakDays: 0,
      lastDays: [
        for (var i = 13; i >= 0; i--)
          DailyReading(
            day: DateTime(end.year, end.month, end.day - i),
            activeTime: Duration.zero,
          ),
      ],
    );
  }

  /// Every [recordPosition], in order.
  final List<(ReaderPosition, NavigationCause)> positions = [];

  /// The causes of [positions], for short assertions.
  List<NavigationCause> get causes => [for (final (_, c) in positions) c];

  /// The `(position, chapterEndSection)` of every [timeLeft] call.
  final List<(ReaderPosition, int?)> timeLeftCalls = [];

  int hiddenCalls = 0;
  int shownCalls = 0;
  int dismissCalls = 0;
  int flushCalls = 0;
  int closeCalls = 0;

  /// What [timeLeft] returns. Null means the pace isn't known yet.
  TimeLeft? timeLeftValue;

  @override
  InsightsSummary summary;

  @override
  ReaderPosition? furthest;

  final StreamController<ConfusionSignal> _signals =
      StreamController<ConfusionSignal>.broadcast();

  ConfusionSignal? _nudge;

  /// Tells the listening screen that [timeLeftValue] or [summary] changed.
  void changed() => notifyListeners();

  /// Shows [signal] as the nudge, or hides it when null.
  set nudgeSignal(ConfusionSignal? signal) {
    _nudge = signal;
    notifyListeners();
  }

  /// Pretends the detector found [signal]: it goes out on [signals] and
  /// becomes the nudge.
  void emitSignal(ConfusionSignal signal) {
    _signals.add(signal);
    nudgeSignal = signal;
  }

  @override
  void recordPosition(ReaderPosition position, NavigationCause cause) =>
      positions.add((position, cause));

  @override
  void recordHidden() => hiddenCalls++;

  @override
  void recordShown() => shownCalls++;

  @override
  TimeLeft? timeLeft(ReaderPosition position, {int? chapterEndSection}) {
    timeLeftCalls.add((position, chapterEndSection));
    return timeLeftValue;
  }

  @override
  Stream<ConfusionSignal> get signals => _signals.stream;

  @override
  ConfusionSignal? get nudge => _nudge;

  @override
  void dismissNudge() {
    dismissCalls++;
    _nudge = null;
    notifyListeners();
  }

  @override
  bool hintsEnabled;

  /// Every value [setHintsEnabled] was called with.
  final List<bool> hintsSet = [];

  @override
  Future<void> setHintsEnabled(bool enabled) async {
    hintsSet.add(enabled);
    hintsEnabled = enabled;
    notifyListeners();
  }

  @override
  Future<void> flush() async => flushCalls++;

  @override
  Future<void> close() async {
    closeCalls++;
    await _signals.close();
  }
}

/// A signal for tests, about the start of section 1.
ConfusionSignal testSignal({
  ConfusionKind kind = ConfusionKind.reread,
  String reason = 'You\'ve gone back to this passage 3 times in 12 minutes',
}) => ConfusionSignal(
  kind: kind,
  at: DateTime(2026, 11, 1, 10),
  start: const ReaderPosition(1, 0.2),
  end: const ReaderPosition(1, 0.3),
  reason: reason,
);
