@Tags(['benchmark'])
@Timeout(Duration(minutes: 10))
library;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/benchmark/benchmark.dart';

// Scalability targets from the spec: a 500,000-word book, chapter processing
// under 60 s, and 28 of 30 character cards opening in under a second.
//
// Runs the same code as `dart run tool/benchmark/run.dart`, but under
// `flutter test`: JIT, assertions on, so slower than the AOT numbers in
// docs/benchmarks.md. The budgets here are far above what a run needs, so a
// busy CI machine does not make them flaky, yet a real regression (say, a
// snapshot that scans every record per fact) still fails them.
void main() {
  late final BenchmarkReport report;

  setUpAll(() => report = runBenchmark(const BenchmarkConfig()));

  test('the book is 500,000 words long', () {
    expect(report.facts['words'], inInclusiveRange(495000, 510000));
    expect(report.facts['chapters'], 100);
  });

  test('extracts the text of the whole book well inside 60 s', () {
    final row = report.rows.first;
    expect(row.max, lessThan(20 * 1000));
  });

  test('extracts one chapter in well under a second', () {
    final row = report.rows[1];
    expect(row.p95, lessThan(1000));
  });

  test('the story model has the spec size', () {
    expect(report.facts['story_sections'], 100);
    expect(report.facts['story_records'] as int, greaterThanOrEqualTo(20000));
    expect(report.facts['story_entities'] as int, greaterThanOrEqualTo(2000));
  });

  test('opens at least 28 of 30 character cards in under a second', () {
    expect(report.cardsUnderOneSecond, greaterThanOrEqualTo(28));
    expect(report.row(cardRowName).p95, lessThan(2000));
  });

  test('prints a table', () {
    final table = report.toMarkdown();
    expect(table, contains(cardRowName));
    // ignore: avoid_print
    print(table);
  });
}
