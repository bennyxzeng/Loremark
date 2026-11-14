import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/story_map/story_map_backend.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/story_model/story_snapshot.dart';

import '../story_model/story_model_fixture.dart';

// A small book for the welcome back's tests: the Story Map fixture's two
// chapters, "Chapter 1: Arrival" and "Chapter 2: The Letter".

final recapTestBook = Book(
  id: 'book-1',
  title: 'The Glass Harbor',
  author: null,
  epubPath: '/nowhere.epub',
  coverPath: null,
  importedAt: DateTime.utc(2026),
);

StoryModel recapTestModel() => storyModelFixture();

/// A Story Map backend with a [model] and a reader at [progress]. Only what
/// the welcome back uses is here.
class FakeStoryMap extends Fake implements StoryMapBackend {
  FakeStoryMap({this.model, this.progress = const StoryReadingProgress(0)});

  StoryModel? model;
  StoryReadingProgress progress;

  /// Thrown by [loadModel], if set.
  Object? error;

  int progressLooks = 0;

  @override
  Future<StoryModel?> loadModel(Book book) async {
    if (error case final error?) throw error;
    return model;
  }

  @override
  Future<StoryReadingProgress> readingProgress(
    Book book,
    List<StorySection> sections,
  ) async {
    progressLooks++;
    return progress;
  }
}

/// A reader partway through chapter 2, having turned past its first
/// [paragraphs] paragraphs.
StoryReadingProgress partwayThroughChapter2(int paragraphs) =>
    StoryReadingProgress(
      1,
      hiddenInNext: const {'f014'},
      paragraphsReadInNext: paragraphs,
    );
