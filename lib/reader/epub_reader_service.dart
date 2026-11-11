import 'package:flutter/widgets.dart';

import '../reading/text_position.dart';
import 'page_end.dart';
import 'page_start.dart';
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

  /// Where each page the reader lands on ends, as [pageTextEnds] reports it
  /// and with the text block it ends in. The last page of a spine item, and a
  /// page the renderer can't measure, report nothing.
  Stream<PageEnd> get pageEnds;

  /// Where each page the reader lands on starts. A page the renderer can't
  /// place reports nothing.
  Stream<PageStart> get pageStarts;

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

  /// Text the reader selected, each time they pick an action from the menu
  /// over it.
  Stream<PassageSelection> get selections;

  /// The id of each [NoteHighlight] the reader taps on the page.
  Stream<String> get highlightTaps;

  /// Draws [highlights] on the pages, replacing the ones drawn before. They
  /// are kept apart from the search highlight, so neither clears the other.
  Future<void> showNoteHighlights(List<NoteHighlight> highlights);

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
    this.also = const [],
  });

  final int sectionIndex;
  final double progression;

  /// The text to highlight, from a single line of one paragraph.
  final String highlight;

  /// Up to 32 characters just before and after [highlight], to tell repeated
  /// lines apart.
  final String before;
  final String after;

  /// More of the passage to highlight with this, such as the paragraphs after
  /// it when several are cited together. The jump goes to this one.
  final List<PassageTarget> also;

  /// This, with [more] to highlight too.
  PassageTarget alsoHighlighting(List<PassageTarget> more) => PassageTarget(
    sectionIndex: sectionIndex,
    progression: progression,
    highlight: highlight,
    before: before,
    after: after,
    also: [...also, ...more],
  );

  @override
  String toString() => 'PassageTarget($sectionIndex, $progression, $highlight)';
}

/// What the reader can do with text they selected, in menu order.
enum SelectionCommand { highlight, addNote, copy }

/// Text the reader selected, and the menu action they picked for it.
class PassageSelection {
  const PassageSelection({
    required this.command,
    required this.sectionIndex,
    required this.progression,
    required this.text,
    this.before = '',
    this.after = '',
  });

  final SelectionCommand command;
  final int sectionIndex;

  /// About where the selection is in its section, as the renderer reports
  /// it.
  final double progression;

  final String text;

  /// The text just before and after the selection, to find it again where
  /// the same words repeat.
  final String before;
  final String after;

  /// The selection as a passage to jump to and highlight later.
  PassageTarget get target => PassageTarget(
    sectionIndex: sectionIndex,
    progression: progression,
    highlight: text,
    before: before,
    after: after,
  );

  @override
  String toString() =>
      'PassageSelection($command, $sectionIndex, $progression, $text)';
}

/// A saved note or highlight to draw on the page.
class NoteHighlight {
  const NoteHighlight({
    required this.id,
    required this.target,
    required this.color,
  });

  /// Reported on [EpubReaderSession.highlightTaps] when it is tapped.
  final String id;

  final PassageTarget target;

  /// The fill, translucent so the text shows through.
  final Color color;
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
