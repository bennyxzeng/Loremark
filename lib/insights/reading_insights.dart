import 'package:flutter/foundation.dart';

import '../reader/reader_position.dart';

/// Why the reader moved, as far as the Read tab knows.
///
/// Page buttons and contents jumps are started by our code, so their cause is
/// known. A position that arrives with no pending request came from a swipe
/// inside the rendered book.
enum NavigationCause {
  /// The first position after the book opened.
  open('o'),
  pageForward('pf'),
  pageBackward('pb'),
  tocJump('toc'),
  searchJump('sr'),
  swipe('sw');

  const NavigationCause(this.code);

  /// Short code written to the reading log.
  final String code;

  static NavigationCause? fromCode(String code) {
    for (final cause in values) {
      if (cause.code == code) return cause;
    }
    return null;
  }
}

/// Estimated reading time left, at the reader's own pace.
class TimeLeft {
  const TimeLeft({required this.chapter, required this.book});

  /// Until the next table of contents entry.
  final Duration chapter;

  /// Until the end of the last linear spine item.
  final Duration book;
}

/// Reading time on one local calendar day.
class DailyReading {
  const DailyReading({required this.day, required this.activeTime});

  /// Midnight, local time.
  final DateTime day;
  final Duration activeTime;
}

/// What the reading insights sheet shows.
class InsightsSummary {
  const InsightsSummary({
    required this.today,
    required this.unitsPerMinute,
    required this.paceSamples,
    required this.paceIsPersonal,
    required this.countsCharacters,
    required this.streakDays,
    required this.lastDays,
  });

  /// Active reading time today, idle time excluded.
  final Duration today;

  /// The reader's pace, or the default pace until there is enough data.
  final double unitsPerMinute;

  /// Page turns the pace was estimated from.
  final int paceSamples;

  /// Whether [unitsPerMinute] comes from this reader rather than a default.
  final bool paceIsPersonal;

  /// True for books mostly in Chinese, Japanese or Korean, where a unit is a
  /// character rather than a word.
  final bool countsCharacters;

  /// Days in a row with enough reading, counting back from today (or from
  /// yesterday if today has too little so far).
  final int streakDays;

  /// The last 14 days, oldest first, today last.
  final List<DailyReading> lastDays;
}

enum ConfusionKind {
  /// The same passage visited again and again in a short time.
  reread,

  /// A page that took far longer than usual, followed by looking back.
  stall,

  /// Going back to the same earlier chapter more than once.
  chapterBounce,

  /// Several searches in quick succession. Never nudges on its own.
  searchBurst,
}

/// A sign that the reader may have lost the thread, with the passage it is
/// about and a plain reason. These are heuristics, not diagnoses.
class ConfusionSignal {
  const ConfusionSignal({
    required this.kind,
    required this.at,
    required this.start,
    required this.end,
    required this.reason,
  });

  final ConfusionKind kind;
  final DateTime at;

  /// Where the passage starts and ends. Only progression within one section
  /// is known, so a span that crosses sections ends at the start of the next.
  final ReaderPosition start;
  final ReaderPosition end;

  /// Why it fired, e.g. "You've gone back to this passage 3 times in 12
  /// minutes". For logs and the insights sheet, not the nudge itself.
  final String reason;

  @override
  String toString() => 'ConfusionSignal($kind, $start..$end, $reason)';
}

/// Reading statistics and confusion signals for one open book, kept on the
/// device.
///
/// The Read tab feeds it every position with its [NavigationCause]; it logs
/// them, keeps the estimates up to date and notifies listeners when anything
/// shown changes. Logging problems never interrupt reading.
abstract interface class ReadingInsights implements Listenable {
  /// Records that the reader moved to [position].
  void recordPosition(ReaderPosition position, NavigationCause cause);

  /// Records that the app went to the background, so the time away doesn't
  /// count as reading, and writes the log out.
  void recordHidden();

  /// Records that the app came back to the foreground.
  void recordShown();

  /// Time left from [position] at the reader's pace, or null until the pace
  /// is known well enough to show minutes. [chapterEndSection] is the
  /// section index where the next chapter starts, or null if the current
  /// chapter runs to the end of the book.
  TimeLeft? timeLeft(ReaderPosition position, {int? chapterEndSection});

  InsightsSummary get summary;

  /// The furthest position reached in this book, or null if never opened.
  ReaderPosition? get furthest;

  /// Every signal the detector emits, whether or not it is shown.
  Stream<ConfusionSignal> get signals;

  /// The signal to show as a nudge right now, if the nudge policy allows one.
  ConfusionSignal? get nudge;

  /// Hides [nudge] and holds back new ones for a while.
  void dismissNudge();

  /// Whether nudges are shown. Signals are still detected when off.
  bool get hintsEnabled;

  Future<void> setHintsEnabled(bool enabled);

  /// Writes everything out. Call when the app is hidden and before [close].
  Future<void> flush();

  /// Flushes and releases the book's log. Can't be used afterwards.
  Future<void> close();
}
