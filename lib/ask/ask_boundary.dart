import 'dart:math';

import '../reader/epub_sections.dart' show pageLines;
import '../reading/text_position.dart';
import '../story_model/story_model.dart';
import '../story_model/story_snapshot.dart';
import '../story_update/story_paragraphs.dart';

/// The text of the reader's recent pages: the page they are on, with a little
/// of what came before it.
class AskPage {
  const AskPage(this.text, this.end);

  /// Ends exactly where the page does: see `textBeforePageEnd`.
  final String text;

  /// Where the page ends.
  final TextPosition end;

  /// [text] line by line, as the model sees it numbered from 1 and cites it:
  /// see `pageLines`.
  List<String> get lines => [for (final line in pageLines(text)) line.text];
}

/// How far Ask may go, as the device measures it: the whole page the reader is
/// on, where the Story Map stops at its start.
class AskReach {
  const AskReach({
    required this.progress,
    required this.limit,
    this.page,
    this.pastMap = false,
  });

  /// Nothing has been read.
  static const none = AskReach(
    progress: StoryReadingProgress(0),
    limit: TextPosition(0, 0),
  );

  /// How much of the Story Map is behind the reader, to the end of their page.
  final StoryReadingProgress progress;

  /// Where the page ends, or where it starts if its end couldn't be measured.
  /// Kept with each question, as where the reader was when they asked it.
  final TextPosition limit;

  /// The text of the page, or null if its end couldn't be measured.
  final AskPage? page;

  /// Whether the reader's page is in a part of the book the Story Map has no
  /// section for, after one it has: past its end, or in chapters it skipped.
  /// Something not found may then just not be in the map yet.
  final bool pastMap;
}

/// Everything one answer may draw on, taken once when the question is asked.
///
/// Nothing past the reader is in here, so nothing built from it can reach
/// further: [snapshot] knows only what [progress] lets it, and [paragraphs]
/// holds only the paragraphs read.
class AskBoundary {
  AskBoundary({required this.reach, this.model, StoryParagraphs? paragraphs})
    : paragraphs = paragraphs ?? StoryParagraphs(const {});

  final AskReach reach;

  /// The book's Story Map, or null if it has none.
  final StoryModel? model;

  /// The paragraphs of the Story Map that are behind the reader.
  final StoryParagraphs paragraphs;

  StoryReadingProgress get progress => reach.progress;
  AskPage? get page => reach.page;

  /// How many of the map's sections have something to show.
  int get _shown => min(progress.shown, model?.sections.length ?? 0);

  /// What the reader knows from the map, or null if nothing yet.
  late final StorySnapshot? snapshot = () {
    final model = this.model;
    if (model == null || _shown == 0) return null;
    return StorySnapshot(
      model,
      model.sections[_shown - 1],
      hidden: progress.hiddenInNext ?? const {},
    );
  }();

  /// The map's sections the reader has reached, in reading order.
  List<StorySection> get sections =>
      model?.sections.take(_shown).toList() ?? const [];

  /// Whether the reader is partway through the last of [sections].
  bool get partway => progress.hiddenInNext != null && sections.isNotEmpty;

  /// Whether there is anything at all to answer from.
  bool get isEmpty => snapshot == null && page == null;
}
