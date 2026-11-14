import 'dart:io';

import 'lcov.dart';

/// Prints a Markdown line-coverage report from an lcov file.
///
///   flutter test --coverage
///   dart run tool/coverage/report.dart [coverage/lcov.info] [--summary <path>]
///
/// `--summary` also appends the report to a file; CI passes
/// `$GITHUB_STEP_SUMMARY` so it shows on the run page. Run it from the
/// repository root, because `lib/` is scanned to find files no test loads.
/// It is a report, not a gate: the exit code is 1 only if the lcov file or
/// `lib/` is missing.
void main(List<String> args) {
  final ({String lcov, String? summary}) options;
  try {
    options = parseArgs(args);
  } on FormatException catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln(
        'Usage: dart run tool/coverage/report.dart '
        '[coverage/lcov.info] [--summary <path>]',
      );
    exitCode = 2;
    return;
  }

  final lcovFile = File(options.lcov);
  if (!lcovFile.existsSync()) {
    stderr.writeln(
      'No lcov file at ${options.lcov}. Run `flutter test --coverage` first.',
    );
    exitCode = 1;
    return;
  }
  final lib = Directory('lib');
  if (!lib.existsSync()) {
    stderr.writeln('No lib/ folder here. Run this from the repository root.');
    exitCode = 1;
    return;
  }

  final markdown = renderReport(
    parseLcov(lcovFile.readAsStringSync()),
    libDartFiles(lib),
  );
  stdout.write(markdown);

  final summary = options.summary;
  if (summary != null && summary.isNotEmpty) {
    File(summary).writeAsStringSync(markdown, mode: FileMode.append);
  }
}

/// Splits [args] into the lcov path and the optional summary path.
({String lcov, String? summary}) parseArgs(List<String> args) {
  String? lcov;
  String? summary;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--summary') {
      if (i + 1 >= args.length) {
        throw const FormatException('--summary needs a path');
      }
      summary = args[++i];
    } else if (arg.startsWith('--summary=')) {
      summary = arg.substring('--summary='.length);
    } else if (arg.startsWith('-')) {
      throw FormatException('Unknown option: $arg');
    } else if (lcov == null) {
      lcov = arg;
    } else {
      throw FormatException('Unexpected argument: $arg');
    }
  }
  return (lcov: lcov ?? 'coverage/lcov.info', summary: summary);
}

/// Every `.dart` file under [lib], as `lib/...` paths with forward slashes.
List<String> libDartFiles(Directory lib) => [
  for (final entity in lib.listSync(recursive: true))
    if (entity is File && entity.path.endsWith('.dart'))
      normalizePath(entity.path),
];
