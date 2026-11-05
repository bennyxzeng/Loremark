import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'delta_schema.dart';
import 'story_api_client.dart';
import 'story_book.dart';
import 'story_merge.dart';
import 'story_model_choice.dart';
import 'story_run_folder.dart';
import 'story_store.dart';
import 'story_validation.dart';

/// The bundled prompt's name, recorded with every revision.
const updatePromptName = 'update_story_v2.txt';

/// Sections at least this long are taken for the story when suggesting where to
/// start. Shorter ones are usually a title page or an epigraph.
const _storySectionParagraphs = 20;
final _frontMatterTitle = RegExp(
  r'\b(front ?matter|cover|title ?page|copyright|contents|dedication|epigraph|'
  r'acknowledg\w*)\b',
  caseSensitive: false,
);

/// The folder of a book's story model, inside the library folder at [library].
String storyStorePath(String library, String bookId) =>
    '$library/story_models/$bookId';

/// Why a map loaded from a single `story_model.json` can't be added to.
const storyViewOnlyReason =
    'This map was loaded from a single file, so it can only be viewed. Load the '
    'full .zip to keep updating.';

/// A section the reader can pick: where a new Story Map starts, or a later one
/// to add to an existing map.
class StorySectionChoice {
  const StorySectionChoice(
    this.sectionId,
    this.title,
    this.paragraphCount, {
    this.skips = const [],
  });

  final String sectionId;
  final String title;
  final int paragraphCount;

  /// The sections left out for good by adding this one, by title. Only for a
  /// map that already exists.
  final List<String> skips;
}

/// What pressing Update would do for a book right now.
class StoryUpdateStatus {
  const StoryUpdateStatus._({
    this.choices = const [],
    this.suggestedStart,
    this.nextSectionId,
    this.nextTitle,
    this.blocked,
  });

  /// No store yet: the reader picks where it starts, from [choices].
  const StoryUpdateStatus.newStore({
    required List<StorySectionChoice> choices,
    required String suggested,
  }) : this._(choices: choices, suggestedStart: suggested);

  /// [title] is the next section, and the first of [choices].
  const StoryUpdateStatus.ready(
    String sectionId,
    String title, {
    List<StorySectionChoice> choices = const [],
  }) : this._(nextSectionId: sectionId, nextTitle: title, choices: choices);

  /// Every section is in the store.
  const StoryUpdateStatus.finished() : this._();

  /// The next section can't be processed, for the reason given. The reader may
  /// still skip past it to one of [choices].
  const StoryUpdateStatus.blocked(
    String reason, {
    List<StorySectionChoice> choices = const [],
  }) : this._(blocked: reason, choices: choices);

  /// The sections that can be picked, in reading order.
  final List<StorySectionChoice> choices;
  final String? suggestedStart;
  final String? nextSectionId;
  final String? nextTitle;
  final String? blocked;

  bool get isNewStore => suggestedStart != null;
  bool get isReady => nextSectionId != null;
  bool get isFinished => !isNewStore && !isReady && blocked == null;

  /// Whether there is anything to pick besides pressing Update.
  bool get canChoose {
    if (isNewStore) return false;
    return isReady ? choices.length > 1 : choices.isNotEmpty;
  }

  /// The title of the choice called [sectionId], or else the next section's.
  String? titleOf(String? sectionId) =>
      choices
          .where((choice) => choice.sectionId == sectionId)
          .firstOrNull
          ?.title ??
      nextTitle;
}

/// What an update needs that doesn't come from the book or its store.
class StoryUpdateRequest {
  const StoryUpdateRequest({
    required this.epubPath,
    required this.storePath,
    required this.model,
    required this.effort,
    required this.checkQuotes,
    required this.prompt,
    required this.schemaText,
    this.sectionId,
    this.runsPath,
  });

  final String epubPath;
  final String storePath;
  final StoryModelChoice model;
  final StoryEffort? effort;

  /// Whether a quote missing from its paragraph fails the update. Off, it's
  /// only a warning, and the store remembers that for the section.
  final bool checkQuotes;
  final String prompt;
  final String schemaText;

  /// The section to add: where a new store starts, or a later one to skip ahead
  /// to. Null for an existing store means the next section.
  final String? sectionId;

  /// The folder to keep a [StoryRunFolder] of this update in, if any.
  final String? runsPath;
}

/// An update ready to send: everything a finished call is checked against.
class PreparedStoryUpdate {
  const PreparedStoryUpdate({
    required this.request,
    required this.state,
    required this.chapter,
    required this.sectionOrder,
    required this.body,
    required this.hashes,
    required this.runId,
    this.run,
  });

  final StoryUpdateRequest request;
  final StoryStoreState state;
  final JsonMap chapter;
  final int sectionOrder;

  /// The JSON body to send.
  final String body;
  final JsonMap hashes;
  final String runId;
  final StoryRunFolder? run;
}

/// How an update ended. Failing never changes the store.
class StoryUpdateOutcome {
  const StoryUpdateOutcome(
    this.status, {
    this.message,
    this.sectionTitle,
    this.revision,
    this.usage,
    this.issues = const [],
    this.category,
  });

  /// `committed`, or the lab's name for what went wrong: `input_error`,
  /// `api_error`, `refusal`, `incomplete`, `failed`, `empty_output`,
  /// `schema_invalid`, `validation_failed`, `stale_base` or `commit_failed`.
  final String status;
  final String? message;
  final String? sectionTitle;

  /// The new revision's number, once committed.
  final int? revision;
  final JsonMap? usage;
  final List<StoryIssue> issues;

  /// For an `api_error`: `authentication`, `rate_limit`, `network` and so on.
  final String? category;

  bool get committed => status == 'committed';

  /// How many quotes weren't found in their paragraph, with the check off.
  int get unmatchedQuotes =>
      issues.where((issue) => issue.code == 'quote_not_found').length;
}

/// Reads the store at [storePath] for showing it, or null if there is none.
JsonMap? readStoryModel(String storePath) {
  recoverReplacedStore(storePath);
  return StoryStore(Directory(storePath)).readLatest();
}

/// What pressing Update would do for the book at [epubPath].
StoryUpdateStatus inspectStoryUpdate(String epubPath, String storePath) {
  try {
    final book = StoryBook.open(File(epubPath).readAsBytesSync());
    final store = StoryStore(Directory(storePath));
    final model = store.readLatest();
    if (model == null) return _newStoreStatus(book);
    if (!store.hasSnapshotOf(model)) {
      return const StoryUpdateStatus.blocked(storyViewOnlyReason);
    }
    checkStoryContinues(model, book);
    final choices = _laterChoices(model, book);
    try {
      final next = _nextSection(model, book);
      if (next == null) return const StoryUpdateStatus.finished();
      return StoryUpdateStatus.ready(
        next.$1.sectionId,
        next.$1.title,
        choices: choices,
      );
    } on StoryEpubError catch (error) {
      return StoryUpdateStatus.blocked(error.message, choices: choices);
    }
  } on StoryEpubError catch (error) {
    return StoryUpdateStatus.blocked(error.message);
  } on StoryStoreError catch (error) {
    return StoryUpdateStatus.blocked(error.message);
  } on FileSystemException catch (error) {
    return StoryUpdateStatus.blocked(error.message);
  }
}

StoryUpdateStatus _newStoreStatus(StoryBook book) {
  final choices = <StorySectionChoice>[];
  for (final section in book.sections) {
    if (section.problem != null) continue;
    try {
      final paragraphs = book.extract(section)['paragraphs'] as List;
      choices.add(
        StorySectionChoice(section.sectionId, section.title, paragraphs.length),
      );
    } on StoryEpubError {
      // Nothing to start from here: no text, or no reliable end.
    }
  }
  if (choices.isEmpty) {
    return const StoryUpdateStatus.blocked(
      'No section of this book can be read reliably.',
    );
  }
  final suggested =
      choices
          .where(
            (choice) =>
                choice.paragraphCount >= _storySectionParagraphs &&
                !_frontMatterTitle.hasMatch(choice.title),
          )
          .firstOrNull ??
      choices.first;
  return StoryUpdateStatus.newStore(
    choices: choices,
    suggested: suggested.sectionId,
  );
}

/// Checks that [model] was built from [book], so sections still mean the same.
/// Throws a [StoryEpubError] if not.
void checkStoryContinues(JsonMap model, StoryBook book) {
  final bookRef = model['book'] as JsonMap;
  if (book.sha256Hash != bookRef['epub_sha256']) {
    throw const StoryEpubError(
      'This EPUB is not the file the Story Map was built from.',
    );
  }
  final byId = {for (final s in book.sections) s.sectionId: s};
  final processed = (model['processed_sections'] as List).cast<JsonMap>();
  for (final source in processed) {
    final current = byId[source['section_id']];
    if (current == null ||
        current.order != source['section_order'] ||
        current.href != source['href'] ||
        current.fragment != source['fragment'] ||
        current.title != source['title']) {
      throw StoryEpubError(
        '${source['section_id']} no longer maps to the same place in the book, '
        'so this Story Map cannot be continued.',
      );
    }
  }
}

int _lastProcessedOrder(JsonMap model) =>
    (model['processed_sections'] as List).cast<JsonMap>().last['section_order']
        as int;

/// The section to add after [model]'s last, with its text; null when none is
/// left. Sections with no text, such as a full-page illustration, are stepped
/// over: they hold nothing to learn, and stopping at one would end the map
/// there for good. A section that can't be cut reliably does stop it, since
/// stepping over that unasked could lose text. The reader can choose to.
(StoryBookSection, JsonMap)? _nextSection(JsonMap model, StoryBook book) {
  final last = _lastProcessedOrder(model);
  for (final section in book.sections.where((s) => s.order > last)) {
    if (section.problem != null) {
      throw StoryEpubError(
        '${section.title} cannot be read reliably, so updating stops here for '
        'now (${section.problem}).',
      );
    }
    try {
      return (section, book.extract(section));
    } on StorySectionEmptyError {
      continue;
    }
  }
  return null;
}

/// The sections that can be added after [model]'s last, in reading order, each
/// with what adding it would leave out. A section with no text isn't left out,
/// having nothing to lose. One that can't be read can't be picked, but is.
List<StorySectionChoice> _laterChoices(JsonMap model, StoryBook book) {
  final last = _lastProcessedOrder(model);
  final choices = <StorySectionChoice>[];
  final skips = <String>[];
  for (final section in book.sections.where((s) => s.order > last)) {
    try {
      if (section.problem != null) throw StoryEpubError(section.problem!);
      final paragraphs = book.extract(section)['paragraphs'] as List;
      choices.add(
        StorySectionChoice(
          section.sectionId,
          section.title,
          paragraphs.length,
          skips: [...skips],
        ),
      );
    } on StorySectionEmptyError {
      continue;
    } on StoryEpubError {
      // Can't be picked, so falls through to being left out.
    }
    skips.add(section.title);
  }
  return choices;
}

/// The section called [sectionId], with its text, if it can be added to [model].
/// Sections only go in reading order, since each is built on those before it, so
/// nothing at or before the last processed one can be added.
(StoryBookSection, JsonMap) _chosenSection(
  JsonMap model,
  StoryBook book,
  String sectionId,
) {
  final section = book.sections
      .where((section) => section.sectionId == sectionId)
      .firstOrNull;
  if (section == null) {
    throw StoryEpubError('This book has no section "$sectionId".');
  }
  if (section.order <= _lastProcessedOrder(model)) {
    throw StoryEpubError(
      '${section.title} comes before the end of the Story Map, and sections '
      'can only be added in reading order.',
    );
  }
  return (section, book.extract(section));
}

JsonMap _emptyModel(StoryBook book, StoryBookSection start) => {
  'schema_version': '2.0',
  'scope': 'cumulative',
  'book': {'title': book.title, 'epub_sha256': book.sha256Hash},
  'revision': <String, dynamic>{
    'number': 0,
    'id': '',
    'created_at': '',
    'source_run_id': '',
    'parent_snapshot_path': null,
    'parent_sha256': null,
  },
  'processed_sections': <dynamic>[],
  'coverage': {
    'start_section_id': start.sectionId,
    'omitted_prefix_section_ids': [
      for (final section in book.sections)
        if (section.order < start.order) section.sectionId,
    ],
  },
  'entities': <dynamic>[],
  'records': {for (final name in storyCollections) name: <dynamic>[]},
  'transitions': <dynamic>[],
  'current': {
    'active_record_ids': <dynamic>[],
    'resolved_uncertainty_ids': <dynamic>[],
    'identity_groups': <dynamic>[],
  },
  'provenance': {'manual_corrections': <dynamic>[]},
};

String _randomHex(int bytes) {
  final random = Random.secure();
  return [
    for (var i = 0; i < bytes; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

String _newRunId() {
  final stamp = storyUtcNow().replaceAll('-', '').replaceAll(':', '');
  return '$stamp-${_randomHex(3)}';
}

/// Everything that can fail without the model: finds the next section and builds
/// its request, so nothing is paid for if the book or the store is at fault.
///
/// Throws a [StoryEpubError] or a [StoryStoreError] if it can't. Returns null
/// when there is nothing left to process.
PreparedStoryUpdate? prepareStoryUpdate(StoryUpdateRequest request) {
  final book = StoryBook.open(File(request.epubPath).readAsBytesSync());
  final store = StoryStore(Directory(request.storePath));
  final StoryStoreState state;
  final JsonMap chapter;
  final int sectionOrder;
  if (store.exists) {
    state = store.load();
    checkStoryContinues(state.model, book);
    final next = request.sectionId == null
        ? _nextSection(state.model, book)
        : _chosenSection(state.model, book, request.sectionId!);
    if (next == null) return null;
    chapter = next.$2;
    sectionOrder = next.$1.order;
  } else {
    store.ensureNew();
    final start = book.sections
        .where((section) => section.sectionId == request.sectionId)
        .firstOrNull;
    if (start == null) {
      throw const StoryStoreError(
        'A new Story Map needs a section to start from.',
      );
    }
    chapter = book.extract(start);
    sectionOrder = start.order;
    state = StoryStoreState(model: _emptyModel(book, start), inputs: const {});
  }

  final schema = jsonDecode(request.schemaText) as JsonMap;
  final context = buildUpdateContext(
    state.model,
    chapter,
    sectionOrder: sectionOrder,
  );
  final body = buildUpdateRequest(
    context: context,
    prompt: request.prompt,
    schema: schema,
    model: request.model,
    effort: request.effort,
  );
  final hashes = {
    'text_sha256': chapter['text_sha256'],
    'prompt_sha256': sha256OfBytes(utf8.encode(request.prompt)),
    'schema_sha256': sha256OfJson(schema),
    'context_sha256': sha256OfJson(context),
    'base_sha256': state.latestSha256,
  };
  final runId = _newRunId();
  final runsPath = request.runsPath;
  return PreparedStoryUpdate(
    request: request,
    state: state,
    chapter: chapter,
    sectionOrder: sectionOrder,
    body: jsonEncode(body),
    hashes: hashes,
    runId: runId,
    run: runsPath == null
        ? null
        : StoryRunFolder.start(
            runsPath: runsPath,
            runId: runId,
            book: book,
            epubPath: request.epubPath,
            storePath: request.storePath,
            chapter: chapter,
            sectionOrder: sectionOrder,
            prompt: request.prompt,
            promptSource: _promptSource,
            schema: schema,
            context: context,
            requestBody: body,
            model: request.model,
            effort: request.effort,
            checkQuotes: request.checkQuotes,
            hashes: hashes,
            state: state,
          ),
  );
}

const _promptSource = 'builtin:$updatePromptName';

/// A failure as the lab records it in `failure.json`.
JsonMap _failureRecord(
  StoryCallResult call,
  String status,
  StoryUpdateValidation? validation,
) => {
  'status': status,
  'error': call.status == 'completed' && validation != null
      ? {
          'category': 'validation',
          'message': '${validation.errors.length} errors; see validation.json',
        }
      : call.error,
  'response_id': call.responseId,
  'request_id': call.requestId,
  'usage': call.usage,
  'output_text': call.candidate == null ? call.outputText : null,
};

JsonMap _commitFailure(String status, String message) => {
  'status': status,
  'error': {'category': status, 'message': message},
};

String _failureStatus(String callStatus, StoryUpdateValidation? validation) {
  if (callStatus == 'parse_error') return 'schema_invalid';
  if (callStatus != 'completed') return callStatus;
  if (validation == null) return 'empty_output';
  return validation.structureValid ? 'validation_failed' : 'schema_invalid';
}

/// Checks what the model returned and, if it passes, commits a new revision.
StoryUpdateOutcome finishStoryUpdate(
  PreparedStoryUpdate prepared,
  StoryCallResult call,
) {
  final PreparedStoryUpdate(:request, :state, :chapter, :run) = prepared;
  // First of all, so that nothing below can lose what was paid for.
  run?.recordCall(call);
  final title = chapter['title'] as String;
  final base = state.model;
  final number = ((base['revision'] as JsonMap)['number'] as int) + 1;
  final (section, inputPath, inputData) = sectionSource(
    chapter,
    sectionOrder: prepared.sectionOrder,
    revision: number,
    quotesChecked: request.checkQuotes,
  );
  final revision = <String, dynamic>{
    'number': number,
    'id': _randomHex(6),
    'created_at': storyUtcNow(),
    'source_run_id': prepared.runId,
    'parent_snapshot_path': state.snapshotPath,
    'parent_sha256': state.latestSha256,
  };

  StoryUpdateValidation? validation;
  if (call.status == 'completed') {
    validation = validateUpdate(
      base,
      call.candidate,
      schema: StoryDeltaSchema.parse(request.schemaText),
      chapter: chapter,
      baseInputs: state.inputs,
      section: section,
      revision: revision,
    );
    run?.recordValidation(validation);
  }

  if (call.status != 'completed' || validation == null || !validation.passed) {
    final status = _failureStatus(call.status, validation);
    run?.finish(status, failure: _failureRecord(call, status, validation));
    return StoryUpdateOutcome(
      status,
      message: call.error?['message'] as String?,
      category: call.error?['category'] as String?,
      sectionTitle: title,
      usage: call.usage,
      issues: validation?.issues ?? const [],
    );
  }

  final after = validation.after!;
  final candidateRevision = {'number': number, 'id': revision['id']};
  final files = <String, List<int>>{
    inputPath: inputData,
    ..._provenanceFiles(prepared, call, validation, section, revision),
  };
  try {
    StoryStore(Directory(request.storePath))
        .commit(after, files, expectedBaseSha256: state.latestSha256);
  } on StaleBaseError catch (error) {
    run?.finish(
      'stale_base',
      failure: _commitFailure('stale_base', error.message),
      commitStatus: 'stale_base',
      candidateRevision: candidateRevision,
    );
    return StoryUpdateOutcome(
      'stale_base',
      message: error.message,
      sectionTitle: title,
      usage: call.usage,
    );
  } on StoryStoreError catch (error) {
    return _commitFailed(run, error.message, candidateRevision, title, call);
  } on FileSystemException catch (error) {
    return _commitFailed(run, error.message, candidateRevision, title, call);
  }
  run?.finish(
    'committed',
    commitStatus: 'committed',
    candidateRevision: candidateRevision,
    committedRevision: candidateRevision,
  );
  return StoryUpdateOutcome(
    'committed',
    sectionTitle: title,
    revision: number,
    usage: call.usage,
    issues: validation.issues,
  );
}

StoryUpdateOutcome _commitFailed(
  StoryRunFolder? run,
  String message,
  JsonMap candidateRevision,
  String title,
  StoryCallResult call,
) {
  run?.finish(
    'commit_failed',
    failure: _commitFailure('commit_failed', message),
    commitStatus: 'failed',
    candidateRevision: candidateRevision,
  );
  return StoryUpdateOutcome(
    'commit_failed',
    message: message,
    sectionTitle: title,
    usage: call.usage,
  );
}

/// What the store keeps about an update: the delta, ID map and base it was
/// applied to, under `provenance/<run id>/`.
Map<String, List<int>> _provenanceFiles(
  PreparedStoryUpdate prepared,
  StoryCallResult call,
  StoryUpdateValidation validation,
  JsonMap section,
  JsonMap revision,
) {
  final state = prepared.state;
  final baseRevision = state.model['revision'] as JsonMap;
  final files = <String, List<int>>{
    'delta.candidate.json': storyJsonBytes(call.candidate),
    'delta.json': storyJsonBytes(validation.delta),
    'id_map.json': storyJsonBytes(validation.idMap!.toJson()),
    'commit.json': storyJsonBytes({
      'run_id': prepared.runId,
      'base_revision': state.isNew
          ? null
          : {
              'number': baseRevision['number'],
              'id': baseRevision['id'],
              'sha256': state.latestSha256,
              'snapshot_path': state.snapshotPath,
            },
      'revision': {'number': revision['number'], 'id': revision['id']},
      'section_id': section['section_id'],
      'input_relative_path': section['input_relative_path'],
      'provider': prepared.request.model.providerName,
      'model': prepared.request.model.id,
      'response_model': call.responseModel,
      'response_id': call.responseId,
      'usage': call.usage,
      'prompt_source': _promptSource,
      'hashes': prepared.hashes,
      'manual_corrections': const <dynamic>[],
    }),
  };
  final directory = 'provenance/${prepared.runId}';
  return {
    for (final MapEntry(key: name, value: data) in files.entries)
      '$directory/$name': data,
    '$directory/manifest.json': storyManifestBytes(files, prepared.runId),
  };
}

/// An update on its way, for finding it again after leaving the book.
class RunningStoryUpdate {
  const RunningStoryUpdate(this.outcome, this.startedAt, this.sectionId);

  final Future<StoryUpdateOutcome> outcome;
  final DateTime startedAt;

  /// The section asked for, or null for the next one.
  final String? sectionId;
}

/// Runs updates, one at a time per book.
///
/// The reader may leave the book while one runs. It is already paid for, so it
/// carries on and commits, and coming back finds it through [running].
class StoryUpdater {
  StoryUpdater._();

  static final _running = <String, RunningStoryUpdate>{};

  /// The update running for the book [bookId], if any.
  static RunningStoryUpdate? running(String bookId) => _running[bookId];

  /// Adds the section asked for, or the next one. Never throws: every way of
  /// failing is an outcome, and none of them changes the store.
  static Future<StoryUpdateOutcome> run(
    StoryUpdateRequest request, {
    required String bookId,
    required String apiKey,
    StoryHttpPost post = postStoryRequest,
  }) {
    final existing = _running[bookId];
    if (existing != null) return existing.outcome;
    final outcome = _run(request, apiKey, post).whenComplete(() {
      // In a block, so as not to return the removed update: `whenComplete`
      // would wait for a future it got back, and this is that future.
      _running.remove(bookId);
    });
    _running[bookId] = RunningStoryUpdate(
      outcome,
      DateTime.now(),
      request.sectionId,
    );
    return outcome;
  }

  static Future<StoryUpdateOutcome> _run(
    StoryUpdateRequest request,
    String apiKey,
    StoryHttpPost post,
  ) async {
    PreparedStoryUpdate? prepared;
    try {
      final ready = await Isolate.run(() => prepareStoryUpdate(request));
      prepared = ready;
      if (ready == null) {
        return const StoryUpdateOutcome(
          'input_error',
          message: 'Every section is already in the Story Map.',
        );
      }
      final call = await callResponsesApi(
        model: request.model,
        apiKey: apiKey,
        body: ready.body,
        post: post,
      );
      return await Isolate.run(() => finishStoryUpdate(ready, call));
    } on StoryEpubError catch (error) {
      return StoryUpdateOutcome('input_error', message: error.message);
    } on StoryStoreError catch (error) {
      return StoryUpdateOutcome('input_error', message: error.message);
    } on FileSystemException catch (error) {
      return StoryUpdateOutcome('input_error', message: error.message);
    } on Object catch (error) {
      // Whatever it is, the reader mustn't be left waiting.
      final message = redactStoryKey('$error', apiKey);
      prepared?.run?.recordCrash(error, message);
      return StoryUpdateOutcome('input_error', message: 'Unexpected: $message');
    }
  }
}
