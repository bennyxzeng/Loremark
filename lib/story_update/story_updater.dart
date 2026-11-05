import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'delta_schema.dart';
import 'story_api_client.dart';
import 'story_book.dart';
import 'story_merge.dart';
import 'story_model_choice.dart';
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

/// A section the reader can start a new Story Map from.
class StoryStartChoice {
  const StoryStartChoice(this.sectionId, this.title, this.paragraphCount);

  final String sectionId;
  final String title;
  final int paragraphCount;
}

/// What pressing Update would do for a book right now.
class StoryUpdateStatus {
  const StoryUpdateStatus._({
    this.startChoices = const [],
    this.suggestedStart,
    this.nextSectionId,
    this.nextTitle,
    this.blocked,
  });

  /// No store yet: the reader picks where it starts, from [startChoices].
  const StoryUpdateStatus.newStore({
    required List<StoryStartChoice> choices,
    required String suggested,
  }) : this._(startChoices: choices, suggestedStart: suggested);

  /// [title] is the next section.
  const StoryUpdateStatus.ready(String sectionId, String title)
    : this._(nextSectionId: sectionId, nextTitle: title);

  /// Every section is in the store.
  const StoryUpdateStatus.finished() : this._();

  /// The next section can't be processed, for the reason given.
  const StoryUpdateStatus.blocked(String reason) : this._(blocked: reason);

  final List<StoryStartChoice> startChoices;
  final String? suggestedStart;
  final String? nextSectionId;
  final String? nextTitle;
  final String? blocked;

  bool get isNewStore => suggestedStart != null;
  bool get isReady => nextSectionId != null;
  bool get isFinished => !isNewStore && !isReady && blocked == null;
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
    this.startSectionId,
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

  /// Where a new store starts; ignored once there is one.
  final String? startSectionId;
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
  });

  final StoryUpdateRequest request;
  final StoryStoreState state;
  final JsonMap chapter;
  final int sectionOrder;

  /// The JSON body to send.
  final String body;
  final JsonMap hashes;
  final String runId;
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
    this.outputText,
    this.requestId,
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

  /// What the model returned, if it wasn't usable, for diagnosing it.
  final String? outputText;
  final String? requestId;

  bool get committed => status == 'committed';

  /// How many quotes weren't found in their paragraph, with the check off.
  int get unmatchedQuotes =>
      issues.where((issue) => issue.code == 'quote_not_found').length;
}

/// Reads the store at [storePath] for showing it, or null if there is none.
JsonMap? readStoryModel(String storePath) =>
    StoryStore(Directory(storePath)).readLatest();

/// What pressing Update would do for the book at [epubPath].
StoryUpdateStatus inspectStoryUpdate(String epubPath, String storePath) {
  try {
    final book = StoryBook.open(File(epubPath).readAsBytesSync());
    final store = StoryStore(Directory(storePath));
    final model = store.readLatest();
    if (model == null) return _newStoreStatus(book);
    final next = _nextSection(model, book);
    if (next == null) return const StoryUpdateStatus.finished();
    return StoryUpdateStatus.ready(next.$1.sectionId, next.$1.title);
  } on StoryEpubError catch (error) {
    return StoryUpdateStatus.blocked(error.message);
  } on StoryStoreError catch (error) {
    return StoryUpdateStatus.blocked(error.message);
  } on FileSystemException catch (error) {
    return StoryUpdateStatus.blocked(error.message);
  }
}

StoryUpdateStatus _newStoreStatus(StoryBook book) {
  final choices = <StoryStartChoice>[];
  for (final section in book.sections) {
    if (section.problem != null) continue;
    try {
      final paragraphs = book.extract(section)['paragraphs'] as List;
      choices.add(
        StoryStartChoice(section.sectionId, section.title, paragraphs.length),
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

/// The section to add after [model]'s last, with its text; null when none is
/// left. Sections with no text, such as a full-page illustration, are stepped
/// over: they hold nothing to learn, and stopping at one would end the map
/// there for good. A section that can't be cut reliably does stop it, since
/// stepping over that could lose text.
(StoryBookSection, JsonMap)? _nextSection(JsonMap model, StoryBook book) {
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
  final last = processed.last['section_order'] as int;
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

String _utcNow() =>
    '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';

String _randomHex(int bytes) {
  final random = Random.secure();
  return [
    for (var i = 0; i < bytes; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

String _newRunId() {
  final stamp = _utcNow().replaceAll('-', '').replaceAll(':', '');
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
    final next = _nextSection(state.model, book);
    if (next == null) return null;
    chapter = next.$2;
    sectionOrder = next.$1.order;
  } else {
    store.ensureNew();
    final start = book.sections
        .where((section) => section.sectionId == request.startSectionId)
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
  return PreparedStoryUpdate(
    request: request,
    state: state,
    chapter: chapter,
    sectionOrder: sectionOrder,
    body: jsonEncode(
      buildUpdateRequest(
        context: context,
        prompt: request.prompt,
        schema: schema,
        model: request.model,
        effort: request.effort,
      ),
    ),
    hashes: {
      'text_sha256': chapter['text_sha256'],
      'prompt_sha256': sha256OfBytes(utf8.encode(request.prompt)),
      'schema_sha256': sha256OfJson(schema),
      'context_sha256': sha256OfJson(context),
      'base_sha256': state.latestSha256,
    },
    runId: _newRunId(),
  );
}

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
  final PreparedStoryUpdate(:request, :state, :chapter) = prepared;
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
    'created_at': _utcNow(),
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
  }

  if (call.status != 'completed' || validation == null || !validation.passed) {
    return StoryUpdateOutcome(
      _failureStatus(call.status, validation),
      message: call.error?['message'] as String?,
      category: call.error?['category'] as String?,
      sectionTitle: title,
      usage: call.usage,
      issues: validation?.issues ?? const [],
      outputText: call.outputText,
      requestId: call.requestId,
    );
  }

  final after = validation.after!;
  final files = <String, List<int>>{
    inputPath: inputData,
    ..._provenanceFiles(prepared, call, validation, section, revision),
  };
  try {
    StoryStore(Directory(request.storePath))
        .commit(after, files, expectedBaseSha256: state.latestSha256);
  } on StaleBaseError catch (error) {
    return StoryUpdateOutcome(
      'stale_base',
      message: error.message,
      sectionTitle: title,
      usage: call.usage,
    );
  } on StoryStoreError catch (error) {
    return StoryUpdateOutcome(
      'commit_failed',
      message: error.message,
      sectionTitle: title,
      usage: call.usage,
    );
  } on FileSystemException catch (error) {
    return StoryUpdateOutcome(
      'commit_failed',
      message: error.message,
      sectionTitle: title,
      usage: call.usage,
    );
  }
  return StoryUpdateOutcome(
    'committed',
    sectionTitle: title,
    revision: number,
    usage: call.usage,
    issues: validation.issues,
    requestId: call.requestId,
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
      'prompt_source': 'builtin:$updatePromptName',
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

/// Runs updates, one at a time per book.
///
/// The reader may leave the book while one runs. It is already paid for, so it
/// carries on and commits, and coming back finds it through [running].
class StoryUpdater {
  StoryUpdater._();

  static final _running = <String, Future<StoryUpdateOutcome>>{};

  /// The update running for the book [bookId], if any.
  static Future<StoryUpdateOutcome>? running(String bookId) => _running[bookId];

  /// Adds the next section. Never throws: every way of failing is an outcome,
  /// and none of them changes the store.
  static Future<StoryUpdateOutcome> run(
    StoryUpdateRequest request, {
    required String bookId,
    required String apiKey,
    StoryHttpPost post = postStoryRequest,
  }) {
    final existing = _running[bookId];
    if (existing != null) return existing;
    return _running[bookId] = _run(request, apiKey, post).whenComplete(() {
      // In a block, so as not to return the removed future: `whenComplete`
      // would wait for it, and it is the one being completed.
      _running.remove(bookId);
    });
  }

  static Future<StoryUpdateOutcome> _run(
    StoryUpdateRequest request,
    String apiKey,
    StoryHttpPost post,
  ) async {
    try {
      final prepared = await Isolate.run(() => prepareStoryUpdate(request));
      if (prepared == null) {
        return const StoryUpdateOutcome(
          'input_error',
          message: 'Every section is already in the Story Map.',
        );
      }
      final call = await callResponsesApi(
        model: request.model,
        apiKey: apiKey,
        body: prepared.body,
        post: post,
      );
      return await Isolate.run(() => finishStoryUpdate(prepared, call));
    } on StoryEpubError catch (error) {
      return StoryUpdateOutcome('input_error', message: error.message);
    } on StoryStoreError catch (error) {
      return StoryUpdateOutcome('input_error', message: error.message);
    } on FileSystemException catch (error) {
      return StoryUpdateOutcome('input_error', message: error.message);
    } on Object catch (error) {
      // Whatever it is, the reader mustn't be left waiting. The key never
      // reaches the code that could throw this: see [callResponsesApi].
      return StoryUpdateOutcome('input_error', message: 'Unexpected: $error');
    }
  }
}
