import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/insights/reading_insights.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/insights/reading_log.dart';

import 'insights_test_helpers.dart';

void main() {
  late Directory temp;
  late File file;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('loremark_log_');
    file = readingLogFile(temp, 'book1');
  });

  tearDown(() => temp.delete(recursive: true));

  ReadingLog newLog() =>
      ReadingLog(file, bookId: 'book1', clock: FakeClock().call);

  PositionRecord pos(int t, int section, double p) => PositionRecord(
    t: t,
    section: section,
    progression: p,
    cause: NavigationCause.pageForward,
  );

  group('records', () {
    test('round trip through JSON', () {
      final records = <LogRecord>[
        const OpenRecord(t: 1, tz: -420),
        pos(2, 3, 0.4372),
        const BackgroundRecord(t: 3),
        const ForegroundRecord(t: 4, tz: 60),
        const CloseRecord(t: 5),
        const DayRecord(
          day: '2026-09-30',
          ms: 9,
          units: 8,
          pages: 7,
          sessions: 2,
        ),
        const FurthestRecord(section: 4, progression: 0.5, t: 6),
      ];
      for (final record in records) {
        final decoded = LogRecord.fromJson(
          jsonDecode(jsonEncode(record.toJson())),
        );
        expect(decoded.runtimeType, record.runtimeType);
        expect(decoded!.toJson(), record.toJson());
      }
    });

    test(
      'positions retain exact progression without rounding a cutoff upward',
      () {
        final record = PositionRecord.at(
          1,
          const ReaderPosition(2, 0.123456789),
          NavigationCause.swipe,
        );
        expect(record.progression, 0.123456789);
        expect(jsonEncode(record.toJson()), contains('"p":0.123456789'));
      },
    );

    test('unknown kinds and malformed records are ignored', () {
      expect(LogRecord.fromJson({'k': 'zzz', 't': 1}), isNull);
      expect(
        LogRecord.fromJson({'k': 'pos', 't': 1, 's': -1, 'p': 0.5}),
        isNull,
      );
      expect(
        LogRecord.fromJson({'k': 'pos', 't': 1, 's': 1, 'p': 1.5}),
        isNull,
      );
      expect(LogRecord.fromJson({'k': 'pos', 's': 1, 'p': 0.5}), isNull);
      expect(LogRecord.fromJson({'k': 'day', 'd': 'tuesday', 'ms': 1}), isNull);
      expect(LogRecord.fromJson('nope'), isNull);
    });

    test('an unknown cause code reads as a swipe', () {
      final record = LogRecord.fromJson({
        'k': 'pos',
        't': 1,
        's': 0,
        'p': 0.5,
        'c': 'future',
      });
      expect((record! as PositionRecord).cause, NavigationCause.swipe);
    });

    test('rejects a book id that could escape the folder', () {
      expect(() => readingLogFile(temp, '../evil'), throwsArgumentError);
      expect(() => readingLogFile(temp, 'a/b'), throwsArgumentError);
      expect(() => readingLogFile(temp, ''), throwsArgumentError);
    });
  });

  group('parseLog', () {
    test('skips a torn last line', () {
      final good = jsonEncode(pos(1, 0, 0.1).toJson());
      final text =
          '{"k":"hdr","v":1,"id":"b","t":1}\n$good\n{"k":"pos","t":2,"s":0,"p"';

      final parsed = parseLog(text);

      expect(parsed.records, hasLength(1));
      expect(parsed.skippedLines, 1);
      expect(parsed.headerVersion, 1);
    });

    test('skips garbage lines, blank lines and unknown kinds', () {
      final good = jsonEncode(pos(1, 0, 0.1).toJson());
      final text = [
        '{"k":"hdr","v":1,"id":"b","t":1}',
        'not json at all',
        '',
        '{"k":"future","t":9}',
        '[1,2,3]',
        good,
        '\u0000\u0000\u0000',
      ].join('\n');

      final parsed = parseLog(text);

      expect(parsed.records, hasLength(1));
      expect(parsed.skippedLines, 4);
    });

    test('flags a newer version', () {
      expect(parseLog('{"k":"hdr","v":2,"id":"b","t":1}\n').isNewer, isTrue);
      expect(parseLog('{"k":"hdr","v":1,"id":"b","t":1}\n').isNewer, isFalse);
      expect(parseLog('').isNewer, isFalse);
    });

    test('readLogFile reads a missing file as empty', () async {
      final parsed = await readLogFile(file.path);

      expect(parsed.records, isEmpty);
    });
  });

  group('ReadingLog', () {
    test('writes a header, then the records', () async {
      final log = newLog();

      log
        ..append(const OpenRecord(t: 1))
        ..append(pos(2, 0, 0.1));
      await log.idle;

      final lines = await file.readAsLines();
      expect(lines, hasLength(3));
      expect(jsonDecode(lines.first), containsPair('k', 'hdr'));
      expect(jsonDecode(lines.first), containsPair('id', 'book1'));
      expect(jsonDecode(lines.first), containsPair('v', 1));
      expect(jsonDecode(lines[2]), containsPair('k', 'pos'));
    });

    test('appends without a second header on later runs', () async {
      final first = newLog()..append(const OpenRecord(t: 1));
      await first.idle;

      final second = newLog()..append(const CloseRecord(t: 2));
      await second.idle;

      final parsed = parseLog(await file.readAsString());
      expect(parsed.records.map((r) => r.runtimeType), [
        OpenRecord,
        CloseRecord,
      ]);
      expect(
        (await file.readAsLines()).where((l) => l.contains('"hdr"')),
        hasLength(1),
      );
    });

    test('writes records queued together in one write', () async {
      final log = newLog();

      for (var i = 0; i < 50; i++) {
        log.append(pos(i, 0, 0.5));
      }
      await log.idle;

      expect(parseLog(await file.readAsString()).records, hasLength(50));
    });

    test('a torn tail from a crash cannot swallow the next record', () async {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '{"k":"hdr","v":1,"id":"book1","t":1}\n'
        '${jsonEncode(pos(1, 0, 0.1).toJson())}\n'
        '{"k":"pos","t":2,"s":0,"p":0.',
      );

      final log = newLog()..append(pos(3, 1, 0.2));
      await log.idle;

      final parsed = parseLog(await file.readAsString());
      expect(parsed.records, hasLength(2));
      expect((parsed.records.last as PositionRecord).t, 3);
      expect(parsed.skippedLines, 1);
    });

    test('no extra blank line when the file ends cleanly', () async {
      final first = newLog()..append(const OpenRecord(t: 1));
      await first.idle;
      final second = newLog()..append(const CloseRecord(t: 2));
      await second.idle;

      expect(await file.readAsString(), isNot(contains('\n\n')));
    });

    test('a log from a newer version is read but never written', () async {
      await file.parent.create(recursive: true);
      const original =
          '{"k":"hdr","v":2,"id":"book1","t":1}\n{"k":"open","t":5,"tz":0}\n';
      await file.writeAsString(original);

      final log = newLog()..append(const CloseRecord(t: 9));
      await log.idle;

      expect(log.readOnly, isTrue);
      expect(await file.readAsString(), original);
      final parsed = await log.read();
      expect(parsed.isNewer, isTrue);
      expect(parsed.records, hasLength(1));
    });

    test('sync flush completes and keeps the data', () async {
      final log = newLog()..append(const OpenRecord(t: 1));

      await log.flush(sync: true);

      expect(parseLog(await file.readAsString()).records, hasLength(1));
      expect(log.lastError, isNull);
    });

    test('sync flush on a log that was never written is harmless', () async {
      await newLog().flush(sync: true);

      expect(await file.exists(), isFalse);
    });

    test(
      'exclusive work runs after earlier appends and holds back later ones',
      () async {
        final log = newLog();
        int? linesSeen;

        log.append(const OpenRecord(t: 1));
        final result = log.exclusive(() async {
          linesSeen = (await file.readAsLines()).length;
          // An append made during the operation waits for it to finish.
          log.append(const CloseRecord(t: 2));
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return (await file.readAsLines()).length;
        });
        // The header and the open record, then nothing more until it ends.
        expect(await result, 2);
        expect(linesSeen, 2);
        await log.idle;
        expect(parseLog(await file.readAsString()).records, hasLength(2));
      },
    );

    test('a failing exclusive operation does not block the queue', () async {
      final log = newLog();

      final failing = log.exclusive<void>(() async => throw StateError('x'));
      await expectLater(failing, throwsStateError);
      log.append(const OpenRecord(t: 1));
      await log.idle;

      expect(parseLog(await file.readAsString()).records, hasLength(1));
    });

    test('a write that fails is reported, not thrown', () async {
      // The log folder's parent is a file, so it can never be created.
      final blocker = File('${temp.path}/blocker');
      await blocker.writeAsString('x');
      final log = ReadingLog(
        File('${blocker.path}/reading_log/book1.jsonl'),
        bookId: 'book1',
      );

      log.append(const OpenRecord(t: 1));
      await log.idle;

      expect(log.lastError, isNotNull);

      // Later records are still attempted.
      log.append(const OpenRecord(t: 2));
      await log.idle;
    });
  });
}
