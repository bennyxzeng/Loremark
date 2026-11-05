import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/story_update/story_book.dart';
import 'package:loremark/story_update/story_merge.dart';
import 'package:loremark/story_update/story_validation.dart';

import 'golden.dart';

void main() {
  final golden = readValidationGolden();
  final schema = readDeltaSchema();
  final first = golden['first'] as JsonMap;
  final base = first['after'] as JsonMap;
  final baseInputs = {'section-002': first['chapter'] as JsonMap};
  final chapter = golden['chapter'] as JsonMap;
  final revision = golden['revision'] as JsonMap;

  JsonMap sectionFor(bool checkQuotes) => {
    'section_id': chapter['section_id'],
    'section_order': golden['section_order'],
    'chapter_number': chapter['chapter_number'],
    'title': chapter['title'],
    'href': chapter['source_href'],
    'fragment': chapter['source_fragment'],
    'text_sha256': chapter['text_sha256'],
    'extraction_version': chapter['extraction_version'],
    'paragraph_count': (chapter['paragraphs'] as List).length,
    'input_relative_path': 'inputs/x.json',
    'input_file_sha256': '0' * 64,
    'introduced_revision': 2,
    'quotes_checked': checkQuotes,
  };

  Set<String> keys(List<Map<String, String>> issues) => {
    for (final i in issues) '${i['severity']} ${i['code']} ${i['path']}',
  };

  test('the first update of a store builds what the lab built', () {
    final result = validateUpdate(
      golden['empty'] as JsonMap,
      first['candidate'],
      schema: schema,
      chapter: first['chapter'] as JsonMap,
      baseInputs: const {},
      section: first['section'] as JsonMap,
      revision: first['revision'] as JsonMap,
    );
    expect(
      keys(issueList(result.issues)),
      keys([
        for (final i in first['issues'] as List)
          (i as Map).cast<String, String>(),
      ]),
    );
    expect(result.passed, isTrue);
    expect(jsonEquals(result.after, first['after']), isTrue);
    expect(result.idMap!.toJson(), first['id_map']);
  });

  group('an update is judged the way the lab judges it:', () {
    for (final raw in golden['cases'] as List) {
      final item = raw as JsonMap;
      final checkQuotes = item['check_quotes'] as bool;
      test('${item['name']} (quote check ${checkQuotes ? 'on' : 'off'})', () {
        final result = validateUpdate(
          base,
          item['candidate'],
          schema: schema,
          chapter: chapter,
          baseInputs: baseInputs,
          section: sectionFor(checkQuotes),
          revision: revision,
        );
        expect(
          keys(issueList(result.issues)),
          keys([
            for (final i in item['issues'] as List)
              (i as Map).cast<String, String>(),
          ]),
        );
        expect(result.structureValid, item['structure_valid']);
        expect(result.passed, item['passed']);
        if (item.containsKey('id_map')) {
          expect(result.idMap!.toJson(), item['id_map']);
        }
      });
    }
  });

  group('a whole model is judged the way the lab judges it:', () {
    final inputs = {...baseInputs, 'section-003': chapter};
    for (final raw in golden['whole_model'] as List) {
      final item = raw as JsonMap;
      test('${item['name']}', () {
        final report = validateCumulative(item['model'] as JsonMap, inputs);
        expect(
          keys(issueList(report.issues)),
          keys([
            for (final i in item['issues'] as List)
              (i as Map).cast<String, String>(),
          ]),
        );
      });
    }
  });

  test('merging keeps earlier knowledge and continues the numbering', () {
    final clean = (golden['cases'] as List).cast<JsonMap>().firstWhere(
      (item) => item['name'] == 'clean',
    );
    final (after, idMap) = applyDelta(
      base,
      clean['candidate'] as JsonMap,
      section: sectionFor(true),
      revision: revision,
    );
    expect(checkHistory(base, after), isEmpty);
    expect(idMap.records.values.first, 'f000023');
    expect(projectCurrent(after), after['current']);
  });
}
