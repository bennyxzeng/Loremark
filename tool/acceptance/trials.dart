import 'dart:async';
import 'dart:math';

import 'adb.dart';
import 'metrics.dart';
import 'privacy.dart';
import 'report.dart';
import 'seed.dart';
import 'uiautomator.dart';

const _activity = '$appPackage/.MainActivity';

/// Drives the installed debug build through adb.
///
/// Page turns are `input tap` on the "Next page" button, whose bounds come
/// from one `uiautomator dump` per launch (the layout is static). A page turn
/// is confirmed from the app's own `LOREMARK_POSITION` logcat line, never from
/// another dump: a dump takes seconds and can fail while the page animates.
class AppDriver {
  AppDriver(this.adb, this.seeder, {this.log = _noLog});

  final Adb adb;
  final AppSeeder seeder;
  final void Function(String message) log;

  static void _noLog(String _) {}

  /// Page counts per section seen in the last launch, to turn a saved
  /// progression into a page.
  final pagesOfSection = <int, int>{};

  Future<void> forceStop() async {
    await adb.shell('am force-stop $appPackage');
    await _waitUntilGone();
  }

  /// SIGKILL through `run-as`, the way the OS kills a background app under
  /// memory pressure. Plain `adb shell kill` is denied for the app's UID.
  Future<void> killNine() async {
    final pids = (await adb.shell(
      'pidof $appPackage',
      check: false,
    )).trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (pids.isEmpty) throw StateError('The app is not running to be killed');
    await adb.shell('run-as $appPackage kill -9 ${pids.join(' ')}');
    await _waitUntilGone();
  }

  Future<void> _waitUntilGone() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      final pids = await adb.shell('pidof $appPackage', check: false);
      if (pids.trim().isEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError('The app is still running after being killed');
  }

  /// Starts the app with a clean log, so every position line read afterwards
  /// belongs to this launch.
  Future<void> launch() async {
    pagesOfSection.clear();
    await adb.clearLogcat();
    await adb.shell('am start -n $_activity');
  }

  Future<List<PagePosition>> positions() async {
    final lines = parsePositionLines(await adb.positionLogcat());
    for (final p in lines) {
      pagesOfSection[p.section] = p.pages;
    }
    return lines;
  }

  /// Dumps the UI until a node whose description contains [needle] appears.
  ///
  /// A dump can fail or come back sparse right after a cold start or during an
  /// animation, so a miss is not an error until [timeout].
  Future<UiNode> waitForNode(
    String needle, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      try {
        final node = findByDesc(parseUiDump(await adb.uiDump()), needle);
        if (node != null) return node;
      } on CommandTimeout {
        // Try again until the deadline.
      }
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('No "$needle" on screen', timeout);
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Waits for the reader to report its position and then stop moving.
  ///
  /// Readium can report an initial locator before it jumps to the saved one,
  /// so the first line is not the answer: the answer is the last line once
  /// nothing new has arrived for [quiet].
  Future<PagePosition> waitSettled({
    Duration quiet = const Duration(milliseconds: 2500),
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var seen = 0;
    var changedAt = DateTime.now();
    List<PagePosition> latest = const [];
    while (DateTime.now().isBefore(deadline)) {
      latest = await positions();
      if (latest.length != seen) {
        seen = latest.length;
        changedAt = DateTime.now();
      } else if (seen > 0 && DateTime.now().difference(changedAt) >= quiet) {
        return latest.last;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    throw TimeoutException(
      seen == 0
          ? 'The reader never reported a position'
          : 'The reader kept moving',
      timeout,
    );
  }

  /// Taps "Next page" and waits for the page to change; returns the new count
  /// of position lines.
  Future<List<PagePosition>> turnPage(UiNode button, int linesBefore) async {
    final bounds = button.bounds!;
    await adb.tap(bounds.centerX, bounds.centerY);
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(deadline)) {
      final lines = await positions();
      if (lines.length > linesBefore) return lines;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw TimeoutException('The page did not turn', const Duration(seconds: 8));
  }
}

/// Runs the trials of one harness session.
class TrialRunner {
  TrialRunner({
    required this.adb,
    required this.driver,
    required this.seeder,
    required this.random,
    required this.chapters,
    this.log = print,
  });

  final Adb adb;
  final AppDriver driver;
  final AppSeeder seeder;
  final Random random;
  final int chapters;
  final void Function(String message) log;

  /// When airplane mode was on and the reader was in use, for the capture
  /// check "nothing routable left the guest".
  final offlineWindows = <TimeWindow>[];

  /// Taps the book in the library and checks that the reader opens.
  Future<TrialResult> openFromLibrary() async {
    final timer = Stopwatch()..start();
    await driver.forceStop();
    await seeder.seedLibrary(lastOpened: false);
    await seeder.clearPosition();
    await driver.launch();
    try {
      final card = await driver.waitForNode(seeder.book.title);
      await adb.tap(card.bounds!.centerX, card.bounds!.centerY);
      final next = await driver.waitForNode('Next page');
      final first = await driver.waitSettled();
      final lines = await driver.turnPage(
        next,
        (await driver.positions()).length,
      );
      final second = lines.last;
      final moved = pageDistance(first, second) == 1;
      return TrialResult(
        index: 0,
        kind: 'open-from-library',
        pageTurns: 1,
        pass: moved,
        durationMs: timer.elapsedMilliseconds,
        before: first,
        last: second,
        note: moved
            ? 'tapped "${seeder.book.title}", reader opened at $first'
            : 'page turn moved $first to $second',
      );
    } on Object catch (error) {
      return _failed(0, 'open-from-library', timer, '$error');
    }
  }

  /// One force-quit trial: seed a mid-chapter position, open the book, turn
  /// 1 to 8 pages, kill the app (SIGKILL when [useKillNine], else
  /// `am force-stop`) a random moment after the last page appeared, relaunch,
  /// and compare.
  Future<TrialResult> forceQuit(int index, {required bool useKillNine}) async {
    final kind = useKillNine ? 'kill-9' : 'force-stop';
    final timer = Stopwatch()..start();
    try {
      await driver.forceStop();
      final section = 1 + random.nextInt(chapters - 2);
      final progression = double.parse(
        (0.05 + random.nextDouble() * 0.40).toStringAsFixed(3),
      );
      await seeder.seedLibrary(lastOpened: true);
      await seeder.seedPosition(section, progression);
      await driver.launch();
      final next = await driver.waitForNode('Next page');
      final before = await driver.waitSettled();
      if (before.section != section) {
        return _failed(
          index,
          kind,
          timer,
          'opened at $before, not in the seeded section $section',
        );
      }

      // Stay in the chapter: leave one page of room before its end.
      final room = max(1, before.pages - 2 - before.page);
      final turns = 1 + random.nextInt(min(8, room));
      var lines = await driver.positions();
      for (var i = 0; i < turns; i++) {
        lines = await driver.turnPage(next, lines.length);
      }
      final last = lines.last;

      // The save of the newest page may still be in flight; that is the
      // point of killing now rather than after a pause.
      await Future<void>.delayed(Duration(milliseconds: random.nextInt(300)));
      if (useKillNine) {
        await driver.killNine();
      } else {
        await driver.forceStop();
      }

      final savedFile = await seeder.readPosition();
      PagePosition? saved;
      final pagesOfSaved = savedFile == null
          ? null
          : driver.pagesOfSection[savedFile.section];
      if (savedFile != null && pagesOfSaved != null) {
        saved = PagePosition.fromProgression(
          section: savedFile.section,
          progression: savedFile.progression,
          pages: pagesOfSaved,
        );
      }

      await driver.launch();
      await driver.waitForNode('Next page');
      final restored = await driver.waitSettled();

      final restoredDistance = pageDistance(last, restored);
      final savedDistance = saved == null ? null : pageDistance(last, saved);
      final pass =
          restoredDistance != null &&
          restoredDistance <= 1 &&
          (savedDistance == null || savedDistance <= 1);
      return TrialResult(
        index: index,
        kind: kind,
        pageTurns: turns,
        pass: pass,
        durationMs: timer.elapsedMilliseconds,
        before: before,
        last: last,
        saved: saved,
        restored: restored,
        restoredDistance: restoredDistance,
        savedDistance: savedDistance,
        note: pass
            ? null
            : restoredDistance == null
            ? 'positions not comparable'
            : 'restored $restoredDistance pages away',
      );
    } on Object catch (error) {
      return _failed(index, kind, timer, '$error');
    }
  }

  /// Airplane mode on: the book still opens, pages still turn, and a
  /// force-stop still restores the position. Airplane mode is always switched
  /// back off.
  Future<TrialResult> offline() async {
    final timer = Stopwatch()..start();
    try {
      await setAirplane(true);
      final windowStart = DateTime.now().add(const Duration(seconds: 5));
      await driver.forceStop();
      await seeder.seedLibrary(lastOpened: true);
      await seeder.seedPosition(2, 0.2);
      await driver.launch();
      final next = await driver.waitForNode('Next page');
      final before = await driver.waitSettled();
      var lines = await driver.positions();
      const turns = 3;
      for (var i = 0; i < turns; i++) {
        lines = await driver.turnPage(next, lines.length);
      }
      final last = lines.last;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await driver.forceStop();
      await driver.launch();
      await driver.waitForNode('Next page');
      final restored = await driver.waitSettled();
      offlineWindows.add(
        TimeWindow(
          windowStart.microsecondsSinceEpoch,
          DateTime.now().microsecondsSinceEpoch,
        ),
      );
      final distance = pageDistance(last, restored);
      final pass = distance != null && distance <= 1;
      return TrialResult(
        index: 0,
        kind: 'offline',
        pageTurns: turns,
        pass: pass,
        durationMs: timer.elapsedMilliseconds,
        before: before,
        last: last,
        restored: restored,
        restoredDistance: distance,
        note: 'airplane mode on, book opened, restored after force-stop',
      );
    } on Object catch (error) {
      return _failed(0, 'offline', timer, '$error');
    } finally {
      await setAirplane(false);
    }
  }

  /// Switches airplane mode and waits until the setting and the network agree.
  Future<void> setAirplane(bool on) async {
    await adb.shell(
      'cmd connectivity airplane-mode ${on ? 'enable' : 'disable'}',
    );
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      final setting = (await adb.shell('settings get global airplane_mode_on'))
          .trim();
      final reachable = await _canReachInternet();
      if (setting == (on ? '1' : '0') && reachable == !on) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw StateError('Airplane mode ${on ? 'on' : 'off'} did not take effect');
  }

  /// Whether the device can resolve a public name. GitHub's hosted runners
  /// drop outbound ICMP, so a ping reply can't be the signal; ping prints its
  /// `PING host (address)` header only once the name resolved, and airplane
  /// mode makes resolution fail.
  Future<bool> _canReachInternet() async {
    final result = await adb.run([
      'shell',
      'ping -c 1 -W 2 connectivitycheck.gstatic.com',
    ], timeout: const Duration(seconds: 15));
    return result.stdout.contains('PING connectivitycheck.gstatic.com (');
  }

  TrialResult _failed(int index, String kind, Stopwatch timer, String why) {
    log('  trial $index ($kind) failed: $why');
    return TrialResult(
      index: index,
      kind: kind,
      pageTurns: 0,
      pass: false,
      durationMs: timer.elapsedMilliseconds,
      note: why.replaceAll('|', '/').replaceAll('\n', ' '),
    );
  }
}
