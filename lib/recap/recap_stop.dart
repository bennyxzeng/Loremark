import 'dart:math';

import '../story_model/story_model.dart';
import '../story_model/story_snapshot.dart';

/// Where a reader stopped in a book, as the welcome back says it: the Story
/// Map section they are in or last finished.
class RecapStop {
  const RecapStop({required this.sectionTitle, required this.partway});

  /// The Story Map section, such as "Chapter 3: The Letter".
  final String sectionTitle;

  /// Whether the reader stopped partway through it, rather than at its end.
  final bool partway;
}

/// Where a reader at [progress] through [model] stopped, or null if they
/// haven't read anything the Story Map covers.
///
/// [progress] is the Story Map's own boundary
/// (`StoryMapBackend.readingProgress`), so the welcome back names the same
/// place the map shows up to.
RecapStop? recapStopAt(StoryModel model, StoryReadingProgress progress) {
  final shown = min(progress.shown, model.sections.length);
  if (shown <= 0) return null;
  return RecapStop(
    sectionTitle: model.sections[shown - 1].title,
    partway: progress.hiddenInNext != null,
  );
}
