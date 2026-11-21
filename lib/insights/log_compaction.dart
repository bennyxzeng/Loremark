import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'book_units.dart';
import 'insights_config.dart';
import 'reading_log.dart';
import 'reading_timeline.dart';
import 'view_tracker.dart';

/// What compaction needs, as plain data that can cross to an isolate.
class CompactionJob {
  const CompactionJob({
    required this.path,
    required this.bookId,
    required this.nowMs,
    required this.tz,
    required this.units,
    this.config = const InsightsConfig(),
  });

  final String path;
  final String bookId;
  final int nowMs;

  /// Minutes east of UTC, to find the start of the day the cut falls on.
  final int tz;
  final BookUnits units;
  final InsightsConfig config;
}

/// Shrinks the log at `job.path` if it has grown past the limits in the
/// config, off the UI isolate. Returns whether it was rewritten.
///
/// Must run while nothing appends to the file (inside `ReadingLog.exclusive`).
Future<bool> compactReadingLog(CompactionJob job) =>
    Isolate.run(() => compactLogFileSync(job));

/// [compactReadingLog] on the calling isolate.
///
/// Raw events of the last [InsightsConfig.keepRawDays] days stay, so the pace
/// window, revisit windows and sessions are exact. Older events become one
/// `day` record per local day and a single `fur` record for the furthest
/// position. The new file is written beside the old one and renamed over it,
/// so a crash leaves the old log or the new one. If the result is still over
/// the hard cap, only [InsightsConfig.hardCapRawDays] days stay raw.
bool compactLogFileSync(CompactionJob job) {
  final file = File(job.path);
  if (!file.existsSync()) return false;
  final config = job.config;
  final bytes = file.readAsBytesSync();
  final text = utf8.decode(bytes, allowMalformed: true);
  final parsed = parseLog(text);
  if (parsed.isNewer) return false;
  if (bytes.length <= config.compactBytes &&
      parsed.lineCount <= config.compactLines) {
    return false;
  }

  var output = compactRecords(parsed.records, job, config.keepRawDays);
  var encoded = _encode(output, job);
  if (utf8.encode(encoded).length > config.hardCapBytes) {
    output = compactRecords(parsed.records, job, config.hardCapRawDays);
    encoded = _encode(output, job);
  }
  // Intense recent reading can exceed the cap even inside the shorter window.
  // Keep the newest raw tail and fold older events into the same daily totals.
  while (utf8.encode(encoded).length > config.hardCapBytes) {
    final positions = [
      for (var i = 0; i < output.length; i++)
        if (output[i] is PositionRecord) i,
    ];
    if (positions.length <= 1) {
      output = _compactToCheckpoint(output, job);
      encoded = _encode(output, job);
      break; // Only header, summaries and live checkpoint remain.
    }
    output = _compactPrefix(output, positions[positions.length ~/ 2], job);
    encoded = _encode(output, job);
  }
  final temp = File('${job.path}.tmp');
  temp.writeAsStringSync(encoded, flush: true);
  temp.renameSync(job.path);
  return true;
}

/// The irreducible form when even a single raw tail exceeds the byte budget.
List<LogRecord> _compactToCheckpoint(
  List<LogRecord> records,
  CompactionJob job,
) {
  final tracker = ViewTracker(job.units, job.config);
  final timeline = ReadingTimeline(job.config);
  var hidden = false;
  var closed = false;
  var lastMs = job.nowMs;
  PositionRecord? position;
  for (final record in records) {
    if (record is DayRecord) {
      timeline.addDay(record);
    } else {
      tracker.add(record).forEach(timeline.onEvent);
      lastMs = record.timeMs ?? lastMs;
      if (record is PositionRecord) position = record;
      if (record is BackgroundRecord) hidden = true;
      if (record is ForegroundRecord || record is OpenRecord) hidden = false;
      if (record is OpenRecord) closed = false;
      if (record is CloseRecord) closed = true;
    }
  }
  // Settle only time already evidenced by a log record, never wall time now.
  tracker.add(CloseRecord(t: lastMs)).forEach(timeline.onEvent);
  final furthest = tracker.furthest;
  final days = timeline.days.keys.toList()..sort();
  return [
    if (furthest != null)
      FurthestRecord(
        section: furthest.sectionIndex,
        progression: furthest.progression,
        t: lastMs,
      ),
    for (final day in days)
      DayRecord(
        day: day,
        ms: timeline.days[day]!.ms,
        units: timeline.days[day]!.units,
        pages: timeline.days[day]!.pages,
        sessions: timeline.days[day]!.sessions,
      ),
    if (!closed) ...[
      OpenRecord(t: lastMs, tz: tracker.tz),
      if (position != null)
        PositionRecord(
          t: lastMs,
          section: position.section,
          progression: position.progression,
          cause: position.cause,
        ),
      if (hidden) BackgroundRecord(t: lastMs),
    ],
  ];
}

/// Summarises a raw prefix, retaining a position checkpoint to resume the tail.
List<LogRecord> _compactPrefix(
  List<LogRecord> records,
  int keepFrom,
  CompactionJob job,
) {
  final tracker = ViewTracker(job.units, job.config);
  final timeline = ReadingTimeline(job.config);
  for (final record in records.take(keepFrom)) {
    if (record is DayRecord) {
      timeline.addDay(record);
    } else {
      tracker.add(record).forEach(timeline.onEvent);
    }
  }
  final boundary = records[keepFrom] as PositionRecord;
  // Feeding the boundary settles the previous page's dwell and units exactly;
  // the new page is retained below and has not accrued time in the summaries.
  tracker.add(boundary).forEach(timeline.onEvent);
  final view = tracker.current!;
  final session = timeline.sessions[view.sessionId];
  if (session != null && session.activeMs > 0) {
    // The retained tail will count this same session when its first page ends.
    timeline.days[session.day]!.sessions--;
  }
  final furthest = tracker.furthest;
  final days = timeline.days.keys.toList()..sort();
  return [
    if (furthest != null)
      FurthestRecord(
        section: furthest.sectionIndex,
        progression: furthest.progression,
        t: boundary.t,
      ),
    for (final day in days)
      DayRecord(
        day: day,
        ms: timeline.days[day]!.ms,
        units: timeline.days[day]!.units,
        pages: timeline.days[day]!.pages,
        sessions: timeline.days[day]!.sessions,
      ),
    OpenRecord(t: view.sessionStartMs, tz: view.tz),
    ...records
        .skip(keepFrom)
        .where((r) => r is! DayRecord && r is! FurthestRecord),
  ];
}

String _encode(List<LogRecord> records, CompactionJob job) {
  final text = StringBuffer(
    jsonEncode(HeaderRecord(id: job.bookId, t: job.nowMs).toJson()),
  )..write('\n');
  for (final record in records) {
    text
      ..write(jsonEncode(record.toJson()))
      ..write('\n');
  }
  return text.toString();
}

/// The records of a compacted log: summaries of everything before the start
/// of the local day [keepDays] days ago, then the raw events since.
List<LogRecord> compactRecords(
  List<LogRecord> records,
  CompactionJob job,
  int keepDays,
) {
  var cutDay = dayKey(job.nowMs, job.tz);
  for (var i = 0; i < keepDays; i++) {
    cutDay = previousDay(cutDay);
  }
  final cutMs = _startOfDay(cutDay, job.tz);

  final old = <LogRecord>[];
  final kept = <LogRecord>[];
  final summaries = <LogRecord>[];
  for (final record in records) {
    final t = record.timeMs;
    if (t == null) {
      summaries.add(record);
    } else if (t < cutMs) {
      old.add(record);
    } else {
      kept.add(record);
    }
  }

  // Replay what is being dropped through the same code that reads the log, so
  // the totals can't drift from what the app would have shown.
  final tracker = ViewTracker(job.units, job.config);
  final timeline = ReadingTimeline(job.config);
  for (final record in [...summaries, ...old]) {
    if (record is DayRecord) {
      timeline.addDay(record);
    } else {
      tracker.add(record).forEach(timeline.onEvent);
    }
  }
  final days = timeline.days.keys.toList()..sort();
  final furthest = tracker.furthest;
  return [
    if (furthest != null)
      FurthestRecord(
        section: furthest.sectionIndex,
        progression: furthest.progression,
        t: old.isEmpty ? 0 : old.last.timeMs!,
      ),
    for (final day in days)
      if (timeline.days[day]!.ms > 0 ||
          timeline.days[day]!.units > 0 ||
          timeline.days[day]!.sessions > 0)
        DayRecord(
          day: day,
          ms: timeline.days[day]!.ms,
          units: timeline.days[day]!.units,
          pages: timeline.days[day]!.pages,
          sessions: timeline.days[day]!.sessions,
        ),
    ...kept,
  ];
}

/// Epoch milliseconds of local midnight at the start of [day].
int _startOfDay(String day, int tzMinutes) {
  final parts = day.split('-').map(int.parse).toList();
  return DateTime.utc(parts[0], parts[1], parts[2]).millisecondsSinceEpoch -
      tzMinutes * 60000;
}
