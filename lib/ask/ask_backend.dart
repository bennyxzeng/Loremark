import 'dart:math';

import '../library/book.dart';
import '../reader/epub_reader_service.dart';
import '../search/snippet.dart';
import '../story_model/story_model.dart';
import '../story_model/story_snapshot.dart';
import '../story_update/story_paragraphs.dart';
import 'ask_boundary.dart';

/// What Ask needs from the device, so tests can stand in for it.
abstract interface class AskBackend {
  /// The book's Story Map, or null if it has none.
  Future<StoryModel?> loadModel(Book book);

  /// How far Ask may go in [book]: the whole page the reader is on.
  /// [sections] are the map's, or none if it has no map.
  Future<AskReach> askReach(Book book, List<StorySection> sections);

  /// The paragraphs of [book]'s Story Map that a reader at [progress] has read.
  /// Throws a `StoryStoreError` or a `StoryEpubError` if a section's text
  /// can't be read.
  Future<StoryParagraphs> paragraphs(Book book, StoryReadingProgress progress);

  /// Where [paragraph] of [section] is in the reader, or null if it can't be
  /// placed.
  Future<PassageTarget?> passageTarget(
    Book book,
    StorySection section,
    StoryParagraph paragraph,
  );
}

/// Everything a question about [book] may draw on, as it is now.
///
/// Throws if the Story Map's text can't be read, rather than answering from
/// part of it.
Future<AskBoundary> openAskBoundary(AskBackend backend, Book book) async {
  final model = await backend.loadModel(book);
  final reach = await backend.askReach(book, model?.sections ?? const []);
  final paragraphs = model == null || reach.progress.shown == 0
      ? null
      : await backend.paragraphs(book, reach.progress);
  return AskBoundary(reach: reach, model: model, paragraphs: paragraphs);
}

/// Where [paragraph] is in [sectionText], the plain text of the spine item at
/// [sectionIndex], for the renderer to find and highlight.
///
/// The paragraph is found by its first words. If they aren't there, as when
/// the text was cut differently, the paragraph alone is sent and the renderer
/// looks for it near the item's start.
PassageTarget storyPassageTarget(
  int sectionIndex,
  String sectionText,
  String paragraph,
) {
  final text = paragraph.trim();
  final probe = text.substring(0, min(text.length, minQuoteLength));
  final at = probe.isEmpty ? -1 : sectionText.indexOf(probe);
  if (at == -1) {
    final alone = buildPassageTarget(
      sectionIndex: sectionIndex,
      sectionText: text,
      paragraphStart: 0,
      paragraphEnd: text.length,
      matchStart: 0,
      matchEnd: min(text.length, maxQuoteLength),
      visibleEnd: text.length,
    );
    return PassageTarget(
      sectionIndex: sectionIndex,
      progression: 0,
      highlight: alone.highlight,
    );
  }
  final end = min(sectionText.length, at + text.length);
  return buildPassageTarget(
    sectionIndex: sectionIndex,
    sectionText: sectionText,
    paragraphStart: at,
    paragraphEnd: end,
    matchStart: at,
    matchEnd: min(end, at + maxQuoteLength),
    visibleEnd: end,
  );
}
