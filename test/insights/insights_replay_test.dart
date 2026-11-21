import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/insights/confusion_detector.dart';
import 'package:loremark/insights/insights_config.dart';
import 'package:loremark/insights/insights_engine.dart';
import 'package:loremark/insights/reading_insights.dart';
import 'package:loremark/insights/reading_log.dart';
import 'package:loremark/insights/view_tracker.dart';
import 'package:loremark/reader/reader_position.dart';

import 'insights_test_helpers.dart';

/// Everything that identifies a signal, as text.
String describe(ConfusionSignal s) =>
    '${s.kind.name} ${s.at.millisecondsSinceEpoch} ${s.start} ${s.end} '
    '${s.reason}';

/// A long evening with a bit of everything: steady reading, rereading, a
/// stall and a look back, bounces to the contents, a trip to the background,
/// a crash and a second day.
List<LogRecord> evening() {
  final script = LogScript().open();
  const dwells = [30, 40, 50, 60, 70];
  var i = 0;
  for (var section = 0; section < 4; section++) {
    for (var p = 0; p < 10; p++) {
      script.page(section, p, dwells[i++ % dwells.length]);
    }
  }
  // A reread.
  for (var k = 0; k < 2; k++) {
    script
      ..page(3, 2, 20, NavigationCause.pageBackward)
      ..page(3, 3, 20);
  }
  script.page(3, 4, 20);
  // A stall and a look back.
  script
    ..page(4, 3, 170)
    ..page(4, 2, 20, NavigationCause.pageBackward)
    ..page(4, 3, 20);
  // Two bounces to chapter 1.
  for (var k = 0; k < 2; k++) {
    script
      ..page(1, 0, 30, NavigationCause.tocJump)
      ..page(4, 3, 30, NavigationCause.tocJump);
  }
  // Searches.
  for (var k = 0; k < 3; k++) {
    script.page(6, k, 40, NavigationCause.searchJump);
  }
  // A section turn, the app in the background and a crash.
  script
    ..pos(6, 1)
    ..pos(7, 0)
    ..wait(30)
    ..bg()
    ..wait(120)
    ..fg()
    ..page(7, 1, 40)
    ..page(7, 2, 40)
    ..wait(3 * 3600)
    ..open()
    ..page(7, 2, 40)
    ..page(7, 3, 40)
    ..close();
  // The next day.
  final next = LogScript(startMs: script.t + 20 * 3600 * 1000, tz: 60)
    ..open()
    ..read(7, 3, 9, 35)
    ..close();
  return [...script.records, ...next.records];
}

void main() {
  final records = evening();

  List<String> incremental() {
    final detector = ConfusionDetector(units: tenSections());
    return [
      for (final record in records) ...detector.process(record).map(describe),
    ];
  }

  test('the evening produces every kind of signal', () {
    final kinds = {for (final s in incremental()) s.split(' ').first};

    expect(kinds, {'reread', 'stall', 'chapterBounce', 'searchBurst'});
  });

  test('replaying a whole log gives the signals of following it live', () {
    final live = incremental();

    final engine = InsightsEngine(units: tenSections());
    final batch = [
      for (final record in records) ...engine.add(record).map(describe),
    ];

    expect(batch, live);
  });

  test('the engine replays a log without emitting signals', () {
    final engine = InsightsEngine(units: tenSections());

    engine.replay(records);

    expect(engine.policy.current, isNull);
    expect(engine.furthest, isNotNull);
  });

  test('a log read back from disk text gives the same signals', () {
    final live = incremental();
    final text = StringBuffer(
      '${jsonEncode(const HeaderRecord(id: 'b', t: 0).toJson())}\n',
    );
    for (final record in records) {
      text.write('${jsonEncode(record.toJson())}\n');
      // Garbage the reader must step over.
      if (record is BackgroundRecord) text.write('not json\n{"k":"future"}\n');
    }

    final parsed = parseLog(text.toString());
    final detector = ConfusionDetector(units: tenSections());
    final fromDisk = [
      for (final record in parsed.records)
        ...detector.process(record).map(describe),
    ];

    expect(parsed.records, hasLength(records.length));
    expect(fromDisk, live);
  });

  test('feeding settled events in any chunks gives the same signals', () {
    final live = incremental();
    final random = Random(7);
    for (var trial = 0; trial < 5; trial++) {
      final tracker = ViewTracker(tenSections(), const InsightsConfig());
      final detector = ConfusionDetector(units: tenSections());
      final signals = <String>[];
      var at = 0;
      while (at < records.length) {
        final size = 1 + random.nextInt(9);
        final events = <ViewEvent>[];
        for (final record in records.skip(at).take(size)) {
          events.addAll(tracker.add(record));
        }
        signals.addAll(detector.processEvents(events).map(describe));
        at += size;
      }

      expect(signals, live, reason: 'trial $trial');
    }
  });

  test('daily totals and furthest are the same incrementally or replayed', () {
    final first = InsightsEngine(units: tenSections());
    for (final record in records) {
      first.add(record);
    }
    final second = InsightsEngine(units: tenSections())..replay(records);

    Map<String, List<int>> totals(InsightsEngine e) => {
      for (final MapEntry(:key, :value) in e.timeline.days.entries)
        key: [value.ms, value.units, value.pages, value.sessions],
    };
    expect(totals(first), totals(second));
    expect(first.furthest, second.furthest);
    expect(first.timeline.samples.length, second.timeline.samples.length);
    expect(first.timeline.days.keys.length, 2);
  });

  group('after a jump ahead and back', () {
    final jumped =
        (LogScript()
              ..open()
              ..page(0, 0, 30, NavigationCause.open)
              ..page(0, 1, 30)
              ..page(9, 0, 30, NavigationCause.tocJump)
              ..page(0, 1, 30, NavigationCause.tocJump)
              ..read(0, 2, 10, 30)
              ..pos(0, 1)
              ..pos(1, 0)
              ..wait(30)
              ..page(1, 1, 30)
              ..close())
            .records;

    test('the frontier is where continuous reading got to', () {
      final engine = InsightsEngine(units: tenSections())..replay(jumped);

      expect(engine.furthest, const ReaderPosition(1, 0.1));
    });

    test('pace is learned from the pages read after coming back', () {
      final engine = InsightsEngine(units: tenSections())..replay(jumped);

      expect(engine.timeline.samples.length, greaterThanOrEqualTo(6));
    });

    test('replaying gives what following it live gave', () {
      final live = InsightsEngine(units: tenSections());
      for (final record in jumped) {
        live.add(record);
      }
      final replayed = InsightsEngine(units: tenSections())..replay(jumped);

      expect(replayed.furthest, live.furthest);
      expect(
        replayed.timeline.samples.map((s) => s.toJson()),
        live.timeline.samples.map((s) => s.toJson()),
      );
    });
  });
}
