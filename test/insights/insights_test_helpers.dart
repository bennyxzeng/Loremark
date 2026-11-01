import 'package:loremark/insights/book_units.dart';
import 'package:loremark/insights/reading_insights.dart';
import 'package:loremark/insights/reading_log.dart';

/// 2026-10-05 12:00:00 UTC, a Monday.
final baseMs = DateTime.utc(2026, 10, 5, 12).millisecondsSinceEpoch;

/// A clock tests move by hand.
class FakeClock {
  FakeClock([DateTime? start]) : _now = start ?? DateTime.utc(2026, 10, 5, 12);

  DateTime _now;

  DateTime call() => _now;

  void advance(Duration by) => _now = _now.add(by);

  void advanceSeconds(num seconds) =>
      advance(Duration(milliseconds: (seconds * 1000).round()));
}

/// Ten sections of 2000 units. At ten pages a section, a page is 200 units.
BookUnits tenSections({int perSection = 2000, List<bool>? linear}) => BookUnits(
  counts: List.filled(10, perSection),
  linear: linear ?? List.filled(10, true),
);

/// Builds a log record by record on a timeline.
///
/// A page `n` of a section is at progression `n / 10`, so with
/// [tenSections] each page is 200 units.
class LogScript {
  LogScript({int? startMs, this.tz = 0}) : t = startMs ?? baseMs;

  int t;
  final int tz;
  final records = <LogRecord>[];

  LogScript wait(num seconds) {
    t += (seconds * 1000).round();
    return this;
  }

  LogScript open() {
    records.add(OpenRecord(t: t, tz: tz));
    return this;
  }

  LogScript close() {
    records.add(CloseRecord(t: t));
    return this;
  }

  LogScript bg() {
    records.add(BackgroundRecord(t: t));
    return this;
  }

  LogScript fg() {
    records.add(ForegroundRecord(t: t, tz: tz));
    return this;
  }

  LogScript pos(
    int section,
    double progression, [
    NavigationCause cause = NavigationCause.pageForward,
  ]) {
    records.add(
      PositionRecord(
        t: t,
        section: section,
        progression: progression,
        cause: cause,
      ),
    );
    return this;
  }

  /// Shows page [page] of [section] and stays [dwell] seconds.
  LogScript page(
    int section,
    int page,
    num dwell, [
    NavigationCause cause = NavigationCause.pageForward,
  ]) {
    pos(section, page / 10, cause);
    return wait(dwell);
  }

  /// Reads pages [from] to [to] (exclusive) of [section], [dwell] seconds
  /// each.
  LogScript read(int section, int from, int to, num dwell) {
    for (var p = from; p < to; p++) {
      page(section, p, dwell);
    }
    return this;
  }
}
