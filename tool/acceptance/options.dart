/// Thrown for a bad command line; the message is shown with the usage text.
class UsageError implements Exception {
  UsageError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Command-line options of `dart run tool/acceptance/run.dart`.
class Options {
  const Options({
    this.help = false,
    this.ci = false,
    this.serial,
    this.adb,
    this.apk,
    this.install = true,
    this.trials = 20,
    this.seed = 403,
    this.chapters = 12,
    this.words = 3000,
    this.reportDir = 'build/acceptance',
    this.pcap,
    this.baselineSeconds = 45,
    this.allowedHosts = const {},
    this.skipOffline = false,
    this.skipPrivacy = false,
    this.prepareDevice,
  });

  final bool help;

  /// Fail instead of warn when the capture is missing.
  final bool ci;
  final String? serial;
  final String? adb;
  final String? apk;
  final bool install;
  final int trials;
  final int seed;
  final int chapters;
  final int words;
  final String reportDir;
  final String? pcap;
  final int baselineSeconds;
  final Set<String> allowedHosts;
  final bool skipOffline;
  final bool skipPrivacy;

  /// Whether to turn off animations and Private DNS on the device for the run.
  /// Null decides by device: yes for emulators, no for a real phone.
  final bool? prepareDevice;
}

const usage = '''
Loremark device acceptance checks

  dart run tool/acceptance/run.dart [options]

Runs on a debuggable build (flutter build apk --debug) over adb:
  * force-quit trials: the book reopens within one page of the last position
  * an offline trial (airplane mode on)
  * a privacy audit: the app UID's network counters, and the pcap policy
    check when --pcap is given

Options:
  --serial <id>          Device to use. Default: ANDROID_SERIAL or the only
                         ready device.
  --adb <path>           adb binary. Default: ANDROID_HOME, then PATH.
  --apk <path>           Debug APK to install. Default:
                         build/app/outputs/flutter-apk/app-debug.apk if it
                         exists.
  --no-install           Test the build already on the device.
  --trials <n>           Force-quit trials. Default 20 (the spec's number).
  --seed <n>             Seed for the book and the random choices. Default 403.
  --chapters <n>         Chapters in the generated book. Default 12.
  --words <n>            Words per chapter. Default 3000.
  --report <dir>         Where report.json and report.md go.
                         Default build/acceptance.
  --pcap <file>          The file the emulator writes with -tcpdump <file>.
  --baseline-seconds <n> Length of the control window, app stopped, that
                         defines the OS's own traffic. Default 45.
  --allow-host <host>    A host the app may contact (repeatable, "*.x.com"
                         allowed). None today: the app makes no requests.
  --skip-offline         Skip the airplane-mode trial.
  --skip-privacy         Skip the netstats and capture checks.
  --prepare-device       Turn off animations and Private DNS for the run
                         (restored afterwards). Default on for emulators.
  --ci                   A missing or empty capture is a failure, not a note.
  -h, --help             This text.

Exit code: 0 all checks passed, 1 a check failed, 2 the harness could not run.
''';

/// Parses [args]; throws [UsageError] on anything unknown or malformed.
Options parseOptions(List<String> args) {
  var options = const Options();
  final allowed = <String>{};
  String valueOf(int i, String name) {
    if (i + 1 >= args.length) throw UsageError('$name needs a value');
    return args[i + 1];
  }

  int number(int i, String name, {int min = 0}) {
    final value = int.tryParse(valueOf(i, name));
    if (value == null || value < min) {
      throw UsageError('$name needs a whole number of at least $min');
    }
    return value;
  }

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '-h' || '--help':
        options = _copy(options, help: true);
      case '--ci':
        options = _copy(options, ci: true);
      case '--no-install':
        options = _copy(options, install: false);
      case '--skip-offline':
        options = _copy(options, skipOffline: true);
      case '--skip-privacy':
        options = _copy(options, skipPrivacy: true);
      case '--prepare-device':
        options = _copy(options, prepareDevice: true);
      case '--serial':
        options = _copy(options, serial: valueOf(i, arg));
        i++;
      case '--adb':
        options = _copy(options, adb: valueOf(i, arg));
        i++;
      case '--apk':
        options = _copy(options, apk: valueOf(i, arg));
        i++;
      case '--report':
        options = _copy(options, reportDir: valueOf(i, arg));
        i++;
      case '--pcap':
        options = _copy(options, pcap: valueOf(i, arg));
        i++;
      case '--allow-host':
        allowed.add(valueOf(i, arg).toLowerCase());
        i++;
      case '--trials':
        options = _copy(options, trials: number(i, arg, min: 1));
        i++;
      case '--seed':
        options = _copy(options, seed: number(i, arg));
        i++;
      case '--chapters':
        options = _copy(options, chapters: number(i, arg, min: 4));
        i++;
      case '--words':
        options = _copy(options, words: number(i, arg, min: 500));
        i++;
      case '--baseline-seconds':
        options = _copy(options, baselineSeconds: number(i, arg));
        i++;
      default:
        throw UsageError('Unknown option: $arg');
    }
  }
  return _copy(options, allowedHosts: allowed);
}

Options _copy(
  Options o, {
  bool? help,
  bool? ci,
  String? serial,
  String? adb,
  String? apk,
  bool? install,
  int? trials,
  int? seed,
  int? chapters,
  int? words,
  String? reportDir,
  String? pcap,
  int? baselineSeconds,
  Set<String>? allowedHosts,
  bool? skipOffline,
  bool? skipPrivacy,
  bool? prepareDevice,
}) => Options(
  help: help ?? o.help,
  ci: ci ?? o.ci,
  serial: serial ?? o.serial,
  adb: adb ?? o.adb,
  apk: apk ?? o.apk,
  install: install ?? o.install,
  trials: trials ?? o.trials,
  seed: seed ?? o.seed,
  chapters: chapters ?? o.chapters,
  words: words ?? o.words,
  reportDir: reportDir ?? o.reportDir,
  pcap: pcap ?? o.pcap,
  baselineSeconds: baselineSeconds ?? o.baselineSeconds,
  allowedHosts: allowedHosts ?? o.allowedHosts,
  skipOffline: skipOffline ?? o.skipOffline,
  skipPrivacy: skipPrivacy ?? o.skipPrivacy,
  prepareDevice: prepareDevice ?? o.prepareDevice,
);
