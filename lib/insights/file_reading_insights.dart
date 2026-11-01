import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../reader/reader_position.dart';
import 'book_units.dart';
import 'insights_config.dart';
import 'insights_engine.dart';
import 'log_compaction.dart';
import 'pace_pool.dart';
import 'reading_insights.dart';
import 'reading_log.dart';
import 'reading_timeline.dart';

/// [ReadingInsights] for one book, kept in files under the library folder:
/// `reading_log/<book id>.jsonl` is the event log, `<book id>.stats.json` a
/// summary for the reader's other books, `<book id>.units.json` the counted
/// size of the book, and `settings.json` the hints switch.
///
/// Opening a book reads its log and replays it through the same code that
/// follows the reader live, so nothing but the log has to survive a restart.
/// Problems with the files are reported with `debugPrint` and never thrown at
/// the reader.
class FileReadingInsights extends ChangeNotifier implements ReadingInsights {
  FileReadingInsights._({
    required this.root,
    required this.bookId,
    required this._engine,
    required this._log,
    required this._pool,
    required this._clock,
    required this._hintsEnabled,
  });

  /// Opens the insights of the book [bookId] whose file is at [epubPath].
  ///
  /// [root] is the library folder, the app's support directory by default.
  /// [clock] defaults to `DateTime.now`; tests pass a fake one. [units]
  /// replaces counting the book, for tests.
  static Future<FileReadingInsights> open({
    required String bookId,
    required String epubPath,
    Directory? root,
    DateTime Function()? clock,
    InsightsConfig config = const InsightsConfig(),
    BookUnits? units,
  }) async {
    final library = root ?? await _libraryFolder();
    final now = clock ?? DateTime.now;
    final file = readingLogFile(library, bookId);
    final log = ReadingLog(file, bookId: bookId, clock: now);

    final results = await Future.wait<Object?>([
      units != null
          ? Future.value(units)
          : _countUnits(epubPath, library, bookId),
      log.read().catchError((Object error) {
        debugPrint('Reading log unreadable: $error');
        return const ParsedLog();
      }),
      _readSettings(library),
    ]);
    final bookUnits = results[0] as BookUnits;
    final parsed = results[1] as ParsedLog;
    final hints = results[2] as bool;
    final pool = await loadPool(
      library,
      excludeId: bookId,
      config: config,
      countsCharacters: bookUnits.countsCharacters(config),
    );

    final engine = InsightsEngine(
      units: bookUnits,
      config: config,
      pool: pool.samples,
      hintsEnabled: hints,
    );
    final insights = FileReadingInsights._(
      root: library,
      bookId: bookId,
      engine: engine,
      log: log,
      pool: pool,
      clock: now,
      hintsEnabled: hints,
    );
    engine.replay(parsed.records);
    insights._ingest(OpenRecord(t: insights._ms, tz: insights._tz));
    insights._compactIfNeeded(parsed, file);
    insights._saveStats();
    return insights;
  }

  static Future<Directory> _libraryFolder() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/library');
  }

  static Future<BookUnits> _countUnits(
    String epubPath,
    Directory library,
    String bookId,
  ) async {
    try {
      return await BookUnits.loadCached(
        epubPath,
        cache: File('${library.path}/reading_log/$bookId.units.json'),
        bookId: bookId,
      );
    } on Object catch (error) {
      // Without section sizes there are no estimates, but time and days are
      // still logged.
      debugPrint('Could not count the book for reading insights: $error');
      return BookUnits.empty();
    }
  }

  /// The library folder.
  final Directory root;
  final String bookId;
  final InsightsEngine _engine;
  final ReadingLog _log;
  final PoolData _pool;
  final DateTime Function() _clock;
  final _signals = StreamController<ConfusionSignal>.broadcast();
  bool _hintsEnabled;
  var _closed = false;
  Future<void>? _closing;
  var _eventsSinceSizeCheck = 0;

  int get _ms => _clock().millisecondsSinceEpoch;
  int get _tz => _clock().timeZoneOffset.inMinutes;

  InsightsConfig get _config => _engine.config;
  BookUnits get _units => _engine.units;

  PaceEstimate get _pace => PaceEstimator(_config).estimate(
    own: _engine.timeline.samples,
    pool: _pool.samples,
    defaultUnitsPerMinute: _units.defaultUnitsPerMinute(_config),
  );

  @override
  void recordPosition(ReaderPosition position, NavigationCause cause) =>
      _ingest(PositionRecord.at(_ms, position, cause));

  @override
  void recordHidden() {
    _ingest(BackgroundRecord(t: _ms));
    // The app may be killed while hidden, and this is the one moment the OS
    // gives us to make the log durable.
    unawaited(flush());
  }

  @override
  void recordShown() => _ingest(ForegroundRecord(t: _ms, tz: _tz));

  /// Logs [record] and feeds it to the engine. The log comes first, so a
  /// problem computing never loses the event.
  void _ingest(LogRecord record) {
    if (_closed) return;
    try {
      _log.append(record);
    } on Object catch (error, stackTrace) {
      debugPrint('Could not log $record: $error\n$stackTrace');
    }
    try {
      for (final signal in _engine.add(record)) {
        _signals.add(signal);
      }
    } on Object catch (error, stackTrace) {
      debugPrint('Reading insights failed on $record: $error\n$stackTrace');
    }
    if (++_eventsSinceSizeCheck >= 256) {
      _eventsSinceSizeCheck = 0;
      _compactIfNeeded(const ParsedLog(), _log.file);
    }
    notifyListeners();
  }

  @override
  TimeLeft? timeLeft(ReaderPosition position, {int? chapterEndSection}) {
    final pace = _pace;
    if (!pace.personal || _units.isEmpty) return null;
    final end = chapterEndSection == null
        ? _units.sectionCount
        : chapterEndSection <= position.sectionIndex
        ? position.sectionIndex + 1
        : chapterEndSection;
    Duration time(double units) =>
        Duration(milliseconds: (units * pace.secPerUnit * 1000).round());
    return TimeLeft(
      chapter: time(_units.remaining(position, end)),
      book: time(_units.remaining(position, _units.sectionCount)),
    );
  }

  @override
  InsightsSummary get summary {
    final pace = _pace;
    final today = dayKey(_ms, _tz);
    int activeMs(String day) =>
        _engine.timeline.activeMsOn(day) + (_pool.days[day] ?? 0);
    return InsightsSummary(
      today: Duration(milliseconds: activeMs(today)),
      unitsPerMinute: pace.unitsPerMinute,
      paceSamples: pace.samples,
      paceIsPersonal: pace.personal,
      countsCharacters: _units.countsCharacters(_config),
      streakDays: streakDays(today, activeMs, _config.streakDayMinutes * 60000),
      lastDays: [
        for (final day in lastDayKeys(today, 14))
          DailyReading(
            day: _localMidnight(day),
            activeTime: Duration(milliseconds: activeMs(day)),
          ),
      ],
    );
  }

  static DateTime _localMidnight(String day) {
    final parts = day.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2]);
  }

  @override
  ReaderPosition? get furthest => _engine.furthest;

  @override
  Stream<ConfusionSignal> get signals => _signals.stream;

  @override
  ConfusionSignal? get nudge => _hintsEnabled ? _engine.policy.current : null;

  @override
  void dismissNudge() {
    if (_closed || _engine.policy.current == null) return;
    _engine.policy.dismiss(_ms);
    notifyListeners();
  }

  @override
  void acceptNudge() {
    if (_closed || _engine.policy.current == null) return;
    _engine.policy.accept();
    notifyListeners();
  }

  @override
  bool get hintsEnabled => _hintsEnabled;

  @override
  Future<void> setHintsEnabled(bool enabled) async {
    if (_closed || enabled == _hintsEnabled) return;
    _hintsEnabled = enabled;
    _engine.policy.hintsEnabled = enabled;
    notifyListeners();
    await _writeSettings(root, enabled);
  }

  @override
  Future<void> flush() async {
    try {
      // Both are queued before waiting, so nothing slips in after a close.
      await Future.wait([_log.flush(sync: true), _saveStats()]);
    } on Object catch (error, stackTrace) {
      debugPrint('Could not flush the reading log: $error\n$stackTrace');
    }
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _ingest(CloseRecord(t: _ms));
    // Stop producers before awaiting I/O, including a second close call.
    _closed = true;
    await flush();
    await _signals.close();
    dispose();
  }

  /// Rewrites the log if it has grown past its limits, in the writer's
  /// queue so no append interleaves.
  void _compactIfNeeded(ParsedLog parsed, File file) {
    if (_log.readOnly || parsed.isNewer) return;
    unawaited(
      _log.exclusive(() async {
        try {
          final size = await file.exists() ? await file.length() : 0;
          if (size <= _config.compactBytes &&
              parsed.lineCount <= _config.compactLines) {
            return;
          }
          await compactReadingLog(
            CompactionJob(
              path: file.path,
              bookId: bookId,
              nowMs: _ms,
              tz: _tz,
              units: _units,
              config: _config,
            ),
          );
        } on Object catch (error, stackTrace) {
          debugPrint('Could not compact the reading log: $error\n$stackTrace');
        }
      }),
    );
  }

  /// Writes the summary the reader's other books learn from, behind the
  /// log's writes.
  Future<void> _saveStats() => _log.exclusive(() async {
    try {
      final days = _engine.timeline.days;
      final recent = days.keys.toList()..sort();
      await writeStats(
        statsFile(root, bookId),
        samples: _engine.timeline.samples,
        days: {
          for (final day in recent.reversed.take(_config.keepRawDays))
            day: days[day]!.ms,
        },
        config: _config,
        countsCharacters: _units.countsCharacters(_config),
      );
    } on Object catch (error, stackTrace) {
      debugPrint('Could not save reading stats: $error\n$stackTrace');
    }
  });
}

// Settings are shared by every book, so their writes queue together.
Future<void> _settingsWriting = Future.value();

File _settingsFile(Directory root) =>
    File('${root.path}/reading_log/settings.json');

Future<bool> _readSettings(Directory root) async {
  try {
    final json = jsonDecode(await _settingsFile(root).readAsString());
    if (json is Map && json['hintsEnabled'] is bool) {
      return json['hintsEnabled'] as bool;
    }
  } on Object {
    // Missing or broken: the default is on.
  }
  return true;
}

Future<void> _writeSettings(Directory root, bool hintsEnabled) {
  final write = _settingsWriting.then((_) async {
    try {
      final file = _settingsFile(root);
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({'version': 1, 'hintsEnabled': hintsEnabled}),
        flush: true,
      );
      await temp.rename(file.path);
    } on Object catch (error, stackTrace) {
      debugPrint('Could not save reading settings: $error\n$stackTrace');
    }
  });
  _settingsWriting = write;
  return write;
}
