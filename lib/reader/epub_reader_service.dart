import 'package:flutter/widgets.dart';

import '../reading/text_position.dart';
import 'reader_position.dart';

/// Opens EPUBs for reading.
///
/// The Read tab only talks to this interface, so the rendering package stays
/// in one adapter and widget tests can use a fake instead of native code.
abstract interface class EpubReaderService {
  /// Opens the EPUB at [epubPath].
  ///
  /// Throws an [EpubOpenException] if the file is missing or can't be read.
  Future<EpubReaderSession> open(String epubPath);
}

/// One open book.
abstract interface class EpubReaderSession {
  /// The book's table of contents, flattened in reading order. Nested entries
  /// keep their [TocEntry.depth].
  List<TocEntry> get tableOfContents;

  /// Number of items in the EPUB spine, which is one more than the largest
  /// [ReaderPosition.sectionIndex].
  int get sectionCount;

  /// The chapter the reader is in each time it changes, as one of the
  /// entries of [tableOfContents]. Pages the renderer can't place in a
  /// chapter report nothing.
  Stream<TocEntry> get chapterChanges;

  /// Every position the reader moves to: page turns, chapter jumps, and the
  /// initial position once the view has opened. When the reader turns from
  /// the end of a section into the next one, the old section is reported at
  /// exactly 1.0 first.
  Stream<ReaderPosition> get positions;

  /// How far the reader has seen, in the book's text, for each page they land
  /// on: everything before the reported point is on this page or an earlier
  /// one. Unlike [positions], the progression is a fraction of the section's
  /// plain text (`readSectionTexts`), counted in characters, not of its
  /// pages. A page the renderer can't measure reports nothing.
  Stream<TextPosition> get pageTextEnds;

  /// The rendered book, starting at [initialPosition] or the beginning.
  Widget buildView({ReaderPosition? initialPosition});

  Future<void> goTo(TocEntry entry);

  Future<void> goToPosition(ReaderPosition position);

  /// Jumps to [target] and highlights it, replacing any earlier highlight.
  ///
  /// Does nothing if the section can't be shown, such as a non-linear spine
  /// item. The highlight stays through page turns until [clearPassageHighlight]
  /// or the next [showPassage].
  Future<void> showPassage(PassageTarget target);

  /// Removes the highlight [showPassage] drew, if any.
  Future<void> clearPassageHighlight();

  /// Turns to the next page.
  Future<void> goForward();

  /// Turns to the previous page.
  Future<void> goBackward();

  /// Releases the book. The session can't be used afterwards.
  Future<void> close();
}

/// A chapter in the table of contents.
class TocEntry {
  const TocEntry({
    required this.title,
    required this.href,
    required this.sectionIndex,
    this.depth = 0,
    this.position,
  });

  final String title;

  /// Where the entry points, as written in the EPUB, possibly with a
  /// `#fragment`.
  final String href;

  /// The spine item the entry points to, or null if it points outside the
  /// spine.
  final int? sectionIndex;

  /// Nesting level: 0 for a top-level chapter.
  final int depth;

  /// Where the entry is when the book has no table of contents of its own and
  /// the entry is one of the sections Loremark cut it into (see
  /// `sectionsWithoutToc`), otherwise null. The share is of the item's words,
  /// not its pages.
  final ReaderPosition? position;

  /// Whether this is a section Loremark made, not a chapter from the book.
  bool get isSynthetic => position != null;

  @override
  String toString() => 'TocEntry($title, $href, $sectionIndex, depth: $depth)';
}

/// A passage to jump to and highlight, such as a search hit.
///
/// The renderer finds the passage by its text, which survives differences
/// between our plain text and the rendered page. [progression] is only the
/// fallback when the text can't be found.
class PassageTarget {
  const PassageTarget({
    required this.sectionIndex,
    required this.progression,
    required this.highlight,
    this.before = '',
    this.after = '',
  });

  final int sectionIndex;
  final double progression;

  /// The text to highlight, from a single line of one paragraph.
  final String highlight;

  /// Up to 32 characters just before and after [highlight], to tell repeated
  /// lines apart.
  final String before;
  final String after;

  @override
  String toString() => 'PassageTarget($sectionIndex, $progression, $highlight)';
}

enum EpubOpenFailure {
  /// The app's copy of the EPUB is gone.
  missingFile,

  /// The file exists but isn't an EPUB the reader can open.
  unreadable,
}

/// Why an EPUB couldn't be opened, so the Read tab can say so plainly.
class EpubOpenException implements Exception {
  const EpubOpenException(this.failure, [this.cause]);

  final EpubOpenFailure failure;

  /// The underlying error, for logs.
  final Object? cause;

  @override
  String toString() => 'EpubOpenException($failure, $cause)';
}
