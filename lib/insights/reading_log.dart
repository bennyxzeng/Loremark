import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../reader/reader_position.dart';
import 'reading_insights.dart';

/// The log format this code writes and fully understands. A log whose header
/// says otherwise is read but never written, so an older app can't damage a
/// file a newer one made.
const readingLogVersion = 1;

final _validId = RegExp(r'^[A-Za-z0-9_-]+$');

/// The log file for [bookId] under the library folder [root]:
/// `reading_log/<book id>.jsonl`.
///
/// Book ids are SHA-256 hashes, but a path separator or `..` must never reach
/// the file system.
File readingLogFile(Directory root, String bookId) {
  if (!_validId.hasMatch(bookId)) {
    throw ArgumentError.value(bookId, 'bookId', 'Not a valid book id');
  }
  return File('${root.path}/reading_log/$bookId.jsonl');
}

/// One line of a reading log.
///
/// The log is append-only JSON lines, a record per line, with integer epoch
/// milliseconds in UTC. It holds positions and lifecycle events only, never
/// any text of the book.
sealed class LogRecord {
  const LogRecord();

  Map<String, Object?> toJson();

  /// When this happened, or null for records that summarise a period.
  int? get timeMs;

  /// Reads one decoded line, or returns null for an unknown kind or a record
  /// whose fields are wrong, so a damaged line never stops the rest.
  static LogRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    try {
      return switch (json['k']) {
        'hdr' => HeaderRecord(
          version: json['v'] as int,
          id: json['id'] as String? ?? '',
          t: json['t'] as int? ?? 0,
        ),
        'open' => OpenRecord(t: json['t'] as int, tz: json['tz'] as int? ?? 0),
        'pos' => _position(json),
        'bg' => BackgroundRecord(t: json['t'] as int),
        'fg' => ForegroundRecord(
          t: json['t'] as int,
          tz: json['tz'] as int? ?? 0,
        ),
        'close' => CloseRecord(t: json['t'] as int),
        'day' => DayRecord(
          day: _dayKey(json['d']),
          ms: json['ms'] as int,
          units: json['u'] as int? ?? 0,
          pages: json['pg'] as int? ?? 0,
          sessions: json['ses'] as int? ?? 0,
        ),
        'fur' => _furthest(json),
        _ => null,
      };
    } on Object {
      return null;
    }
  }

  static PositionRecord? _position(Map json) {
    final section = json['s'] as int;
    final progression = (json['p'] as num).toDouble();
    if (section < 0 || !(progression >= 0 && progression <= 1)) return null;
    return PositionRecord(
      t: json['t'] as int,
      section: section,
      progression: progression,
      // An unknown code from a newer version is a move we can't explain.
      cause:
          NavigationCause.fromCode(json['c'] as String? ?? '') ??
          NavigationCause.swipe,
    );
  }

  static FurthestRecord? _furthest(Map json) {
    final section = json['s'] as int;
    final progression = (json['p'] as num).toDouble();
    if (section < 0 || !(progression >= 0 && progression <= 1)) return null;
    return FurthestRecord(
      section: section,
      progression: progression,
      t: json['t'] as int? ?? 0,
    );
  }

  static String _dayKey(Object? value) {
    if (value is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return value;
    }
    throw FormatException('Not a day: $value');
  }
}

class HeaderRecord extends LogRecord {
  const HeaderRecord({
    this.version = readingLogVersion,
    required this.id,
    required this.t,
  });

  final int version;
  final String id;
  final int t;

  @override
  int? get timeMs => t;

  @override
  Map<String, Object?> toJson() => {'k': 'hdr', 'v': version, 'id': id, 't': t};
}

/// The reader screen for the book opened. [tz] is the offset from UTC in
/// minutes, which decides what local day later events fall on.
class OpenRecord extends LogRecord {
  const OpenRecord({required this.t, this.tz = 0});

  final int t;
  final int tz;

  @override
  int? get timeMs => t;

  @override
  Map<String, Object?> toJson() => {'k': 'open', 't': t, 'tz': tz};
}

/// The reader moved to a position: where the page that is now showing starts.
class PositionRecord extends LogRecord {
  const PositionRecord({
    required this.t,
    required this.section,
    required this.progression,
    required this.cause,
  });

  /// A position as the log stores it: progression to four decimals, which is
  /// finer than a unit in any section. Live code and replay both go through
  /// this, so they can't disagree on rounding.
  factory PositionRecord.at(
    int t,
    ReaderPosition position,
    NavigationCause cause,
  ) => PositionRecord(
    t: t,
    section: position.sectionIndex,
    progression: (position.progression.clamp(0.0, 1.0) * 10000).round() / 10000,
    cause: cause,
  );

  final int t;
  final int section;
  final double progression;
  final NavigationCause cause;

  @override
  int? get timeMs => t;

  @override
  Map<String, Object?> toJson() => {
    'k': 'pos',
    't': t,
    's': section,
    'p': progression,
    'c': cause.code,
  };
}

class BackgroundRecord extends LogRecord {
  const BackgroundRecord({required this.t});

  final int t;

  @override
  int? get timeMs => t;

  @override
  Map<String, Object?> toJson() => {'k': 'bg', 't': t};
}

class ForegroundRecord extends LogRecord {
  const ForegroundRecord({required this.t, this.tz = 0});

  final int t;
  final int tz;

  @override
  int? get timeMs => t;

  @override
  Map<String, Object?> toJson() => {'k': 'fg', 't': t, 'tz': tz};
}

/// The reader screen closed normally. A crash leaves no such record.
class CloseRecord extends LogRecord {
  const CloseRecord({required this.t});

  final int t;

  @override
  int? get timeMs => t;

  @override
  Map<String, Object?> toJson() => {'k': 'close', 't': t};
}

/// What compaction leaves of a day whose raw events were dropped.
class DayRecord extends LogRecord {
  const DayRecord({
    required this.day,
    required this.ms,
    this.units = 0,
    this.pages = 0,
    this.sessions = 0,
  });

  /// Local calendar day, `2026-09-30`.
  final String day;

  /// Active reading time.
  final int ms;
  final int units;
  final int pages;
  final int sessions;

  @override
  int? get timeMs => null;

  @override
  Map<String, Object?> toJson() => {
    'k': 'day',
    'd': day,
    'ms': ms,
    'u': units,
    'pg': pages,
    'ses': sessions,
  };
}

/// The furthest position, kept through compaction so it survives the raw
/// events that showed it.
class FurthestRecord extends LogRecord {
  const FurthestRecord({
    required this.section,
    required this.progression,
    required this.t,
  });

  final int section;
  final double progression;
  final int t;

  @override
  int? get timeMs => null;

  @override
  Map<String, Object?> toJson() => {
    'k': 'fur',
    's': section,
    'p': progression,
    't': t,
  };
}

/// What a log file held.
class ParsedLog {
  const ParsedLog({
    this.records = const [],
    this.headerVersion,
    this.skippedLines = 0,
    this.lineCount = 0,
  });

  /// Every understood record except the header, in file order.
  final List<LogRecord> records;

  /// The `v` of the first header, or null if there was none.
  final int? headerVersion;

  /// Lines that were damaged, such as a torn last line, or of unknown kind.
  final int skippedLines;
  final int lineCount;

  /// True if a newer version of the app wrote this log.
  bool get isNewer => (headerVersion ?? 0) > readingLogVersion;
}

/// Reads a log.
///
/// Tolerates what a crash or a newer app leaves: a truncated last line, lines
/// of garbage and records of unknown kind are skipped, never fatal. A
/// truncated JSON object can't parse, since its closing brace is missing, so
/// no checksum is needed.
ParsedLog parseLog(String text) {
  final records = <LogRecord>[];
  int? headerVersion;
  var skipped = 0;
  var lines = 0;
  for (final line in const LineSplitter().convert(text)) {
    if (line.trim().isEmpty) continue;
    lines++;
    Object? json;
    try {
      json = jsonDecode(line);
    } on FormatException {
      skipped++;
      continue;
    }
    final record = LogRecord.fromJson(json);
    if (record == null) {
      skipped++;
    } else if (record is HeaderRecord) {
      headerVersion ??= record.version;
    } else {
      records.add(record);
    }
  }
  return ParsedLog(
    records: records,
    headerVersion: headerVersion,
    skippedLines: skipped,
    lineCount: lines,
  );
}

/// [parseLog] for the file at [path], off the UI isolate. A missing or
/// unreadable file reads as an empty log.
Future<ParsedLog> readLogFile(String path) => Isolate.run(() {
  try {
    final bytes = File(path).readAsBytesSync();
    return parseLog(utf8.decode(bytes, allowMalformed: true));
  } on FileSystemException {
    return const ParsedLog();
  }
});

/// One book's log file, with a single serialized writer.
///
/// Every record is appended as soon as it is handed over, because pages turn
/// every few seconds and buffering would lose reading time when the app is
/// killed. What is queued in the same turn goes out in one write, so the two
/// positions of a section turn land together. `FileMode.append` writes at the
/// end of file even if the process dies right after, so only an operating
/// system crash can lose a record that was handed to [append]; [flush] with
/// `sync` also forces it to storage, for when the app is hidden or closed.
///
/// Problems writing are reported with `debugPrint` and never thrown: logging
/// must not break reading.
class ReadingLog {
  ReadingLog(this.file, {required this.bookId, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final File file;
  final String bookId;
  final DateTime Function() _clock;

  final _pending = <LogRecord>[];
  var _scheduled = false;
  Future<void> _writing = Future.value();
  var _prepared = false;
  var _readOnly = false;

  /// The last write failure, for tests.
  Object? lastError;

  /// True once the log is known to come from a newer version. Nothing is
  /// written to it.
  bool get readOnly => _readOnly;

  /// Completes once every record handed over so far is written.
  Future<void> get idle => _writing;

  /// Queues [record] to be appended.
  void append(LogRecord record) {
    _pending.add(record);
    if (_scheduled) return;
    _scheduled = true;
    _writing = _writing.then((_) => _drain());
  }

  /// Completes when everything handed over so far is written, and, with
  /// [sync], forced to storage (`fsync`).
  Future<void> flush({bool sync = false}) {
    if (sync) _writing = _writing.then((_) => _sync());
    return _writing;
  }

  /// Runs [operation] after every write queued so far, and before any later
  /// one, so it never sees or interleaves with an append. Used to rewrite the
  /// file.
  Future<T> exclusive<T>(Future<T> Function() operation) {
    final result = _writing.then((_) => operation());
    _writing = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// What the log holds, after waiting for the writes so far.
  Future<ParsedLog> read() async {
    await _writing;
    return readLogFile(file.path);
  }

  Future<void> _drain() async {
    _scheduled = false;
    if (_pending.isEmpty) return;
    final batch = List.of(_pending);
    _pending.clear();
    try {
      await file.parent.create(recursive: true);
      final prefix = _prepared ? '' : await _prepare();
      if (_readOnly) return;
      final text = StringBuffer(prefix);
      for (final record in batch) {
        text
          ..write(jsonEncode(record.toJson()))
          ..write('\n');
      }
      await file.writeAsString(text.toString(), mode: FileMode.append);
    } on Object catch (error, stackTrace) {
      lastError = error;
      debugPrint('Reading log write failed: $error\n$stackTrace');
    }
  }

  /// What to write before the first record of this run: a header for a new
  /// file, a newline if the last write was cut off mid-line (so the next
  /// record can't glue onto the torn fragment), and a read-only mark for a
  /// newer log.
  Future<String> _prepare() async {
    var prefix = '';
    if (!await file.exists()) {
      prefix = _header();
    } else {
      final access = await file.open();
      try {
        final length = await access.length();
        if (length == 0) {
          prefix = _header();
        } else {
          final head = utf8.decode(
            await access.read(length < 1024 ? length : 1024),
            allowMalformed: true,
          );
          final first = LogRecord.fromJson(_tryDecode(head.split('\n').first));
          if (first is HeaderRecord && first.version > readingLogVersion) {
            _readOnly = true;
          }
          await access.setPosition(length - 1);
          if (await access.readByte() != 0x0A) prefix = '\n';
        }
      } finally {
        await access.close();
      }
    }
    _prepared = true;
    return prefix;
  }

  String _header() =>
      '${jsonEncode(HeaderRecord(id: bookId, t: _clock().millisecondsSinceEpoch).toJson())}\n';

  Object? _tryDecode(String line) {
    try {
      return jsonDecode(line);
    } on FormatException {
      return null;
    }
  }

  Future<void> _sync() async {
    try {
      if (_readOnly || !await file.exists()) return;
      // Appending is allowed on every platform and doesn't touch the data;
      // flushing the handle is an fsync on Android and Linux.
      final access = await file.open(mode: FileMode.append);
      try {
        await access.flush();
      } finally {
        await access.close();
      }
    } on Object catch (error, stackTrace) {
      lastError = error;
      debugPrint('Reading log sync failed: $error\n$stackTrace');
    }
  }
}
