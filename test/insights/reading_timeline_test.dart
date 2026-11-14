import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/insights/insights_config.dart';
import 'package:loremark/insights/reading_insights.dart';
import 'package:loremark/insights/reading_log.dart';
import 'package:loremark/insights/reading_timeline.dart';
import 'package:loremark/insights/view_tracker.dart';

import 'insights_test_helpers.dart';

ReadingTimeline timelineOf(
  LogScript script, {
  InsightsConfig config = const InsightsConfig(),
}) {
  final tracker = ViewTracker(tenSections(), config);
  final timeline = ReadingTimeline(config);
  for (final record in script.records) {
    tracker.add(record).forEach(timeline.onEvent);
  }
  return timeline;
}

void main() {
  group('day keys', () {
    test('use the offset stored in the log', () {
      final ms = DateTime.utc(2026, 10, 6, 2, 30).millisecondsSinceEpoch;

      expect(dayKey(ms, 0), '2026-10-06');
      expect(dayKey(ms, -420), '2026-10-05');
      expect(dayKey(ms, 540), '2026-10-06');
      expect(dayKey(ms, 24 * 60), '2026-10-07');
    });

    test('count back over month and year ends', () {
      expect(previousDay('2026-03-01'), '2026-02-28');
      expect(previousDay('2024-03-01'), '2024-02-29');
      expect(previousDay('2026-01-01'), '2025-12-31');
      expect(lastDayKeys('2026-03-02', 4), [
        '2026-02-27',
        '2026-02-28',
        '2026-03-01',
        '2026-03-02',
      ]);
    });
  });

  group('streak', () {
    const five = 5 * 60000;
    int Function(String) minutes(Map<String, int> byDay) =>
        (day) => (byDay[day] ?? 0) * 60000;

    test('counts days in a row back from today', () {
      final streak = streakDays(
        '2026-10-05',
        minutes({'2026-10-05': 6, '2026-10-04': 30, '2026-10-03': 5}),
        five,
      );

      expect(streak, 3);
    });

    test('a today without enough reading yet does not break it', () {
      final byDay = {'2026-10-05': 2, '2026-10-04': 30, '2026-10-03': 9};

      expect(streakDays('2026-10-05', minutes(byDay), five), 2);
    });

    test('a missed day ends it', () {
      final byDay = {'2026-10-05': 20, '2026-10-03': 20, '2026-10-02': 20};

      expect(streakDays('2026-10-05', minutes(byDay), five), 1);
    });

    test('is zero with no reading', () {
      expect(streakDays('2026-10-05', minutes({}), five), 0);
    });

    test('a day just under the minimum does not count', () {
      expect(streakDays('2026-10-05', (day) => 5 * 60000 - 1, five), 0);
    });
  });

  group('timeline', () {
    test('adds up active time by day', () {
      final script = LogScript().open().read(0, 0, 6, 40).close();

      final timeline = timelineOf(script);

      expect(timeline.days['2026-10-05']!.ms, 6 * 40000);
      expect(timeline.days['2026-10-05']!.sessions, 1);
    });

    test('counts new units and pages, not rereads', () {
      final script = LogScript()
          .open()
          .read(0, 0, 4, 30)
          .page(0, 1, 30, NavigationCause.pageBackward)
          .page(0, 2, 30)
          .page(0, 3, 30)
          .page(0, 4, 30)
          .close();

      final day = timelineOf(script).days['2026-10-05']!;

      // A page counts once, when it is first left forward: pages 0-2, then
      // page 3 on the way on. Pages 1 and 2 the second time are rereads.
      expect(day.units, 800);
      expect(day.pages, 4);
    });

    test('splits a session at midnight by the day of each page', () {
      final start = DateTime.utc(2026, 10, 5, 23, 59, 0).millisecondsSinceEpoch;
      final script = LogScript(startMs: start).open().read(0, 0, 6, 30).close();

      final timeline = timelineOf(script);

      // 23:59:00 and 23:59:30 are Monday; 00:00:00 onwards is Tuesday.
      expect(timeline.days['2026-10-05']!.ms, 60000);
      expect(timeline.days['2026-10-06']!.ms, 4 * 30000);
      // One session, counted on the day it started.
      expect(timeline.sessions, hasLength(1));
      expect(timeline.days['2026-10-05']!.sessions, 1);
      expect(timeline.days['2026-10-06']?.sessions ?? 0, 0);
    });

    test('uses the reader\'s own zone for the day', () {
      // 03:00 UTC is 20:00 the evening before at UTC-7.
      final start = DateTime.utc(2026, 10, 6, 3).millisecondsSinceEpoch;
      final script = LogScript(
        startMs: start,
        tz: -420,
      ).open().read(0, 0, 3, 60).close();

      final timeline = timelineOf(script);

      expect(timeline.days.keys, ['2026-10-05']);
    });

    test('a session survives the app going to the background and back', () {
      final script = LogScript()
          .open()
          .page(0, 0, 30)
          .bg()
          .wait(60)
          .fg()
          .page(0, 1, 30)
          .page(0, 2, 30)
          .close();

      final timeline = timelineOf(script);

      expect(timeline.sessions, hasLength(1));
      final session = timeline.sessions.values.single;
      // The minute in the background is not reading time.
      expect(session.activeMs, 90000);
      expect(session.wallMs, 150000);
    });

    test('a long background splits sessions', () {
      final script = LogScript()
          .open()
          .page(0, 0, 30)
          .bg()
          .wait(20 * 60)
          .fg()
          .page(0, 1, 30)
          .pos(0, 0.2)
          .close();

      final timeline = timelineOf(script);

      expect(timeline.sessions, hasLength(2));
      expect(timeline.days['2026-10-05']!.sessions, 2);
    });

    test('a crash is credited one dwell and ends the session', () {
      final script = LogScript()
          .open()
          .read(0, 0, 3, 30)
          .wait(3 * 3600)
          .open()
          .read(0, 3, 5, 30)
          .close();

      final timeline = timelineOf(script);

      expect(timeline.sessions, hasLength(2));
      // Two finished pages plus 120 s for the page being read when the app
      // died, and 30 s for the first page of the next run; its second page
      // is closed after 30 s.
      final first = timeline.sessions[0]!;
      expect(first.activeMs, 30000 + 30000 + 120000);
      // The days differ because three hours passed.
      expect(timeline.days.keys, hasLength(1));
    });

    test('merges a day that compaction summarised', () {
      final timeline = ReadingTimeline(const InsightsConfig())
        ..addDay(
          const DayRecord(
            day: '2026-08-01',
            ms: 600000,
            units: 500,
            pages: 3,
            sessions: 1,
          ),
        )
        ..addDay(
          const DayRecord(
            day: '2026-08-01',
            ms: 60000,
            units: 50,
            pages: 1,
            sessions: 1,
          ),
        );

      final day = timeline.days['2026-08-01']!;
      expect((day.ms, day.units, day.pages, day.sessions), (660000, 550, 4, 2));
      expect(timeline.activeMsOn('2026-08-01'), 660000);
      expect(timeline.activeMsOn('2026-08-02'), 0);
    });
  });

  group('pace samples', () {
    List<PaceSample> samplesOf(LogScript script) => timelineOf(script).samples;

    test('come from first reads turned forward at a steady pace', () {
      final script = LogScript().open().read(0, 0, 6, 40).close();

      final samples = samplesOf(script);

      expect(samples, hasLength(5));
      expect(samples.first.units, 200);
      expect(samples.first.sec, 40);
    });

    test('skip flip-throughs and very slow pages', () {
      final script = LogScript()
          .open()
          .page(0, 0, 1)
          .page(0, 1, 2.9)
          .page(0, 2, 121)
          .page(0, 3, 40)
          .pos(0, 0.4);

      expect(samplesOf(script), hasLength(1));
    });

    test('skip skimming and an interruption by speed', () {
      final script = LogScript()
          .open()
          // 200 units in 10 s is 1200 per minute: skimming.
          .page(0, 0, 10)
          // In 100 s it is 120 per minute: fine.
          .page(0, 1, 100)
          .pos(0, 0.2);

      expect(samplesOf(script), hasLength(1));
    });

    test('skip rereads, backward moves and jumps', () {
      final script = LogScript()
          .open()
          .read(0, 0, 4, 40)
          .page(0, 1, 40, NavigationCause.pageBackward)
          .page(0, 2, 40)
          .page(0, 3, 40)
          .pos(0, 0.4);

      // Pages 0-2 turned forward, then page 3 the second time (it was left
      // backwards the first). The reread of 1 and 2 give nothing.
      expect(samplesOf(script), hasLength(4));
    });

    test('skip pages with too little text', () {
      final tiny = LogScript().open().pos(0, 0).wait(30).pos(0, 0.01);
      // 20 units in a tenth of a percent step of 2000.

      expect(samplesOf(tiny), isEmpty);
    });

    test('skip the page a session resumed on', () {
      final script = LogScript()
          .open()
          .page(0, 0, 30)
          .bg()
          .wait(600)
          .fg()
          .page(0, 0, 30)
          .pos(0, 0.1);

      expect(samplesOf(script), isEmpty);
    });
  });

  group('PaceEstimator', () {
    const estimator = PaceEstimator(InsightsConfig());

    List<PaceSample> synthetic(
      int count, {
      required double secPerUnit,
      double sigma = 0.3,
      double interruptions = 0.05,
      int seed = 1,
    }) {
      final random = Random(seed);
      double normal() =>
          sqrt(-2 * log(1 - random.nextDouble())) *
          cos(2 * pi * random.nextDouble());
      final samples = <PaceSample>[];
      while (samples.length < count) {
        final units = 150.0 + random.nextInt(100);
        var sec = units * secPerUnit * exp(sigma * normal());
        if (random.nextDouble() < interruptions) {
          sec *= 2 + random.nextDouble() * 4;
        }
        // What paceSampleOf would let through.
        if (sec < 3 || sec > 120) continue;
        samples.add(PaceSample(t: samples.length, units: units, sec: sec));
      }
      return samples;
    }

    test('stays within 10% of the truth for a log-normal reader', () {
      // A reader at 300 units a minute whose page times vary by 30%, with one
      // page in twenty interrupted. The truth is the mean time per unit on
      // normal pages, which is what a total is made of.
      const sigma = 0.3;
      final truth = 0.2 * exp(sigma * sigma / 2);
      for (var seed = 1; seed <= 20; seed++) {
        final samples = synthetic(
          80,
          secPerUnit: 0.2,
          sigma: sigma,
          seed: seed,
        );

        final estimate = estimator.estimate(
          own: samples,
          defaultUnitsPerMinute: 230,
        );

        final estimated = estimate.secPerUnit;
        expect(
          (estimated - truth).abs() / truth,
          lessThan(0.10),
          reason: 'seed $seed: estimated $estimated, truth $truth',
        );
      }
    });

    test('the default pace is shown until there are enough samples', () {
      final few = synthetic(5, secPerUnit: 0.15);

      final estimate = estimator.estimate(own: few, defaultUnitsPerMinute: 230);

      expect(estimate.personal, isFalse);
      expect(estimate.unitsPerMinute, 230);
      expect(estimate.samples, 5);
    });

    test('becomes personal at the sixth sample', () {
      final samples = synthetic(6, secPerUnit: 0.15);

      final estimate = estimator.estimate(
        own: samples,
        defaultUnitsPerMinute: 230,
      );

      expect(estimate.personal, isTrue);
      expect(estimate.samples, 6);
    });

    test('with no own samples the prior from other books is used once there are 20', () {
      final pool = synthetic(
        25,
        secPerUnit: 0.1,
        sigma: 0.1,
        interruptions: 0,
        seed: 3,
      );

      final estimate = estimator.estimate(
        own: const [],
        pool: pool,
        defaultUnitsPerMinute: 230,
      );

      expect(estimate.personal, isTrue);
      expect(estimate.unitsPerMinute, closeTo(600, 30));
    });

    test('19 samples from other books are not enough', () {
      final pool = synthetic(19, secPerUnit: 0.1);

      final estimate = estimator.estimate(
        own: const [],
        pool: pool,
        defaultUnitsPerMinute: 230,
      );

      expect(estimate.personal, isFalse);
    });

    test('a new book is pulled towards the prior but follows the reader', () {
      final own = synthetic(6, secPerUnit: 0.3, sigma: 0.05, interruptions: 0);
      final pool = synthetic(
        30,
        secPerUnit: 0.15,
        sigma: 0.05,
        interruptions: 0,
        seed: 4,
      );

      final mixed = estimator.estimate(
        own: own,
        pool: pool,
        defaultUnitsPerMinute: 230,
      );
      final alone = estimator.estimate(own: own, defaultUnitsPerMinute: 230);

      // Own pace 200/min, pool pace 400/min: with six samples and a prior
      // weight of six, halfway.
      expect(mixed.unitsPerMinute, greaterThan(alone.unitsPerMinute));
      expect(mixed.unitsPerMinute, closeTo(60 / 0.225, 5));
    });

    test('only the newest 40 samples count', () {
      final slowThenFast = [
        for (var i = 0; i < 40; i++) PaceSample(t: i, units: 200, sec: 60),
        for (var i = 40; i < 80; i++) PaceSample(t: i, units: 200, sec: 30),
      ];

      final estimate = estimator.estimate(
        own: slowThenFast,
        defaultUnitsPerMinute: 230,
      );

      // 400 units a minute from the fast pages, nudged towards 230 by the
      // prior.
      expect(estimate.unitsPerMinute, greaterThan(340));
    });

    test('drops the slowest tenth as interruptions', () {
      final samples = [
        for (var i = 0; i < 36; i++) PaceSample(t: i, units: 200, sec: 40),
        for (var i = 36; i < 40; i++) PaceSample(t: i, units: 200, sec: 119),
      ];

      final trimmed = estimator.trimmedSecPerUnit(samples, 40)!;

      expect(trimmed, closeTo(0.2, 1e-9));
    });

    test('is clamped to a believable range', () {
      final fast = [
        for (var i = 0; i < 40; i++) PaceSample(t: i, units: 800, sec: 20),
      ];
      final slow = [
        for (var i = 0; i < 40; i++) PaceSample(t: i, units: 100, sec: 100),
      ];

      expect(
        estimator
            .estimate(own: fast, defaultUnitsPerMinute: 230)
            .unitsPerMinute,
        lessThanOrEqualTo(600),
      );
      expect(
        estimator
            .estimate(own: slow, defaultUnitsPerMinute: 230)
            .unitsPerMinute,
        greaterThanOrEqualTo(80),
      );
    });

    test('has no estimate from no samples', () {
      expect(estimator.trimmedSecPerUnit(const [], 40), isNull);
    });
  });
}
