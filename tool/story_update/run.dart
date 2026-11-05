import 'dart:convert';
import 'dart:io';

import 'package:loremark/story_update/story_api_client.dart';
import 'package:loremark/story_update/story_book.dart';
import 'package:loremark/story_update/story_model_choice.dart';
import 'package:loremark/story_update/story_store.dart';
import 'package:loremark/story_update/story_updater.dart';

/// Runs one Story Map update from the command line, with the app's own code.
///
///   dart run tool/story_update/run.dart --epub=book.epub --store=some/folder \
///     --section=section-004 --model=deepseek-flash --effort=high \
///     --out=some/run/folder --dry-run
///
/// `--section` is where a new store starts, or a later section to skip ahead to
/// (without it, the next section). `--dry-run` writes the request to `--out` and
/// sends nothing. Otherwise the provider's key comes from DEEPSEEK_API_KEY or
/// OPENAI_API_KEY, and is never printed or saved.
///
/// `--ledger=<file>` limits what a run may spend: it counts requests, and
/// refuses to send once `--max-successes` updates have succeeded or
/// `--max-failures` in a row have failed. A request counts as a failure from
/// before it is sent, so a crash can't lose one.
Future<void> main(List<String> args) async {
  String? option(String name) => args
      .where((arg) => arg.startsWith('--$name='))
      .map((arg) => arg.substring(name.length + 3))
      .firstOrNull;
  String required(String name) =>
      option(name) ?? (throw ArgumentError('--$name=... is required'));

  final model = StoryModelChoice.values.firstWhere(
    (model) => model.id == required('model'),
  );
  final effort = option('effort');
  final request = StoryUpdateRequest(
    epubPath: required('epub'),
    storePath: required('store'),
    model: model,
    effort: effort == null ? null : StoryEffort.values.byName(effort),
    checkQuotes: args.contains('--check-quotes'),
    prompt: File('assets/story_update/$updatePromptName').readAsStringSync(),
    schemaText: File('assets/story_update/story_delta.schema.json')
        .readAsStringSync(),
    sectionId: option('section'),
  );
  final out = option('out');

  final PreparedStoryUpdate? prepared;
  try {
    prepared = prepareStoryUpdate(request);
  } on StoryEpubError catch (error) {
    _fail(error.message);
  } on StoryStoreError catch (error) {
    _fail(error.message);
  }
  if (prepared == null) _fail('Every section is already in the store.');

  final title = prepared.chapter['title'];
  stdout.writeln(
    'Section: ${prepared.chapter['section_id']} ($title), '
    '${(prepared.chapter['paragraphs'] as List).length} paragraphs',
  );
  if (args.contains('--dry-run')) {
    if (out != null) {
      Directory(out).createSync(recursive: true);
      File('$out/request.json').writeAsStringSync(prepared.body);
    }
    stdout.writeln('Status: dry_run (nothing sent, store unchanged)');
    return;
  }

  final variable = '${model.providerName.toUpperCase()}_API_KEY';
  final apiKey = Platform.environment[variable]?.trim() ?? '';
  if (apiKey.isEmpty) _fail('$variable is not set');

  final ledger = _Ledger.open(
    option('ledger'),
    maxSuccesses: int.parse(option('max-successes') ?? '4'),
    maxFailures: int.parse(option('max-failures') ?? '2'),
  );
  ledger.beforeRequest();

  final started = Stopwatch()..start();
  stdout.writeln('Calling ${model.id} (effort: ${effort ?? 'not sent'})...');
  final call = await callResponsesApi(
    model: model,
    apiKey: apiKey,
    body: prepared.body,
  );
  final outcome = finishStoryUpdate(prepared, call);
  final seconds = started.elapsedMilliseconds / 1000;
  ledger.afterRequest(outcome, seconds, model.id, effort);

  stdout.writeln('Time: ${seconds.toStringAsFixed(1)} s');
  stdout.writeln('Usage: ${jsonEncode(outcome.usage)}');
  final warnings = outcome.issues.where((issue) => !issue.isError);
  final errors = outcome.issues.where((issue) => issue.isError).toList();
  stdout.writeln(
    'Issues: ${errors.length} errors, ${warnings.length} warnings, '
    '${outcome.unmatchedQuotes} unmatched quotes',
  );
  for (final issue in errors.take(20)) {
    stdout.writeln('  $issue');
  }
  if (out != null) {
    Directory(out).createSync(recursive: true);
    File('$out/outcome.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'status': outcome.status,
        'message': outcome.message,
        'category': outcome.category,
        'request_id': outcome.requestId,
        'usage': outcome.usage,
        'seconds': seconds,
        'issues': [for (final issue in outcome.issues) '$issue'],
        'output_text': outcome.outputText,
      }),
    );
  }
  if (!outcome.committed) {
    _fail(
      'Status: ${outcome.status} (${outcome.category ?? ''} '
      '${outcome.message ?? ''}); store unchanged',
    );
  }
  stdout.writeln(
    'Status: committed revision ${outcome.revision} to ${request.storePath}',
  );
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}

class _Ledger {
  _Ledger._(this.file, this.maxSuccesses, this.maxFailures, this.data);

  factory _Ledger.open(
    String? path, {
    required int maxSuccesses,
    required int maxFailures,
  }) {
    final file = path == null ? null : File(path);
    final data = file != null && file.existsSync()
        ? jsonDecode(file.readAsStringSync()) as JsonMap
        : <String, dynamic>{
            'requests': 0,
            'successes': 0,
            'failures_in_a_row': 0,
            'runs': <dynamic>[],
          };
    return _Ledger._(file, maxSuccesses, maxFailures, data);
  }

  final File? file;
  final int maxSuccesses;
  final int maxFailures;
  final JsonMap data;

  void _save() {
    final target = file;
    if (target == null) return;
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  }

  void beforeRequest() {
    if (file == null) return;
    if ((data['successes'] as int) >= maxSuccesses) {
      _fail('Refused: $maxSuccesses successful runs are used up.');
    }
    if ((data['failures_in_a_row'] as int) >= maxFailures) {
      _fail('Refused: $maxFailures failures in a row. Find out why first.');
    }
    data['requests'] = (data['requests'] as int) + 1;
    data['failures_in_a_row'] = (data['failures_in_a_row'] as int) + 1;
    _save();
  }

  void afterRequest(
    StoryUpdateOutcome outcome,
    double seconds,
    String model,
    String? effort,
  ) {
    if (file == null) return;
    if (outcome.committed) {
      data['successes'] = (data['successes'] as int) + 1;
      data['failures_in_a_row'] = 0;
    }
    (data['runs'] as List).add({
      'section': outcome.sectionTitle,
      'model': model,
      'effort': effort,
      'status': outcome.status,
      'category': outcome.category,
      'seconds': seconds,
      'usage': outcome.usage,
      'unmatched_quotes': outcome.unmatchedQuotes,
    });
    _save();
    stdout.writeln(
      'Ledger: ${data['successes']} successful, ${data['requests']} requests',
    );
  }
}
