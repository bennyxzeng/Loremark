import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/insights/book_units.dart';
import 'package:loremark/insights/confusion_detector.dart';
import 'package:loremark/insights/file_reading_insights.dart';
import 'package:loremark/insights/insights_config.dart';
import 'package:loremark/insights/insights_engine.dart';
import 'package:loremark/insights/pace_pool.dart';
import 'package:loremark/insights/reading_insights.dart';
import 'package:loremark/insights/reading_log.dart';
import 'package:loremark/insights/reading_timeline.dart';
import 'package:loremark/reader/reader_position.dart';

import '../library/test_epub.dart';
import 'insights_test_helpers.dart';

/// A chapter of exactly [pages] pages of 200 words.
String chapterBody(int pages) => [
  for (var p = 0; p < pages; p++)
    '<p>${List.generate(200, (i) => 'word$i').join(' ')}</p>',
].join();

void main() {
  late Directory temp;
  late Directory root;
  late String epubPath;
  late FakeClock clock;
  late DebugPrintCallback originalDebugPrint;

  setUp(() async {
    originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {};
    temp = await Directory.systemTemp.createTemp('loremark_insights_');
    root = Directory('${temp.path}/library');
    // Ten chapters of ten pages; chapter 9 is a footnote page.
    final epub = File('${temp.path}/book.epub');
    await epub.writeAsBytes(
      buildEpub(
        chapters: [
          for (var i = 0; i < 10; i++)
            EpubChapter(
              id: 'c$i',
              fileName: 'c$i.xhtml',
              body: chapterBody(10),
              linear: i != 9,
            ),
        ],
      ),
    );
    epubPath = epub.path;
    clock = FakeClock();
  });

  tearDown(() async {
    debugPrint = originalDebugPrint;
    await temp.delete(recursive: true);
  });

  Future<FileReadingInsights> open({
    String id = 'book1',
    InsightsConfig config = const InsightsConfig(),
    String? path,
  }) => FileReadingInsights.open(
    bookId: id,
    epubPath: path ?? epubPath,
    root: root,
    clock: clock.call,
    config: config,
  );

  /// Shows page [page] of [section], then lets [dwell] seconds pass.
  void page(
    ReadingInsights insights,
    int section,
    int page,
    num dwell, [
    NavigationCause cause = NavigationCause.pageForward,
  ]) {
    insights.recordPosition(ReaderPosition(section, page / 10), cause);
    clock.advanceSeconds(dwell);
  }

  void read(
    ReadingInsights insights,
    int section,
    int from,
    int to,
    num dwell,
  ) {
    for (var p = from; p < to; p++) {
      page(insights, section, p, dwell);
    }
  }

  Future<List<LogRecord>> logOf(String id) async =>
      (await readLogFile(readingLogFile(root, id).path)).records;

  test(
    'concurrent close is idempotent and ignores late position events',
    () async {
      final insights = await open();
      page(insights, 0, 0, 20);
      final first = insights.close();
      final second = insights.close();
      insights.recordPosition(
        const ReaderPosition(0, 0.5),
        NavigationCause.swipe,
      );
      await Future.wait([first, second]);
      final records = await logOf('book1');
      expect(records.whereType<CloseRecord>(), hasLength(1));
      expect(records.whereType<PositionRecord>(), hasLength(1));
    },
  );

  group('opening', () {
    test('writes a header and an open record', () async {
      final insights = await open();
      await insights.flush();

      final lines = await readingLogFile(root, 'book1').readAsLines();
      expect(jsonDecode(lines.first), containsPair('k', 'hdr'));
      expect(jsonDecode(lines[1]), containsPair('k', 'open'));
      expect(insights.furthest, isNull);
      expect(insights.summary.today, Duration.zero);
      expect(insights.hintsEnabled, isTrue);
      expect(insights.nudge, isNull);
      await insights.close();
    });

    test('refuses a book id that could escape the folder', () async {
      await expectLater(open(id: '../x'), throwsArgumentError);
    });

    test('works for a book that cannot be read, with no estimates', () async {
      final insights = await open(path: '${temp.path}/missing.epub');

      read(insights, 0, 0, 12, 20);
      await insights.flush();

      expect(insights.timeLeft(const ReaderPosition(0, 0.5)), isNull);
      expect(insights.summary.today, greaterThan(Duration.zero));
      expect(insights.furthest, isNotNull);
      await insights.close();
    });

    test('works when the library folder cannot be written', () async {
      final blocker = File('${temp.path}/blocker')..writeAsStringSync('x');
      final insights = await FileReadingInsights.open(
        bookId: 'book1',
        epubPath: epubPath,
        root: Directory('${blocker.path}/library'),
        clock: clock.call,
      );

      read(insights, 0, 0, 8, 20);
      insights.recordHidden();
      insights.recordShown();
      await insights.flush();
      await insights.close();

      expect(insights.furthest, const ReaderPosition(0, 0.7));
    });

    test('ignores damaged lines in an old log', () async {
      final file = readingLogFile(root, 'book1');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '{"k":"hdr","v":1,"id":"book1","t":1}\n'
        'garbage\n'
        '{"k":"pos","t":${baseMs - 600000},"s":3,"p":0.5,"c":"pf"}\n'
        '{"k":"pos","t":${baseMs - 590000},"s":3,"p":0.6',
      );

      final insights = await open();

      expect(insights.furthest, const ReaderPosition(3, 0.5));
      page(insights, 3, 6, 30);
      await insights.close();
      // The torn line did not swallow what came after it.
      final records = await logOf('book1');
      expect(records.whereType<PositionRecord>().last.progression, 0.6);
    });

    test('a log from a newer version is read but not written', () async {
      final file = readingLogFile(root, 'book1');
      await file.parent.create(recursive: true);
      final original =
          '{"k":"hdr","v":9,"id":"book1","t":1}\n'
          '{"k":"pos","t":${baseMs - 1000},"s":4,"p":0.2,"c":"pf"}\n';
      await file.writeAsString(original);

      final insights = await open();
      read(insights, 4, 3, 6, 20);
      await insights.close();

      expect(insights.furthest!.sectionIndex, 4);
      expect(await file.readAsString(), original);
    });
  });

  group('pace and time left', () {
    test('shows no minutes until the pace is known', () async {
      final insights = await open();

      read(insights, 0, 0, 5, 20);

      expect(insights.summary.paceIsPersonal, isFalse);
      expect(insights.summary.unitsPerMinute, 230);
      expect(insights.timeLeft(const ReaderPosition(0, 0.5)), isNull);
      await insights.close();
    });

    test('shows minutes at the reader\'s own pace after six pages', () async {
      final insights = await open();

      // 200 words every 40 seconds is 300 a minute.
      read(insights, 0, 0, 9, 40);

      final summary = insights.summary;
      expect(summary.paceIsPersonal, isTrue);
      expect(summary.paceSamples, greaterThanOrEqualTo(6));
      expect(summary.unitsPerMinute, closeTo(290, 25));

      final left = insights.timeLeft(
        const ReaderPosition(0, 0.5),
        chapterEndSection: 1,
      )!;
      // Half a chapter of 2000 words at about 300 a minute.
      expect(left.chapter.inSeconds, closeTo(1000 / 290 * 60, 25));
      // The book: that plus eight more chapters, the footnote page excluded.
      expect(left.book.inSeconds, closeTo((1000 + 8 * 2000) / 290 * 60, 600));
      expect(left.book, greaterThan(left.chapter));
      await insights.close();
    });

    test('a reader with long pages gets minutes too', () async {
      final insights = await FileReadingInsights.open(
        bookId: 'book1',
        epubPath: epubPath,
        root: root,
        clock: clock.call,
        // A tablet with small type: 350 words a page.
        units: BookUnits(
          counts: List.filled(10, 14000),
          linear: List.filled(10, true),
        ),
      );

      for (var i = 0; i < 22; i++) {
        insights.recordPosition(
          ReaderPosition(0, i / 40),
          NavigationCause.swipe,
        );
        clock.advanceSeconds(60);
      }

      final summary = insights.summary;
      expect(summary.paceIsPersonal, isTrue);
      // 350 words a minute, pulled a little towards the default.
      expect(summary.unitsPerMinute, inInclusiveRange(300, 350));
      expect(insights.timeLeft(const ReaderPosition(0, 0.5)), isNotNull);
      await insights.close();
    });

    test('the chapter runs to the next chapter\'s section', () async {
      final insights = await open();
      read(insights, 0, 0, 9, 40);

      final shortChapter = insights.timeLeft(
        const ReaderPosition(2, 0),
        chapterEndSection: 3,
      )!;
      final longChapter = insights.timeLeft(
        const ReaderPosition(2, 0),
        chapterEndSection: 5,
      )!;
      final lastChapter = insights.timeLeft(const ReaderPosition(2, 0))!;

      expect(
        longChapter.chapter.inSeconds / shortChapter.chapter.inSeconds,
        closeTo(3, 0.01),
      );
      expect(lastChapter.chapter, lastChapter.book);
      // A chapter that ends at or before the reader's section is the rest of
      // that section.
      final odd = insights.timeLeft(
        const ReaderPosition(2, 0.5),
        chapterEndSection: 1,
      )!;
      expect(
        odd.chapter.inSeconds / shortChapter.chapter.inSeconds,
        closeTo(0.5, 0.01),
      );
      await insights.close();
    });

    test('counts only linear items in the time left in the book', () async {
      final insights = await open();
      read(insights, 0, 0, 9, 40);

      final fromEight = insights.timeLeft(const ReaderPosition(8, 0))!;

      // Section 9 is a footnote page: only section 8 is left.
      final whole = insights.timeLeft(
        const ReaderPosition(8, 0),
        chapterEndSection: 9,
      )!;
      expect(fromEight.book, whole.chapter);
      await insights.close();
    });

    test(
      'a new book starts with the reader\'s pace from other books',
      () async {
        await writeStats(
          statsFile(root, 'older'),
          samples: [
            for (var i = 0; i < 30; i++) PaceSample(t: i, units: 200, sec: 20),
          ],
          days: {dayKey(baseMs, 0): 10 * 60000, '2026-10-04': 10 * 60000},
        );

        final insights = await open();

        // 600 units a minute from the other book: at the clamp.
        expect(insights.summary.paceIsPersonal, isTrue);
        expect(insights.summary.unitsPerMinute, closeTo(600, 1));
        expect(insights.timeLeft(const ReaderPosition(0, 0)), isNotNull);
        // The other book's reading counts for today and the streak.
        expect(insights.summary.today, const Duration(minutes: 10));
        expect(insights.summary.streakDays, 2);
        await insights.close();
      },
    );
  });

  group('days and streak', () {
    test('adds up today across the pages read', () async {
      final insights = await open();

      read(insights, 0, 0, 10, 30);
      page(insights, 1, 0, 30);

      final summary = insights.summary;
      expect(summary.today, const Duration(minutes: 5));
      expect(summary.lastDays, hasLength(14));
      expect(summary.lastDays.last.activeTime, const Duration(minutes: 5));
      expect(summary.lastDays.last.day, DateTime(2026, 10, 5));
      expect(summary.lastDays.first.day, DateTime(2026, 9, 22));
      expect(summary.lastDays[12].activeTime, Duration.zero);
      expect(summary.streakDays, 1);
      await insights.close();
    });

    test('keeps a streak from yesterday while today is short', () async {
      final yesterday = FakeClock(DateTime.utc(2026, 10, 4, 20));
      final first = await FileReadingInsights.open(
        bookId: 'book1',
        epubPath: epubPath,
        root: root,
        clock: yesterday.call,
      );
      for (var p = 0; p < 12; p++) {
        first.recordPosition(
          ReaderPosition(0, (p % 10) / 10),
          NavigationCause.pageForward,
        );
        yesterday.advanceSeconds(30);
      }
      await first.close();

      final insights = await open();
      read(insights, 1, 0, 3, 20);

      // The page still showing is not counted yet.
      expect(insights.summary.today, const Duration(seconds: 40));
      expect(insights.summary.streakDays, 1);
      await insights.close();
    });
  });

  group('signals and nudges', () {
    /// Reads two chapters at a steady pace, then looks back at one page
    /// twice.
    void rereadScript(ReadingInsights insights) {
      read(insights, 0, 0, 10, 30);
      read(insights, 1, 0, 4, 30);
      for (var i = 0; i < 2; i++) {
        page(insights, 1, 2, 20, NavigationCause.pageBackward);
        page(insights, 1, 3, 20);
      }
      page(insights, 1, 4, 20);
    }

    test('announces a reread and offers a nudge', () async {
      final insights = await open();
      final signals = <ConfusionSignal>[];
      insights.signals.listen(signals.add);
      var notified = 0;
      insights.addListener(() => notified++);

      rereadScript(insights);
      await Future<void>.delayed(Duration.zero);

      expect(signals.map((s) => s.kind), [ConfusionKind.reread]);
      expect(insights.nudge, same(signals.single));
      expect(notified, greaterThan(0));
      await insights.close();
    });

    test('dismissing hides the nudge and tells listeners', () async {
      final insights = await open();
      rereadScript(insights);
      var notified = 0;
      insights.addListener(() => notified++);

      insights.dismissNudge();

      expect(insights.nudge, isNull);
      expect(notified, 1);
      insights.dismissNudge();
      expect(notified, 1);
      await insights.close();
    });

    test('hints off: signals still come, the nudge does not', () async {
      final insights = await open();
      await insights.setHintsEnabled(false);
      final signals = <ConfusionSignal>[];
      insights.signals.listen(signals.add);

      rereadScript(insights);
      await Future<void>.delayed(Duration.zero);

      expect(signals, hasLength(1));
      expect(insights.nudge, isNull);
      expect(insights.hintsEnabled, isFalse);
      await insights.close();
    });

    test('the hints setting survives a restart', () async {
      final first = await open();
      await first.setHintsEnabled(false);
      await first.close();

      final second = await open();
      expect(second.hintsEnabled, isFalse);
      await second.setHintsEnabled(true);
      await second.close();

      final third = await open(id: 'another');
      expect(third.hintsEnabled, isTrue);
      await third.close();
    });

    test('live signals are those of replaying the log from disk', () async {
      final insights = await open();
      final live = <ConfusionSignal>[];
      insights.signals.listen(live.add);
      rereadScript(insights);
      read(insights, 2, 0, 5, 30);
      insights.recordHidden();
      clock.advanceSeconds(600);
      insights.recordShown();
      page(insights, 2, 5, 30);
      await insights.close();
      expect(live, isNotEmpty);

      final parsed = await readLogFile(readingLogFile(root, 'book1').path);
      final units = await BookUnits.load(epubPath);
      final detector = ConfusionDetector(units: units);
      final replayed = [
        for (final record in parsed.records) ...detector.process(record),
      ];

      String describe(ConfusionSignal s) =>
          '${s.kind} ${s.at.millisecondsSinceEpoch} ${s.start} ${s.end} '
          '${s.reason}';
      expect(replayed.map(describe), live.map(describe));
    });
  });

  group('lifecycle and restart', () {
    test('hidden writes a background record and makes it durable', () async {
      final insights = await open();
      page(insights, 0, 0, 30);

      insights.recordHidden();
      await insights.flush();
      clock.advanceSeconds(60);
      insights.recordShown();
      await insights.close();

      final records = await logOf('book1');
      expect(records.map((r) => r.runtimeType), [
        OpenRecord,
        PositionRecord,
        BackgroundRecord,
        ForegroundRecord,
        CloseRecord,
      ]);
    });

    test('everything survives a restart', () async {
      final first = await open();
      read(first, 0, 0, 10, 40);
      read(first, 1, 0, 5, 40);
      await first.close();
      final summary = first.summary;
      final furthest = first.furthest;

      final second = await open();

      expect(second.furthest, furthest);
      expect(second.summary.today, summary.today);
      expect(second.summary.paceSamples, summary.paceSamples);
      expect(second.summary.unitsPerMinute, summary.unitsPerMinute);
      expect(second.summary.streakDays, summary.streakDays);
      await second.close();
    });

    test('a crash is credited one dwell and the book carries on', () async {
      final first = await open();
      read(first, 0, 0, 4, 30);
      // The app dies here, with no close record and the page still showing.
      await first.flush();
      clock.advanceSeconds(3600);

      final second = await open();
      // 3 pages of 30 s, plus at most 120 s for the page being read.
      expect(second.summary.today, const Duration(seconds: 90 + 120));
      read(second, 0, 4, 6, 30);
      await second.close();
    });

    test('the log keeps every page turn in order', () async {
      final insights = await open();
      read(insights, 0, 0, 3, 20);
      page(insights, 0, 1, 20, NavigationCause.pageBackward);
      page(insights, 3, 0, 20, NavigationCause.tocJump);
      await insights.close();

      final positions = (await logOf('book1')).whereType<PositionRecord>();
      expect(positions.map((p) => p.cause.code), [
        'pf',
        'pf',
        'pf',
        'pb',
        'toc',
      ]);
      expect(positions.map((p) => p.section), [0, 0, 0, 0, 3]);
    });

    test('nothing is recorded after close', () async {
      final insights = await open();
      page(insights, 0, 0, 20);
      await insights.close();
      final before = await readingLogFile(root, 'book1').readAsString();

      insights.recordPosition(
        const ReaderPosition(5, 0.5),
        NavigationCause.swipe,
      );
      insights.recordHidden();
      insights.recordShown();
      insights.dismissNudge();
      await insights.setHintsEnabled(false);
      await insights.flush();
      await insights.close();

      expect(await readingLogFile(root, 'book1').readAsString(), before);
    });

    test('the signal stream ends on close', () async {
      final insights = await open();
      final done = Completer<void>();
      insights.signals.listen((_) {}, onDone: done.complete);

      await insights.close();

      await done.future.timeout(const Duration(seconds: 2));
    });

    test('leaves a summary for the reader\'s other books', () async {
      final insights = await open();
      read(insights, 0, 0, 9, 40);
      await insights.close();

      final pool = await loadPool(root, excludeId: 'another');

      expect(pool.samples.length, greaterThanOrEqualTo(6));
      expect(pool.days[dayKey(baseMs, 0)], greaterThan(0));
      expect((await loadPool(root, excludeId: 'book1')).samples, isEmpty);
    });
  });

  group('compaction', () {
    test('a long log is compacted when the book opens', () async {
      final file = readingLogFile(root, 'book1');
      await file.parent.create(recursive: true);
      final text = StringBuffer(
        '${jsonEncode(const HeaderRecord(id: 'book1', t: 1).toJson())}\n',
      );
      for (var d = 89; d >= 1; d--) {
        final script = LogScript(startMs: baseMs - d * 24 * 3600 * 1000)
          ..open();
        // The first week is a walk to section 7, then rereading.
        final section = d >= 82 ? 89 - d : d % 4;
        script.page(section, 0, 30, NavigationCause.open);
        script.read(section, 1, 10, 30).close();
        for (final record in script.records) {
          text.write('${jsonEncode(record.toJson())}\n');
        }
      }
      await file.writeAsString(text.toString());
      final before = await file.length();

      final insights = await open(
        config: const InsightsConfig(compactLines: 100),
      );
      await insights.flush();

      expect(await file.length(), lessThan(before));
      // Day 82 is long gone from the raw events, but not from the log.
      expect(insights.furthest!.sectionIndex, 7);
      // Eighty-nine days in a row at exactly the five-minute minimum.
      expect(insights.summary.streakDays, 89);

      final reopened = await open();
      expect(reopened.furthest!.sectionIndex, 7);
      expect(reopened.summary.streakDays, 89);
      expect(reopened.summary.lastDays.map((d) => d.activeTime), [
        for (var i = 0; i < 13; i++) const Duration(minutes: 5),
        Duration.zero,
      ]);
      await insights.close();
      await reopened.close();
    });
  });

  test('the engine and the file service agree', () async {
    final insights = await open();
    read(insights, 0, 0, 10, 40);
    read(insights, 1, 0, 4, 35);
    await insights.close();

    final units = await BookUnits.load(epubPath);
    final engine = InsightsEngine(units: units)..replay(await logOf('book1'));

    expect(engine.furthest, const ReaderPosition(1, 0.3));
    expect(engine.timeline.samples, isNotEmpty);
  });
}
