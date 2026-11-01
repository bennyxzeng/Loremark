import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/insights/insights_config.dart';
import 'package:loremark/insights/insights_engine.dart';
import 'package:loremark/insights/reading_insights.dart';
import 'package:loremark/reader/reader_position.dart';

import 'insights_test_helpers.dart';

/// Feeds a script into the whole pipeline and notes every nudge that showed.
///
/// The book has ten sections of 100 pages.
class Rig {
  Rig({InsightsConfig config = const InsightsConfig()})
    : engine = InsightsEngine(units: longBook(100), config: config);

  final InsightsEngine engine;
  final script = LogScript(pagesPerSection: 100);
  final signals = <ConfusionSignal>[];
  final shown = <ConfusionSignal>[];
  var _fed = 0;
  ConfusionSignal? _last;

  ConfusionSignal? get nudge => engine.policy.current;

  void feed() {
    for (final record in script.records.skip(_fed)) {
      signals.addAll(engine.add(record));
      _noteNudge();
    }
    _fed = script.records.length;
  }

  void _noteNudge() {
    final now = engine.policy.current;
    if (now != null && !identical(now, _last)) shown.add(now);
    _last = now;
  }

  /// Opens the book and reads pages [from] to [to] of [section].
  Rig open() {
    script.open();
    feed();
    return this;
  }

  Rig read(int section, int from, int to, {num dwell = 30}) {
    script.read(section, from, to, dwell);
    feed();
    return this;
  }

  /// Looks back at page [p] of section 0 twice from page [p] + 2, so the
  /// third visit ends and a reread fires. Leaves the reader on page [p] + 1.
  Rig reread(int p, {int section = 0}) {
    for (var i = 0; i < 2; i++) {
      script.page(section, p, 20, NavigationCause.pageBackward);
      script.page(section, p + 1, 20);
    }
    feed();
    return this;
  }

  /// A signal made by hand about page [page] of [section], as of now.
  ConfusionSignal inject({
    ConfusionKind kind = ConfusionKind.reread,
    int section = 0,
    required int page,
  }) {
    final signal = ConfusionSignal(
      kind: kind,
      at: DateTime.fromMillisecondsSinceEpoch(script.t),
      start: ReaderPosition(section, page / 100),
      end: ReaderPosition(section, (page + 1) / 100),
      reason: 'by hand',
    );
    engine.policy.process(const [], [signal]);
    _noteNudge();
    return signal;
  }

  void dismiss() {
    engine.policy.dismiss(script.t);
    _noteNudge();
  }
}

void main() {
  /// A reader five minutes into a session, on page 10 of section 0.
  Rig warmRig([InsightsConfig config = const InsightsConfig()]) =>
      Rig(config: config)
        ..open()
        ..read(0, 0, 11);

  group('showing a nudge', () {
    test('a reread after the warm-up shows', () {
      final rig = warmRig()
        ..read(0, 11, 14)
        ..reread(12);

      expect(rig.signals.map((s) => s.kind), [ConfusionKind.reread]);
      expect(rig.nudge, isNotNull);
      expect(rig.nudge!.kind, ConfusionKind.reread);
      expect(rig.shown, hasLength(1));
    });

    test('a weak signal never shows', () {
      final rig = warmRig();

      rig.inject(kind: ConfusionKind.searchBurst, page: 10);

      expect(rig.nudge, isNull);
      expect(rig.engine.policy.waiting, 0);
    });

    test('a medium signal alone does not show', () {
      final rig = warmRig();

      rig.inject(kind: ConfusionKind.stall, page: 10);

      expect(rig.nudge, isNull);
    });

    test('a medium signal shows once another signal is near in time', () {
      final rig = warmRig();
      rig.inject(kind: ConfusionKind.stall, page: 10);
      rig.script.page(0, 10, 20).wait(0);
      rig.feed();

      rig.inject(kind: ConfusionKind.searchBurst, page: 3);
      rig.script.page(0, 11, 20);
      rig.feed();

      expect(rig.nudge?.kind, ConfusionKind.stall);
    });

    test('a medium signal shows when the same rule fires twice', () {
      final rig = warmRig();
      rig.inject(kind: ConfusionKind.stall, page: 9);

      rig.script.page(0, 11, 20);
      rig.feed();
      rig.inject(kind: ConfusionKind.stall, page: 10);

      expect(rig.nudge, isNotNull);
    });

    test('a medium signal does not use a partner from long ago', () {
      final rig = warmRig();
      rig.inject(kind: ConfusionKind.stall, page: 3);
      // Keep reading for 12 minutes, away from page 3.
      rig.read(0, 11, 36);

      rig.inject(kind: ConfusionKind.stall, page: 35);

      expect(rig.nudge, isNull);
    });

    test('a nudge about a chapter bounce is anchored where the reader is', () {
      final rig = warmRig();
      // The passage is far behind the reader, in chapter 2.
      rig.inject(kind: ConfusionKind.chapterBounce, section: 2, page: 5);
      rig.inject(kind: ConfusionKind.searchBurst, page: 10);

      rig.script.page(0, 11, 20);
      rig.feed();

      expect(rig.nudge?.kind, ConfusionKind.chapterBounce);
    });
  });

  group('timing', () {
    test('waits out the first two minutes of a session', () {
      final rig = Rig()..open();
      // The reader resumes on page 10 and looks back inside two minutes.
      rig.script.page(0, 10, 10).page(0, 11, 10).page(0, 12, 10);
      rig.script.page(0, 13, 10);
      rig.feed();
      rig.reread(12);
      expect(rig.signals, hasLength(1));
      expect(rig.nudge, isNull);
      expect(rig.engine.policy.waiting, 1);

      // The next page turn is past two minutes and the reader is still near.
      rig.script.wait(30).page(0, 14, 20);
      rig.feed();

      expect(rig.nudge?.kind, ConfusionKind.reread);
    });

    test('drops a signal once the reader moves three pages past it', () {
      final rig = Rig()..open();
      rig.script.read(0, 10, 14, 5);
      rig.feed();
      rig.reread(12);
      expect(rig.nudge, isNull);

      rig.read(0, 14, 18, dwell: 10);

      expect(rig.nudge, isNull);
      expect(rig.engine.policy.waiting, 0);
      expect(rig.shown, isEmpty);
    });

    test('drops a signal that waited three minutes', () {
      final rig = warmRig();
      rig.inject(page: 10);
      rig.dismiss();
      expect(rig.engine.policy.waiting, 0);

      // Dismissed, so a signal now would have to wait an hour. It is dropped
      // after three minutes instead, as the passage is no longer the news.
      rig.script.page(0, 11, 20);
      rig.feed();
      rig.inject(page: 10);
      // Three minutes on, still near the passage.
      rig.script.wait(100).page(0, 12, 100).page(0, 13, 10);
      rig.feed();

      expect(rig.nudge, isNull);
      expect(rig.engine.policy.waiting, 0);
    });

    test('holds off for 30 seconds after the app came back', () {
      final rig = warmRig();
      rig.read(0, 11, 14);
      rig.script.bg().wait(10).fg().wait(5);
      rig.feed();

      rig.inject(page: 12);
      expect(rig.nudge, isNull);

      rig.script.wait(40).page(0, 14, 20);
      rig.feed();

      expect(rig.nudge, isNotNull);
    });

    test('a nudge on screen goes when the reader has moved on', () {
      final rig = warmRig();
      rig.inject(page: 10);
      expect(rig.nudge, isNotNull);

      rig.read(0, 11, 13);
      expect(rig.nudge, isNotNull);

      rig.read(0, 13, 16);
      expect(rig.nudge, isNull);
    });

    test('only shows while the reader is near the passage', () {
      final rig = warmRig();

      rig.inject(page: 3);

      expect(rig.nudge, isNull);
    });
  });

  group('limits', () {
    test('cools down for 30 minutes and 25 pages after a nudge', () {
      final rig = warmRig()
        ..read(0, 11, 14)
        ..reread(12);
      expect(rig.shown, hasLength(1));

      // Another reread soon after is held back by time and by pages.
      rig.read(0, 14, 24);
      rig.reread(22);
      expect(rig.shown, hasLength(1));

      // Plenty of time and pages: allowed.
      rig.read(0, 24, 73);
      rig.reread(70);
      expect(rig.shown, hasLength(2));
    });

    test('needs 30 minutes as well as 25 pages', () {
      final rig = warmRig()
        ..read(0, 11, 14)
        ..reread(12);
      expect(rig.shown, hasLength(1));

      // 31 pages in ten minutes.
      rig.read(0, 14, 45, dwell: 20);
      rig.reread(45);

      expect(rig.shown, hasLength(1));
    });

    test('needs 25 pages as well as 30 minutes', () {
      final rig = warmRig()
        ..read(0, 11, 14)
        ..reread(12);
      expect(rig.shown, hasLength(1));

      // Over half an hour, but only 19 pages.
      rig.read(0, 14, 33, dwell: 110);
      rig.reread(30);
      expect(rig.shown, hasLength(1));

      rig.read(0, 33, 70, dwell: 20);
      rig.reread(66);
      expect(rig.shown, hasLength(2));
    });

    test('allows two nudges a session', () {
      final rig = warmRig()
        ..read(0, 11, 14)
        ..reread(12)
        ..read(0, 14, 73)
        ..reread(70)
        ..read(1, 0, 73)
        ..reread(70, section: 1);

      expect(rig.shown, hasLength(2));
      expect(
        rig.signals.where((s) => s.kind == ConfusionKind.reread),
        hasLength(3),
      );
    });

    test('caps nudges a day and starts over the next day', () {
      const config = InsightsConfig(
        nudgesPerSession: 10,
        nudgesPerDay: 2,
        nudgeCooldown: Duration.zero,
        nudgeCooldownPages: 0,
      );
      final rig = warmRig(config);

      for (var i = 0; i < 3; i++) {
        rig.read(0, 11 + i * 10, 20 + i * 10);
        rig.inject(page: 19 + i * 10);
        rig.read(0, 20 + i * 10, 24 + i * 10);
      }
      expect(rig.shown, hasLength(2));

      // A day later is a new day.
      rig.script.wait(24 * 3600).open();
      rig.feed();
      rig.read(1, 0, 10);
      rig.inject(section: 1, page: 9);

      expect(rig.shown, hasLength(3));
    });

    test('two dismissals in a row end nudges for the session', () {
      const config = InsightsConfig(
        nudgesPerSession: 10,
        nudgeCooldown: Duration.zero,
        nudgeCooldownPages: 0,
        dismissSuppression: Duration.zero,
      );
      final rig = warmRig(config);

      rig.inject(page: 10);
      rig.dismiss();
      rig.read(0, 11, 20);
      rig.inject(page: 19);
      rig.dismiss();
      rig.read(0, 20, 30);
      rig.inject(page: 29);

      expect(rig.shown, hasLength(2));
      expect(rig.nudge, isNull);

      // A new session starts over.
      rig.script.close().wait(60).open();
      rig.feed();
      rig.read(0, 30, 45);
      rig.inject(page: 44);
      expect(rig.shown, hasLength(3));
    });

    test('a dismissal holds nudges back for an hour', () {
      final rig = warmRig();
      rig.inject(page: 10);
      rig.dismiss();

      // Plenty of time and pages for the cooldown, but not for the hour.
      rig.read(0, 11, 60);
      rig.inject(page: 59);
      expect(rig.shown, hasLength(1));
      expect(rig.nudge, isNull);

      rig.read(0, 60, 100, dwell: 60);
      rig.read(1, 0, 10, dwell: 60);
      rig.inject(section: 1, page: 9);
      expect(rig.shown, hasLength(2));
    });

    test('a passage is nudged about once', () {
      const config = InsightsConfig(
        nudgeCooldown: Duration.zero,
        nudgeCooldownPages: 0,
      );
      final rig = warmRig(config);
      rig.inject(page: 10);
      rig.read(0, 11, 16);
      expect(rig.nudge, isNull);

      rig.read(0, 5, 11, dwell: 30);
      rig.inject(page: 10);

      expect(rig.shown, hasLength(1));
    });

    test('a passage can be nudged again once the reader has been a chapter further', () {
      const config = InsightsConfig(
        nudgeCooldown: Duration.zero,
        nudgeCooldownPages: 0,
      );
      final rig = warmRig(config);
      rig.inject(page: 10);
      // Reading on through the chapter, page by page, not jumping ahead.
      rig.read(0, 11, 100);
      rig.read(1, 0, 10);

      rig.script.page(0, 10, 30, NavigationCause.tocJump);
      rig.feed();
      rig.inject(page: 10);

      expect(rig.shown, hasLength(2));
    });
  });

  group('settings', () {
    test('no nudge with hints off, and nothing saved up for later', () {
      final rig = warmRig();
      rig.engine.policy.hintsEnabled = false;

      rig.inject(page: 10);
      rig.script.page(0, 11, 20);
      rig.feed();
      rig.engine.policy.hintsEnabled = true;
      rig.script.page(0, 12, 20);
      rig.feed();

      expect(rig.nudge, isNull);
      expect(rig.engine.policy.waiting, 0);
    });

    test('turning hints off hides the nudge on screen', () {
      final rig = warmRig();
      rig.inject(page: 10);
      expect(rig.nudge, isNotNull);

      rig.engine.policy.hintsEnabled = false;

      expect(rig.nudge, isNull);
    });

    test('signals are still detected with hints off', () {
      final rig = Rig();
      rig.engine.policy.hintsEnabled = false;
      rig
        ..open()
        ..read(0, 0, 14)
        ..reread(12);

      expect(rig.signals, hasLength(1));
      expect(rig.nudge, isNull);
    });
  });

  test('replaying a log shows no nudge but remembers the limits', () {
    final live = warmRig()
      ..read(0, 11, 14)
      ..reread(12);
    expect(live.shown, hasLength(1));

    final replayed = InsightsEngine(units: longBook(100));
    replayed.replay(live.script.records);

    expect(replayed.policy.current, isNull);
    expect(replayed.policy.waiting, 0);
  });
}
