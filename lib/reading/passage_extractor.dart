import 'dart:math';

import 'text_position.dart';

/// Returns book text for AI requests, never past the reader's boundary.
///
/// Only whole finished sections are returned. The section the reader is in
/// right now is left out until they finish it.
class PassageExtractor {
  final List<String> sections;

  /// Creates an extractor for a book's [sections] in spine order.
  PassageExtractor(this.sections);

  /// Number of whole finished sections for [boundary].
  ///
  /// This is also the exclusive end index of what [extract] can return.
  int finishedSectionCount(TextPosition boundary) {
    var count = boundary.sectionIndex;
    if (boundary.progression == 1.0) {
      count++;
    }
    return min(count, sections.length);
  }

  /// Finished sections from [fromSection] up to [boundary].
  ///
  /// The section at index `fromSection + i` is element `i` of the result.
  List<String> extract(TextPosition boundary, {int fromSection = 0}) {
    final end = finishedSectionCount(boundary);
    if (fromSection >= end) {
      return [];
    }
    return sections.sublist(fromSection, end);
  }
}
