import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/story_model/story_snapshot.dart';
import 'package:loremark/story_update/story_api_client.dart';
import 'package:loremark/story_update/story_book.dart';
import 'package:loremark/story_update/story_model_choice.dart';
import 'package:loremark/story_update/story_paragraphs.dart';
import 'package:loremark/story_update/story_store.dart';
import 'package:loremark/story_update/story_updater.dart';

import 'golden.dart';

const _epub = '$goldenDir/story.epub';

String _responseBody(Object? output) => jsonEncode({
  'status': 'completed',
  'output': [
    {
      'type': 'message',
      'content': [
        {'type': 'output_text', 'text': jsonEncode(output)},
      ],
    },
  ],
});

List<StoryParagraph> _section(String id, int count) => [
  for (var i = 1; i <= count; i++)
    StoryParagraph(
      sectionId: id,
      id: 'p${'$i'.padLeft(4, '0')}',
      number: i,
      text: 'Paragraph $i of $id',
    ),
];

Evidence _cite(String section, String paragraph) =>
    Evidence(sectionId: section, paragraphId: paragraph, quote: 'quote');

List<String> _names(List<StoryParagraph> paragraphs) => [
  for (final item in paragraphs) '${item.sectionId}:${item.id}',
];

void main() {
  group('forEvidence', () {
    final paragraphs = StoryParagraphs({
      'section-001': _section('section-001', 3),
      'section-002': _section('section-002', 5),
    });

    test('is just the cited paragraph without context', () {
      expect(_names(paragraphs.forEvidence([_cite('section-002', 'p0003')])), [
        'section-002:p0003',
      ]);
    });

    test('stops context at the edges of a section', () {
      expect(
        _names(
          paragraphs.forEvidence([
            _cite('section-001', 'p0003'),
            _cite('section-002', 'p0001'),
          ], context: 1),
        ),
        [
          'section-001:p0002',
          'section-001:p0003',
          'section-002:p0001',
          'section-002:p0002',
        ],
      );
    });

    test('has no repeats, and comes in reading order', () {
      expect(
        _names(
          paragraphs.forEvidence([
            _cite('section-002', 'p0003'),
            _cite('section-001', 'p0002'),
            _cite('section-002', 'p0002'),
            _cite('section-002', 'p0003'),
          ], context: 1),
        ),
        [
          'section-001:p0001',
          'section-001:p0002',
          'section-001:p0003',
          'section-002:p0001',
          'section-002:p0002',
          'section-002:p0003',
          'section-002:p0004',
        ],
      );
    });

    test('skips what it does not have', () {
      expect(
        paragraphs.forEvidence([
          _cite('section-001', 'p9999'),
          _cite('section-009', 'p0001'),
        ], context: 2),
        isEmpty,
      );
    });
  });

  group('readStoryParagraphs', () {
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

    Future<void> add(Object? delta, {String? section}) async {
      final outcome = await StoryUpdater.run(
        StoryUpdateRequest(
          epubPath: _epub,
          storePath: storePath,
          model: StoryModelChoice.deepseekFlash,
          effort: StoryEffort.high,
          checkQuotes: false,
          prompt: prompt,
          schemaText: schemaText,
          sectionId: section,
        ),
        bookId: 'book',
        apiKey: 'sk-test',
        post: (url, headers, body) async =>
            StoryHttpResponse(200, _responseBody(delta)),
      );
      expect(outcome.status, 'committed', reason: '${outcome.issues}');
    }

    setUp(() async {
      temp = Directory.systemTemp.createTempSync('story_paragraphs_');
      storePath = '${temp.path}/store';
      await add(chapter1Delta, section: 'section-002');
      await add(chapter2Delta);
    });
    tearDown(() => temp.deleteSync(recursive: true));

    StoryParagraphs read(int finished, {String epub = _epub}) =>
        readStoryParagraphs(storePath, epub, StoryReadingProgress(finished));

    /// A reader who has finished the first section and is [paragraphs] into the
    /// second.
    StoryParagraphs partway(int paragraphs) => readStoryParagraphs(
      storePath,
      _epub,
      StoryReadingProgress(
        1,
        hiddenInNext: const {},
        paragraphsReadInNext: paragraphs,
      ),
    );

    StoryModel model() => StoryModel.fromJson(readStoryModel(storePath)!);

    List<Evidence> evidenceOf(StoryModel model) => [
      ...model.allRecords.expand((record) => record.evidence),
      ...model.transitions.expand((transition) => transition.evidence),
    ];

    /// All of each cited section, to compare where the text came from.
    List<String> textOf(StoryParagraphs paragraphs) => [
      for (final item in paragraphs.forEvidence(
        evidenceOf(model()),
        context: 1 << 20,
      ))
        '${item.sectionId} ${item.id} ${item.number} ${item.text}',
    ];

    void saveModel(JsonMap model) {
      File('$storePath/story_model.json')
          .writeAsBytesSync(storyJsonBytes(model));
    }

    test('finds every paragraph the evidence names', () {
      final evidence = evidenceOf(model());
      final paragraphs = read(2);
      expect(evidence, isNotEmpty);
      for (final item in evidence) {
        expect(
          paragraphs.paragraph(item.sectionId, item.paragraphId)?.text,
          contains(item.quote),
        );
      }
    });

    test('numbers a section from 1', () {
      final first = read(1).paragraph('section-002', 'p0001');
      expect(first?.number, 1);
      expect(first?.sectionId, 'section-002');
    });

    test('cannot reach past the sections asked for', () {
      final map = model();
      final later = map.sections[1].id;
      final cited = evidenceOf(map)
          .firstWhere((item) => item.sectionId == later);

      final paragraphs = read(1);
      expect(paragraphs.paragraph(later, cited.paragraphId), isNull);
      expect(paragraphs.forEvidence([cited]), isEmpty);
      expect(read(2).forEvidence([cited]), hasLength(1));
    });

    group('partway through a section,', () {
      test('holds finished sections whole, and only the start of that one', () {
        final map = model();
        final first = map.sections[0].id;
        final second = map.sections[1].id;
        final paragraphs = partway(2);

        expect(
          paragraphs.ofSection(first),
          hasLength(read(1).ofSection(first).length),
        );
        expect(_names(paragraphs.ofSection(second)), [
          '$second:p0001',
          '$second:p0002',
        ]);
      });

      test('cannot reach a paragraph ahead of the page', () {
        final second = model().sections[1].id;
        final paragraphs = partway(2);

        expect(paragraphs.paragraph(second, 'p0003'), isNull);
        expect(paragraphs.forEvidence([_cite(second, 'p0003')]), isEmpty);
      });

      test('context stops at the page', () {
        final second = model().sections[1].id;
        expect(
          _names(partway(2).forEvidence([_cite(second, 'p0002')], context: 5)),
          ['$second:p0001', '$second:p0002'],
        );
      });

      test('holds nothing of a section not in the map', () {
        final paragraphs = readStoryParagraphs(
          storePath,
          _epub,
          const StoryReadingProgress(
            5,
            hiddenInNext: {},
            paragraphsReadInNext: 1,
          ),
        );
        expect(textOf(paragraphs), textOf(read(2)));
      });
    });

    test('holds nothing when no section is visible', () {
      final evidence = evidenceOf(model());
      expect(read(0).forEvidence(evidence), isEmpty);
      expect(read(-1).forEvidence(evidence), isEmpty);
    });

    test('takes what there is when asked for more sections', () {
      expect(textOf(read(99)), textOf(read(2)));
    });

    test('is empty without a map', () {
      final paragraphs = readStoryParagraphs(
        '${temp.path}/none',
        _epub,
        const StoryReadingProgress(3),
      );
      expect(paragraphs.paragraph('section-002', 'p0001'), isNull);
    });

    test('needs no EPUB when the saved text is there', () {
      expect(textOf(read(2, epub: '${temp.path}/gone.epub')), textOf(read(2)));
    });

    test('reads a lone story_model.json from the EPUB', () {
      final lone = '${temp.path}/lone';
      Directory(lone).createSync();
      File('$storePath/story_model.json').copySync('$lone/story_model.json');
      final paragraphs = readStoryParagraphs(
        lone,
        _epub,
        const StoryReadingProgress(2),
      );
      expect(textOf(paragraphs), textOf(read(2)));
    });

    test('falls back to the EPUB when a saved file is changed', () {
      final before = textOf(read(2));
      Directory('$storePath/inputs')
          .listSync()
          .whereType<File>()
          .first
          .writeAsStringSync(
            jsonEncode({
              'paragraphs': [
                {'id': 'p0001', 'text': 'Tampered'},
              ],
            }),
          );
      expect(textOf(read(2)), before);
    });

    test('falls back to the EPUB when the saved files are gone', () {
      final before = textOf(read(2));
      Directory('$storePath/inputs').deleteSync(recursive: true);
      expect(textOf(read(2)), before);
    });

    test('never reads a saved file outside the store', () {
      final before = textOf(read(2));
      final secret = File('${temp.path}/secret.json')
        ..writeAsStringSync(
          jsonEncode({
            'paragraphs': [
              {'id': 'p0001', 'text': 'Secret'},
            ],
          }),
        );
      final map = readStoryModel(storePath)!;
      ((map['processed_sections'] as List).first as JsonMap)
        ..['input_relative_path'] = '../secret.json'
        ..['input_file_sha256'] = sha256OfBytes(secret.readAsBytesSync());
      saveModel(map);
      expect(textOf(read(2)), before);
    });

    group('with no saved text,', () {
      setUp(() => Directory('$storePath/inputs').deleteSync(recursive: true));

      test('refuses a different EPUB', () {
        expect(
          () => read(1, epub: '$goldenDir/nav_order.epub'),
          throwsA(isA<StoryEpubError>()),
        );
      });

      test('reports an EPUB that is gone', () {
        expect(
          () => read(1, epub: '${temp.path}/gone.epub'),
          throwsA(isA<StoryEpubError>()),
        );
      });

      test('refuses text that is not what the map recorded', () {
        final map = readStoryModel(storePath)!;
        ((map['processed_sections'] as List).first as JsonMap)['text_sha256'] =
            'not the hash';
        saveModel(map);
        expect(() => read(1), throwsA(isA<StoryStoreError>()));
      });
    });
  });
}
