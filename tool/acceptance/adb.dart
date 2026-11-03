import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// What a finished command produced.
class CommandResult {
  const CommandResult(this.exitCode, this.stdoutBytes, this.stderrBytes);

  final int exitCode;
  final Uint8List stdoutBytes;
  final Uint8List stderrBytes;

  String get stdout => utf8.decode(stdoutBytes, allowMalformed: true);
  String get stderr => utf8.decode(stderrBytes, allowMalformed: true);
}

/// Thrown when a command timed out or could not start.
class CommandTimeout implements Exception {
  CommandTimeout(this.command, this.timeout);

  final String command;
  final Duration timeout;

  @override
  String toString() => 'Timed out after ${timeout.inSeconds}s: $command';
}

/// Runs a host process. A seam for tests, which must not need a device.
typedef CommandRunner = Future<CommandResult> Function(
  String executable,
  List<String> arguments, {
  required Duration timeout,
});

/// Spawns a real process, reading its output as raw bytes (a screencap or a
/// uiautomator dump must not go through a text decoder) and killing it when
/// [timeout] passes.
///
/// The MSYS variables stop Git Bash from rewriting device paths like
/// `/data/local/tmp` into `C:/Program Files/Git/data/local/tmp` when this
/// harness is started from a shell script; a native Windows child never
/// converts them itself.
Future<CommandResult> systemRunner(
  String executable,
  List<String> arguments, {
  required Duration timeout,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    environment: {'MSYS_NO_PATHCONV': '1', 'MSYS2_ARG_CONV_EXCL': '*'},
  );
  // Closed so a command that reads stdin gets EOF instead of hanging.
  unawaited(process.stdin.close().catchError((Object _) {}));
  Future<Uint8List> collect(Stream<List<int>> stream) async {
    final out = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      out.add(chunk);
    }
    return out.takeBytes();
  }

  final stdout = collect(process.stdout);
  final stderr = collect(process.stderr);
  try {
    final code = await process.exitCode.timeout(timeout);
    return CommandResult(code, await stdout, await stderr);
  } on TimeoutException {
    process.kill();
    throw CommandTimeout('$executable ${arguments.join(' ')}', timeout);
  }
}

/// A failed adb call.
class AdbException implements Exception {
  AdbException(this.message);

  final String message;

  @override
  String toString() => 'adb: $message';
}

/// One attached device or emulator, as `adb devices` lists it.
class AdbDevice {
  const AdbDevice(this.serial, this.state);

  final String serial;
  final String state;

  bool get isReady => state == 'device';
  bool get isEmulator => serial.startsWith('emulator-');

  @override
  String toString() => '$serial ($state)';
}

/// The devices in `adb devices` output.
List<AdbDevice> parseDevices(String output) {
  final devices = <AdbDevice>[];
  for (final line in const LineSplitter().convert(output)) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 2 ||
        line.startsWith('List of') ||
        line.startsWith('*')) {
      continue;
    }
    devices.add(AdbDevice(parts[0], parts[1]));
  }
  return devices;
}

/// The device to run on.
///
/// An explicit [requested] serial wins, then `ANDROID_SERIAL`, then the only
/// ready device. With several ready devices and no choice it refuses to guess:
/// force-stopping the wrong phone is not a mistake worth risking.
AdbDevice chooseDevice(
  List<AdbDevice> devices, {
  String? requested,
  String? environmentSerial,
}) {
  final wanted = requested ?? environmentSerial;
  if (wanted != null && wanted.isNotEmpty) {
    for (final device in devices) {
      if (device.serial != wanted) continue;
      if (!device.isReady) {
        throw AdbException('$device is not ready (state: ${device.state})');
      }
      return device;
    }
    throw AdbException(
      'No device "$wanted". Attached: ${devices.isEmpty ? 'none' : devices.join(', ')}',
    );
  }
  final ready = devices.where((d) => d.isReady).toList();
  if (ready.length == 1) return ready.single;
  if (ready.isEmpty) {
    throw AdbException(
      'No ready device. Start an emulator or pass --serial. '
      'Attached: ${devices.isEmpty ? 'none' : devices.join(', ')}',
    );
  }
  throw AdbException(
    'Several devices are ready (${ready.join(', ')}). Pass --serial.',
  );
}

/// Finds the `adb` binary: an explicit [override], the Android SDK from
/// `ANDROID_HOME` / `ANDROID_SDK_ROOT`, the default SDK location, then PATH.
String findAdb({
  String? override,
  Map<String, String>? environment,
  bool Function(String path)? exists,
}) {
  final env = environment ?? Platform.environment;
  final fileExists = exists ?? (path) => File(path).existsSync();
  if (override != null && override.isNotEmpty) return override;
  final exe = Platform.isWindows ? 'adb.exe' : 'adb';
  final roots = [
    env['ANDROID_HOME'],
    env['ANDROID_SDK_ROOT'],
    if (env['LOCALAPPDATA'] != null) '${env['LOCALAPPDATA']}/Android/Sdk',
    if (env['HOME'] != null) '${env['HOME']}/Library/Android/sdk',
    if (env['HOME'] != null) '${env['HOME']}/Android/Sdk',
  ];
  for (final root in roots) {
    if (root == null || root.isEmpty) continue;
    final candidate = '$root/platform-tools/$exe';
    if (fileExists(candidate)) return candidate;
  }
  return 'adb';
}

/// A thin, retrying wrapper over the `adb` command line for one device.
///
/// Shell commands go through as one string argument. adb joins the arguments
/// with spaces and the device's shell splits them again, so nested quoting like
/// `sh -c 'a; b'` only survives as a single string.
class Adb {
  Adb({
    required this.executable,
    required this.serial,
    this.runner = systemRunner,
    this.defaultTimeout = const Duration(seconds: 30),
    this.retries = 2,
    this.retryDelay = const Duration(seconds: 1),
  });

  final String executable;
  final String serial;
  final Duration defaultTimeout;
  final int retries;
  final Duration retryDelay;
  final CommandRunner runner;

  /// The `adb devices` list, without a device selected.
  static Future<List<AdbDevice>> listDevices(
    String executable, {
    CommandRunner runner = systemRunner,
  }) async {
    final result = await runner(executable, [
      'devices',
    ], timeout: const Duration(seconds: 30));
    if (result.exitCode != 0) {
      throw AdbException('devices failed: ${result.stderr.trim()}');
    }
    return parseDevices(result.stdout);
  }

  /// Runs `adb -s <serial> <arguments>`.
  ///
  /// Transient failures (a device that is still reconnecting, a timeout) are
  /// retried [retries] times. A nonzero exit is returned, not thrown, unless
  /// [check] is set, since commands like `pidof` use it to answer.
  Future<CommandResult> run(
    List<String> arguments, {
    Duration? timeout,
    bool check = false,
    int? attempts,
  }) async {
    final limit = timeout ?? defaultTimeout;
    final tries = (attempts ?? retries + 1).clamp(1, 20);
    Object? lastError;
    for (var attempt = 1; attempt <= tries; attempt++) {
      try {
        final result = await runner(executable, [
          '-s',
          serial,
          ...arguments,
        ], timeout: limit);
        final transient = _isTransient(result);
        if (result.exitCode == 0 || !transient) {
          if (check && result.exitCode != 0) {
            throw AdbException(
              '${arguments.join(' ')} failed (${result.exitCode}): '
              '${result.stderr.trim()} ${result.stdout.trim()}',
            );
          }
          return result;
        }
        lastError = AdbException(
          '${arguments.join(' ')}: ${result.stderr.trim()}',
        );
      } on CommandTimeout catch (error) {
        lastError = error;
      }
      if (attempt < tries) await Future<void>.delayed(retryDelay * attempt);
    }
    throw lastError!;
  }

  static bool _isTransient(CommandResult result) {
    if (result.exitCode == 0) return false;
    final text = result.stderr.toLowerCase();
    return text.contains('device offline') ||
        text.contains('closed') ||
        text.contains('not found') && text.contains('device') ||
        text.contains('protocol fault') ||
        text.contains('connection reset') ||
        text.contains('daemon');
  }

  /// `adb shell <command>` with [command] as one string.
  Future<String> shell(
    String command, {
    Duration? timeout,
    bool check = true,
  }) async {
    final result = await run(
      ['shell', command],
      timeout: timeout,
      check: check,
    );
    return result.stdout;
  }

  /// Runs [script] in the app's sandbox: `run-as <package> sh -c '<script>'`.
  ///
  /// Needs a debuggable build. [script] must not contain single quotes.
  Future<String> runAs(
    String package,
    String script, {
    Duration? timeout,
    bool check = true,
  }) {
    assert(!script.contains("'"), 'single quotes break the nested sh -c');
    return shell(
      "run-as $package sh -c '$script'",
      timeout: timeout,
      check: check,
    );
  }

  /// `adb exec-out`, which returns bytes untouched by the shell's line-ending
  /// handling.
  Future<Uint8List> execOut(String command, {Duration? timeout}) async {
    final result = await run(
      ['exec-out', command],
      timeout: timeout,
      check: true,
    );
    return result.stdoutBytes;
  }

  /// Copies the host file [local] to the device path [remote].
  ///
  /// Binary data goes through `adb push`, never through shell stdin: on
  /// Windows a 0x1A byte ends the stream, which cut a 3 MB file at 77 bytes.
  Future<void> push(String local, String remote, {Duration? timeout}) async {
    await run(
      ['push', local, remote],
      timeout: timeout ?? const Duration(minutes: 2),
      check: true,
    );
  }

  Future<void> install(String apk) async {
    final result = await run(
      ['install', '-r', '-t', apk],
      timeout: const Duration(minutes: 5),
      check: true,
    );
    if (!result.stdout.contains('Success')) {
      throw AdbException('install failed: ${result.stdout} ${result.stderr}');
    }
  }

  /// Dumps the UI hierarchy as XML text.
  ///
  /// `exec-out` and `/dev/tty` keep the dump off the device's disk and out of
  /// the shell's line-ending translation. A dump that failed (uiautomator says
  /// "ERROR: could not get idle state") comes back as text without XML.
  Future<String> uiDump() async {
    final result = await run([
      'exec-out',
      'uiautomator',
      'dump',
      '/dev/tty',
    ], timeout: const Duration(seconds: 40));
    return result.stdout;
  }

  Future<void> tap(int x, int y) => shell('input tap $x $y');

  /// The positions logged since the last [clearLogcat].
  Future<String> positionLogcat() async {
    final result = await run([
      'logcat',
      '-d',
      '-v',
      'epoch',
      'flutter:I',
      '*:S',
    ]);
    return result.stdout;
  }

  Future<void> clearLogcat() async {
    await run(['logcat', '-c'], check: true);
  }
}
