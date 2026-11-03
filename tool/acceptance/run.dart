import 'dart:io';

import 'harness.dart';
import 'options.dart';

/// Entry point of the device acceptance checks. See `--help` and
/// `docs/acceptance.md`.
Future<void> main(List<String> args) async {
  final Options options;
  try {
    options = parseOptions(args);
  } on UsageError catch (error) {
    stderr
      ..writeln(error)
      ..writeln()
      ..write(usage);
    exit(2);
  }
  if (options.help) {
    stdout.write(usage);
    return;
  }
  exit(await runHarness(options));
}
