import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:loremark/ask/ask_boundary.dart';
import 'package:loremark/ask/ask_engine.dart';
import 'package:loremark/ask/story_lookup.dart';
import 'package:loremark/reader/epub_sections.dart';
import 'package:loremark/reading/text_position.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/story_model/story_snapshot.dart';
import 'package:loremark/story_update/story_book.dart';
import 'package:loremark/story_update/story_model_choice.dart';
import 'package:loremark/story_update/story_paragraphs.dart';
import 'package:loremark/story_update/story_store.dart';
import 'package:loremark/story_update/story_updater.dart';

/// Asks a question about a book from the command line, with the app's own
/// code, as a reader at a chosen point would.
///
///   dart run tool/ask/run.dart --epub=book.epub --store=some/store \
///     --through=section-005:40 --model=gpt-6.1-terra --effort=high \
///     --question="Who is Lena?"
///
/// `--through=<section id>` puts the reader at the end of that section of the
/// Story Map, and `--through=<section id>:<n>` after its first n paragraphs.
/// The page they see is the last [pageTextWindow] characters of what they have
/// read, which is close to what the app sends.
///
/// Spends nothing with either of these:
/// - `--dry-run` prints what the first request would send.
/// - `--tool=<name> --args=<json>` runs one lookup and prints its answer.
///
/// Otherwise the provider's key comes from DEEPSEEK_API_KEY or OPENAI_API_KEY,
/// and is never printed or saved. One question can take up to `--max-rounds`
/// paid requests (default $maxAskRounds).
Future<void> main(List<String> args) async {
  String? option(String name) => args
      .where((arg) => arg.startsWith('--$name='))
      .map((arg) => arg.substring(name.length + 3))
      .firstOrNull;
  String required(String name) =>
      option(name) ?? (throw ArgumentError('--$name=... is required'));

  final storePath = required('store');
  final epubPath = required('epub');
  final json = readStoryModel(storePath);
  if (json == null) _fail('No Story Map at $storePath');
  final model = StoryModel.fromJson(json);

  final StoryReadingProgress progress;
  try {
    progress = _progress(model, storePath, epubPath, required('through'));
  } on StoryStoreError catch (error) {
    _fail(error.message);
  } on StoryEpubError catch (error) {
    _fail(error.message);
  }
  final paragraphs = readStoryParagraphs(storePath, epubPath, progress);
  final read = [
    for (final section in model.sections.take(progress.shown))
      ...paragraphs.ofSection(section.id),
  ];
  final page = _pageOf(read);
  final boundary = AskBoundary(
    reach: AskReach(
      progress: progress,
      limit: const TextPosition(0, 0),
      page: page,
    ),
    model: model,
    paragraphs: paragraphs,
  );
  stderr.writeln(
    'Reader: ${progress.finished} section(s) finished'
    '${progress.hiddenInNext == null ? '' : ', ${progress.paragraphsReadInNext} paragraph(s) into the next'}'
    '; ${read.length} paragraph(s) visible.',
  );

  final lookup = StoryLookup(boundary);
  final tool = option('tool');
  if (tool != null) {
    stdout.writeln(lookup.run(tool, option('args') ?? '{}'));
    return;
  }

  final choice = StoryModelChoice.values.firstWhere(
    (model) => model.id == required('model'),
  );
  final effortName = option('effort');
  final effort = effortName == null
      ? null
      : StoryEffort.values.byName(effortName);
  final prompt = File('assets/chat/$askPromptName').readAsStringSync();
  final question = required('question');

  if (args.contains('--dry-run')) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(
        buildAskRequest(
          model: choice,
          effort: effort,
          instructions: '$prompt\n\n${lookup.overview()}',
          input: [
            {'role': 'user', 'content': askMessage(page, question)},
          ],
          tools: lookup.tools,
          lastRound: false,
        ),
      ),
    );
    stderr.writeln('Status: dry_run (nothing sent)');
    return;
  }

  final variable = '${choice.providerName.toUpperCase()}_API_KEY';
  final apiKey = Platform.environment[variable]?.trim() ?? '';
  if (apiKey.isEmpty) _fail('$variable is not set');

  var round = 0;
  final answer = await askStory(
    boundary: boundary,
    question: question,
    prompt: prompt,
    model: choice,
    effort: effort,
    apiKey: apiKey,
    maxRounds: int.parse(option('max-rounds') ?? '$maxAskRounds'),
    onRound: () => stderr.writeln('-- request ${++round}'),
    onText: stdout.write,
    onLookup: (tools) => stderr.writeln('   looking up: ${tools.join(', ')}'),
  );
  stdout.writeln();
  stderr.writeln('Status: ${answer.status} in ${answer.rounds} request(s)');
  if (answer.error case final error?) stderr.writeln('Error: $error');
  for (final (i, counts) in answer.usage.indexed) {
    stderr.writeln('Usage ${i + 1}: ${jsonEncode(counts)}');
  }
  stdout
    ..writeln('---- kept answer')
    ..writeln(answer.text);
}

/// Where `--through` puts the reader.
StoryReadingProgress _progress(
  StoryModel model,
  String storePath,
  String epubPath,
  String through,
) {
  final [id, ...rest] = through.split(':');
  final index = model.sections.indexWhere((section) => section.id == id);
  if (index == -1) _fail('$id is not in the Story Map');
  if (rest.isEmpty) return StoryReadingProgress(index + 1);
  final read = int.parse(rest.single);
  if (read <= 0) return StoryReadingProgress(index);
  final all = readStoryParagraphs(
    storePath,
    epubPath,
    StoryReadingProgress(index + 1),
  ).ofSection(id);
  if (read >= all.length) return StoryReadingProgress(index + 1);
  return StoryReadingProgress(
    index,
    hiddenInNext: hiddenWithinSection(
      model,
      model.sections[index],
      all,
      paragraphsRead: read,
    ),
    paragraphsReadInNext: read,
  );
}

/// The last [pageTextWindow] characters of [read], as the reader's page.
AskPage? _pageOf(List<StoryParagraph> read) {
  if (read.isEmpty) return null;
  final lines = <String>[];
  var length = 0;
  for (final paragraph in read.reversed) {
    if (length > 0 && length + paragraph.text.length > pageTextWindow) break;
    lines.insert(0, paragraph.text);
    length += paragraph.text.length + 2;
  }
  final text = lines.join('\n\n');
  return AskPage(
    text.substring(max(0, text.length - pageTextWindow)),
    const TextPosition(0, 0),
  );
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
