import 'dart:convert';
import 'dart:io';

import 'story_api_client.dart';
import 'story_book.dart';
import 'story_model_choice.dart';
import 'story_quotes.dart';
import 'story_store.dart';
import 'story_validation.dart';

/// The folder holding the run folders of the store at [storePath]. It sits beside
/// the store and not in it, since a new store has to start from an empty folder.
String storyRunsPath(String storePath) => '$storePath.runs';

/// The time now as the lab writes it, such as `2026-11-05T03:56:03Z`.
String storyUtcNow() =>
    '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';

// The lab's exit codes for how a run can end.
const _exitCodes = {
  'dry_run': 0,
  'committed': 0,
  'validation_failed': 4,
  'schema_invalid': 4,
  'api_error': 3,
  'refusal': 3,
  'incomplete': 3,
  'failed': 3,
  'empty_output': 3,
  'stale_base': 5,
  'commit_failed': 2,
  // The lab has no such ending. 130 is what a shell reports for a run stopped
  // with Ctrl-C.
  'cancelled': 130,
};

/// Everything kept about one update, whether or not it worked, in the same files
/// as a run folder of the lab's. Its `validate --run` can check one.
///
/// Left out, because their features aren't in the app: `diff.md`, `review.md`,
/// manual corrections, and the `evidence` and `counts` of `validation.json`.
/// Added: `quote_repairs.json`, the quotes put back to the book's text before
/// checking, in the form of the lab's `manual_corrections.json`.
///
/// What is written before the request has to succeed, or nothing is sent: the
/// answer couldn't be kept. After that the request has been paid for, so failing
/// to write here never changes how the update ends.
class StoryRunFolder {
  StoryRunFolder._(this.path, this._startedAt, this._record);

  /// Starts the folder of a run with all that is known before it is sent. Throws
  /// a [FileSystemException] if it can't.
  factory StoryRunFolder.start({
    required String runsPath,
    required String runId,
    required StoryBook book,
    required String epubPath,
    required String storePath,
    required JsonMap chapter,
    required int sectionOrder,
    required String prompt,
    required String promptSource,
    required JsonMap schema,
    required JsonMap context,
    required JsonMap requestBody,
    required StoryModelChoice model,
    required StoryEffort? effort,
    required bool checkQuotes,
    required JsonMap hashes,
    required StoryStoreState state,
  }) {
    final path = '$runsPath/$runId';
    final paragraphs = (chapter['paragraphs'] as List).cast<JsonMap>();
    final baseRevision = state.model['revision'] as JsonMap;
    final providerUrl = StoryProvider.named(model.providerName).responsesUrl;
    final folder = StoryRunFolder._(path, DateTime.now(), {
      'run_id': runId,
      'command': 'update',
      'status': 'running',
      'exit_code': null,
      'started_at': storyUtcNow(),
      'finished_at': null,
      'elapsed_seconds': null,
      'output_dir': path,
      'source': {
        'epub_path': epubPath,
        'book_sha256': book.sha256Hash,
        'book_title': book.title,
        'toc_source': book.tocSource,
        'section_id': chapter['section_id'],
        'chapter_number': chapter['chapter_number'],
        'title': chapter['title'],
        'source_href': chapter['source_href'],
        'source_fragment': chapter['source_fragment'],
        'paragraph_count': paragraphs.length,
        'character_count': paragraphs.fold<int>(
          0,
          (sum, paragraph) => sum + (paragraph['text'] as String).runes.length,
        ),
        'omitted_image_count': chapter['omitted_image_count'],
        'extraction_version': chapter['extraction_version'],
        'extraction_notes': chapter['extraction_notes'],
        'epub_warnings': book.warnings,
        'section_order': sectionOrder,
      },
      'hashes': hashes,
      'prompt_source': promptSource,
      'request': {
        'provider': model.providerName,
        'base_url': _baseUrl(providerUrl),
        'model': model.id,
        'max_output_tokens': null,
        'timeout_seconds': storyRequestTimeout.inSeconds,
        'reasoning_effort': effort?.name,
        'max_retries': 0,
        'store': requestBody['store'],
        'truncation': requestBody['truncation'],
        'dry_run': false,
      },
      'response': null,
      'validation': null,
      'versions': {'dart': Platform.version},
      'store': {'path': storePath},
      'base_revision': state.isNew
          ? null
          : {
              'number': baseRevision['number'],
              'id': baseRevision['id'],
              'sha256': state.latestSha256,
              'snapshot_path': state.snapshotPath,
            },
      'candidate_revision': null,
      'committed_revision': null,
      'commit_status': 'not_attempted',
      'report_status': null,
      'quotes_checked': checkQuotes,
    });

    Directory(path).createSync(recursive: true);
    folder
      .._write('chapter.json', storyJsonBytes(chapter))
      .._writeText(
        'chapter.txt',
        paragraphs
            .map((paragraph) => '[${paragraph['id']}] ${paragraph['text']}\n')
            .join(),
      )
      .._writeText('prompt.txt', prompt)
      .._writeJson('schema.json', schema)
      .._writeJson('request.json', {
        'endpoint': 'POST /responses',
        'provider': model.providerName,
        'base_url': _baseUrl(providerUrl),
        ...requestBody,
        'text': {
          'format': {
            'type': 'json_schema',
            'name': 'StoryDelta',
            'strict': true,
            'schema_file': 'schema.json',
            'schema_sha256': sha256OfJson(schema),
          },
        },
      })
      .._writeJson('context.json', context)
      .._write(
        'base_story_model.json',
        state.latestBytes ?? storyJsonBytes(state.model),
      );
    state.inputFiles.forEach((relpath, data) {
      folder._write('base_inputs/${relpath.split('/').last}', data);
    });
    folder._saveRecord();
    return folder;
  }

  final String path;
  final DateTime _startedAt;
  final JsonMap _record;

  static String _baseUrl(String responsesUrl) =>
      responsesUrl.substring(0, responsesUrl.lastIndexOf('/'));

  void _write(String name, List<int> data) {
    final file = File('$path/$name');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data);
  }

  void _writeText(String name, String text) => _write(name, utf8.encode(text));

  void _writeJson(String name, Object? data) =>
      _write(name, storyJsonBytes(data));

  void _saveRecord() => _writeJson('run.json', _record);

  /// Writes something the update doesn't depend on: see [StoryRunFolder].
  void _safely(void Function() write) {
    try {
      write();
    } on FileSystemException {
      // The update carries on; only this record of it is lost.
    }
  }

  /// Keeps the provider's reply as it came, before anything is done with it.
  void recordCall(StoryCallResult call) {
    _record['response'] = {
      'status': call.status,
      'api_status': call.apiStatus,
      'response_id': call.responseId,
      'request_id': call.requestId,
      'model': call.responseModel,
      'usage': call.usage,
      'api_elapsed_seconds': call.elapsedSeconds,
      'retries_taken': 0,
      'http_status': call.httpStatus,
    };
    _safely(() {
      final body = call.responseBody;
      if (body != null) {
        _writeText(_isJson(body) ? 'response.json' : 'response.txt', body);
      }
      if (call.candidate != null) {
        _writeJson('delta.candidate.json', call.candidate);
      }
      _saveRecord();
    });
  }

  static bool _isJson(String text) {
    try {
      jsonDecode(text);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// Keeps how the answer was checked and, if it passed, what it became.
  void recordValidation(StoryUpdateValidation validation) {
    final errors = validation.errors.length;
    final warnings = validation.warnings.length;
    final merged = validation.after != null;
    _record['validation'] = {
      'passed': validation.passed,
      'structure_valid': validation.structureValid,
      'merged': merged,
      'error_count': errors,
      'warning_count': warnings,
      'validator_version': storyValidatorVersion,
      'validated_at': storyUtcNow(),
      'quote_repair_version': storyQuoteRepairVersion,
      'quote_repair_count': validation.quoteRepairs.length,
    };
    _safely(() {
      if (validation.quoteRepairs.isNotEmpty) {
        // In the lab's form for manual corrections, by who made them.
        final at = storyUtcNow();
        _writeJson('quote_repairs.json', [
          for (final repair in validation.quoteRepairs)
            ...repair.corrections(at),
        ]);
      }
      _writeJson('validation.json', {
        'validator_version': storyValidatorVersion,
        'passed': validation.passed,
        'structure_valid': validation.structureValid,
        'merged': merged,
        'error_count': errors,
        'warning_count': warnings,
        'issues': [
          for (final issue in validation.issues)
            {
              'severity': issue.severity,
              'code': issue.code,
              'path': issue.path,
              'message': issue.message,
              'record_id': issue.recordId,
            },
        ],
        'note': storyValidationNote,
      });
      if (validation.passed) {
        _writeJson('delta.json', validation.delta);
        _writeJson('id_map.json', validation.idMap!.toJson());
        _write('story_model.after.json', storyJsonBytes(validation.after));
      }
    });
  }

  /// Ends the run as [status], which is how the update ended.
  void finish(
    String status, {
    JsonMap? failure,
    String? commitStatus,
    JsonMap? candidateRevision,
    JsonMap? committedRevision,
  }) {
    _record
      ..['status'] = status
      ..['exit_code'] = _exitCodes[status]
      ..['finished_at'] = storyUtcNow()
      ..['elapsed_seconds'] =
          DateTime.now().difference(_startedAt).inMilliseconds / 1000;
    if (status == 'dry_run') {
      (_record['request'] as JsonMap)['dry_run'] = true;
    }
    if (commitStatus != null) _record['commit_status'] = commitStatus;
    if (candidateRevision != null) {
      _record['candidate_revision'] = candidateRevision;
    }
    if (committedRevision != null) {
      _record['committed_revision'] = committedRevision;
    }
    _safely(() {
      if (failure != null) _writeJson('failure.json', failure);
      _saveRecord();
    });
  }

  /// Ends the run after something unexpected. This object may be a copy from
  /// before the last steps, in another isolate, so it works from the saved file.
  void recordCrash(Object error, String message) {
    _safely(() {
      final JsonMap record;
      try {
        record =
            jsonDecode(File('$path/run.json').readAsStringSync()) as JsonMap;
      } on FormatException {
        return;
      }
      final details = {
        'category': 'internal_error',
        'type': '${error.runtimeType}',
        'message': message,
      };
      record
        ..['status'] = 'internal_error'
        ..['finished_at'] = storyUtcNow()
        ..['elapsed_seconds'] =
            DateTime.now().difference(_startedAt).inMilliseconds / 1000
        ..['error'] = details;
      _writeJson('run.json', record);
      _writeJson('failure.json', {
        'status': 'internal_error',
        'error': details,
      });
    });
  }
}
