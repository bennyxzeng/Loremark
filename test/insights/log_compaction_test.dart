import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/insights/insights_config.dart';
import 'package:loremark/insights/insights_engine.dart';
import 'package:loremark/insights/log_compaction.dart';
import 'package:loremark/insights/reading_log.dart';

import 'insights_test_helpers.dart';

void main() {
  late Directory temp;
  late File file;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('loremark_compact_');
    file = readingLogFile(temp, 'book1');
    await file.parent.create(recursive: true);
  });

  tearDown(() => temp.delete(recursive: true));

  /// Ninety days of reading ending at [baseMs]: a session a day of ten pages
  /// of section d mod 4, apart from day 85, when the reader got to
  /// section 6.
  List<LogRecord> ninetyDays() {
    final records = <LogRecord>[];
    for (var d = 89; d >= 0; d--) {
      final script = LogScript(startMs: baseMs - d * 24 * 3600 * 1000)..open();
      script.read(d == 85 ? 6 : d % 4, 0, 10, 30).close();
      records.addAll(script.records);
    }
    return records;
  }

  Future<void> writeLog(List<LogRecord> records, {String extra = ''}) async {
    final text = StringBuffer(
      '${jsonEncode(HeaderRecord(id: 'book1', t: baseMs).toJson())}\n',
    );
    for (final record in records) {
      text.write('${jsonEncode(record.toJson())}\n');
    }
    await file.writeAsString('$text$extra');
  }

  CompactionJob job({InsightsConfig? config, int? nowMs}) => CompactionJob(
    path: file.path,
    bookId: 'book1',
    nowMs: nowMs ?? baseMs,
    tz: 0,
    units: tenSections(),
    config: config ?? const InsightsConfig(compactLines: 100),
  );

  InsightsEngine replayed(Iterable<LogRecord> records) {
    final engine = InsightsEngine(units: tenSections());
    engine.replay(records);
    return engine;
  }

  Map<String, List<int>> totals(InsightsEngine engine) => {
    for (final MapEntry(:key, :value) in engine.timeline.days.entries)
      key: [value.ms, value.units, value.pages, value.sessions],
  };

  test('leaves a small log alone', () async {
    await writeLog(ninetyDays());
    final before = await file.readAsString();

    final changed = compactLogFileSync(job(config: const InsightsConfig()));

    expect(changed, isFalse);
    expect(await file.readAsString(), before);
  });

  test('keeps 60 days raw and summarises the rest', () async {
    await writeLog(ninetyDays());

    expect(compactLogFileSync(job()), isTrue);

    final parsed = parseLog(await file.readAsString());
    final cut = DateTime.utc(2026, 8, 6).millisecondsSinceEpoch;
    final raw = parsed.records.where((r) => r.timeMs != null);
    expect(raw.every((r) => r.timeMs! >= cut), isTrue);
    expect(raw, isNotEmpty);
    final days = parsed.records.whereType<DayRecord>().toList();
    expect(days, hasLength(29));
    expect(days.every((d) => d.day.compareTo('2026-08-06') < 0), isTrue);
    expect(days.first.ms, 300000);
    expect(parsed.headerVersion, 1);
    // The header, the furthest position, 29 day records and 61 days of 12
    // records: today and the 60 before it.
    expect(parsed.lineCount, 1 + 1 + 29 + 61 * 12);
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });

  test('keeps the furthest position and the day totals', () async {
    final records = ninetyDays();
    await writeLog(records);
    final before = replayed(records);
    expect(before.furthest!.sectionIndex, 6);

    compactLogFileSync(job());

    final after = replayed(parseLog(await file.readAsString()).records);
    // Day 85 is before the cut, so only the fur record remembers section 6.
    expect(after.furthest!.sectionIndex, 6);
    expect(after.furthest!.progression, before.furthest!.progression);
    expect(totals(after), totals(before));
  });

  test('compacting again does not double count', () async {
    final records = ninetyDays();
    await writeLog(records);
    final expected = totals(replayed(records));

    compactLogFileSync(job());
    compactLogFileSync(job(config: const InsightsConfig(compactLines: 10)));
    compactLogFileSync(job(config: const InsightsConfig(compactLines: 10)));

    final after = replayed(parseLog(await file.readAsString()).records);
    expect(totals(after), expected);
    final lines = (await file.readAsLines()).where((l) => l.contains('"fur"'));
    expect(lines, hasLength(1));
  });

  test(
    'later compaction as time passes moves more days into summaries',
    () async {
      final records = ninetyDays();
      await writeLog(records);
      final expected = totals(replayed(records));
      compactLogFileSync(job());

      // A month later nothing new was read, so more of it is old.
      compactLogFileSync(job(nowMs: baseMs + 30 * 24 * 3600 * 1000));

      final parsed = parseLog(await file.readAsString());
      expect(parsed.records.whereType<DayRecord>(), hasLength(59));
      expect(totals(replayed(parsed.records)), expected);
    },
  );

  test('drops a torn tail and garbage, which are no longer needed', () async {
    await writeLog(ninetyDays(), extra: 'garbage\n{"k":"pos","t":1,"s"');

    compactLogFileSync(job());

    final parsed = parseLog(await file.readAsString());
    expect(parsed.skippedLines, 0);
  });

  test('a log over the hard cap keeps only 14 days raw', () async {
    await writeLog(ninetyDays());
    const config = InsightsConfig(compactLines: 100, hardCapBytes: 1000);

    compactLogFileSync(job(config: config));

    final parsed = parseLog(await file.readAsString());
    final cut = DateTime.utc(2026, 9, 21).millisecondsSinceEpoch;
    expect(
      parsed.records
          .where((r) => r.timeMs != null)
          .every((r) => r.timeMs! >= cut),
      isTrue,
    );
    expect(parsed.records.whereType<DayRecord>(), hasLength(75));
  });

  test('compacts by size too', () async {
    await writeLog(ninetyDays());

    final changed = compactLogFileSync(
      job(
        config: const InsightsConfig(compactBytes: 100, compactLines: 1000000),
      ),
    );

    expect(changed, isTrue);
  });

  test('never rewrites a log from a newer version', () async {
    const original =
        '{"k":"hdr","v":2,"id":"book1","t":1}\n{"k":"open","t":5}\n';
    await file.writeAsString(original);

    final changed = compactLogFileSync(
      job(config: const InsightsConfig(compactLines: 1)),
    );

    expect(changed, isFalse);
    expect(await file.readAsString(), original);
  });

  test('a missing file is not an error', () {
    expect(compactLogFileSync(job()), isFalse);
  });

  test('runs in an isolate too', () async {
    final records = ninetyDays();
    await writeLog(records);
    final expected = totals(replayed(records));

    expect(await compactReadingLog(job()), isTrue);

    expect(
      totals(replayed(parseLog(await file.readAsString()).records)),
      expected,
    );
  });

  test('appends after a compaction continue the same log', () async {
    await writeLog(ninetyDays());
    final log = ReadingLog(file, bookId: 'book1');

    await log.exclusive(() async => compactLogFileSync(job()));
    log.append(const OpenRecord(t: 1));
    await log.idle;

    final lines = await file.readAsLines();
    expect(lines.where((l) => l.contains('"hdr"')), hasLength(1));
    expect(lines.last, contains('"open"'));
  });
}
