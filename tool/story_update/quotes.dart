import 'dart:convert';
import 'dart:io';

import 'package:loremark/story_update/delta_schema.dart';
import 'package:loremark/story_update/story_book.dart';
import 'package:loremark/story_update/story_quotes.dart';
import 'package:loremark/story_update/story_run_folder.dart' show storyUtcNow;
import 'package:loremark/story_update/story_store.dart' show sectionSource;
import 'package:loremark/story_update/story_validation.dart';

/// Replays the app's quote repair on kept run folders, without calling a model.
///
///   dart run tool/story_update/quotes.dart some/runs [some/other/runs ...] \
///     [--store=some/store] [--show] [--json=report.json]
///
/// Reads any run folder with `delta.candidate.json` and `chapter.json`, the
/// app's or the lab's (they're the same), and never writes into it. For each,
/// it counts the model's quotes as `exact` (already in the cited paragraph),
/// `moved` or `snapped` (repaired; see `repairStoryQuotes`) or `unresolved`,
/// and adds them up by model. Where the run kept what an update is checked
/// against (`base_story_model.json`, `schema.json` and `base_inputs/`, or else
/// the inputs of `--store`), it also checks the answer the way the app does
/// with Strict quote check on, before the repair and after.
///
/// `--show` lists every repair and unresolved quote. `--json` also writes all
/// of it to a file.
void main(List<String> args) {
  String? option(String name) => args
      .where((arg) => arg.startsWith('--$name='))
      .map((arg) => arg.substring(name.length + 3))
      .firstOrNull;
  final paths = args.where((arg) => !arg.startsWith('--')).toList();
  if (paths.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/story_update/quotes.dart <runs folder>... '
      '[--store=<store>] [--show] [--json=<file>]',
    );
    exit(64);
  }
  final store = option('store');
  final show = args.contains('--show');

  final runs = [for (final path in paths) ..._runFolders(path)];
  if (runs.isEmpty) {
    stderr.writeln('No run folder with delta.candidate.json in $paths');
    exit(1);
  }
  final reports = [for (final run in runs) _replay(run, store)];

  stdout.writeln(
    '${'Run'.padRight(26)}${'Model'.padRight(16)}${_row(_kinds)}  '
    'Strict quote check',
  );
  for (final report in reports) {
    stdout.writeln(
      '${report.name.padRight(26)}${report.model.padRight(16)}'
      '${_row([for (final kind in _kinds) '${report.counts[kind]}'])}  '
      '${report.strict}',
    );
    if (show) {
      for (final line in report.details) {
        stdout.writeln('    $line');
      }
    }
  }

  final byModel = <String, Map<String, int>>{};
  for (final report in reports) {
    final total = byModel.putIfAbsent(report.model, () => _zero());
    report.counts.forEach((kind, n) => total[kind] = total[kind]! + n);
  }
  stdout
    ..writeln()
    ..writeln('${'By model'.padRight(42)}${_row(_kinds)}');
  byModel.forEach((model, counts) {
    stdout.writeln(
      '${model.padRight(42)}'
      '${_row([for (final kind in _kinds) '${counts[kind]}'])}',
    );
  });
  final fixed = reports
      .where((r) => r.failedBefore && r.passesAfter == true)
      .length;
  final stillFailing = reports.where((r) => r.passesAfter == false).length;
  stdout
    ..writeln()
    ..writeln(
      'With Strict quote check on: $fixed failing run(s) now pass; '
      '$stillFailing still fail.',
    );

  final jsonPath = option('json');
  if (jsonPath != null) {
    File(jsonPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'quote_repair_version': storyQuoteRepairVersion,
        'by_model': byModel,
        'runs': [for (final report in reports) report.toJson()],
      }),
    );
    stdout.writeln('Report: $jsonPath');
  }
}

const _kinds = ['quotes', 'exact', 'moved', 'snapped', 'unresolved'];

Map<String, int> _zero() => {for (final kind in _kinds) kind: 0};

String _row(List<String> cells) => cells.map((cell) => cell.padLeft(11)).join();

/// [path] itself if it's a run folder, else the run folders in it.
List<Directory> _runFolders(String path) {
  bool isRun(Directory dir) =>
      File('${dir.path}/delta.candidate.json').existsSync() &&
      File('${dir.path}/chapter.json').existsSync();
  final dir = Directory(path);
  if (isRun(dir)) return [dir];
  if (!dir.existsSync()) {
    stderr.writeln('Not found: $path');
    return const [];
  }
  return dir.listSync().whereType<Directory>().where(isRun).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

JsonMap? _readJson(String path) {
  final file = File(path);
  return file.existsSync()
      ? jsonDecode(file.readAsStringSync()) as JsonMap
      : null;
}

class _Report {
  _Report(this.name, this.model);

  final String name;
  final String model;
  final counts = _zero();
  final details = <String>[];
  final repairs = <QuoteRepair>[];
  final unresolved = <JsonMap>[];

  /// Whether the answer passes with Strict quote check on, before and after
  /// the repair; null if it couldn't be checked.
  bool? passesBefore;
  bool? passesAfter;
  List<String> errorsAfter = const [];
  String? uncheckedBecause;

  bool get failedBefore => passesBefore == false;

  String get strict {
    if (uncheckedBecause != null) return '- ($uncheckedBecause)';
    String word(bool passes) => passes ? 'passes' : 'fails';
    final after = word(passesAfter!);
    final errors = errorsAfter.isEmpty ? '' : ' (${errorsAfter.join(', ')})';
    return passesBefore == passesAfter
        ? '$after$errors'
        : '${word(passesBefore!)} → $after$errors';
  }

  JsonMap toJson() => {
    'run': name,
    'model': model,
    'counts': counts,
    'strict_before': passesBefore,
    'strict_after': passesAfter,
    'errors_after': errorsAfter,
    'unchecked_because': uncheckedBecause,
    'repairs': [
      for (final repair in repairs)
        {
          'path': repair.path,
          'kind': repair.kind,
          'from_paragraph': repair.fromParagraph,
          'to_paragraph': repair.toParagraph,
          'from_quote': repair.fromQuote,
          'to_quote': repair.toQuote,
          'distance': repair.distance,
        },
    ],
    'unresolved': unresolved,
  };
}

_Report _replay(Directory run, String? store) {
  final dir = run.path;
  final name = dir.split(Platform.pathSeparator).lastWhere((s) => s.isNotEmpty);
  final record = _readJson('$dir/run.json') ?? const {};
  final model =
      ((record['request'] as Map?)?['model'] ??
              record['model'] ??
              _readJson('$dir/request.json')?['model'] ??
              '?')
          as String;
  final report = _Report(name, model);

  final chapter = _readJson('$dir/chapter.json')!;
  final candidate = jsonDecode(
    File('$dir/delta.candidate.json').readAsStringSync(),
  );
  final paragraphs = {
    for (final p in (chapter['paragraphs'] as List).cast<JsonMap>())
      p['id'] as String: p['text'] as String,
  };
  final (repaired, repairs) = repairStoryQuotes(candidate, chapter);
  report.repairs.addAll(repairs);
  final repairOf = {for (final repair in repairs) repair.path: repair};

  for (final (path, evidence) in deltaEvidence(candidate)) {
    if (evidence is! Map) continue;
    report.counts['quotes'] = report.counts['quotes']! + 1;
    final repair = repairOf[path];
    final quote = evidence['quote'];
    final paragraph = evidence['paragraph_id'];
    final String kind;
    if (repair != null) {
      kind = repair.kind;
      report.details.add(
        repair.kind == 'moved'
            ? 'moved    $path  ${repair.fromParagraph} → ${repair.toParagraph}'
                  '  “$quote”'
            : 'snapped  $path  ${repair.fromParagraph} → ${repair.toParagraph}'
                  '  ${repair.distance} edit(s)\n'
                  '      model: $quote\n'
                  '      book:  ${repair.toQuote}',
      );
    } else if (evidence['section_id'] == chapter['section_id'] &&
        quote is String &&
        (paragraphs[paragraph]?.contains(quote) ?? false)) {
      kind = 'exact';
    } else {
      kind = 'unresolved';
      report.unresolved.add({
        'path': path,
        'section_id': evidence['section_id'],
        'paragraph_id': paragraph,
        'quote': quote,
      });
      report.details.add('UNRESOLVED $path  $paragraph  “$quote”');
    }
    report.counts[kind] = report.counts[kind]! + 1;
  }

  _checkStrictly(report, dir, record, chapter, candidate, repaired, store);
  return report;
}

/// Checks the answer before and after the repair as the app would, with Strict
/// quote check on, if the run kept what that needs.
void _checkStrictly(
  _Report report,
  String dir,
  JsonMap record,
  JsonMap chapter,
  Object? candidate,
  Object? repaired,
  String? store,
) {
  final base = _readJson('$dir/base_story_model.json');
  final schemaFile = File('$dir/schema.json');
  final source = record['source'] as Map?;
  if (base == null || !schemaFile.existsSync() || source == null) {
    report.uncheckedBecause = 'the run kept no base model, schema or source';
    return;
  }
  final inputs = <String, JsonMap>{};
  for (final folder in [
    '$dir/base_inputs',
    if (store != null) '$store/inputs',
  ]) {
    final found = Directory(folder);
    if (!found.existsSync()) continue;
    for (final file in found.listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      final input = jsonDecode(file.readAsStringSync()) as JsonMap;
      inputs.putIfAbsent(input['section_id'] as String, () => input);
    }
  }
  final processed = (base['processed_sections'] as List).cast<JsonMap>();
  final missing = [
    for (final section in processed)
      if (!inputs.containsKey(section['section_id'])) section['section_id'],
  ];
  if (missing.isNotEmpty) {
    report.uncheckedBecause = 'no input for ${missing.join(', ')}; try --store';
    return;
  }

  final number = ((base['revision'] as Map)['number'] as int) + 1;
  final (section, _, _) = sectionSource(
    chapter,
    sectionOrder: source['section_order'] as int,
    revision: number,
  );
  final parent = record['base_revision'] as Map?;
  final revision = {
    'number': number,
    'id': 'replay',
    'created_at': storyUtcNow(),
    'source_run_id': report.name,
    'parent_snapshot_path': parent?['snapshot_path'],
    'parent_sha256': parent?['sha256'],
  };
  final schema = StoryDeltaSchema.parse(schemaFile.readAsStringSync());
  StoryUpdateValidation check(Object? answer) => validateUpdate(
    base,
    answer,
    schema: schema,
    chapter: chapter,
    baseInputs: inputs,
    section: section,
    revision: revision,
  );
  final StoryUpdateValidation before;
  final StoryUpdateValidation after;
  try {
    before = check(candidate);
    after = check(repaired);
  } on TypeError {
    // The lab's early runs kept a base model of an older shape.
    report.uncheckedBecause = 'the base model is in an older format';
    return;
  }
  report.passesBefore = before.passed;
  report.passesAfter = after.passed;
  report.errorsAfter = {for (final issue in after.errors) issue.code}.toList();
}
