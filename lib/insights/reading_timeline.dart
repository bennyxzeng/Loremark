import 'dart:math';

import 'insights_config.dart';
import 'reading_log.dart';
import 'view_tracker.dart';

/// The local calendar day of [ms] at [tzMinutes] east of UTC, like
/// `2026-09-30`.
///
/// Days are computed from the offset stored in the log rather than the
/// device's current zone, so replaying a log gives the same days anywhere.
String dayKey(int ms, int tzMinutes) {
  final shifted = DateTime.fromMillisecondsSinceEpoch(
    ms,
    isUtc: true,
  ).add(Duration(minutes: tzMinutes));
  return _formatDay(shifted);
}

String _formatDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

DateTime _parseDay(String key) {
  final parts = key.split('-').map(int.parse).toList();
  return DateTime.utc(parts[0], parts[1], parts[2]);
}

/// The day before [key].
String previousDay(String key) =>
    _formatDay(_parseDay(key).subtract(const Duration(days: 1)));

/// The [count] days ending with [today], oldest first.
List<String> lastDayKeys(String today, int count) {
  final keys = <String>[today];
  while (keys.length < count) {
    keys.insert(0, previousDay(keys.first));
  }
  return keys;
}

/// Days in a row with at least [minMs] of reading, counting back from
/// [today]. A today that doesn't have enough yet doesn't break the streak:
/// counting then starts from yesterday.
int streakDays(String today, int Function(String day) activeMs, int minMs) {
  var day = activeMs(today) >= minMs ? today : previousDay(today);
  var streak = 0;
  while (activeMs(day) >= minMs) {
    streak++;
    day = previousDay(day);
    // A log can't hold more than a few years of days; stop runaway loops.
    if (streak > 36500) break;
  }
  return streak;
}

/// A page that was read at a steady pace: how many units, in how many
/// seconds.
class PaceSample {
  const PaceSample({required this.t, required this.units, required this.sec});

  /// When the page was turned, epoch milliseconds.
  final int t;
  final double units;
  final double sec;

  double get secPerUnit => sec / units;

  List<Object> toJson() => [t, units, double.parse(sec.toStringAsFixed(1))];

  static PaceSample? fromJson(Object? json) {
    if (json is! List || json.length != 3) return null;
    final t = json[0];
    final units = json[1];
    final sec = json[2];
    if (t is! int || units is! num || sec is! num || units <= 0 || sec <= 0) {
      return null;
    }
    return PaceSample(t: t, units: units.toDouble(), sec: sec.toDouble());
  }
}

/// The pace sample [view] gives, or null.
///
/// Stricter than the time totals, because a dwell clamped at two minutes on a
/// full page would fake a slow reader. Only a first read of a page that the
/// reader then turned forward counts, seen for between the minimum and
/// maximum dwell, with enough text on it, at a believable speed.
PaceSample? paceSampleOf(PageView view, InsightsConfig config) {
  if (view.end != ViewEnd.moved ||
      view.move != MoveKind.forwardPage ||
      view.resumed ||
      view.isRevisit ||
      view.isSectionEnd) {
    return null;
  }
  final units = view.forwardUnits;
  final dwell = view.dwellSec;
  if (units < config.sampleMinUnits ||
      dwell < config.minDwell.inMilliseconds / 1000 ||
      dwell > config.maxDwell.inMilliseconds / 1000) {
    return null;
  }
  final perMinute = units / (dwell / 60);
  if (perMinute < config.sampleMinUnitsPerMinute ||
      perMinute > config.sampleMaxUnitsPerMinute) {
    return null;
  }
  return PaceSample(t: view.endMs, units: units, sec: dwell);
}

/// A reading speed, and whether it is the reader's own.
class PaceEstimate {
  const PaceEstimate({
    required this.unitsPerMinute,
    required this.samples,
    required this.personal,
  });

  final double unitsPerMinute;

  /// Samples from this book the estimate used.
  final int samples;

  /// False while the speed is only the default for the book's language.
  final bool personal;

  double get secPerUnit => 60 / unitsPerMinute;
}

/// Estimates how fast the reader gets through text.
///
/// The speed is the ratio of sums (total seconds over total units) of the
/// newest samples, after dropping the slowest tenth as probable interruptions.
/// Time left is a total, so the mean is the right target, and the ratio of
/// sums weighs long pages properly; a median would be optimistic for totals
/// and an EWMA has no clean "enough data" test. A prior, the same estimate
/// over the reader's other books or else the default speed, is blended in
/// with a weight of a few samples, so a new book starts sensible.
class PaceEstimator {
  const PaceEstimator(this.config);

  final InsightsConfig config;

  /// The trimmed ratio of sums over the newest [window] of [samples], in
  /// seconds per unit, or null with no samples.
  double? trimmedSecPerUnit(List<PaceSample> samples, int window) {
    if (samples.isEmpty) return null;
    final recent = samples.length > window
        ? samples.sublist(samples.length - window)
        : samples;
    final sorted = [...recent]
      ..sort((a, b) => a.secPerUnit.compareTo(b.secPerUnit));
    final keep =
        sorted.length - (sorted.length * config.paceTrimFraction).floor();
    var sec = 0.0;
    var units = 0.0;
    for (final sample in sorted.take(keep)) {
      sec += sample.sec;
      units += sample.units;
    }
    return sec / units;
  }

  /// The pace from this book's [own] samples (oldest first) and the
  /// [pool] of samples from other books, falling back to
  /// [defaultUnitsPerMinute].
  PaceEstimate estimate({
    required List<PaceSample> own,
    List<PaceSample> pool = const [],
    required double defaultUnitsPerMinute,
  }) {
    final personal =
        own.length >= config.minSamplesToShow ||
        pool.length >= config.minPoolSamplesToShow;
    if (!personal) {
      return PaceEstimate(
        unitsPerMinute: defaultUnitsPerMinute,
        samples: own.length,
        personal: false,
      );
    }
    final prior = pool.length >= config.minPoolSamplesToShow
        ? trimmedSecPerUnit(pool, config.poolWindow)!
        : 60 / defaultUnitsPerMinute;
    final window = min(own.length, config.paceWindow);
    final mine = trimmedSecPerUnit(own, config.paceWindow);
    final secPerUnit = mine == null
        ? prior
        : (window * mine + config.paceShrinkage * prior) /
              (window + config.paceShrinkage);
    return PaceEstimate(
      unitsPerMinute: (60 / secPerUnit).clamp(
        config.paceFloorUnitsPerMinute,
        config.paceCeilingUnitsPerMinute,
      ),
      samples: window,
      personal: true,
    );
  }
}

/// Reading on one local day.
class DayTotals {
  DayTotals({this.ms = 0, this.units = 0, this.pages = 0, this.sessions = 0});

  /// Active reading time.
  int ms;

  /// New units read: pages turned forward for the first time.
  int units;
  int pages;
  int sessions;
}

/// A stretch of reading with no long break.
class Session {
  Session({required this.id, required this.startMs, required this.day});

  final int id;
  final int startMs;

  /// The local day the session started on.
  final String day;
  int endMs = 0;
  int activeMs = 0;
  int units = 0;

  int get wallMs => endMs - startMs;
}

/// What a reading log adds up to: time per day, sessions and the speed
/// samples.
///
/// Fed with the events of a `ViewTracker`, so it can be rebuilt from the log
/// at any time and there is no state to corrupt. A session that spans
/// midnight is split by the day each page was shown.
class ReadingTimeline {
  ReadingTimeline(this.config);

  final InsightsConfig config;
  final days = <String, DayTotals>{};
  final sessions = <int, Session>{};

  /// Samples of this book, oldest first.
  final samples = <PaceSample>[];

  /// Takes an event from the tracker.
  void onEvent(ViewEvent event) {
    if (event is! ViewEnded) return;
    final view = event.view;
    final activeMs = (view.activeSec * 1000).round();
    final totals = days.putIfAbsent(
      dayKey(view.startMs, view.tz),
      DayTotals.new,
    );
    totals.ms += activeMs;
    final newUnits = view.move == MoveKind.forwardPage && !view.isRevisit
        ? view.forwardUnits.round()
        : 0;
    if (newUnits > 0) {
      totals.units += newUnits;
      totals.pages++;
    }

    final session = sessions.putIfAbsent(
      view.sessionId,
      () => Session(
        id: view.sessionId,
        startMs: view.sessionStartMs,
        day: dayKey(view.sessionStartMs, view.tz),
      ),
    );
    if (session.activeMs == 0 && activeMs > 0) {
      days.putIfAbsent(session.day, DayTotals.new).sessions++;
    }
    session
      ..activeMs += activeMs
      ..units += newUnits
      ..endMs = max(session.endMs, view.endMs);

    final sample = paceSampleOf(view, config);
    if (sample != null) {
      samples.add(sample);
      if (samples.length > config.keptSamples) samples.removeAt(0);
    }
  }

  /// Adds a day that compaction summarised.
  void addDay(DayRecord record) {
    final totals = days.putIfAbsent(record.day, DayTotals.new);
    totals
      ..ms += record.ms
      ..units += record.units
      ..pages += record.pages
      ..sessions += record.sessions;
  }

  int activeMsOn(String day) => days[day]?.ms ?? 0;
}
