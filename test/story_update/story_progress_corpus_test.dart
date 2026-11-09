import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/story_update/story_book.dart';
import 'package:loremark/story_update/story_paragraphs.dart';

// Checks Story Map progress against the real maps on a device, which hold a
// book's text and so aren't in the repository. Set LOREMARK_STORY_LIBRARY to an
// app's `library` folder. Nothing in it is changed.
void main() {
  final root = Platform.environment['LOREMARK_STORY_LIBRARY'];

  /// How many records of each section show at a quarter, half and three quarters
  /// of its paragraphs, worked out by hand from the book's model.
  const expected = {
    '0834655c': {
      'section-003': [35, 50, 62],
      'section-004': [30, 75, 98],
      'section-008': [18, 38, 54],
      'section-009': [27, 43, 77],
    },
  };

  Iterable<(String, String, JsonMap)> maps() sync* {
    for (final store in Directory('$root/story_models').listSync()) {
      final model = File('${store.path}/story_model.json');
      if (store is! Directory || !model.existsSync()) continue;
      final id = store.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      final epub = '$root/books/$id.epub';
      if (!File(epub).existsSync()) continue;
      yield (store.path, epub, jsonDecode(model.readAsStringSync()) as JsonMap);
    }
  }

  test(
    'paragraph progress holds up on real maps',
    () {
      expect(maps(), isNotEmpty);
      for (final (store, epub, json) in maps()) {
        final model = StoryModel.fromJson(json);
        final bookId = store.substring(store.lastIndexOf('/') + 1);
        final paragraphs = readStoryParagraphs(
          store,
          epub,
          visibleSections: model.sections.length,
        );
        final book = StoryBook.open(File(epub).readAsBytesSync());
        final wanted = expected.entries
            .where((entry) => bookId.startsWith(entry.key))
            .firstOrNull
            ?.value;

        for (final section in model.sections) {
          final own = paragraphs.ofSection(section.id);
          final records = [
            for (final record in model.allRecords)
              if (record.learnedInSectionId == section.id) record,
          ];
          Set<String> hiddenAt(int read) =>
              hiddenWithinSection(model, section, own, paragraphsRead: read);

          // Knowing more never hides something that was showing.
          var before = hiddenAt(0);
          for (var read = 1; read <= own.length; read += 25) {
            final now = hiddenAt(read);
            expect(
              now.difference(before),
              isEmpty,
              reason: '${section.id} at $read',
            );
            before = now;
          }

          // Nothing shows before there is a name to show it by.
          final labels = {
            for (final record in [...model.names, ...model.aliases])
              if ((model.sectionById(record.learnedInSectionId)?.order ?? 0) <
                  section.order)
                record.payload.entityId,
          };
          for (var read = 1; read <= own.length; read += 25) {
            final hidden = hiddenAt(read);
            final named = {
              ...labels,
              for (final record in [...model.names, ...model.aliases])
                if (record.learnedInSectionId == section.id &&
                    !hidden.contains(record.id))
                  record.payload.entityId,
            };
            for (final record in records) {
              if (hidden.contains(record.id)) continue;
              for (final entity in record.payload.entityIds) {
                final hasName = [
                  ...model.names,
                  ...model.aliases,
                ].any((label) => label.payload.entityId == entity);
                if (hasName) {
                  expect(
                    named,
                    contains(entity),
                    reason: '${record.id} at $read',
                  );
                }
              }
            }
          }

          if (wanted != null) {
            expect(
              [
                for (final share in const [0.25, 0.5, 0.75])
                  () {
                    final hidden = hiddenAt((own.length * share).floor());
                    return records.where((r) => !hidden.contains(r.id)).length;
                  }(),
              ],
              wanted[section.id],
              reason: section.id,
            );
          }

          // Moving down the page never loses a paragraph already passed.
          final source = book.sections.firstWhere(
            (candidate) => candidate.sectionId == section.id,
          );
          var last = -1;
          for (var child = 1; child < own.length + 40; child += 20) {
            final count = book.paragraphsBefore(
              source,
              ':root > :nth-child(2) > :nth-child($child)',
            );
            if (count == null) continue;
            expect(count, greaterThanOrEqualTo(last), reason: '$child');
            expect(count, lessThanOrEqualTo(own.length));
            last = count;
          }
          expect(last, greaterThan(0), reason: section.id);
        }
      }
    },
    tags: 'corpus',
    skip: root == null ? 'set LOREMARK_STORY_LIBRARY' : false,
  );
}
