import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/story_update/story_book.dart';

import 'golden.dart';

void main() {
  final golden = jsonDecode(
    File('$goldenDir/extraction_golden.json').readAsStringSync(),
  ) as JsonMap;

  for (final MapEntry(key: name, value: expected) in golden.entries) {
    final want = expected as JsonMap;
    group('$name.epub matches the lab', () {
      final book = StoryBook.open(
        File('$goldenDir/$name.epub').readAsBytesSync(),
      );
      test('book', () {
        expect(book.title, want['title']);
        expect(book.sha256Hash, want['sha256']);
        expect(book.tocSource, want['toc_source']);
        expect(book.warnings.length, (want['warnings'] as List).length);
      });
      test('sections', () {
        final sections = (want['sections'] as List).cast<JsonMap>();
        expect(book.sections.map((s) => s.sectionId), [
          for (final s in sections) s['section_id'],
        ]);
        for (var i = 0; i < sections.length; i++) {
          final section = book.sections[i];
          final w = sections[i];
          final id = w['section_id'];
          expect(section.order, w['order'], reason: '$id order');
          expect(section.title, w['title'], reason: '$id title');
          expect(section.chapterNumber, w['chapter_number'], reason: '$id ch');
          expect(section.href, w['href'], reason: '$id href');
          expect(section.fragment, w['fragment'], reason: '$id fragment');
          expect(section.spineIndex, w['spine_index'], reason: '$id spine');
          expect(section.inToc, w['in_toc'], reason: '$id in_toc');
          expect(section.problem != null, w['has_problem'], reason: '$id bad');
          expect(section.notes.length, (w['notes'] as List).length);
        }
      });
      test('text', () {
        final sections = (want['sections'] as List).cast<JsonMap>();
        for (var i = 0; i < sections.length; i++) {
          final input = sections[i]['input'] as JsonMap?;
          if (input == null) {
            expect(
              () => book.extract(book.sections[i]),
              throwsA(isA<StoryEpubError>()),
              reason: '${sections[i]['section_id']} should not extract',
            );
            continue;
          }
          final actual = book.extract(book.sections[i]);
          // Only the wording of the notes can differ.
          expect(
            {...actual, 'extraction_notes': null},
            {...input, 'extraction_notes': null},
            reason: '${sections[i]['section_id']}',
          );
        }
      });
    });
  }

  test('a section with only a picture is told apart from a broken one', () {
    final book = StoryBook.open(
      File('$goldenDir/toc_oddities.epub').readAsBytesSync(),
    );
    expect(
      () => book.extract(book.sections[1]),
      throwsA(isA<StorySectionEmptyError>()),
    );
  });

  test('a document that is not well-formed is flagged, not guessed at', () {
    final book = StoryBook.open(
      File('$goldenDir/malformed_document.epub').readAsBytesSync(),
    );
    expect(book.sections.map((s) => s.title), ['Chapter 1', 'Chapter 2']);
    expect(book.sections[0].problem, isNull);
    expect(book.extract(book.sections[0])['text_sha256'], isNotEmpty);
    expect(book.sections[1].problem, contains('not well-formed'));
    expect(
      () => book.extract(book.sections[1]),
      throwsA(isA<StoryEpubError>()),
    );
  });

  test('text follows the lab\'s rules', () {
    expect(normalizeStoryText('  a  b\n'), 'a b');
    expect(normalizeStoryText('Café'), 'Café');
    expect(parseChapterNumber('CHAPTER IV: x'), 4);
    expect(parseChapterNumber('Chapter 12'), 12);
    expect(parseChapterNumber('Chapters'), isNull);
  });

  group('the sample book', () {
    final file = File('sample_epub/86v1_chapters.epub');
    test(
      'every section matches the lab, hash for hash',
      () {
        final want = readGolden('sample_book_golden.json');
        final book = StoryBook.open(file.readAsBytesSync());
        expect(book.sha256Hash, want['sha256']);
        final sections = (want['sections'] as List).cast<JsonMap>();
        expect(book.sections.length, sections.length);
        for (var i = 0; i < sections.length; i++) {
          final section = book.sections[i];
          expect(section.sectionId, sections[i]['section_id']);
          expect(section.title, sections[i]['title']);
          expect(section.chapterNumber, sections[i]['chapter_number']);
          final input = book.extract(section);
          expect(
            input['text_sha256'],
            sections[i]['text_sha256'],
            reason: '${section.sectionId} text differs',
          );
          expect(
            (input['paragraphs'] as List).length,
            sections[i]['paragraph_count'],
          );
        }
      },
      tags: 'corpus',
      skip: file.existsSync() ? false : 'needs the sample book',
    );
  });
}
