import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/story_update/story_api_client.dart';
import 'package:loremark/story_update/story_book.dart';
import 'package:loremark/story_update/story_model_choice.dart';
import 'package:loremark/story_update/story_run_folder.dart';
import 'package:loremark/story_update/story_store.dart';
import 'package:loremark/story_update/story_updater.dart';

import 'golden.dart';

const _apiKey = 'sk-secret-test-key';

String _responseBody(Object? output) => jsonEncode({
  'id': 'resp_1',
  'model': 'test-model',
  'status': 'completed',
  'output': [
    {
      'type': 'message',
      'content': [
        {'type': 'output_text', 'text': jsonEncode(output)},
      ],
    },
  ],
  'usage': {'input_tokens': 10, 'output_tokens': 20},
});

void main() {
  final golden = readValidationGolden();
  final chapter1Delta = (golden['first'] as JsonMap)['candidate'] as JsonMap;
  final chapter2Delta =
      (golden['cases'] as List).cast<JsonMap>().firstWhere(
            (item) => item['name'] == 'clean',
          )['candidate']
          as JsonMap;
  final prompt = File('assets/story_update/$updatePromptName')
      .readAsStringSync();
  final schemaText = File('assets/story_update/story_delta.schema.json')
      .readAsStringSync();

  late Directory temp;
  late String storePath;
  late String runsPath;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('story_runs_');
    storePath = '${temp.path}/store';
    runsPath = storyRunsPath(storePath);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  StoryUpdateRequest request({
    String? section = 'section-002',
    bool checkQuotes = false,
  }) => StoryUpdateRequest(
    epubPath: '$goldenDir/story.epub',
    storePath: storePath,
    runsPath: runsPath,
    model: StoryModelChoice.deepseekFlash,
    effort: StoryEffort.high,
    checkQuotes: checkQuotes,
    prompt: prompt,
    schemaText: schemaText,
    sectionId: section,
  );

  Future<StoryUpdateOutcome> update(
    StoryUpdateRequest request,
    StoryHttpPost post,
  ) => StoryUpdater.run(request, bookId: 'book', apiKey: _apiKey, post: post);

  StoryHttpPost answering(Object? output) =>
      (url, headers, body) async =>
          StoryHttpResponse(200, _responseBody(output), requestId: 'req_1');

  List<Directory> runs() =>
      Directory(runsPath).listSync().whereType<Directory>().toList();

  Set<String> filesIn(Directory folder) => {
    for (final file in folder.listSync(recursive: true).whereType<File>())
      file.path.substring(folder.path.length + 1),
  };

  JsonMap readJson(Directory folder, String name) =>
      jsonDecode(File('${folder.path}/$name').readAsStringSync()) as JsonMap;

  /// The run of [sectionId]. Runs in the same second can't be told apart by age.
  Directory runOf(String sectionId) => runs().singleWhere(
    (run) =>
        (readJson(run, 'run.json')['source'] as JsonMap)['section_id'] ==
        sectionId,
  );

  group('a successful update', () {
    test('keeps what the lab keeps', () async {
      final outcome = await update(request(), answering(chapter1Delta));
      expect(outcome.status, 'committed', reason: '${outcome.issues}');

      final run = runs().single;
      expect(filesIn(run), {
        'base_story_model.json',
        'chapter.json',
        'chapter.txt',
        'context.json',
        'delta.candidate.json',
        'delta.json',
        'id_map.json',
        'prompt.txt',
        'request.json',
        'response.json',
        'run.json',
        'schema.json',
        'story_model.after.json',
        'validation.json',
      });

      final record = readJson(run, 'run.json');
      expect(record['command'], 'update');
      expect(record['status'], 'committed');
      expect(record['exit_code'], 0);
      expect(record['commit_status'], 'committed');
      expect(record['finished_at'], isNotNull);
      expect(record['elapsed_seconds'], isA<num>());
      expect(record['quotes_checked'], isFalse);
      expect(record['base_revision'], isNull);
      expect(record['committed_revision'], containsPair('number', 1));
      final source = record['source'] as JsonMap;
      expect(source['section_id'], 'section-002');
      expect(source['section_order'], 2);
      expect(source['paragraph_count'], greaterThan(0));
      final requested = record['request'] as JsonMap;
      expect(requested['provider'], 'deepseek');
      expect(requested['base_url'], 'https://api.deepseek.com');
      expect(requested['reasoning_effort'], 'high');
      final response = record['response'] as JsonMap;
      expect(response['status'], 'completed');
      expect(response['api_status'], 'completed');
      expect(response['response_id'], 'resp_1');
      expect(response['request_id'], 'req_1');
      expect(response['http_status'], 200);
      expect(response['api_elapsed_seconds'], isA<num>());
      expect(response['usage'], {'input_tokens': 10, 'output_tokens': 20});
      final checked = record['validation'] as JsonMap;
      expect(checked['passed'], isTrue);
      expect(checked['validator_version'], isNotEmpty);

      // The reply, exactly as it came.
      expect(
        File('${run.path}/response.json').readAsStringSync(),
        _responseBody(chapter1Delta),
      );
      expect(readJson(run, 'delta.candidate.json'), chapter1Delta);
      expect(
        File('${run.path}/story_model.after.json').readAsBytesSync(),
        File('$storePath/story_model.json').readAsBytesSync(),
      );
      expect(File('${run.path}/prompt.txt').readAsStringSync(), prompt);

      // The same run the store says the revision came from.
      final name = run.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      expect(record['run_id'], name);
      expect(Directory('$storePath/provenance/$name').existsSync(), isTrue);
    });

    test('keeps the text that was sent', () async {
      await update(request(), answering(chapter1Delta));
      final run = runs().single;
      final chapter = readJson(run, 'chapter.json');
      final paragraphs = (chapter['paragraphs'] as List).cast<JsonMap>();
      expect(
        File('${run.path}/chapter.txt').readAsStringSync(),
        paragraphs.map((p) => '[${p['id']}] ${p['text']}\n').join(),
      );
      // The same file the store keeps.
      final inputs = Directory('$storePath/inputs')
          .listSync()
          .whereType<File>();
      expect(
        File('${run.path}/chapter.json').readAsBytesSync(),
        inputs.single.readAsBytesSync(),
      );
    });

    test('keeps the request, with the schema in its own file', () async {
      await update(request(), answering(chapter1Delta));
      final run = runs().single;
      final record = readJson(run, 'request.json');
      expect(record['provider'], 'deepseek');
      expect(record['model'], StoryModelChoice.deepseekFlash.id);
      expect(record['reasoning'], {'effort': 'high'});
      expect((record['input'] as List).length, 2);
      final format = (record['text'] as JsonMap)['format'] as JsonMap;
      expect(format['schema_file'], 'schema.json');
      expect(format.containsKey('schema'), isFalse);
      expect(
        format['schema_sha256'],
        sha256OfJson(readJson(run, 'schema.json')),
      );
    });

    test('a later one keeps its exact base', () async {
      await update(request(), answering(chapter1Delta));
      final base = File('$storePath/story_model.json').readAsBytesSync();
      final model = jsonDecode(utf8.decode(base)) as JsonMap;
      final section = (model['processed_sections'] as List).single as JsonMap;

      final outcome = await update(
        request(section: null),
        answering(chapter2Delta),
      );
      expect(outcome.status, 'committed', reason: '${outcome.issues}');

      final run = runOf('section-003');
      expect(File('${run.path}/base_story_model.json').readAsBytesSync(), base);
      final record = readJson(run, 'run.json');
      final hashes = record['hashes'] as JsonMap;
      expect(hashes['base_sha256'], sha256OfBytes(base));
      expect(
        (record['base_revision'] as JsonMap)['sha256'],
        sha256OfBytes(base),
      );
      final name = (section['input_relative_path'] as String).split('/').last;
      expect(
        sha256OfBytes(File('${run.path}/base_inputs/$name').readAsBytesSync()),
        section['input_file_sha256'],
      );
    });
  });

  group('a failed update keeps what happened:', () {
    test('an answer of the wrong shape', () async {
      final bad = {
        ...chapter1Delta,
        'transitions': [
          {'nonsense': true},
        ],
      };
      final outcome = await update(request(), answering(bad));
      expect(outcome.status, 'schema_invalid');

      final run = runs().single;
      expect(filesIn(run), containsAll(['response.json', 'failure.json']));
      expect(filesIn(run), isNot(contains('delta.json')));
      expect(readJson(run, 'delta.candidate.json'), bad);
      final checks = readJson(run, 'validation.json');
      expect(checks['structure_valid'], isFalse);
      expect(checks['error_count'], greaterThan(0));
      expect(readJson(run, 'run.json')['status'], 'schema_invalid');
      expect(readJson(run, 'run.json')['exit_code'], 4);
      expect(readJson(run, 'run.json')['commit_status'], 'not_attempted');
      expect(Directory(storePath).existsSync(), isFalse);
    });

    test('an answer that fails its checks', () async {
      await update(request(checkQuotes: true), answering(chapter1Delta));
      final bad = jsonDecode(jsonEncode(chapter2Delta)) as JsonMap;
      final names = (bad['new_records'] as JsonMap)['names'] as List;
      final evidence = (names[0] as JsonMap)['evidence'] as List;
      (evidence[0] as JsonMap)['quote'] = 'Words that are not in the book';

      final outcome = await update(
        request(section: null, checkQuotes: true),
        answering(bad),
      );
      expect(outcome.status, 'validation_failed');

      final run = runOf('section-003');
      final issues = (readJson(run, 'validation.json')['issues'] as List)
          .cast<JsonMap>();
      final error = issues.singleWhere((i) => i['severity'] == 'error');
      expect(error['code'], 'quote_not_found');
      expect(error['path'], isNotEmpty);
      final failure = readJson(run, 'failure.json');
      expect(failure['status'], 'validation_failed');
      expect(failure['error'], {
        'category': 'validation',
        'message': '1 errors; see validation.json',
      });
      expect(failure['request_id'], 'req_1');
      expect(filesIn(run), isNot(contains('delta.json')));
      expect(filesIn(run), isNot(contains('story_model.after.json')));
    });

    test('an answer that isn’t JSON', () async {
      final outcome = await update(
        request(),
        (u, h, b) async => StoryHttpResponse(
          200,
          jsonEncode({
            'status': 'completed',
            'output': [
              {
                'type': 'message',
                'content': [
                  {'type': 'output_text', 'text': 'Not JSON at all'},
                ],
              },
            ],
          }),
        ),
      );
      expect(outcome.status, 'schema_invalid');
      final failure = readJson(runs().single, 'failure.json');
      expect(failure['output_text'], 'Not JSON at all');
      expect(filesIn(runs().single), isNot(contains('delta.candidate.json')));
    });

    test('a provider’s error page', () async {
      final outcome = await update(
        request(),
        (u, h, b) async => const StoryHttpResponse(503, '<html>Sorry</html>'),
      );
      expect(outcome.status, 'api_error');
      final run = runs().single;
      expect(
        File('${run.path}/response.txt').readAsStringSync(),
        contains('Sorry'),
      );
      expect(filesIn(run), isNot(contains('response.json')));
      final record = readJson(run, 'run.json');
      expect(record['status'], 'api_error');
      expect(record['exit_code'], 3);
      expect((record['response'] as JsonMap)['http_status'], 503);
      final error = readJson(run, 'failure.json')['error'] as JsonMap;
      expect(error['category'], 'server_error');
    });

    test('no reply at all', () async {
      await update(
        request(),
        (u, h, b) async => throw const SocketException('gone'),
      );
      final run = runs().single;
      expect(
        filesIn(run).where((name) => name.startsWith('response')),
        isEmpty,
      );
      expect(
        (readJson(run, 'failure.json')['error'] as JsonMap)['category'],
        'network',
      );
      final response = readJson(run, 'run.json')['response'] as JsonMap;
      expect(response['api_elapsed_seconds'], isA<num>());
      expect(response['http_status'], isNull);
    });

    test('something unexpected', () async {
      final outcome = await update(
        request(),
        (u, h, b) async => throw StateError('Boom with $_apiKey in it'),
      );
      expect(outcome.status, 'input_error');
      expect(outcome.message, isNot(contains(_apiKey)));
      final run = runs().single;
      final record = readJson(run, 'run.json');
      expect(record['status'], 'internal_error');
      expect((record['error'] as JsonMap)['type'], 'StateError');
      expect(readJson(run, 'failure.json')['status'], 'internal_error');
      expect(
        File('${run.path}/run.json').readAsStringSync(),
        isNot(contains(_apiKey)),
      );
    });

    test('each try gets its own folder', () async {
      for (var i = 0; i < 2; i++) {
        await update(
          request(),
          (u, h, b) async => const StoryHttpResponse(503, ''),
        );
      }
      expect(runs(), hasLength(2));
    });
  });

  test(
    'a failed first update doesn’t stop a new store from starting',
    () async {
      final failed = await update(
        request(),
        (u, h, b) async => const StoryHttpResponse(503, ''),
      );
      expect(failed.committed, isFalse);
      expect(Directory(storePath).existsSync(), isFalse);

      final outcome = await update(request(), answering(chapter1Delta));
      expect(outcome.status, 'committed', reason: '${outcome.issues}');
      StoryStore(Directory(storePath)).load();
      expect(runs(), hasLength(2));
    },
  );

  group('the key', () {
    test('is never kept, even if a provider repeats it', () async {
      final outcome = await update(
        request(),
        (u, h, b) async => const StoryHttpResponse(
          401,
          '{"error":{"message":"Incorrect API key: $_apiKey"}}',
        ),
      );
      expect(outcome.category, 'authentication');
      expect(outcome.message, isNot(contains(_apiKey)));
      for (final file in Directory(
        runsPath,
      ).listSync(recursive: true).whereType<File>()) {
        expect(
          file.readAsStringSync(),
          isNot(contains(_apiKey)),
          reason: file.path,
        );
      }
    });

    test('is in no file after a success either', () async {
      await update(request(), answering(chapter1Delta));
      final files = [
        ...Directory(runsPath).listSync(recursive: true).whereType<File>(),
        ...Directory(storePath).listSync(recursive: true).whereType<File>(),
      ];
      expect(files, isNotEmpty);
      for (final file in files) {
        expect(
          file.readAsStringSync(),
          isNot(contains(_apiKey)),
          reason: file.path,
        );
      }
    });
  });

  group('when the folder can’t be written', () {
    test('before sending, nothing is sent', () async {
      File(runsPath).writeAsStringSync('In the way');
      var requests = 0;
      final outcome = await update(request(), (u, h, b) async {
        requests++;
        return StoryHttpResponse(200, _responseBody(chapter1Delta));
      });
      expect(outcome.status, 'input_error');
      expect(requests, 0);
    });

    test('after sending, the update still counts', () async {
      final outcome = await update(request(), (u, h, b) async {
        Directory(runsPath).deleteSync(recursive: true);
        File(runsPath).writeAsStringSync('In the way');
        return StoryHttpResponse(200, _responseBody(chapter1Delta));
      });
      expect(outcome.status, 'committed', reason: '${outcome.issues}');
      StoryStore(Directory(storePath)).load();
    });

    test('after a failed answer, the failure is still reported', () async {
      final outcome = await update(request(), (u, h, b) async {
        Directory(runsPath).deleteSync(recursive: true);
        File(runsPath).writeAsStringSync('In the way');
        return const StoryHttpResponse(503, '');
      });
      expect(outcome.status, 'api_error');
    });
  });

  test('a dry run is recorded as one', () {
    final prepared = prepareStoryUpdate(request())!;
    prepared.run!.finish('dry_run');
    final run = runs().single;
    expect(run.path, prepared.run!.path);
    final record = readJson(run, 'run.json');
    expect(record['status'], 'dry_run');
    expect((record['request'] as JsonMap)['dry_run'], isTrue);
    expect(record['response'], isNull);
    expect(filesIn(run), contains('request.json'));
    expect(Directory(storePath).existsSync(), isFalse);
  });

  test('without a folder to keep it in, nothing is kept', () async {
    final outcome = await update(
      StoryUpdateRequest(
        epubPath: '$goldenDir/story.epub',
        storePath: storePath,
        model: StoryModelChoice.deepseekFlash,
        effort: StoryEffort.high,
        checkQuotes: false,
        prompt: prompt,
        schemaText: schemaText,
        sectionId: 'section-002',
      ),
      answering(chapter1Delta),
    );
    expect(outcome.status, 'committed', reason: '${outcome.issues}');
    expect(Directory(runsPath).existsSync(), isFalse);
  });
}
