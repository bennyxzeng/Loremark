import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/epub_sections.dart';
import 'package:loremark/story_map/story_map_backend.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/story_model/story_snapshot.dart';
import 'package:loremark/story_update/story_paragraphs.dart';

import '../story_model/story_model_fixture.dart';

// A small book for recap tests: the Story Map fixture's two chapters, with
// their files and paragraphs. Every paragraph says which one it is, such as
// "[s2 p3]", so a test can tell exactly which text reached a recap.

final recapTestBook = Book(
  id: 'book-1',
  title: 'The Glass Harbor',
  author: null,
  epubPath: '/nowhere.epub',
  coverPath: null,
  importedAt: DateTime.utc(2026),
);

const recapTestSpine = [
  SpineItem(path: 'OEBPS/title.xhtml', linear: true),
  SpineItem(path: 'OEBPS/ch1.xhtml', linear: true),
  SpineItem(path: 'OEBPS/ch2.xhtml', linear: true),
];

/// How many paragraphs each chapter has.
const recapTestParagraphCounts = {'s1': 4, 's2': 5};

/// The marker in a paragraph's text, such as "[s2 p3]".
String paragraphMark(String sectionId, int number) => '[$sectionId p$number]';

/// The Story Map fixture, with this book's chapter files, and with the events
/// of chapter 2 cited further into it:
///
/// - f014 "Elian hands Mara a letter." cites paragraph 3.
/// - f015 "Elian left home years ago." cites paragraphs 1 and 4.
///
/// [revision] is the map's version, which updating it raises.
StoryModel recapTestModel({int revision = 2}) {
  final json = storyModelFixtureJson();
  json['revision'] = {'number': revision};
  for (final section in json['processed_sections'] as List) {
    final map = section as Map<String, dynamic>;
    map['href'] = map['section_id'] == 's1'
        ? 'OEBPS/ch1.xhtml'
        : 'OEBPS/ch2.xhtml';
  }
  final events = (json['records'] as Map<String, dynamic>)['events'] as List;
  for (final event in events.cast<Map<String, dynamic>>()) {
    event['evidence'] = switch (event['id']) {
      'f014' => [_cite('s2', 3)],
      'f015' => [_cite('s2', 1), _cite('s2', 4)],
      _ => event['evidence'],
    };
  }
  return StoryModel.fromJson(json);
}

Map<String, dynamic> _cite(String section, int number) => {
  'section_id': section,
  'paragraph_id': 'p${number.toString().padLeft(4, '0')}',
  'quote': 'quote',
};

/// Every paragraph of [sectionId], each [length] characters or a little more.
List<StoryParagraph> recapTestParagraphs(String sectionId, {int length = 60}) {
  final count = recapTestParagraphCounts[sectionId]!;
  return [
    for (var number = 1; number <= count; number++)
      StoryParagraph(
        sectionId: sectionId,
        id: 'p${number.toString().padLeft(4, '0')}',
        number: number,
        text:
            '${paragraphMark(sectionId, number)} '
                    '${'Mara walks along the quay. ' * (length ~/ 27 + 1)}'
                .trim(),
      ),
  ];
}

/// What a reader at [progress] has read, cut the way `readStoryParagraphs`
/// cuts it: the finished sections whole, and the first paragraphs of the one
/// they are partway through.
StoryParagraphs readParagraphs(
  StoryModel model,
  StoryReadingProgress progress, {
  int length = 60,
}) {
  final sections = <String, List<StoryParagraph>>{};
  for (final section in model.sections.take(progress.shown)) {
    sections[section.id] = recapTestParagraphs(section.id, length: length);
  }
  if (progress.hiddenInNext != null && sections.isNotEmpty) {
    final partway = sections.keys.last;
    sections[partway] = sections[partway]!
        .take(progress.paragraphsReadInNext)
        .toList();
  }
  return StoryParagraphs(sections);
}

/// A Story Map backend with a [model] and a reader at [progress]. Only what a
/// recap uses is here.
class FakeStoryMap extends Fake implements StoryMapBackend {
  FakeStoryMap({this.model, this.progress = const StoryReadingProgress(0)});

  StoryModel? model;
  StoryReadingProgress progress;

  /// Thrown by [paragraphs], if set.
  Object? paragraphsError;

  /// Each progress [paragraphs] was asked for.
  final paragraphsAskedFor = <StoryReadingProgress>[];
  int progressLooks = 0;

  @override
  Future<StoryModel?> loadModel(Book book) async => model;

  @override
  Future<StoryReadingProgress> readingProgress(
    Book book,
    List<StorySection> sections,
  ) async {
    progressLooks++;
    return progress;
  }

  @override
  Future<StoryParagraphs> paragraphs(
    Book book,
    StoryReadingProgress progress,
  ) async {
    paragraphsAskedFor.add(progress);
    if (paragraphsError case final error?) throw error;
    return readParagraphs(model!, progress);
  }
}

/// A reader partway through chapter 2, having turned past its first
/// [paragraphs] paragraphs, with what they haven't reached of it hidden.
StoryReadingProgress partwayThroughChapter2(int paragraphs) =>
    StoryReadingProgress(
      1,
      hiddenInNext: {
        // Cited past paragraph 2: the letter, Captain Vell's name, and that
        // he is the stranger.
        if (paragraphs < 3) ...{'f014', 'f005', 'f018', 't003'},
      },
      paragraphsReadInNext: paragraphs,
    );
