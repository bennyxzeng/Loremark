import 'dart:io';
import 'dart:math';

import 'adb.dart';
import 'options.dart';
import 'pcap.dart';
import 'privacy.dart';
import 'report.dart';
import 'seed.dart';
import 'trials.dart';

/// Runs every check and writes the report. Returns the process exit code:
/// 0 all passed, 1 a check failed, 2 the harness could not run.
Future<int> runHarness(
  Options options, {
  void Function(String) log = print,
}) async {
  final executable = findAdb(override: options.adb);
  final AdbDevice device;
  try {
    device = chooseDevice(
      await Adb.listDevices(executable),
      requested: options.serial,
      environmentSerial: Platform.environment['ANDROID_SERIAL'],
    );
  } on AdbException catch (error) {
    log('$error');
    return 2;
  }
  final adb = Adb(executable: executable, serial: device.serial);
  log('Device: ${device.serial}');

  final scratch = Directory.systemTemp.createTempSync('loremark-acceptance-');
  final reportDir = Directory(options.reportDir)..createSync(recursive: true);
  final restore = <Future<void> Function()>[];
  TrialRunner? runner;
  try {
    final info = await _deviceInfo(adb);
    log('Android ${info['android']}, ${info['model']}, ${info['screen']}');

    if (options.install) {
      final apk = options.apk ?? _defaultApk();
      if (apk == null || !File(apk).existsSync()) {
        log(
          'No debug APK found. Run: flutter build apk --debug '
          '--target-platform android-x64   (or pass --apk / --no-install)',
        );
        return 2;
      }
      log('Installing $apk');
      await adb.install(apk);
    }
    if ((await adb.run(['shell', 'run-as $appPackage true'])).exitCode != 0) {
      log(
        '$appPackage is not installed as a debuggable build (run-as failed).',
      );
      return 2;
    }

    if (options.prepareDevice ?? device.isEmulator) {
      restore.addAll(await _prepareDevice(adb));
    }

    final book = buildHarnessBook(
      chapters: options.chapters,
      wordsPerChapter: options.words,
      seed: options.seed,
    );
    log(
      'Book ${book.id.substring(0, 12)}: ${options.chapters} chapters, '
      '${(book.bytes.length / 1024).round()} KB',
    );
    final seeder = AppSeeder(adb, book, scratch);
    final random = Random(options.seed);
    final driver = AppDriver(adb, seeder, log: log);
    runner = TrialRunner(
      adb: adb,
      driver: driver,
      seeder: seeder,
      random: random,
      chapters: options.chapters,
      log: log,
    );
    // Airplane mode is a device-wide setting: never leave it on.
    await runner.setAirplane(false);
    await driver.forceStop();

    final uid = await _appUid(adb);
    final notes = <String>[];
    final privacy = !options.skipPrivacy;
    final netBefore = privacy ? await _netstats(adb) : null;

    // Control window: the OS's own traffic with the app not running.
    final pcapFile = options.pcap == null ? null : File(options.pcap!);
    TimeWindow? control;
    if (privacy && pcapFile != null && options.baselineSeconds > 0) {
      log('Recording ${options.baselineSeconds}s of OS-only traffic');
      final start = DateTime.now();
      await Future<void>.delayed(Duration(seconds: options.baselineSeconds));
      control = TimeWindow(
        start.microsecondsSinceEpoch,
        DateTime.now().microsecondsSinceEpoch,
      );
    }

    final sessionStart = DateTime.now();
    log('Trial 0: open the book from the library');
    final open = await runner.openFromLibrary();
    log('  ${open.pass ? 'pass' : 'FAIL'}: ${open.note}');

    final forceQuits = <TrialResult>[];
    for (var i = 1; i <= options.trials; i++) {
      final trial = await runner.forceQuit(i, useKillNine: i.isEven);
      forceQuits.add(trial);
      log(
        'Trial $i/${options.trials} ${trial.kind}: ${trial.pass ? 'pass' : 'FAIL'} '
        '(turned ${trial.pageTurns}, last ${trial.last}, restored ${trial.restored}, '
        'off by ${trial.restoredDistance}) ${trial.durationMs} ms',
      );
    }

    TrialResult? offline;
    if (!options.skipOffline) {
      log('Offline trial');
      offline = await runner.offline();
      log('  ${offline.pass ? 'pass' : 'FAIL'}: ${offline.note}');
    }
    await driver.forceStop();
    // Let the last packets reach the capture before closing the window.
    await Future<void>.delayed(const Duration(seconds: 3));
    final sessionEnd = DateTime.now();

    PrivacyResult? privacyResult;
    if (privacy) {
      final netAfter = await _netstats(adb);
      PcapAudit? audit;
      String? pcapNote;
      if (pcapFile == null) {
        pcapNote = options.ci ? 'FAIL: --ci needs --pcap' : 'no capture given (start the emulator with -tcpdump <file> and pass --pcap)';
      } else {
        try {
          final copy = File('${scratch.path}/emulator.pcap');
          pcapFile.copySync(copy.path);
          final capture = parsePcap(copy.readAsBytesSync());
          if (capture.packets.isEmpty) {
            pcapNote = 'the capture file holds no packets';
          } else {
            audit = auditPcap(
              capture,
              session: TimeWindow(
                sessionStart.microsecondsSinceEpoch,
                sessionEnd.microsecondsSinceEpoch,
              ),
              control: control,
              allowedHosts: options.allowedHosts,
              markers: book.markers,
              offline: runner.offlineWindows,
            );
          }
          copy.copySync('${reportDir.path}/emulator.pcap');
        } on Object catch (error) {
          pcapNote = 'could not read the capture: $error';
        }
      }
      if (netBefore == null || netAfter == null) {
        notes.add(
          'The device did not report per-UID counters; traffic not measured.',
        );
      }
      privacyResult = PrivacyResult(
        uid: uid,
        before: uid == null ? null : netBefore?.trafficOf(uid),
        after: uid == null ? null : netAfter?.trafficOf(uid),
        uidsSeen: netAfter?.byUid.length ?? 0,
        audit: audit,
        pcapNote: pcapNote,
      );
      if (options.ci && audit == null) {
        notes.add('Capture required in CI but missing: $pcapNote');
      }
    }

    final report = AcceptanceReport(
      startedAt: sessionStart,
      device: info,
      seed: options.seed,
      forceQuits: forceQuits,
      openFromLibrary: open,
      offline: offline,
      privacy: privacyResult,
      notes: notes,
      requiredTrials: requiredForceQuits,
    );
    File('${reportDir.path}/report.json')
        .writeAsStringSync(report.toJsonString());
    File('${reportDir.path}/report.md').writeAsStringSync(report.toMarkdown());
    log('');
    log(report.toMarkdown());
    final captureMissing =
        options.ci && privacyResult != null && privacyResult.audit == null;
    return report.pass && !captureMissing ? 0 : 1;
  } on Object catch (error, stack) {
    log('Harness error: $error\n$stack');
    return 2;
  } finally {
    // Always: airplane mode off, settings back, app stopped, staging gone.
    try {
      await runner?.setAirplane(false);
    } on Object catch (error) {
      log('Could not switch airplane mode off: $error');
    }
    for (final undo in restore.reversed) {
      try {
        await undo();
      } on Object catch (error) {
        log('Could not restore a device setting: $error');
      }
    }
    try {
      await adb.shell('am force-stop $appPackage', check: false);
      await adb.shell(
        'rm -rf /data/local/tmp/loremark-acceptance',
        check: false,
      );
    } on Object {
      // The device may be gone; nothing left to clean.
    }
    scratch.deleteSync(recursive: true);
  }
}

String? _defaultApk() {
  const path = 'build/app/outputs/flutter-apk/app-debug.apk';
  return File(path).existsSync() ? path : null;
}

Future<Map<String, String>> _deviceInfo(Adb adb) async {
  Future<String> prop(String name) async =>
      (await adb.shell('getprop $name', check: false)).trim();
  final size = (await adb.shell(
    'wm size',
    check: false,
  )).replaceFirst('Physical size:', '').trim();
  return {
    'model': await prop('ro.product.model'),
    'android':
        '${await prop('ro.build.version.release')} (API ${await prop('ro.build.version.sdk')})',
    'build': await prop('ro.build.type'),
    'screen': size,
  };
}

Future<int?> _appUid(Adb adb) async {
  final dump = await adb.shell(
    'dumpsys package $appPackage',
    timeout: const Duration(seconds: 60),
  );
  final match =
      RegExp(r'appId=(\d+)').firstMatch(dump) ??
      RegExp(r'userId=(\d+)').firstMatch(dump);
  return match == null ? null : int.parse(match.group(1)!);
}

Future<NetstatsSnapshot?> _netstats(Adb adb) async => parseNetstats(
  await adb.shell(
    'dumpsys netstats detail',
    timeout: const Duration(seconds: 90),
  ),
);

/// Turns off animations (a running animation makes uiautomator fail to reach
/// an idle state) and Private DNS (so lookups are visible in the capture).
/// Returns what undoes it.
Future<List<Future<void> Function()>> _prepareDevice(Adb adb) async {
  final undo = <Future<void> Function()>[];
  Future<void> change(String namespace, String key, String value) async {
    final old = (await adb.shell(
      'settings get $namespace $key',
      check: false,
    )).trim();
    await adb.shell('settings put $namespace $key $value');
    undo.add(() async {
      if (old == 'null' || old.isEmpty) {
        await adb.shell('settings delete $namespace $key', check: false);
      } else {
        await adb.shell('settings put $namespace $key $old');
      }
    });
  }

  for (final key in const [
    'window_animation_scale',
    'transition_animation_scale',
    'animator_duration_scale',
  ]) {
    await change('global', key, '0');
  }
  await change('global', 'private_dns_mode', 'off');
  await adb.shell('input keyevent KEYCODE_WAKEUP', check: false);
  return undo;
}
