import 'package:flutter_test/flutter_test.dart';

import '../../tool/acceptance/harness.dart' show captureFailsRun;
import '../../tool/acceptance/options.dart';
import '../../tool/acceptance/privacy.dart';
import '../../tool/acceptance/report.dart';

void main() {
  test('defaults to the spec: 20 trials, report in build/acceptance', () {
    final options = parseOptions(const []);

    expect(options.trials, 20);
    expect(options.install, isTrue);
    expect(options.reportDir, 'build/acceptance');
    expect(options.pcap, isNull);
    expect(options.allowedHosts, isEmpty);
    expect(options.prepareDevice, isNull);
  });

  test('parses every option', () {
    final options = parseOptions([
      '--serial',
      'emulator-5556',
      '--adb',
      '/sdk/adb',
      '--apk',
      'app.apk',
      '--trials',
      '5',
      '--seed',
      '7',
      '--chapters',
      '8',
      '--words',
      '1500',
      '--report',
      'out',
      '--pcap',
      '/tmp/e.pcap',
      '--baseline-seconds',
      '10',
      '--allow-host',
      'API.Example.com',
      '--allow-host',
      '*.ai.example.com',
      '--skip-offline',
      '--skip-privacy',
      '--prepare-device',
      '--no-install',
    ]);

    expect(options.ci, isFalse);
    expect(options.serial, 'emulator-5556');
    expect(options.adb, '/sdk/adb');
    expect(options.apk, 'app.apk');
    expect(options.trials, 5);
    expect(options.seed, 7);
    expect(options.chapters, 8);
    expect(options.words, 1500);
    expect(options.reportDir, 'out');
    expect(options.pcap, '/tmp/e.pcap');
    expect(options.baselineSeconds, 10);
    expect(options.allowedHosts, {'api.example.com', '*.ai.example.com'});
    expect(options.skipOffline, isTrue);
    expect(options.skipPrivacy, isTrue);
    expect(options.prepareDevice, isTrue);
    expect(options.install, isFalse);
  });

  test('recognises help', () {
    expect(parseOptions(['--help']).help, isTrue);
    expect(parseOptions(['-h']).help, isTrue);
  });

  test('CI cannot silently skip acceptance requirements', () {
    expect(parseOptions(['--ci', '--pcap', '/tmp/e.pcap']).ci, isTrue);
    for (final args in [
      ['--ci', '--trials', '19'],
      ['--ci', '--skip-offline'],
      ['--ci', '--skip-privacy'],
      ['--ci'],
    ]) {
      expect(() => parseOptions(args), throwsA(isA<UsageError>()));
    }
  });

  test('--capture-optional only relaxes the capture, and only in CI', () {
    final relaxed = parseOptions([
      '--ci',
      '--capture-optional',
      '--pcap',
      '/tmp/e.pcap',
    ]);
    expect(relaxed.ci, isTrue);
    expect(relaxed.captureOptional, isTrue);
    expect(
      parseOptions(['--ci', '--pcap', '/tmp/e.pcap']).captureOptional,
      isFalse,
    );
    // It cannot be used to skip the other CI requirements.
    expect(
      () => parseOptions(['--ci', '--capture-optional', '--skip-offline']),
      throwsA(isA<UsageError>()),
    );
    expect(
      () => parseOptions(['--ci', '--capture-optional', '--trials', '5']),
      throwsA(isA<UsageError>()),
    );
    expect(
      () => parseOptions(['--capture-optional']),
      throwsA(isA<UsageError>()),
    );
  });

  group('an unverified capture and the exit code', () {
    const counted = PrivacyResult(
      uid: 10216,
      before: UidTraffic(),
      after: UidTraffic(),
      uidsSeen: 16,
      captureRequired: true,
      pcapNote: 'could not verify the capture',
    );
    final ci = parseOptions(['--ci', '--pcap', '/tmp/e.pcap']);
    final ciOptional = parseOptions([
      '--ci',
      '--capture-optional',
      '--pcap',
      '/tmp/e.pcap',
    ]);

    test('fails a plain --ci run, as before', () {
      expect(captureFailsRun(ci, counted), isTrue);
    });

    test('does not fail a --capture-optional run', () {
      expect(captureFailsRun(ciOptional, counted), isFalse);
    });

    test('never fails a run that is not --ci', () {
      expect(captureFailsRun(parseOptions(const []), counted), isFalse);
    });

    test('is still not a pass: the report says INCONCLUSIVE', () {
      expect(counted.captureInconclusive, isTrue);
      expect(counted.audit, isNull);
    });

    test('the app counters still fail the run when the app sent bytes', () {
      const noisy = PrivacyResult(
        uid: 10216,
        before: UidTraffic(),
        after: UidTraffic(txBytes: 500, txPackets: 3),
        uidsSeen: 16,
        captureRequired: true,
        pcapNote: 'could not verify the capture',
      );
      expect(noisy.netstatsPass, isFalse);
      expect(noisy.pass, isFalse);
      // captureFailsRun only covers the capture; the report's pass covers this.
      expect(captureFailsRun(ciOptional, noisy), isFalse);
    });
  });

  test('rejects unknown flags, missing values and bad numbers', () {
    expect(() => parseOptions(['--bogus']), throwsA(isA<UsageError>()));
    expect(() => parseOptions(['--serial']), throwsA(isA<UsageError>()));
    expect(
      () => parseOptions(['--trials', 'many']),
      throwsA(isA<UsageError>()),
    );
    expect(() => parseOptions(['--trials', '0']), throwsA(isA<UsageError>()));
    expect(() => parseOptions(['--chapters', '2']), throwsA(isA<UsageError>()));
  });

  test('the usage text documents every flag the parser accepts', () {
    for (final flag in [
      '--serial',
      '--adb',
      '--apk',
      '--no-install',
      '--trials',
      '--seed',
      '--chapters',
      '--words',
      '--report',
      '--pcap',
      '--baseline-seconds',
      '--allow-host',
      '--skip-offline',
      '--skip-privacy',
      '--prepare-device',
      '--ci',
      '--capture-optional',
      '--help',
    ]) {
      expect(usage, contains(flag));
    }
  });
}
