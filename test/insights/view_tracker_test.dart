import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/insights/insights_config.dart';
import 'package:loremark/insights/reading_insights.dart';
import 'package:loremark/insights/reading_log.dart';
import 'package:loremark/insights/view_tracker.dart';

import 'insights_test_helpers.dart';

/// Runs [script] through a tracker and returns every event.
List<ViewEvent> run(LogScript script, [ViewTracker? tracker]) {
  final t = tracker ?? ViewTracker(tenSections(), const InsightsConfig());
  return [for (final record in script.records) ...t.add(record)];
}

List<PageView> ended(List<ViewEvent> events) => [
  for (final event in events)
    if (event is ViewEnded) event.view,
];

List<PageView> started(List<ViewEvent> events) => [
  for (final event in events)
    if (event is ViewStarted) event.view,
];

void main() {
  group('dwell', () {
    test('is the time until the reader moved on', () {
      final views = ended(run(LogScript().open().read(0, 0, 3, 30)));

      // The third page is still being read.
      expect(views, hasLength(2));
      expect(views.map((v) => v.dwellSec), [30, 30]);
      expect(views.map((v) => v.end), everyElement(ViewEnd.moved));
      expect(views.first.move, MoveKind.forwardPage);
      expect(views.first.forwardUnits, 200);
      expect(views.first.nextCause, NavigationCause.pageForward);
    });

    test('takes out the time in the background but keeps what came before', () {
      final script = LogScript()
          .open()
          .page(0, 0, 20)
          .bg()
          .wait(120)
          .fg()
          .wait(10)
          .pos(0, 0.1);

      final views = ended(run(script));

      expect(views.single.dwellSec, 30);
      expect(views.single.hadBackground, isTrue);
      // A short trip to the background does not end the session.
      expect(views.single.sessionId, 0);
    });

    test('a long stay in the background ends the session and the view', () {
      final script = LogScript()
          .open()
          .page(0, 0, 20)
          .bg()
          .wait(400)
          .fg()
          .wait(15)
          .pos(0, 0.1);

      final events = run(script);

      final views = ended(events);
      expect(views, hasLength(2));
      expect(views[0].end, ViewEnd.background);
      expect(views[0].dwellSec, 20);
      expect(views[0].endMs, baseMs + 20000);
      // The page left up on the screen starts a new view in a new session.
      expect(views[1].resumed, isTrue);
      expect(views[1].sessionId, isNot(views[0].sessionId));
      expect(views[1].dwellSec, 15);
      final lifecycle = events.whereType<LifecycleEvent>().last;
      expect(lifecycle.kind, LifecycleKind.foreground);
      expect(lifecycle.newSession, isTrue);
    });

    test('moving after a long background with no foreground record', () {
      final script = LogScript()
          .open()
          .page(0, 0, 20)
          .bg()
          .wait(900)
          .pos(0, 0.1);

      final views = ended(run(script));

      expect(views.single.end, ViewEnd.background);
      expect(views.single.dwellSec, 20);
    });

    test('is only credited as one clamped dwell after a crash', () {
      final crashed = ended(run(LogScript().open().page(0, 0, 30).open()));
      expect(crashed.single.end, ViewEnd.lost);
      expect(crashed.single.dwellSec, 30);

      final longGone = ended(run(LogScript().open().page(0, 0, 86400).open()));
      expect(longGone.single.end, ViewEnd.lost);
      expect(longGone.single.dwellSec, 120);
      expect(longGone.single.activeSec, 120);
    });

    test('a crash while in the background credits the time before it', () {
      final views = ended(
        run(LogScript().open().page(0, 0, 25).bg().wait(5000).open()),
      );

      expect(views.single.end, ViewEnd.lost);
      expect(views.single.dwellSec, 25);
      expect(views.single.endMs, baseMs + 25000);
    });

    test('a normal close ends the view and the session', () {
      final script = LogScript().open().page(0, 0, 45).close();

      final views = ended(run(script));

      expect(views.single.end, ViewEnd.closed);
      expect(views.single.dwellSec, 45);
    });

    test(
      'counts only reading: flip-throughs are zero, long stays are capped',
      () {
        final script = LogScript()
            .open()
            .page(0, 0, 2)
            .page(0, 1, 500)
            .page(0, 2, 60)
            .pos(0, 0.3);

        final views = ended(run(script));

        expect(views.map((v) => v.activeSec), [0, 120, 60]);
        expect(views[1].dwellSec, 500);
      },
    );

    test(
      'a clock that goes backward gives a zero dwell, not a negative one',
      () {
        final script = LogScript().open().pos(0, 0).wait(-5).pos(0, 0.1);

        final views = ended(run(script));

        expect(views.single.dwellSec, 0);
      },
    );
  });

  group('turns', () {
    test('a finished section and the start of the next are one turn', () {
      final script = LogScript()
          .open()
          .page(0, 9, 30)
          .pos(0, 1)
          .pos(1, 0)
          .wait(40)
          .pos(1, 0.1);

      final events = run(script);

      final views = ended(events);
      expect(views, hasLength(2));
      // The page before the turn ends at the end of the section...
      expect(views[0].nextOffset, 2000);
      expect(views[0].move, MoveKind.forwardPage);
      expect(views[0].forwardUnits, 200);
      // ...and the first page of the next section is the next view, not the
      // transient end of the last one.
      expect(views[1].section, 1);
      expect(views[1].dwellSec, 40);
    });

    test('positions less than 300 ms apart are merged', () {
      final script = LogScript()
          .open()
          .page(0, 0, 10)
          .pos(0, 0.1)
          .wait(0.2)
          .pos(0, 0.2)
          .wait(20)
          .pos(0, 0.3);

      final views = ended(run(script));

      expect(views.map((v) => v.progression), [0, 0.2]);
    });

    test('the same position again is ignored', () {
      final script = LogScript()
          .open()
          .page(0, 0, 10)
          .pos(0, 0)
          .wait(10)
          .pos(0, 0.1);

      final views = ended(run(script));

      expect(views.single.dwellSec, 20);
    });
  });

  group('moves', () {
    PageView after(NavigationCause cause, int section, double progression) {
      final script = LogScript()
          .open()
          .page(2, 5, 30)
          .pos(section, progression, cause);
      return ended(run(script)).single;
    }

    test('a page forward or back is a page', () {
      expect(
        after(NavigationCause.pageForward, 2, 0.6).move,
        MoveKind.forwardPage,
      );
      expect(
        after(NavigationCause.pageBackward, 2, 0.4).move,
        MoveKind.backwardPage,
      );
      expect(after(NavigationCause.swipe, 2, 0.6).move, MoveKind.forwardPage);
      expect(after(NavigationCause.swipe, 2, 0.4).move, MoveKind.backwardPage);
    });

    test('a contents or search jump is a jump however short', () {
      expect(after(NavigationCause.tocJump, 2, 0.6).move, MoveKind.forwardJump);
      expect(
        after(NavigationCause.searchJump, 1, 0.5).move,
        MoveKind.backwardJump,
      );
    });

    test('a swipe over several pages is a jump, but not the page buttons', () {
      // Three pages is 600 units: over 1.5 pages for a swipe, under 4 for the
      // buttons, which a larger font would otherwise turn into jumps.
      expect(after(NavigationCause.swipe, 2, 0.8).move, MoveKind.forwardJump);
      expect(
        after(NavigationCause.pageForward, 2, 0.8).move,
        MoveKind.forwardPage,
      );
      expect(
        after(NavigationCause.pageForward, 4, 0.5).move,
        MoveKind.forwardJump,
      );
    });

    test('knows the direction and whether the page was seen before', () {
      final script = LogScript()
          .open()
          .read(0, 0, 4, 30)
          .page(0, 1, 30, NavigationCause.pageBackward)
          .page(0, 2, 30)
          .pos(0, 0.3);

      final views = started(run(script));

      expect(views[3].isRevisit, isFalse);
      expect(views[4].arrivedBackward, isTrue);
      expect(views[4].isRevisit, isTrue);
      expect(views[5].arrivedBackward, isFalse);
      expect(views[5].isRevisit, isTrue);
    });

    test('learns the page length from forward turns', () {
      final tracker = ViewTracker(tenSections(), const InsightsConfig());
      expect(tracker.pageUnits, 200);

      run(LogScript().open().read(0, 0, 8, 30), tracker);

      expect(tracker.pageUnits, 200);

      // Pages of 500 units: the median follows.
      final bigPages = LogScript()
          .open()
          .pos(5, 0)
          .wait(30)
          .pos(5, 0.25)
          .wait(30)
          .pos(5, 0.5)
          .wait(30)
          .pos(5, 0.75)
          .wait(30)
          .pos(6, 0)
          .wait(30)
          .pos(6, 0.25)
          .wait(30)
          .pos(6, 0.5);
      final big = ViewTracker(tenSections(), const InsightsConfig());
      run(bigPages, big);
      // Quarter-section turns are 500 units, a jump for a swipe but a page
      // for the buttons, and they teach the tracker.
      expect(big.pageUnits, 500);
    });
  });

  group('sessions', () {
    test('a pause longer than the session gap starts a new session', () {
      final script = LogScript()
          .open()
          .page(0, 0, 40)
          .page(0, 1, 11 * 60)
          .page(0, 2, 30)
          .pos(0, 0.3);

      final views = ended(run(script));

      expect(views[0].sessionId, views[1].sessionId);
      expect(views[2].sessionId, isNot(views[1].sessionId));
      // The long page still belongs to the session it began in.
      expect(views[1].dwellSec, 660);
    });

    test('a shorter pause keeps the session', () {
      final script = LogScript()
          .open()
          .page(0, 0, 9 * 60)
          .page(0, 1, 30)
          .pos(0, 0.2);

      final views = ended(run(script));

      expect(views[0].sessionId, views[1].sessionId);
    });

    test('closing and opening again starts a session', () {
      final script = LogScript()
          .open()
          .page(0, 0, 30)
          .close()
          .wait(20)
          .open()
          .page(0, 1, 30)
          .pos(0, 0.2);

      final views = ended(run(script));

      expect(views[0].sessionId, isNot(views[1].sessionId));
    });

    test('a position after a close without an open starts a session', () {
      final script = LogScript()
          .open()
          .page(0, 0, 30)
          .close()
          .wait(5)
          .pos(0, 0.2)
          .wait(30)
          .pos(0, 0.3);

      final views = ended(run(script));

      expect(views[0].sessionId, isNot(views[1].sessionId));
    });

    test('each view remembers the time zone in force', () {
      final script = LogScript(tz: -420).open().page(0, 0, 30).pos(0, 0.1);

      expect(ended(run(script)).single.tz, -420);
    });
  });

  group('furthest', () {
    test('is the furthest position shown, not the latest', () {
      final tracker = ViewTracker(tenSections(), const InsightsConfig());
      run(
        LogScript()
            .open()
            .page(3, 5, 30)
            .page(1, 2, 30, NavigationCause.tocJump)
            .page(1, 3, 30),
        tracker,
      );

      expect(tracker.furthest!.sectionIndex, 3);
      expect(tracker.furthest!.progression, 0.5);
    });

    test('a furthest record from compaction counts', () {
      final tracker = ViewTracker(tenSections(), const InsightsConfig());
      tracker.add(const FurthestRecord(section: 7, progression: 0.2, t: 1));
      run(LogScript().open().page(2, 0, 30), tracker);

      expect(tracker.furthest!.sectionIndex, 7);
    });

    test('is null before anything is read', () {
      expect(
        ViewTracker(tenSections(), const InsightsConfig()).furthest,
        isNull,
      );
    });
  });
}
