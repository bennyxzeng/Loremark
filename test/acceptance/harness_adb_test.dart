import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/acceptance/adb.dart';

CommandResult _result(int code, {String out = '', String err = ''}) =>
    CommandResult(
      code,
      Uint8List.fromList(utf8.encode(out)),
      Uint8List.fromList(utf8.encode(err)),
    );

/// A runner that answers from a script and records every call.
class _Script {
  _Script(this.responses);

  final List<Object> responses; // CommandResult or Exception
  final calls = <List<String>>[];

  Future<CommandResult> call(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    calls.add(arguments);
    final next = responses.length > 1 ? responses.removeAt(0) : responses.first;
    if (next is Exception) throw next;
    return next as CommandResult;
  }
}

Adb _adb(_Script script) => Adb(
  executable: 'adb',
  serial: 'emulator-5554',
  runner: script.call,
  retryDelay: Duration.zero,
);

void main() {
  group('parseDevices', () {
    test('reads serials and states, skipping the header and daemon lines', () {
      final devices = parseDevices('''
* daemon not running; starting now at tcp:5037
* daemon started successfully
List of devices attached
emulator-5554\tdevice
R58M123ABC\tunauthorized
emulator-5556\toffline

''');

      expect(devices.map((d) => d.serial), [
        'emulator-5554',
        'R58M123ABC',
        'emulator-5556',
      ]);
      expect(devices[0].isReady, isTrue);
      expect(devices[0].isEmulator, isTrue);
      expect(devices[1].isReady, isFalse);
      expect(devices[1].isEmulator, isFalse);
    });
  });

  group('chooseDevice', () {
    const one = [AdbDevice('emulator-5554', 'device')];
    const two = [
      AdbDevice('emulator-5554', 'device'),
      AdbDevice('emulator-5556', 'device'),
    ];

    test('takes the only ready device', () {
      expect(chooseDevice(one).serial, 'emulator-5554');
      expect(
        chooseDevice(const [
          AdbDevice('a', 'offline'),
          AdbDevice('b', 'device'),
        ]).serial,
        'b',
      );
    });

    test('prefers an explicit serial over the environment', () {
      final device = chooseDevice(
        two,
        requested: 'emulator-5556',
        environmentSerial: 'emulator-5554',
      );

      expect(device.serial, 'emulator-5556');
      expect(
        chooseDevice(two, environmentSerial: 'emulator-5556').serial,
        'emulator-5556',
      );
    });

    test('refuses to guess between several devices', () {
      expect(() => chooseDevice(two), throwsA(isA<AdbException>()));
    });

    test('explains a missing, unknown or not ready device', () {
      expect(() => chooseDevice(const []), throwsA(isA<AdbException>()));
      expect(
        () => chooseDevice(one, requested: 'nope'),
        throwsA(
          isA<AdbException>().having(
            (e) => e.message,
            'message',
            contains('nope'),
          ),
        ),
      );
      expect(
        () => chooseDevice(const [
          AdbDevice('x', 'unauthorized'),
        ], requested: 'x'),
        throwsA(isA<AdbException>()),
      );
    });
  });

  group('findAdb', () {
    test('uses an explicit path first, then the SDK, then PATH', () {
      expect(findAdb(override: '/opt/adb', environment: {}), '/opt/adb');
      expect(
        findAdb(
          environment: {'ANDROID_HOME': '/sdk'},
          exists: (path) => path.startsWith('/sdk/platform-tools/'),
        ),
        startsWith('/sdk/platform-tools/adb'),
      );
      expect(findAdb(environment: {}, exists: (_) => false), 'adb');
    });
  });

  group('Adb', () {
    test('runs commands against the chosen serial', () async {
      final script = _Script([_result(0, out: 'ok')]);

      await _adb(script).shell('echo hi');

      expect(script.calls.single, ['-s', 'emulator-5554', 'shell', 'echo hi']);
    });

    test(
      'passes a run-as script as one nested-quoted shell argument',
      () async {
        final script = _Script([_result(0)]);

        await _adb(script).runAs('com.example.app', 'mkdir -p a && cp b a/c');

        expect(script.calls.single, [
          '-s',
          'emulator-5554',
          'shell',
          "run-as com.example.app sh -c 'mkdir -p a && cp b a/c'",
        ]);
      },
    );

    test('retries a transient failure and then succeeds', () async {
      final script = _Script([
        _result(1, err: 'error: device offline'),
        CommandTimeout('adb', const Duration(seconds: 1)),
        _result(0, out: 'fine'),
      ]);

      final out = await _adb(script).shell('getprop x');

      expect(out, 'fine');
      expect(script.calls, hasLength(3));
    });

    test('gives up with the last error after the retries are used', () async {
      final script = _Script([_result(1, err: 'error: device offline')]);

      await expectLater(
        _adb(script).shell('getprop x'),
        throwsA(isA<AdbException>()),
      );
      expect(script.calls, hasLength(3));
    });

    test('does not retry a real command failure', () async {
      final script = _Script([
        _result(1, err: 'run-as: package not debuggable'),
      ]);

      await expectLater(
        _adb(script).shell('run-as x true'),
        throwsA(isA<AdbException>()),
      );
      expect(script.calls, hasLength(1));
    });

    test('returns a nonzero exit when asked not to check', () async {
      final script = _Script([_result(1)]);

      final result = await _adb(script).run(['shell', 'pidof x']);

      expect(result.exitCode, 1);
    });

    test('install fails unless adb prints Success', () async {
      final ok = _Script([
        _result(0, out: 'Performing Streamed Install\nSuccess\n'),
      ]);
      await _adb(ok).install('app.apk');
      expect(ok.calls.single, containsAll(['install', '-r', 'app.apk']));

      final bad = _Script([
        _result(0, out: 'Failure [INSTALL_FAILED_OLDER_SDK]'),
      ]);
      await expectLater(
        _adb(bad).install('app.apk'),
        throwsA(isA<AdbException>()),
      );
    });
  });

  group('parseWmSize', () {
    test('reads the physical size', () {
      final size = parseWmSize('Physical size: 1080x2400\n');

      expect(size, (width: 1080, height: 2400));
    });

    test('prefers the override size', () {
      final size = parseWmSize(
        'Physical size: 1080x2400\nOverride size: 720x1600\n',
      );

      expect(size, (width: 720, height: 1600));
    });

    test('gives null for output that is not a size', () {
      expect(parseWmSize(''), isNull);
      expect(parseWmSize('error: closed'), isNull);
    });
  });
}
