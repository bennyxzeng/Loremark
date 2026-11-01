import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/acceptance/metrics.dart';
import '../../tool/acceptance/privacy.dart';
import '../../tool/acceptance/report.dart';

PagePosition _at(int page) => PagePosition(section: 3, page: page, pages: 18);

TrialResult _trial(int index, {bool pass = true, int? distance = 0}) =>
    TrialResult(
      index: index,
      kind: index.isEven ? 'kill-9' : 'force-stop',
      pageTurns: 4,
      pass: pass,
      durationMs: 25000 + index,
      last: _at(9),
      saved: _at(9),
      restored: _at(9 + (distance ?? 0)),
      restoredDistance: distance,
      savedDistance: 0,
      note: pass ? null : 'restored $distance pages away | odd',
    );

PrivacyResult _privacy({int tx = 0, PcapAudit? audit}) => PrivacyResult(
  uid: 10216,
  before: const UidTraffic(),
  after: UidTraffic(txBytes: tx, txPackets: tx == 0 ? 0 : 1),
  uidsSeen: 16,
  audit: audit,
  pcapNote: audit == null ? 'no capture given' : null,
);

AcceptanceReport _report({
  int trials = 20,
  int failing = 0,
  PrivacyResult? privacy,
  TrialResult? offline,
}) => AcceptanceReport(
  startedAt: DateTime.utc(2026, 11, 1, 18),
  device: const {'model': 'sdk_gphone64_x86_64', 'android': '16 (API 36)'},
  seed: 403,
  forceQuits: [
    for (var i = 1; i <= trials; i++)
      _trial(i, pass: i > failing, distance: i > failing ? 0 : 2),
  ],
  openFromLibrary: _trial(0),
  offline: offline,
  privacy: privacy ?? _privacy(),
);

void main() {
  group('AcceptanceReport', () {
    test(
      'passes only when 20 of 20 force-quits and every other check pass',
      () {
        final report = _report();

        expect(report.forceQuitPasses, 20);
        expect(report.forceQuitComplete, isTrue);
        expect(report.pass, isTrue);
      },
    );

    test('one trial two pages off fails the whole run', () {
      final report = _report(failing: 1);

      expect(report.forceQuitPasses, 19);
      expect(report.pass, isFalse);
    });

    test('fewer trials than the spec asks for is incomplete, not complete', () {
      final report = _report(trials: 5);

      expect(report.forceQuitPass, isTrue);
      expect(report.forceQuitComplete, isFalse);
      expect(report.toMarkdown(), contains('INCOMPLETE'));
      expect(report.toMarkdown(), contains('fewer trials than the spec'));
    });

    test('any app traffic fails the privacy check', () {
      final report = _report(privacy: _privacy(tx: 512));

      expect(report.privacy!.netstatsPass, isFalse);
      expect(report.pass, isFalse);
      expect(report.toMarkdown(), contains('512 B sent'));
    });

    test('counters that could not be read are a failure, not a zero', () {
      const unmeasured = PrivacyResult(
        uid: 10216,
        before: null,
        after: null,
        uidsSeen: 0,
      );

      expect(unmeasured.netstatsPass, isFalse);
      expect(unmeasured.pass, isFalse);
    });

    test("a supplied capture that can't be verified is inconclusive", () {
      const missing = PrivacyResult(
        uid: 10216,
        before: UidTraffic(),
        after: UidTraffic(),
        uidsSeen: 16,
        captureRequired: true,
        pcapNote: 'stale capture',
      );
      expect(missing.netstatsPass, isTrue);
      expect(missing.captureInconclusive, isTrue);
      // The UID counters still decide; the capture row never says PASS.
      expect(missing.pass, isTrue);
      final markdown = _report(privacy: missing).toMarkdown();
      expect(markdown, contains('| INCONCLUSIVE |'));
      expect(
        markdown,
        isNot(contains('Capture policy (HTTPS, hosts, markers) | PASS')),
      );
    });

    test('a failing offline trial fails the run', () {
      final report = _report(offline: _trial(0, pass: false, distance: null));

      expect(report.pass, isFalse);
    });
  });

  group('JSON', () {
    test('round-trips through jsonDecode with the numbers a CI step reads', () {
      final decoded = jsonDecode(_report(failing: 2).toJsonString());

      expect(decoded['pass'], isFalse);
      expect(decoded['forceQuit']['required'], 20);
      expect(decoded['forceQuit']['trials'], 20);
      expect(decoded['forceQuit']['passed'], 18);
      expect(decoded['forceQuit']['results'], hasLength(20));
      expect(decoded['forceQuit']['results'][0]['pass'], isFalse);
      expect(decoded['forceQuit']['results'][19]['last']['page'], 9);
      expect(decoded['privacy']['appUid'], 10216);
      expect(decoded['privacy']['netstatsDelta']['txBytes'], 0);
      expect(decoded['seed'], 403);
    });
  });

  group('Markdown', () {
    test('has a summary, a row per trial and the verdict', () {
      final markdown = _report(failing: 1).toMarkdown();

      expect(markdown, contains('**FAIL**'));
      expect(markdown, contains('19 of 20 within one page (spec: 20 of 20)'));
      expect(markdown, contains('## Force-quit trials'));
      expect('\n| 20 | kill-9 |'.allMatches(markdown), hasLength(1));
      expect(markdown, contains('| s3 p10/18 |'));
    });

    test('keeps a table row on one line when a note contains a pipe', () {
      final markdown = _report(failing: 1).toMarkdown();
      final row = markdown
          .split('\n')
          .firstWhere((l) => l.startsWith('| 1 | force-stop'));

      expect(row, contains('2 / 0'));
      expect(row, contains('odd'));
      expect(row.split('|').length, 11);
    });

    test('says when no capture was given and what to do', () {
      final markdown = _report().toMarkdown();

      expect(markdown, contains('Capture policy'));
      expect(markdown, contains('no capture given'));
    });
  });
}
