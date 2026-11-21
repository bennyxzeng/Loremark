import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/insights/book_units.dart';
import 'package:loremark/insights/confusion_detector.dart';
import 'package:loremark/insights/reading_insights.dart';
import 'package:loremark/insights/reading_timeline.dart';
import 'package:loremark/reader/reader_position.dart';

import 'insights_test_helpers.dart';

List<ConfusionSignal> detect(
  LogScript script, {
  BookUnits? units,
  List<PaceSample> external = const [],
}) {
  final detector = ConfusionDetector(
    units: units ?? tenSections(),
    externalBaseline: external,
  );
  return [for (final record in script.records) ...detector.process(record)];
}

List<ConfusionKind> kinds(List<ConfusionSignal> signals) => [
  for (final signal in signals) signal.kind,
];

/// Reads sections 0-3 in full at a spread of speeds, so there are 40 samples
/// of what is normal. Dwells of 30-70 s on 200 units: the median is 50 s, and
/// the modified z of a page crosses 3.5 between 150 s and 170 s.
LogScript withBaseline([LogScript? script]) {
  final s = script ?? LogScript().open();
  const dwells = [30, 40, 50, 60, 70];
  var i = 0;
  for (var section = 0; section < 4; section++) {
    for (var p = 0; p < 10; p++) {
      s.page(section, p, dwells[i++ % dwells.length]);
    }
  }
  return s;
}

/// Goes back to page [p] of [section] and forward again, [times] times.
void lookBack(LogScript s, int section, int p, int times, {num dwell = 20}) {
  for (var i = 0; i < times; i++) {
    s.page(section, p, dwell, NavigationCause.pageBackward);
    s.page(section, p + 1, dwell);
  }
}

void main() {
  group('R1 reread', () {
    test('fires on the third visit, two of them by going back', () {
      final script = LogScript().open().read(0, 0, 4, 30);
      lookBack(script, 0, 2, 2);
      script.page(0, 4, 20);

      final signals = detect(script);

      expect(kinds(signals), [ConfusionKind.reread]);
      final signal = signals.single;
      expect(signal.start, const ReaderPosition(0, 0.2));
      expect(signal.end.sectionIndex, 0);
      expect(signal.end.progression, closeTo(0.3, 1e-9));
      expect(signal.reason, contains('3 times'));
      expect(signal.reason, contains('minute'));
    });

    test('fires when the third visit ends, not before', () {
      final script = LogScript().open().read(0, 0, 4, 30);
      lookBack(script, 0, 2, 1);
      script.page(0, 2, 20, NavigationCause.pageBackward);
      final before = detect(script);
      script.page(0, 3, 20);

      final after = detect(script);

      expect(before, isEmpty);
      expect(kinds(after), [ConfusionKind.reread]);
    });

    test('one look back never fires', () {
      final script = LogScript().open().read(0, 0, 4, 30);
      lookBack(script, 0, 2, 1);
      script.page(0, 4, 20).page(0, 5, 20);

      expect(detect(script), isEmpty);
    });

    test('reading straight on never fires', () {
      expect(detect(LogScript().open().read(0, 0, 10, 40).close()), isEmpty);
    });

    test('three visits of which only one is a going back does not fire', () {
      // Back to page 2 once, then forward over it again by another route.
      final script = LogScript().open().read(0, 0, 4, 30);
      script
          .page(0, 2, 20, NavigationCause.pageBackward)
          .page(0, 3, 20)
          .page(0, 4, 20);

      expect(detect(script), isEmpty);
    });

    test('glances under four seconds are not visits', () {
      final script = LogScript().open().read(0, 0, 4, 30);
      lookBack(script, 0, 2, 3, dwell: 2);
      script.page(0, 4, 20);

      expect(detect(script), isEmpty);
    });

    test('visits spread over more than 20 minutes do not add up', () {
      final script = LogScript().open().read(0, 0, 4, 30);
      lookBack(script, 0, 2, 1);
      script.wait(25 * 60);
      lookBack(script, 0, 2, 1);
      script.page(0, 4, 20);

      expect(detect(script), isEmpty);
    });

    test('a different page does not share the count', () {
      final script = LogScript().open().read(0, 0, 6, 30);
      lookBack(script, 0, 1, 1);
      lookBack(script, 0, 3, 1);
      script.page(0, 6, 20);

      expect(detect(script), isEmpty);
    });

    test('stepping back to regain context right after opening is ignored', () {
      // The reader resumes on page 5 and steps back twice to page 4 inside
      // the first 90 seconds.
      final script = LogScript().open().page(0, 5, 10);
      lookBack(script, 0, 4, 2, dwell: 10);
      script.page(0, 6, 10);

      expect(detect(script), isEmpty);
    });

    test('the same look backs later in the session do fire', () {
      final script = LogScript().open().page(0, 3, 40).page(0, 4, 40);
      script.page(0, 5, 40);
      lookBack(script, 0, 4, 2, dwell: 10);
      script.page(0, 6, 10);

      expect(kinds(detect(script)), [ConfusionKind.reread]);
    });

    test('is emitted once per passage per day', () {
      final script = LogScript().open().read(0, 0, 4, 30);
      lookBack(script, 0, 2, 2);
      script.page(0, 4, 20);
      lookBack(script, 0, 2, 2);
      script.page(0, 4, 20);

      expect(detect(script), hasLength(1));
    });

    test('is emitted again for the passage a day later', () {
      final script = LogScript().open().read(0, 0, 4, 30);
      lookBack(script, 0, 2, 2);
      script.page(0, 4, 20).wait(25 * 3600).open().read(0, 0, 4, 30);
      lookBack(script, 0, 2, 2);
      script.page(0, 4, 20);

      expect(kinds(detect(script)), [
        ConfusionKind.reread,
        ConfusionKind.reread,
      ]);
    });

    test(
      'a page left and returned to after a long background is one visit',
      () {
        // 20 s, away for ten minutes, 20 s more: one visit, not two.
        final script = LogScript().open().read(0, 0, 4, 30);
        script
            .page(0, 2, 10, NavigationCause.pageBackward)
            .bg()
            .wait(600)
            .fg()
            .wait(10)
            .page(0, 3, 120);
        script.page(0, 2, 20, NavigationCause.pageBackward).page(0, 3, 20);

        // First read, then one merged back visit, then one more: three visits
        // and two backs, so it does fire once. Without the merge there would
        // be four visits and it would have fired earlier.
        final signals = detect(script);
        expect(kinds(signals), [ConfusionKind.reread]);
        expect(signals.single.reason, contains('3 times'));
      },
    );

    test('works across a section turn', () {
      final script = LogScript().open();
      script.page(0, 8, 30).page(0, 9, 30);
      script.pos(0, 1).pos(1, 0).wait(30).pos(1, 0.1).wait(30);
      for (var i = 0; i < 2; i++) {
        script.page(0, 9, 20, NavigationCause.pageBackward);
        script.pos(0, 1).pos(1, 0).wait(20).pos(1, 0.1).wait(20);
      }
      script.page(1, 2, 20);

      final signals = detect(script);

      expect(kinds(signals), [ConfusionKind.reread]);
      expect(signals.single.start, const ReaderPosition(0, 0.9));
    });

    test('says nothing for a book that could not be read', () {
      final script = LogScript().open().read(0, 0, 4, 30);
      lookBack(script, 0, 2, 3);

      expect(detect(script, units: BookUnits.empty()), isEmpty);
    });
  });

  group('R2 stall', () {
    LogScript stallScript(num stallDwell, {num lookbackAfter = 0}) {
      final script = withBaseline();
      script.page(4, 3, stallDwell);
      if (lookbackAfter > 0) script.page(4, 4, lookbackAfter);
      script.page(
        4,
        lookbackAfter > 0 ? 3 : 2,
        20,
        NavigationCause.pageBackward,
      );
      return script.page(4, 4, 20);
    }

    test('fires on a very slow page followed at once by looking back', () {
      final signals = detect(stallScript(170));

      expect(kinds(signals), [ConfusionKind.stall]);
      expect(signals.single.start, const ReaderPosition(4, 0.3));
      expect(signals.single.reason, contains('longer than usual'));
    });

    test('fires if the lookback is within 20 seconds of leaving the page', () {
      expect(kinds(detect(stallScript(170, lookbackAfter: 10))), [
        ConfusionKind.stall,
      ]);
    });

    test('does not fire if the lookback comes later than 20 seconds', () {
      expect(detect(stallScript(170, lookbackAfter: 25)), isEmpty);
    });

    test('does not fire without a lookback', () {
      final script = withBaseline()
          .page(4, 3, 170)
          .page(4, 4, 40)
          .page(4, 5, 40);

      expect(detect(script), isEmpty);
    });

    test('a z-score just under the threshold does not fire', () {
      // 150 s is exactly three times the median page and z is about 3.4.
      expect(detect(stallScript(150)), isEmpty);
    });

    test('a dwell over four minutes is an idle phone, not a stall', () {
      expect(detect(stallScript(300)), isEmpty);
    });

    test('a dwell under a minute never fires', () {
      expect(detect(stallScript(55)), isEmpty);
    });

    test('a background trip inside the dwell invalidates it', () {
      final script = withBaseline();
      script
          .page(4, 3, 60)
          .bg()
          .wait(30)
          .fg()
          .wait(80)
          .page(4, 2, 20, NavigationCause.pageBackward)
          .page(4, 3, 20);

      expect(detect(script), isEmpty);
    });

    test('is silent until there are 30 samples of what is normal', () {
      final script = LogScript().open();
      const dwells = [30, 40, 50, 60, 70];
      for (var p = 0; p < 9; p++) {
        script.page(0, p, dwells[p % 5]);
      }
      for (var p = 0; p < 9; p++) {
        script.page(1, p, dwells[p % 5]);
      }
      for (var p = 0; p < 9; p++) {
        script.page(2, p, dwells[p % 5]);
      }
      // 27 samples so far (the turns between sections are samples too, but
      // only the page before each).
      script.page(4, 3, 170).page(4, 2, 20, NavigationCause.pageBackward);

      expect(detect(script), isEmpty);
    });

    test('uses the reader\'s other books until this one has enough', () {
      final external = [
        for (var i = 0; i < 40; i++)
          PaceSample(
            t: i,
            units: 200,
            sec: [30.0, 40.0, 50.0, 60.0, 70.0][i % 5],
          ),
      ];
      final script = LogScript().open().page(4, 1, 40).page(4, 2, 40);
      script.page(4, 3, 170).page(4, 2, 20, NavigationCause.pageBackward);

      expect(kinds(detect(script, external: external)), [ConfusionKind.stall]);
      expect(detect(script), isEmpty);
    });

    test('a second stall on the same page the same day is not repeated', () {
      final script = stallScript(170);
      script
          .page(4, 3, 170)
          .page(4, 2, 20, NavigationCause.pageBackward)
          .page(4, 3, 20);

      final stalls = detect(script).where((s) => s.kind == ConfusionKind.stall);

      expect(stalls, hasLength(1));
    });

    test('a very steady reader does not make small slowdowns look huge', () {
      // Every baseline page takes exactly 40 s, so the spread is nil; the
      // floor on sigma keeps 120 s (three times, z of about 7) from being
      // judged by a tiny MAD alone and the 3x rule still has to hold.
      final script = LogScript().open();
      for (var section = 0; section < 4; section++) {
        script.read(section, 0, 10, 40);
      }
      script.page(4, 3, 119).page(4, 2, 20, NavigationCause.pageBackward);

      expect(detect(script), isEmpty);

      final slower = LogScript().open();
      for (var section = 0; section < 4; section++) {
        slower.read(section, 0, 10, 40);
      }
      slower.page(4, 3, 125).page(4, 2, 20, NavigationCause.pageBackward);
      expect(kinds(detect(slower)), [ConfusionKind.stall]);
    });
  });

  group('R3 chapter bounce', () {
    /// Reads to section 5 page 5, then goes back to [target] by the contents
    /// and returns, [times] times.
    LogScript bounceScript(
      int times, {
      List<int> targets = const [2],
      num gapBetween = 60,
      NavigationCause outCause = NavigationCause.tocJump,
    }) {
      final script = LogScript().open().read(5, 0, 6, 30);
      for (var i = 0; i < times; i++) {
        final target = targets[i % targets.length];
        script.page(target, 0, 30, outCause);
        script.page(5, 5, gapBetween, NavigationCause.tocJump);
      }
      return script.page(5, 6, 30);
    }

    test('fires on the second trip back to the same chapter', () {
      final signals = detect(bounceScript(2));

      expect(kinds(signals), [ConfusionKind.chapterBounce]);
      expect(signals.single.start, const ReaderPosition(2, 0));
      expect(signals.single.reason, contains('2 times'));
    });

    test('one trip is a normal lookup', () {
      expect(detect(bounceScript(1)), isEmpty);
    });

    test('a neighbouring chapter counts as the same', () {
      expect(kinds(detect(bounceScript(2, targets: [2, 3]))), [
        ConfusionKind.chapterBounce,
      ]);
    });

    test('different chapters do not add up', () {
      expect(detect(bounceScript(2, targets: [1, 3])), isEmpty);
    });

    test('trips more than half an hour apart do not add up', () {
      expect(detect(bounceScript(2, gapBetween: 35 * 60)), isEmpty);
    });

    test('going back without returning is not a bounce', () {
      final script = LogScript().open().read(5, 0, 6, 30);
      script.page(2, 0, 30, NavigationCause.tocJump);
      script.page(2, 0, 0).page(2, 1, 30).page(2, 2, 30);
      script.page(2, 0, 30, NavigationCause.tocJump).page(2, 1, 30);

      expect(detect(script), isEmpty);
    });

    test('a jump forward or within the chapter is not a trip', () {
      final script = LogScript().open().read(5, 0, 6, 30);
      for (var i = 0; i < 3; i++) {
        script.page(5, 1, 30, NavigationCause.tocJump);
        script.page(5, 5, 30, NavigationCause.tocJump);
      }

      // Visiting one page over and over is a reread, but not a bounce.
      expect(
        kinds(detect(script)),
        isNot(contains(ConfusionKind.chapterBounce)),
      );
    });

    test('a swipe over many pages counts like a jump', () {
      final script = bounceScript(2, outCause: NavigationCause.swipe);

      expect(kinds(detect(script)), [ConfusionKind.chapterBounce]);
    });

    test('a third trip is not announced again', () {
      final bounces = detect(bounceScript(3))
          .where((s) => s.kind == ConfusionKind.chapterBounce);

      expect(bounces, hasLength(1));
    });

    test('stepping back one page across a chapter border is not a trip', () {
      final script = LogScript().open().read(5, 0, 1, 30);
      for (var i = 0; i < 3; i++) {
        script.pos(4, 0.9, NavigationCause.pageBackward).wait(30);
        script.pos(5, 0.0).wait(30);
      }

      expect(
        kinds(detect(script)),
        isNot(contains(ConfusionKind.chapterBounce)),
      );
    });
  });

  group('R4 search burst', () {
    LogScript searches(int count, {num every = 60}) {
      final script = LogScript().open().read(5, 0, 4, 30);
      for (var i = 0; i < count; i++) {
        script.page(i % 3, 3 + i, every, NavigationCause.searchJump);
      }
      return script;
    }

    test('fires on three searches within five minutes', () {
      expect(kinds(detect(searches(3))), [ConfusionKind.searchBurst]);
    });

    test('two searches are not a burst', () {
      expect(detect(searches(2)), isEmpty);
    });

    test('searches spread over more than five minutes are not a burst', () {
      expect(detect(searches(3, every: 180)), isEmpty);
    });

    test('is weak', () {
      expect(ConfusionKind.searchBurst.severity, Severity.weak);
      expect(ConfusionKind.reread.severity, Severity.strong);
      expect(ConfusionKind.stall.severity, Severity.medium);
      expect(ConfusionKind.chapterBounce.severity, Severity.medium);
    });
  });

  group('incremental use', () {
    test('a new session forgets a half-finished stall', () {
      final script = withBaseline();
      script
          .page(4, 3, 170)
          .open()
          .page(4, 2, 20, NavigationCause.pageBackward)
          .page(4, 3, 20);

      expect(detect(script), isEmpty);
    });

    test('signals carry the time they were detected', () {
      final script = LogScript().open().read(0, 0, 4, 30);
      lookBack(script, 0, 2, 2);
      script.page(0, 4, 20);

      final signal = detect(script).single;

      // Detected when the third visit ended, the move to the next page, 40 s before the end.
      expect(signal.at.millisecondsSinceEpoch, script.t - 40000);
    });
  });
}
