import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:loremark/reader/epub_sections.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/story_model/story_snapshot.dart';

import '../../test/acceptance/synthetic_story_model.dart';
import '../../test/support/synthetic_book.dart';

/// Scalability benchmark for the spec's targets: a 500,000-word book,
/// chapter processing under 60 s, and 28 of 30 character cards opening in
/// under a second.
///
/// Pure Dart (no Flutter), so `tool/benchmark/run.dart` can be compiled
/// ahead of time and the same code runs inside `flutter test --tags
/// benchmark`. Timings use [Stopwatch], and percentiles are nearest-rank.

/// How big a run is. The defaults are the spec's numbers.
class BenchmarkConfig {
  const BenchmarkConfig({
    this.chapters = 100,
    this.wordsPerChapter = 5000,
    this.storySpec = SyntheticStoryModelSpec.large,
    this.cutoffs = 30,
    this.wholeBookRuns = 5,
    this.chapterRuns = 30,
    this.loadRuns = 3,
    this.seed = 1,
  });

  final int chapters;
  final int wordsPerChapter;
  final SyntheticStoryModelSpec storySpec;

  /// Late cutoffs to open a character card at; the spec says 30.
  final int cutoffs;
  final int wholeBookRuns;
  final int chapterRuns;
  final int loadRuns;
  final int seed;

  int get words => chapters * wordsPerChapter;
}

/// One measured step, in milliseconds per run.
class BenchmarkRow {
  BenchmarkRow(this.name, List<double> samplesMs, {this.note = ''})
    : samples = List.unmodifiable(samplesMs);

  final String name;
  final String note;
  final List<double> samples;

  late final List<double> _sorted = [...samples]..sort();

  double percentile(double p) {
    final rank = (p * _sorted.length).ceil().clamp(1, _sorted.length);
    return _sorted[rank - 1];
  }

  double get p50 => percentile(0.5);
  double get p95 => percentile(0.95);
  double get min => _sorted.first;
  double get max => _sorted.last;

  /// How many runs finished in under [ms] milliseconds.
  int under(double ms) => samples.where((s) => s < ms).length;

  Map<String, Object> toJson() => {
    'name': name,
    'runs': samples.length,
    'p50_ms': p50,
    'p95_ms': p95,
    'min_ms': min,
    'max_ms': max,
    'note': note,
  };
}

/// What a run measured, plus the pass/fail figures the spec asks for.
class BenchmarkReport {
  BenchmarkReport({
    required this.config,
    required this.rows,
    required this.facts,
    required this.mode,
  });

  final BenchmarkConfig config;
  final List<BenchmarkRow> rows;

  /// Sizes and counts, such as words and records, that give the rows meaning.
  final Map<String, Object> facts;

  /// "AOT" or "JIT", since JIT timings include warm-up and assertions.
  final String mode;

  BenchmarkRow row(String name) => rows.firstWhere((r) => r.name == name);

  /// How many of the character-card runs finished in under a second.
  int get cardsUnderOneSecond => row(cardRowName).under(1000);

  Map<String, Object> toJson() => {
    'generated': DateTime.now().toUtc().toIso8601String(),
    'mode': mode,
    'machine': {
      'os': Platform.operatingSystemVersion,
      'processors': Platform.numberOfProcessors,
      'dart': Platform.version.split(' ').first,
    },
    'config': {
      'chapters': config.chapters,
      'words_per_chapter': config.wordsPerChapter,
      'cutoffs': config.cutoffs,
      'seed': config.seed,
    },
    'facts': facts,
    'spec': {
      'cards_under_1s': cardsUnderOneSecond,
      'cards_total': config.cutoffs,
      'cards_required': 28,
      'chapter_processing_budget_ms': 60000,
    },
    'rows': [for (final row in rows) row.toJson()],
  };

  String toMarkdown() {
    String ms(double value) => value >= 100
        ? value.toStringAsFixed(0)
        : value >= 10
        ? value.toStringAsFixed(1)
        : value.toStringAsFixed(2);
    final out = StringBuffer()
      ..writeln('| Step | Runs | p50 (ms) | p95 (ms) | Max (ms) |')
      ..writeln('| :--- | ---: | ---: | ---: | ---: |');
    for (final row in rows) {
      out.writeln(
        '| ${row.name} | ${row.samples.length} | ${ms(row.p50)} | '
        '${ms(row.p95)} | ${ms(row.max)} |',
      );
    }
    out
      ..writeln()
      ..writeln(
        'Character cards under 1 s: **$cardsUnderOneSecond of '
        '${config.cutoffs}** (spec: at least 28 of 30).',
      );
    return out.toString();
  }
}

/// The row the "28 of 30" target is judged on.
const cardRowName = 'Character card: snapshot + lookup';

/// Inputs shared by the cases, built once and not timed.
class BenchmarkContext {
  BenchmarkContext(this.config);

  final BenchmarkConfig config;

  late final Uint8List bookBytes = buildSyntheticBook(
    chapters: config.chapters,
    wordsPerChapter: config.wordsPerChapter,
    seed: config.seed,
  );

  /// The book's text per section, extracted outside any timing. Cases that
  /// need text, such as a search index build, start from this.
  late final List<String> sectionTexts = sectionTextsFromBytes(bookBytes);

  late final SyntheticStoryModel story = generateSyntheticStoryModel(
    SyntheticStoryModelSpec(
      seed: config.seed,
      sections: config.storySpec.sections,
      characters: config.storySpec.characters,
      locations: config.storySpec.locations,
      organizations: config.storySpec.organizations,
      records: config.storySpec.records,
      transitionRate: config.storySpec.transitionRate,
      identityLinks: config.storySpec.identityLinks,
    ),
  );

  /// Facts for the report, filled in by cases as they learn them.
  final facts = <String, Object>{};
}

/// A step of the benchmark that adds [BenchmarkRow]s to the report.
typedef BenchmarkCase = List<BenchmarkRow> Function(BenchmarkContext context);

/// The steps, in report order.
///
/// EXTENSION POINT: when passage search (Feature A, `feat/passage-search`)
/// merges, add its cases here, each a function like those below that returns
/// rows built from [timeRuns]:
///   - search index build over `context.sectionTexts`
///   - search latency, p50/p95 over many seeded queries at a late cutoff
/// The spec's targets for them are in `docs/benchmarks.md`.
final List<BenchmarkCase> benchmarkCases = [
  textExtractionCases,
  storyModelLoadCases,
  characterCardCases,
];

BenchmarkReport runBenchmark(BenchmarkConfig config) {
  final context = BenchmarkContext(config);
  final rows = [for (final run in benchmarkCases) ...run(context)];
  return BenchmarkReport(
    config: config,
    rows: rows,
    facts: context.facts,
    mode: const bool.fromEnvironment('dart.vm.product') ? 'AOT' : 'JIT',
  );
}

/// Calls [action] [runs] times and returns each run's time in milliseconds.
List<double> timeRuns(int runs, void Function(int run) action) => [
  for (var i = 0; i < runs; i++)
    () {
      final watch = Stopwatch()..start();
      action(i);
      watch.stop();
      return watch.elapsedMicroseconds / 1000;
    }(),
];

/// A value the optimizer cannot prove unused, so timed work is not removed.
int sink = 0;

int countWords(String text) => RegExp(r'\S+').allMatches(text).length;

/// Chapter processing, the text-extraction part: the whole book, and one
/// chapter's EPUB at a time (what the app does as each chapter is opened).
List<BenchmarkRow> textExtractionCases(BenchmarkContext context) {
  final config = context.config;
  final bytes = context.bookBytes;
  context.facts['epub_bytes'] = bytes.length;
  context.facts['words'] = context.sectionTexts.fold<int>(
    0,
    (total, text) => total + countWords(text),
  );
  context.facts['chapters'] = config.chapters;

  // One untimed run first so JIT warm-up does not land on run 0 of a table
  // meant to show steady state; the AOT numbers are unaffected.
  sectionTextsFromBytes(bytes);
  final whole = timeRuns(
    config.wholeBookRuns,
    (_) => sink += sectionTextsFromBytes(bytes).length,
  );

  // A different seed per run so no run sees bytes an earlier run did.
  final chapters = [
    for (var i = 0; i < config.chapterRuns; i++)
      buildSyntheticBook(
        chapters: 1,
        wordsPerChapter: config.wordsPerChapter,
        seed: config.seed + 1 + i,
      ),
  ];
  final single = timeRuns(
    config.chapterRuns,
    (i) => sink += sectionTextsFromBytes(chapters[i]).length,
  );

  return [
    BenchmarkRow(
      'Extract text, whole book (${config.chapters} chapters)',
      whole,
    ),
    BenchmarkRow(
      'Extract text, one ${config.wordsPerChapter}-word chapter',
      single,
    ),
  ];
}

/// Reading the story model file: JSON decode plus `StoryModel.fromJson`.
List<BenchmarkRow> storyModelLoadCases(BenchmarkContext context) {
  final story = context.story;
  final text = jsonEncode(story.json);
  final model = story.model;
  context.facts['story_json_bytes'] = utf8.encode(text).length;
  context.facts['story_sections'] = model.sections.length;
  context.facts['story_entities'] = model.entities.length;
  context.facts['story_records'] = model.allRecords.length;
  context.facts['story_transitions'] = model.transitions.length;

  final load = timeRuns(
    context.config.loadRuns,
    (_) =>
        sink += StoryModel.fromJson(jsonDecode(text) as Map<String, dynamic>)
            .allRecords
            .length,
  );
  return [BenchmarkRow('Load story model (JSON decode + parse)', load)];
}

/// Opening a character card: build the snapshot at a late cutoff, then read
/// everything a card shows about one character.
///
/// The spec's target is 28 of 30 cards under a second. Each run uses a
/// different one of the last [BenchmarkConfig.cutoffs] sections and one of the
/// busiest characters known by then (the slowest cards), with a fresh
/// snapshot, so nothing is cached between runs.
List<BenchmarkRow> characterCardCases(BenchmarkContext context) {
  final story = context.story;
  final model = story.model;
  final config = context.config;
  final lastSections = model.sections.length;
  final cutoffs = [
    for (var i = 0; i < config.cutoffs; i++)
      model.sections[lastSections - config.cutoffs + i],
  ];
  context.facts['card_first_cutoff'] = cutoffs.first.order;
  context.facts['card_last_cutoff'] = cutoffs.last.order;

  final busiest =
      model.entities.values
          .where((e) => e.kind == EntityKind.character)
          .map((e) => e.id)
          .toList()
        ..sort((a, b) {
          final byCount = (story.recordCounts[b] ?? 0).compareTo(
            story.recordCounts[a] ?? 0,
          );
          return byCount != 0 ? byCount : a.compareTo(b);
        });

  final snapshots = <double>[];
  final lookups = <double>[];
  final both = <double>[];
  final watch = Stopwatch();
  for (var i = 0; i < cutoffs.length; i++) {
    final cutoff = cutoffs[i];
    // The i-th busiest character the reader has met by this cutoff.
    final id = busiest
        .where((id) => (story.introducedIn[id] ?? 1 << 30) <= cutoff.order)
        .elementAt(i);

    watch
      ..reset()
      ..start();
    final snapshot = StorySnapshot(model, cutoff);
    final built = watch.elapsedMicroseconds;
    sink += characterCard(snapshot, id);
    final total = watch.elapsedMicroseconds;
    watch.stop();
    snapshots.add(built / 1000);
    lookups.add((total - built) / 1000);
    both.add(total / 1000);
  }
  return [
    BenchmarkRow('StorySnapshot construction', snapshots),
    BenchmarkRow('Character card lookup', lookups),
    BenchmarkRow(
      cardRowName,
      both,
      note: 'busiest characters at the last ${config.cutoffs} sections',
    ),
  ];
}

/// Reads what a character card shows: names, facts, relationships, events,
/// open questions and changes, as text. Returns a count so the work is kept.
int characterCard(StorySnapshot snapshot, String entityId) {
  var count = snapshot.displayName(entityId).length;
  count += snapshot.aliasesOf(entityId).length;
  count += snapshot.firstSeenSection(entityId).order;
  for (final record in snapshot.attributesOf(entityId)) {
    count += snapshot.describe(record.payload).length;
  }
  for (final record in snapshot.relationshipsOf(entityId)) {
    count += snapshot.describe(record.payload).length;
  }
  for (final record in snapshot.eventsOf(entityId)) {
    count += snapshot.describe(record.payload).length;
  }
  for (final question in snapshot.questionsOf(entityId)) {
    count += snapshot.describe(question.record.payload).length;
  }
  for (final transition in snapshot.transitionsOf(entityId)) {
    count += snapshot.describeTransition(transition).length;
  }
  return count;
}
