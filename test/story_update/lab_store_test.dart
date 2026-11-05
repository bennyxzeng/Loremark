import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/story_update/story_book.dart';
import 'package:loremark/story_update/story_merge.dart';
import 'package:loremark/story_update/story_store.dart';
import 'package:loremark/story_update/story_validation.dart';

import 'golden.dart';

// Checks stores the story model lab really built, which hold a book's text and
// so aren't in the repository. Set LOREMARK_STORY_STORES to a folder of them.
void main() {
  final root = Platform.environment['LOREMARK_STORY_STORES'];
  final stores = root == null
      ? const <Directory>[]
      : Directory(root).listSync().whereType<Directory>().toList();

  JsonMap read(File file) => jsonDecode(file.readAsStringSync()) as JsonMap;

  test(
    'real stores load, and replaying each delta gives what the lab committed',
    () {
      final schema = readDeltaSchema();
      expect(stores, isNotEmpty);
      for (final directory in stores) {
        final state = StoryStore(directory).load();
        final number = (state.model['revision'] as JsonMap)['number'] as int;
        final snapshots =
            Directory('${directory.path}/revisions')
                .listSync()
                .whereType<File>()
                .map(read)
                .toList()
              ..sort(
                (a, b) => ((a['revision'] as JsonMap)['number'] as int)
                    .compareTo((b['revision'] as JsonMap)['number'] as int),
              );
        expect(snapshots, hasLength(number), reason: directory.path);

        var base = <String, dynamic>{
          ...snapshots.first,
          'revision': <String, dynamic>{'number': 0},
          'processed_sections': <Object>[],
          'entities': <Object>[],
          'records': {for (final name in storyCollections) name: <Object>[]},
          'transitions': <Object>[],
          'provenance': {'manual_corrections': <Object>[]},
        };
        final inputs = <String, JsonMap>{};
        for (final snapshot in snapshots) {
          final revision = snapshot['revision'] as JsonMap;
          final where = '${directory.path} revision ${revision['number']}';
          final sections = snapshot['processed_sections'] as List;
          final section = sections.last as JsonMap;
          final chapter = state.inputs[section['section_id']]!;
          final delta = read(
            File(
              '${directory.path}/provenance/${revision['source_run_id']}/delta.json',
            ),
          );
          final result = validateUpdate(
            base,
            delta,
            schema: schema,
            chapter: chapter,
            baseInputs: inputs,
            section: section,
            revision: revision,
          );
          // Manual corrections are the lab's alone; the model records them.
          final corrected = result.errors
              .where((issue) => issue.code != 'history_changed')
              .toList();
          expect(corrected, isEmpty, reason: where);
          final after = result.after!;
          for (final field in const [
            'book',
            'coverage',
            'entities',
            'records',
            'transitions',
            'current',
          ]) {
            expect(
              jsonEncode(after[field]),
              jsonEncode(snapshot[field]),
              reason: '$where: $field',
            );
          }
          inputs[section['section_id'] as String] = chapter;
          base = snapshot;
        }
      }
    },
    tags: 'corpus',
    skip: root == null ? 'set LOREMARK_STORY_STORES' : false,
  );
}
