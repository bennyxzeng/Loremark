import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/story_update/delta_schema.dart';
import 'package:loremark/story_update/story_api_client.dart';
import 'package:loremark/story_update/story_book.dart';
import 'package:loremark/story_update/story_merge.dart';
import 'package:loremark/story_update/story_model_choice.dart';
import 'package:loremark/story_update/story_store.dart';
import 'package:loremark/story_update/story_updater.dart';

import 'golden.dart';

const _storyEpub = '$goldenDir/story.epub';
const _apiKey = 'sk-secret-test-key';

/// A body the provider would answer with, holding [output] as its text.
String _responseBody(Object? output, {String status = 'completed'}) =>
    jsonEncode({
      'id': 'resp_1',
      'model': 'test-model',
      'status': status,
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

/// An EPUB of three chapters whose second can't be found: its table of
/// contents entry points at an anchor that isn't there.
Uint8List _epubWithBrokenMiddle() {
  String page(String text) =>
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title></head>'
      '<body><p>$text</p></body></html>';
  final files = {
    'META-INF/container.xml':
        '<container version="1.0" '
        'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
        '<rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles></container>',
    'OEBPS/content.opf':
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title>Stuck</dc:title></metadata><manifest>'
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
        'properties="nav"/>'
        '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
        '</manifest><spine><itemref idref="a"/><itemref idref="b"/>'
        '<itemref idref="c"/></spine></package>',
    'OEBPS/nav.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>n</title></head>'
        '<body><nav epub:type="toc"><ol>'
        '<li><a href="a.xhtml">Chapter 1</a></li>'
        '<li><a href="b.xhtml#gone">Chapter 2</a></li>'
        '<li><a href="c.xhtml">Chapter 3</a></li>'
        '</ol></nav></body></html>',
    'OEBPS/a.xhtml': page('First words.'),
    'OEBPS/b.xhtml': page('Second words.'),
    'OEBPS/c.xhtml': page('Third words.'),
  };
  final archive = Archive();
  files.forEach((name, text) {
    archive.addFile(ArchiveFile.string(name, text));
  });
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  final golden = readValidationGolden();
  final first = golden['first'] as JsonMap;
  final chapter1Delta = first['candidate'] as JsonMap;
  final chapter2Delta =
      (golden['cases'] as List).cast<JsonMap>().firstWhere(
            (item) => item['name'] == 'clean',
          )['candidate']
          as JsonMap;
  final prompt = File('assets/story_update/$updatePromptName')
      .readAsStringSync();
  final schemaText = File('assets/story_update/story_delta.schema.json')
      .readAsStringSync();

  final emptyDelta = {
    'new_entities': <Object>[],
    'new_records': {for (final name in storyCollections) name: <Object>[]},
    'transitions': <Object>[],
  };

  late Directory temp;
  late String storePath;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('story_update_');
    storePath = '${temp.path}/store';
  });
  tearDown(() => temp.deleteSync(recursive: true));

  StoryUpdateRequest request({
    String epub = _storyEpub,
    StoryModelChoice model = StoryModelChoice.deepseekFlash,
    StoryEffort? effort = StoryEffort.high,
    bool checkQuotes = false,
    String? section = 'section-002',
  }) => StoryUpdateRequest(
    epubPath: epub,
    storePath: storePath,
    model: model,
    effort: effort,
    checkQuotes: checkQuotes,
    prompt: prompt,
    schemaText: schemaText,
    sectionId: section,
  );

  /// Runs an update the way the app does, against a stand-in provider.
  Future<StoryUpdateOutcome> update(
    StoryUpdateRequest request,
    StoryHttpPost post,
  ) => StoryUpdater.run(request, bookId: 'book', apiKey: _apiKey, post: post);

  StoryHttpPost answering(Object? output) =>
      (url, headers, body) async =>
          StoryHttpResponse(200, _responseBody(output), requestId: 'req_1');

  Map<String, String> treeOf(String path) {
    final directory = Directory(path);
    if (!directory.existsSync()) return const {};
    return {
      for (final file in directory.listSync(recursive: true).whereType<File>())
        file.path: sha256OfBytes(file.readAsBytesSync()),
    };
  }

  Future<void> buildChapter1() async {
    final outcome = await update(request(), answering(chapter1Delta));
    expect(outcome.status, 'committed', reason: '${outcome.issues}');
  }

  group('a request', () {
    for (final raw in readGoldenList('request_golden.json')) {
      final item = raw as JsonMap;
      final name =
          '${item['provider']} ${item['effort']} ${item['section_id']}';
      test('matches what the lab sends: $name', () {
        final base = item['base_revision'] == 0
            ? golden['empty'] as JsonMap
            : first['after'] as JsonMap;
        final chapter = item['base_revision'] == 0
            ? first['chapter'] as JsonMap
            : golden['chapter'] as JsonMap;
        final model = StoryModelChoice.values.firstWhere(
          (model) => model.id == item['model'],
        );
        final effort = item['effort'] as String?;
        final schema = jsonDecode(schemaText) as JsonMap;
        final body = buildUpdateRequest(
          context: buildUpdateContext(
            base,
            chapter,
            sectionOrder: item['base_revision'] == 0 ? 2 : 3,
          ),
          prompt: prompt,
          schema: schema,
          model: model,
          effort: effort == null ? null : StoryEffort.values.byName(effort),
        );
        final comparable = jsonDecode(jsonEncode(body)) as JsonMap;
        ((comparable['input'] as List)[0] as JsonMap)['content'] =
            sha256OfBytes(utf8.encode(prompt));
        final format = (comparable['text'] as JsonMap)['format'] as JsonMap;
        format['schema'] = sha256OfJson(schema);
        expect(comparable, item['body']);
      });
    }
  });

  group('updating', () {
    test('builds a store one section at a time', () async {
      await buildChapter1();
      final store = StoryStore(Directory(storePath));
      final state = store.load();
      expect((state.model['revision'] as JsonMap)['number'], 1);
      expect(
        (state.model['coverage'] as JsonMap)['omitted_prefix_section_ids'],
        ['section-001'],
      );

      final outcome = await update(
        request(section: null),
        answering(chapter2Delta),
      );
      expect(outcome.status, 'committed', reason: '${outcome.issues}');
      expect(outcome.revision, 2);
      expect(outcome.usage, {'input_tokens': 10, 'output_tokens': 20});
      final after = store.load();
      expect(
        [
          for (final s in after.model['processed_sections'] as List)
            (s as JsonMap)['section_id'],
        ],
        ['section-002', 'section-003'],
      );
    });

    test('the second request carries the first section\'s knowledge', () async {
      await buildChapter1();
      late String sent;
      await update(request(section: null), (url, headers, body) async {
        sent = body;
        return StoryHttpResponse(200, _responseBody(chapter2Delta));
      });
      final user =
          ((jsonDecode(sent) as JsonMap)['input'] as List)[1] as JsonMap;
      expect(user['content'], contains('PRIOR_STORY_MODEL (revision 1;'));
      expect(user['content'], contains('"section_id":"section-002"'));
      expect(user['content'], contains('Section ID: section-003'));
      // Later sections are never sent.
      expect(user['content'], isNot(contains('INTERLUDE-SENTINEL')));
    });

    test(
      'sends the chosen model and effort, with the key only in the header',
      () async {
        late Uri url;
        late Map<String, String> headers;
        late JsonMap body;
        await update(
          request(model: StoryModelChoice.gpt61Sol, effort: StoryEffort.low),
          (sentUrl, sentHeaders, sentBody) async {
            url = sentUrl;
            headers = sentHeaders;
            body = jsonDecode(sentBody) as JsonMap;
            return StoryHttpResponse(200, _responseBody(chapter1Delta));
          },
        );
        expect(url.toString(), 'https://api.openai.com/v1/responses');
        expect(body['model'], 'gpt-6.1-sol');
        expect(body['reasoning'], {'effort': 'low'});
        expect(body['store'], false);
        expect(body['truncation'], 'disabled');
        expect(headers['authorization'], 'Bearer $_apiKey');
        expect(jsonEncode(body), isNot(contains(_apiKey)));
      },
    );

    test('DeepSeek gets its own address and no store or truncation', () async {
      late Uri url;
      late JsonMap body;
      await update(request(), (sentUrl, headers, sentBody) async {
        url = sentUrl;
        body = jsonDecode(sentBody) as JsonMap;
        return StoryHttpResponse(200, _responseBody(chapter1Delta));
      });
      expect(url.toString(), 'https://api.deepseek.com/responses');
      expect(body.containsKey('store'), isFalse);
      expect(body.containsKey('truncation'), isFalse);
    });

    test('the key is never written to the store', () async {
      await buildChapter1();
      final files = Directory(storePath).listSync(recursive: true);
      for (final file in files.whereType<File>()) {
        expect(file.readAsStringSync(), isNot(contains(_apiKey)));
      }
    });

    test('runs one update at a time for a book', () async {
      final release = Completer<void>();
      var requests = 0;
      Future<StoryHttpResponse> slow(
        Uri url,
        Map<String, String> headers,
        String body,
      ) async {
        requests++;
        await release.future;
        return StoryHttpResponse(200, _responseBody(chapter1Delta));
      }

      final one = update(request(), slow);
      final two = update(request(), slow);
      final running = StoryUpdater.running('book')!;
      expect(running.sectionId, 'section-002');
      expect(
        DateTime.now().difference(running.startedAt).inSeconds,
        lessThan(30),
      );
      // Let the first reach the provider, off in its isolate.
      for (var i = 0; requests == 0 && i < 400; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(requests, 1);
      release.complete();
      expect((await one).committed, isTrue);
      expect((await two).committed, isTrue);
      expect(requests, 1);
      expect(StoryUpdater.running('book'), isNull);
    });
  });

  group('the quote check', () {
    JsonMap withBadQuote() {
      final delta = jsonDecode(jsonEncode(chapter2Delta)) as JsonMap;
      final names = (delta['new_records'] as JsonMap)['names'] as List;
      final evidence = (names[0] as JsonMap)['evidence'] as List;
      (evidence[0] as JsonMap)['quote'] = 'Words that are not in the book';
      return delta;
    }

    test('off, a bad quote is flagged and the update is kept', () async {
      await buildChapter1();
      final outcome = await update(
        request(section: null),
        answering(withBadQuote()),
      );
      expect(outcome.status, 'committed');
      expect(outcome.unmatchedQuotes, 1);
      final sections =
          StoryStore(Directory(storePath)).load().model['processed_sections']
              as List;
      expect((sections[0] as JsonMap)['quotes_checked'], isFalse);
      expect((sections[1] as JsonMap)['quotes_checked'], isFalse);
    });

    test('on, a bad quote rejects the update', () async {
      final firstOutcome = await update(
        request(checkQuotes: true),
        answering(chapter1Delta),
      );
      expect(firstOutcome.status, 'committed');
      final before = treeOf(storePath);
      final outcome = await update(
        request(section: null, checkQuotes: true),
        answering(withBadQuote()),
      );
      expect(outcome.status, 'validation_failed');
      expect(
        outcome.issues.where((i) => i.isError).single.code,
        'quote_not_found',
      );
      expect(treeOf(storePath), before);
    });

    test(
      'remembered per section: turning it on later keeps the old ones',
      () async {
        await buildChapter1();
        final outcome = await update(
          request(section: null, checkQuotes: true),
          answering(chapter2Delta),
        );
        expect(outcome.status, 'committed');
        final sections =
            StoryStore(Directory(storePath)).load().model['processed_sections']
                as List;
        expect((sections[0] as JsonMap)['quotes_checked'], isFalse);
        expect((sections[1] as JsonMap)['quotes_checked'], isTrue);
      },
    );
  });

  group('a failed update changes nothing:', () {
    final failures = <String, (StoryHttpPost, String, String?)>{
      'rejected key': (
        (u, h, b) async =>
            const StoryHttpResponse(401, '{"error":{"message":"Bad key"}}'),
        'api_error',
        'authentication',
      ),
      'rate limit': (
        (u, h, b) async => const StoryHttpResponse(429, 'slow down'),
        'api_error',
        'rate_limit',
      ),
      'server error': (
        (u, h, b) async => const StoryHttpResponse(503, ''),
        'api_error',
        'server_error',
      ),
      'unknown model': (
        (u, h, b) async => const StoryHttpResponse(
          400,
          '{"error":{"message":"No such model"}}',
        ),
        'api_error',
        'invalid_request',
      ),
      'lost connection': (
        (u, h, b) async => throw const SocketException('gone'),
        'api_error',
        'network',
      ),
      'timeout': (
        (u, h, b) async => throw TimeoutException('late'),
        'api_error',
        'timeout',
      ),
      'not JSON': (
        (u, h, b) async => const StoryHttpResponse(200, '<html>'),
        'api_error',
        'invalid_response_body',
      ),
      'refusal': (
        (u, h, b) async => StoryHttpResponse(
          200,
          jsonEncode({
            'status': 'completed',
            'output': [
              {
                'type': 'message',
                'content': [
                  {'type': 'refusal', 'refusal': 'No.'},
                ],
              },
            ],
          }),
        ),
        'refusal',
        'refusal',
      ),
      'cut off': (
        (u, h, b) async => StoryHttpResponse(
          200,
          jsonEncode({
            'status': 'incomplete',
            'incomplete_details': {'reason': 'max_output_tokens'},
            'output': <Object>[],
          }),
        ),
        'incomplete',
        'incomplete',
      ),
      'response failed': (
        (u, h, b) async => StoryHttpResponse(
          200,
          jsonEncode({
            'status': 'failed',
            'error': 'boom',
            'output': <Object>[],
          }),
        ),
        'failed',
        'response_failed',
      ),
      'no output': (
        (u, h, b) async => StoryHttpResponse(
          200,
          jsonEncode({'status': 'completed', 'output': <Object>[]}),
        ),
        'empty_output',
        'empty_output',
      ),
      'output is not JSON': (
        (u, h, b) async => StoryHttpResponse(
          200,
          jsonEncode({
            'status': 'completed',
            'output': [
              {
                'type': 'message',
                'content': [
                  {'type': 'output_text', 'text': 'not json'},
                ],
              },
            ],
          }),
        ),
        'schema_invalid',
        'invalid_json',
      ),
      'output has the wrong shape': (
        (u, h, b) async => StoryHttpResponse(200, _responseBody({'a': 1})),
        'schema_invalid',
        null,
      ),
    };

    for (final MapEntry(key: name, value: failure) in failures.entries) {
      test(name, () async {
        final (post, status, category) = failure;
        await buildChapter1();
        final before = treeOf(storePath);
        final outcome = await update(request(section: null), post);
        expect(outcome.status, status);
        expect(outcome.category, category);
        expect(outcome.committed, isFalse);
        expect(treeOf(storePath), before);
      });
    }

    test('an unusable key doesn\'t show up in the error', () async {
      final outcome = await StoryUpdater.run(
        request(),
        bookId: 'book',
        apiKey: 'sk-secret\nkey',
        // The real network call: its header check throws before anything is
        // sent, quoting the value.
        post: postStoryRequest,
      );
      expect(outcome.committed, isFalse);
      expect(outcome.message, isNot(contains('secret')));
    });

    test('a reply in an unexpected form is a failure, not a crash', () async {
      final outcome = await update(
        request(),
        (u, h, b) async =>
            const StoryHttpResponse(200, '{"id":1,"status":"completed"}'),
      );
      expect(outcome.status, 'api_error');
      expect(outcome.category, 'invalid_response_body');
    });

    test('and a failed first update creates no store', () async {
      final outcome = await update(
        request(),
        (u, h, b) async => const StoryHttpResponse(500, ''),
      );
      expect(outcome.committed, isFalse);
      expect(StoryStore(Directory(storePath)).exists, isFalse);
    });

    test('a store that changed meanwhile is not overwritten', () async {
      await buildChapter1();
      final prepared = prepareStoryUpdate(request(section: null))!;
      final latest = File('$storePath/story_model.json');
      latest.writeAsStringSync('${latest.readAsStringSync()}\n');
      final call = StoryCallResult('completed')..candidate = chapter2Delta;
      final outcome = finishStoryUpdate(prepared, call);
      expect(outcome.status, 'stale_base');
    });
  });

  group('choosing the next section', () {
    test('steps over a section with no text', () async {
      const epub = '$goldenDir/toc_oddities.epub';
      final book = StoryBook.open(File(epub).readAsBytesSync());
      expect(book.sections.map((s) => s.title), [
        'Chapter 1',
        'Plate',
        'Document',
      ]);
      final outcome = await update(
        request(epub: epub, section: 'section-001'),
        answering(emptyDelta),
      );
      expect(outcome.status, 'committed', reason: '${outcome.issues}');
      final status = inspectStoryUpdate(epub, storePath);
      expect(status.nextSectionId, 'section-003');

      final second = await update(
        request(epub: epub, section: null),
        answering(emptyDelta),
      );
      expect(second.committed, isTrue, reason: '${second.issues}');
      expect(
        StoryStore(Directory(storePath)).load().model['revision'],
        isNotNull,
      );
      expect(inspectStoryUpdate(epub, storePath).isFinished, isTrue);
    });

    test(
      'stops at a section that can\'t be cut reliably, before paying',
      () async {
        const epub = '$goldenDir/blocked_later.epub';
        final first = await update(
          request(epub: epub, section: 'section-001'),
          answering(emptyDelta),
        );
        expect(first.committed, isTrue, reason: '${first.issues}');

        expect(
          inspectStoryUpdate(epub, storePath).blocked,
          contains('Chapter 2'),
        );
        var requests = 0;
        final outcome = await update(request(epub: epub, section: null), (
          url,
          headers,
          body,
        ) async {
          requests++;
          return const StoryHttpResponse(500, '');
        });
        expect(outcome.status, 'input_error');
        expect(requests, 0);
      },
    );

    test('only offers readable sections to start from', () {
      final status = inspectStoryUpdate(
        '$goldenDir/bad_anchors.epub',
        storePath,
      );
      expect(status.isNewStore, isTrue);
      expect(status.choices.map((choice) => choice.sectionId), [
        'section-007',
        'section-008',
      ]);
    });

    test(
      'suggests a long section, past the front matter',
      () {
        final status = inspectStoryUpdate(
          'sample_epub/86v1_chapters.epub',
          storePath,
        );
        expect(status.suggestedStart, 'section-003');
      },
      tags: 'corpus',
      skip: File('sample_epub/86v1_chapters.epub').existsSync()
          ? false
          : 'needs the sample book',
    );

    test('without a long section, suggests the first one with text', () {
      final status = inspectStoryUpdate('$goldenDir/story.epub', storePath);
      expect(status.suggestedStart, 'section-001');
    });

    test('a different file with the same store is refused', () async {
      await buildChapter1();
      final status = inspectStoryUpdate('$goldenDir/nav_order.epub', storePath);
      expect(status.blocked, contains('not the file'));
    });

    test('continues from the last section processed', () async {
      await buildChapter1();
      expect(
        inspectStoryUpdate(_storyEpub, storePath).nextSectionId,
        'section-003',
      );
    });
  });

  group('choosing a later section', () {
    test('skips ahead, and the map keeps the gap', () async {
      await buildChapter1();
      late String sent;
      final outcome = await update(request(section: 'section-004'), (
        url,
        headers,
        body,
      ) async {
        sent = body;
        return StoryHttpResponse(200, _responseBody(emptyDelta));
      });
      expect(outcome.status, 'committed', reason: '${outcome.issues}');
      expect(outcome.sectionTitle, 'Interlude: The Lamp');

      final user =
          ((jsonDecode(sent) as JsonMap)['input'] as List)[1] as JsonMap;
      expect(user['content'], contains('Section ID: section-004'));
      expect(user['content'], isNot(contains('Section ID: section-003')));

      final model = StoryStore(Directory(storePath)).load().model;
      expect(
        [
          for (final s in model['processed_sections'] as List)
            (s as JsonMap)['section_id'],
        ],
        ['section-002', 'section-004'],
      );
      // Carries on from the new place, not from the gap.
      expect(
        inspectStoryUpdate(_storyEpub, storePath).nextSectionId,
        'section-005',
      );
    });

    test('lists what each section would leave out', () async {
      await buildChapter1();
      final status = inspectStoryUpdate(_storyEpub, storePath);
      expect(status.canChoose, isTrue);
      expect(status.choices.map((choice) => choice.sectionId), [
        'section-003',
        'section-004',
        'section-005',
      ]);
      expect(status.choices.map((choice) => choice.skips), [
        isEmpty,
        ['Chapter 2: The Storm'],
        ['Chapter 2: The Storm', 'Interlude: The Lamp'],
      ]);
      expect(status.titleOf('section-005'), 'Chapter 3: Aftermath');
      expect(status.titleOf(null), 'Chapter 2: The Storm');
    });

    for (final (name, section) in const [
      ('the last one processed', 'section-002'),
      ('one before the map starts', 'section-001'),
      ('one that doesn\'t exist', 'section-099'),
    ]) {
      test('refuses $name, before paying', () async {
        await buildChapter1();
        final before = treeOf(storePath);
        var requests = 0;
        final outcome = await update(request(section: section), (
          url,
          headers,
          body,
        ) async {
          requests++;
          return StoryHttpResponse(200, _responseBody(emptyDelta));
        });
        expect(outcome.status, 'input_error');
        expect(requests, 0);
        expect(treeOf(storePath), before);
      });
    }

    test('a section with no text is neither offered nor left out', () async {
      const epub = '$goldenDir/toc_oddities.epub';
      await update(
        request(epub: epub, section: 'section-001'),
        answering(emptyDelta),
      );
      final status = inspectStoryUpdate(epub, storePath);
      expect(status.choices.map((choice) => choice.sectionId), ['section-003']);
      expect(status.choices.single.skips, isEmpty);
      expect(status.canChoose, isFalse);

      var requests = 0;
      final outcome = await update(
        request(epub: epub, section: 'section-002'),
        (url, headers, body) async {
          requests++;
          return StoryHttpResponse(200, _responseBody(emptyDelta));
        },
      );
      expect(outcome.status, 'input_error');
      expect(requests, 0);
    });

    test('the reader can step past a section that can\'t be read', () async {
      final epub = '${temp.path}/stuck.epub';
      File(epub).writeAsBytesSync(_epubWithBrokenMiddle());
      final first = await update(
        request(epub: epub, section: 'section-001'),
        answering(emptyDelta),
      );
      expect(first.committed, isTrue, reason: '${first.issues}');

      final status = inspectStoryUpdate(epub, storePath);
      expect(status.isReady, isFalse);
      expect(status.blocked, contains('Chapter 2'));
      expect(status.canChoose, isTrue);
      expect(status.choices.single.sectionId, 'section-003');
      expect(status.choices.single.skips, ['Chapter 2']);

      // Left alone, it still stops there rather than stepping past unasked.
      var requests = 0;
      final stopped = await update(request(epub: epub, section: null), (
        url,
        headers,
        body,
      ) async {
        requests++;
        return StoryHttpResponse(200, _responseBody(emptyDelta));
      });
      expect(stopped.status, 'input_error');
      expect(requests, 0);

      final skipped = await update(
        request(epub: epub, section: 'section-003'),
        answering(emptyDelta),
      );
      expect(skipped.committed, isTrue, reason: '${skipped.issues}');
      StoryStore(Directory(storePath)).load();
      expect(inspectStoryUpdate(epub, storePath).isFinished, isTrue);
    });

    test(
      'a section that can\'t be read is refused when asked for by name',
      () async {
        final epub = '${temp.path}/stuck.epub';
        File(epub).writeAsBytesSync(_epubWithBrokenMiddle());
        await update(
          request(epub: epub, section: 'section-001'),
          answering(emptyDelta),
        );
        final outcome = await update(
          request(epub: epub, section: 'section-002'),
          answering(emptyDelta),
        );
        expect(outcome.status, 'input_error');
      },
    );
  });

  group('a store', () {
    test('that was tampered with is refused', () async {
      await buildChapter1();
      final store = StoryStore(Directory(storePath));

      void expectRefused(String what) =>
          expect(store.load, throwsA(isA<StoryStoreError>()), reason: what);

      final inputs = Directory('$storePath/inputs').listSync().single as File;
      final savedInput = inputs.readAsStringSync();
      inputs.writeAsStringSync('$savedInput ');
      expectRefused('input changed');
      inputs.writeAsStringSync(savedInput);
      store.load();

      final snapshot =
          Directory('$storePath/revisions').listSync().single as File;
      final savedSnapshot = snapshot.readAsStringSync();
      snapshot.writeAsStringSync('$savedSnapshot ');
      expectRefused('snapshot changed');
      snapshot.writeAsStringSync(savedSnapshot);
      store.load();

      final provenance =
          Directory('$storePath/provenance').listSync().single as Directory;
      final delta = File('${provenance.path}/delta.json');
      final savedDelta = delta.readAsStringSync();
      delta.writeAsStringSync('$savedDelta ');
      expectRefused('provenance changed');
      delta.writeAsStringSync(savedDelta);

      File('${provenance.path}/manifest.json').deleteSync();
      expectRefused('provenance missing');
    });

    test('never leaves a temporary file behind', () async {
      await buildChapter1();
      final files = Directory(storePath).listSync(recursive: true);
      expect(files.where((f) => f.path.endsWith('.tmp')), isEmpty);
    });
  });

  group('model choices', () {
    test('a provider\'s default comes first', () {
      expect(
        StoryModelChoice.resolve('deepseek', null),
        StoryModelChoice.deepseekFlash,
      );
      expect(
        StoryModelChoice.resolve('openai', null),
        StoryModelChoice.gpt61Terra,
      );
    });

    test('OpenAI offers Terra and Sol', () {
      expect(StoryModelChoice.forProvider('openai').map((m) => m.id), [
        'gpt-6.1-terra',
        'gpt-6.1-sol',
      ]);
    });

    test('OpenRouter offers DeepSeek Flash and Terra by their router ids', () {
      expect(StoryModelChoice.forProvider('openrouter').map((m) => m.id), [
        'deepseek/deepseek-v4-flash',
        'openai/gpt-6.1-terra',
      ]);
      expect(
        StoryProvider.named('openrouter').responsesUrl,
        'https://openrouter.ai/api/v1/responses',
      );
      expect(StoryProvider.named('openrouter').sendsStoreAndTruncation, false);
    });

    test('a choice made for another provider falls back', () {
      expect(
        StoryModelChoice.resolve('deepseek', 'gpt-6.1-sol'),
        StoryModelChoice.deepseekFlash,
      );
    });

    test('an effort the model doesn\'t take falls back to high', () {
      expect(StoryModelChoice.gpt61Sol.resolveEffort('none'), StoryEffort.high);
      expect(
        StoryModelChoice.deepseekFlash.resolveEffort('medium'),
        StoryEffort.high,
      );
      expect(
        StoryModelChoice.gpt61Terra.resolveEffort('medium'),
        StoryEffort.medium,
      );
    });
  });

  test('the schema file is what the lab sends', () {
    final schema = StoryDeltaSchema.parse(schemaText);
    final (_, issues) = schema.check(chapter1Delta);
    expect(issues, isEmpty);
  });
}
