import 'dart:convert';
import 'dart:io';

import 'benchmark.dart';

/// Runs the scalability benchmark, prints a Markdown table and writes JSON.
///
/// JIT, for a quick look:
///   dart run tool/benchmark/run.dart
/// AOT, which is what ships and has no warm-up noise:
///   dart compile exe tool/benchmark/run.dart -o build/benchmark/run.exe
///   build/benchmark/run.exe
///
/// Options: `--out=<path>` for the JSON (default build/benchmark/results.json)
/// and `--words-per-chapter=<n>` / `--chapters=<n>` for a smaller run.
/// Exits 1 if a spec target is missed, so CI can use it as a gate.
void main(List<String> args) {
  String? option(String name) => args
      .where((a) => a.startsWith('--$name='))
      .map((a) => a.substring(name.length + 3))
      .firstOrNull;

  final defaults = const BenchmarkConfig();
  final config = BenchmarkConfig(
    chapters: int.tryParse(option('chapters') ?? '') ?? defaults.chapters,
    wordsPerChapter:
        int.tryParse(option('words-per-chapter') ?? '') ??
        defaults.wordsPerChapter,
  );
  final outPath = option('out') ?? 'build/benchmark/results.json';

  stderr.writeln(
    'Benchmarking ${config.words} words, ${config.storySpec.records} '
    'story records...',
  );
  final report = runBenchmark(config);

  stdout
    ..writeln(
      'Mode: ${report.mode}, ${Platform.operatingSystemVersion}, '
      '${Platform.numberOfProcessors} logical processors',
    )
    ..writeln()
    ..write(report.toMarkdown());

  final out = File(outPath)..parent.createSync(recursive: true);
  out.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  stderr.writeln('Wrote $outPath');

  final wholeBook = report.rows.first;
  final ok = report.cardsUnderOneSecond >= 28 && wholeBook.max < 60 * 1000;
  if (!ok) exitCode = 1;
}
