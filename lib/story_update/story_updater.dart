import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'delta_schema.dart';
import 'story_api_client.dart';
import 'story_book.dart';
import 'story_merge.dart';
import 'story_model_choice.dart';
import 'story_quotes.dart';
import 'story_run_folder.dart';
import 'story_section_kind.dart';
import 'story_store.dart';
import 'story_validation.dart';

/// The bundled prompt's name, recorded with every revision.
const updatePromptName = 'update_story_v2.txt';

/// Sections at least this long are taken for the story when suggesting where to
/// start. Shorter ones are usually a title page or an epigraph.
const _storySectionParagraphs = 20;

/// The folder of a book's story model, inside the library folder at [library].
String storyStorePath(String library, String bookId) =>
    '$library/story_models/$bookId';

/// Why a map loaded from a single `story_model.json` can't be added to.
const storyViewOnlyReason =
    'This map was loaded from a single file, so it can only be viewed. Load the '
    'full .zip to keep updating.';

/// A section of the book that could go in the Story Map: where a new map
/// starts, or a later one to add to an existing map. Sections with no text
/// aren't listed, having nothing to add.
class StorySectionChoice {
  const StorySectionChoice(
    this.sectionId,
    this.title,
    this.paragraphCount, {
    this.kind = StorySectionKind.story,
    this.problem,
  });

  final String sectionId;
  final String title;
  final int paragraphCount;

  /// What part of the book it looks like.
  final StorySectionKind kind;

  /// Why it can't be added, if it can't. It is still listed, since picking a
  /// section after it leaves it out for good.
  final String? problem;

  bool get canPick => problem == null;
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

  /// The sections that could be picked, in reading order. Those with a
  /// [StorySectionChoice.problem] can't be.
  final List<StorySectionChoice> choices;
  final String? suggestedStart;
  final String? nextSectionId;
  final String? nextTitle;
  final String? blocked;

  bool get isNewStore => suggestedStart != null;
  bool get isReady => nextSectionId != null;
  bool get isFinished => !isNewStore && !isReady && blocked == null;

  /// The next section, which Update adds; null unless [isReady].
  StorySectionChoice? get next {
    final id = nextSectionId;
    if (id == null) return null;
    return choices.where((choice) => choice.sectionId == id).firstOrNull ??
        StorySectionChoice(id, nextTitle ?? id, 0);
  }

  /// The sections that can be picked.
  Iterable<StorySectionChoice> get pickable =>
      choices.where((choice) => choice.canPick);

  /// Whether there is anything to pick besides pressing Update.
  bool get canChoose {
    if (isNewStore) return false;
    return pickable.length > (isReady ? 1 : 0);
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

  /// This request, for the section called [sectionId].
  StoryUpdateRequest forSection(String sectionId) => StoryUpdateRequest(
    epubPath: epubPath,
    storePath: storePath,
    model: model,
    effort: effort,
    checkQuotes: checkQuotes,
    prompt: prompt,
    schemaText: schemaText,
    sectionId: sectionId,
    runsPath: runsPath,
  );
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
  /// Or `cancelled`, which the lab doesn't have, if the reader stopped it.
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
  final choices = _choices(book, book.sections);
  final pickable = choices.where((choice) => choice.canPick);
  if (pickable.isEmpty) {
    return const StoryUpdateStatus.blocked(
      'No section of this book can be read reliably.',
    );
  }
  final story = pickable.where(
    (choice) => choice.kind == StorySectionKind.story,
  );
  final suggested =
      story
          .where((choice) => choice.paragraphCount >= _storySectionParagraphs)
          .firstOrNull ??
      story.firstOrNull ??
      pickable.first;
  return StoryUpdateStatus.newStore(
    choices: choices,
    suggested: suggested.sectionId,
  );
}

/// [sections] as choices, in reading order. Those with no text are left out,
/// having nothing to add or to lose. Those that can't be read are listed with
/// why, since picking one after them leaves them out.
List<StorySectionChoice> _choices(
  StoryBook book,
  Iterable<StoryBookSection> sections,
) {
  final choices = <StorySectionChoice>[];
  for (final section in sections) {
    try {
      if (section.problem != null) throw StoryEpubError(section.problem!);
      final chapter = book.extract(section);
      choices.add(
        StorySectionChoice(
          section.sectionId,
          section.title,
          (chapter['paragraphs'] as List).length,
          kind: book.kindOf(section, chapter),
        ),
      );
    } on StorySectionEmptyError {
      continue;
    } on StoryEpubError catch (error) {
      choices.add(
        StorySectionChoice(
          section.sectionId,
          section.title,
          0,
          kind: book.kindOf(section, null),
          problem: error.message,
        ),
      );
    }
  }
  return choices;
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

/// The sections after [model]'s last, in reading order: see [_choices].
List<StorySectionChoice> _laterChoices(JsonMap model, StoryBook book) {
  final last = _lastProcessedOrder(model);
  return _choices(book, book.sections.where((s) => s.order > last));
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
    // Before the lab's checks, which are kept as they are: the answer's
    // quotes that slipped are put back to the book's text.
    final (candidate, repairs) = repairStoryQuotes(call.candidate, chapter);
    validation = validateUpdate(
      base,
      candidate,
      schema: StoryDeltaSchema.parse(request.schemaText),
      chapter: chapter,
      baseInputs: state.inputs,
      section: section,
      revision: revision,
    ).withQuoteRepairs(repairs);
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
      'quote_repair_version': storyQuoteRepairVersion,
      'quote_repairs': [
        for (final repair in validation.quoteRepairs)
          ...repair.corrections(revision['created_at'] as String),
      ],
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
  const RunningStoryUpdate(
    this.outcome,
    this.startedAt,
    this.sectionId, {
    this.cancel,
  });

  final Future<StoryUpdateOutcome> outcome;
  final DateTime startedAt;

  /// The section asked for, or null for the next one.
  final String? sectionId;

  /// Stops it while it can still be stopped: see [StoryUpdater.cancel].
  final StoryCancel? cancel;
}

/// How a run of sections ended: an outcome for each section it got to, in
/// order. It got to at least the first.
class StoryBatchOutcome {
  const StoryBatchOutcome(this.sections, this.outcomes);

  /// The sections asked for, in reading order.
  final List<StorySectionChoice> sections;
  final List<StoryUpdateOutcome> outcomes;

  int get total => sections.length;

  /// How many sections went into the map.
  int get added => outcomes.where((outcome) => outcome.committed).length;

  /// How the last section it got to ended.
  StoryUpdateOutcome get last => outcomes.last;

  /// The last section it got to.
  StorySectionChoice get lastSection => sections[outcomes.length - 1];

  /// Every section went in.
  bool get complete => last.committed && outcomes.length == total;

  /// The reader cancelled the last section it got to.
  bool get cancelled => last.status == 'cancelled';

  /// The last section it got to failed, which stopped the rest.
  bool get failed => !last.committed && !cancelled;

  /// The reader stopped it after a section that went in.
  bool get stopped => last.committed && outcomes.length < total;

  /// How many quotes weren't found in their paragraph, in every section.
  int get unmatchedQuotes =>
      outcomes.fold(0, (total, outcome) => total + outcome.unmatchedQuotes);
}

/// Sections being added one after another, in reading order, for finding them
/// again after leaving the book. It stops at the first that doesn't go in.
class RunningStoryBatch {
  /// Starts adding [sections], each with [update]. [onCancel] stops the one
  /// under way: see [cancel]. [clock] tells the time; tests replace it.
  RunningStoryBatch(
    this.sections,
    Future<StoryUpdateOutcome> Function(StorySectionChoice section) update, {
    this._onCancel,
    this._clock = DateTime.now,
  }) : assert(sections.isNotEmpty),
       startedAt = _clock(),
       _currentStartedAt = _clock() {
    done = _run(update);
  }

  /// The sections asked for, in reading order.
  final List<StorySectionChoice> sections;

  /// When the first section began.
  final DateTime startedAt;
  final void Function()? _onCancel;
  final DateTime Function() _clock;
  final _outcomes = <StoryUpdateOutcome>[];
  int _index = 0;
  DateTime _currentStartedAt;
  bool _stopping = false;
  bool _cancelling = false;
  final _changes = StreamController<void>.broadcast(sync: true);

  /// How it ended, once it has.
  late final Future<StoryBatchOutcome> done;

  int get total => sections.length;

  /// How each section it has got through ended, so far.
  List<StoryUpdateOutcome> get outcomes => List.unmodifiable(_outcomes);

  /// The section under way, or the last one to be, counted from 0.
  int get index => _index;
  StorySectionChoice get current => sections[_index];

  /// When the section under way began.
  DateTime get currentStartedAt => _currentStartedAt;

  /// Whether the reader asked to stop once the section under way is done.
  bool get stopping => _stopping;

  /// Whether the reader cancelled the section under way.
  bool get cancelling => _cancelling;

  /// Fires as a section begins and ends, and when the reader asks to stop.
  Stream<void> get changes => _changes.stream;

  /// Lets the section under way finish and go in, and starts no more.
  void stopAfterCurrent() {
    if (_stopping || _changes.isClosed) return;
    _stopping = true;
    _changes.add(null);
  }

  /// Stops the section under way if it still can be, and starts no more.
  void cancel() {
    _cancelling = true;
    _onCancel?.call();
  }

  Future<StoryBatchOutcome> _run(
    Future<StoryUpdateOutcome> Function(StorySectionChoice section) update,
  ) async {
    for (var i = 0; i < sections.length; i++) {
      // A cancel that came as one section ended still stops the next.
      if (i > 0 && (_stopping || _cancelling)) break;
      _index = i;
      _currentStartedAt = _clock();
      _changes.add(null);
      final outcome = await update(sections[i]);
      _outcomes.add(outcome);
      _changes.add(null);
      if (!outcome.committed) break;
    }
    await _changes.close();
    return StoryBatchOutcome(sections, List.unmodifiable(_outcomes));
  }
}

/// Runs updates, one at a time per book.
///
/// The reader may leave the book while one runs. It is already paid for, so it
/// carries on and commits, and coming back finds it through [running]. Only
/// the reader can stop one: see [cancel].
class StoryUpdater {
  StoryUpdater._();

  static final _running = <String, RunningStoryUpdate>{};
  static final _batches = <String, RunningStoryBatch>{};

  /// The update running for the book [bookId], if any.
  static RunningStoryUpdate? running(String bookId) => _running[bookId];

  /// The sections being added to the book [bookId], if any.
  static RunningStoryBatch? batch(String bookId) => _batches[bookId];

  /// Whether anything is being added to the book [bookId].
  static bool busy(String bookId) =>
      _running.containsKey(bookId) || _batches.containsKey(bookId);

  /// Stops the update running for the book [bookId], if it is still waiting
  /// for the provider. It ends `cancelled`, and nothing is saved. Once the
  /// provider has answered, the answer has been paid for, so it is checked and
  /// committed as usual. Either way, no more of its sections are started.
  static void cancel(String bookId) {
    final batch = _batches[bookId];
    if (batch != null) return batch.cancel();
    _running[bookId]?.cancel?.cancel();
  }

  /// Adds [sections] one after another, in reading order, each with [request]
  /// for it, and stops at the first that doesn't go in. Sections between them
  /// are left out for good. Nothing is retried. If sections are already being
  /// added to the book, returns those.
  static RunningStoryBatch runSections(
    StoryUpdateRequest request,
    List<StorySectionChoice> sections, {
    required String bookId,
    required String apiKey,
    StoryHttpPost? post,
  }) {
    assert(sections.isNotEmpty);
    final existing = _batches[bookId];
    if (existing != null) return existing;
    final batch = RunningStoryBatch(
      sections,
      (section) => run(
        request.forSection(section.sectionId),
        bookId: bookId,
        apiKey: apiKey,
        post: post,
      ),
      onCancel: () => _running[bookId]?.cancel?.cancel(),
    );
    _batches[bookId] = batch;
    batch.done.whenComplete(() {
      // In a block, so as not to return the removed batch.
      _batches.remove(bookId);
    });
    return batch;
  }

  /// Adds the section asked for, or the next one. Never throws: every way of
  /// failing is an outcome, and none of them changes the store.
  ///
  /// [post] sends the request. Left out, it goes over the network, and
  /// cancelling drops the connection.
  static Future<StoryUpdateOutcome> run(
    StoryUpdateRequest request, {
    required String bookId,
    required String apiKey,
    StoryHttpPost? post,
  }) {
    final existing = _running[bookId];
    if (existing != null) return existing.outcome;
    final cancel = StoryCancel();
    final outcome =
        _run(
          request,
          apiKey,
          post ??
              (url, headers, body) =>
                  postStoryRequest(url, headers, body, cancel: cancel),
          cancel,
        ).whenComplete(() {
          // In a block, so as not to return the removed update: `whenComplete`
          // would wait for a future it got back, and this is that future.
          _running.remove(bookId);
        });
    _running[bookId] = RunningStoryUpdate(
      outcome,
      DateTime.now(),
      request.sectionId,
      cancel: cancel,
    );
    return outcome;
  }

  static Future<StoryUpdateOutcome> _run(
    StoryUpdateRequest request,
    String apiKey,
    StoryHttpPost post,
    StoryCancel cancel,
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
        cancel: cancel,
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
