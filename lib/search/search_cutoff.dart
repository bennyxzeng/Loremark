import '../reader/reader_position.dart';
import '../reading/text_position.dart';

/// How far search may look: everything the reader has finished up to the
/// returned position, and nothing past it.
///
/// This is the one place that decides the spoiler boundary for search. It is
/// the later of the reader's [current] and [furthest] positions, so turning
/// back to reread an early chapter never hides what they already read. With
/// neither it is the start of the book, which matches nothing.
// TODO(kevin): use Grisha's ReadingProgressTracker furthest position once #2
// merges.
ReaderPosition searchCutoff({
  ReaderPosition? current,
  ReaderPosition? furthest,
}) {
  if (current == null) return furthest ?? const ReaderPosition(0, 0);
  if (furthest == null) return current;
  return _isLater(furthest, current) ? furthest : current;
}

/// Whether [a] is strictly later in the book than [b], by section and then by
/// progression.
bool _isLater(ReaderPosition a, ReaderPosition b) =>
    a.sectionIndex != b.sectionIndex
    ? a.sectionIndex > b.sectionIndex
    : a.progression > b.progression;

/// Safe UI boundary for a renderer whose page progression is not a text offset.
/// Images, headings and layout can make page percentages differ from character
/// percentages, so a renderer position only unlocks completed spine sections.
/// [pageCutoff] adds the exact page starts the reader can locate.
ReaderPosition completedSectionCutoff({
  ReaderPosition? current,
  ReaderPosition? furthest,
}) {
  final reached = searchCutoff(current: current, furthest: furthest);
  if (reached.sectionIndex < 0) return const ReaderPosition(0, 0);
  if (reached.progression == 1) {
    return ReaderPosition(reached.sectionIndex, 1);
  }
  return reached.sectionIndex == 0
      ? const ReaderPosition(0, 0)
      : ReaderPosition(reached.sectionIndex - 1, 1);
}

/// The Read tab's search boundary: all text on the furthest page the reader
/// reached or before it, except a paragraph that carries on past that page.
///
/// [furthestPageText] is a text position (`EpubReaderSession.pageTextEnds`):
/// its progression is a share of the section's text in characters, and
/// everything before it was on the page or an earlier one. [current] and
/// [furthest] are renderer positions, measured in pages, which only count
/// whole finished sections ([completedSectionCutoff]); they cover pages the
/// renderer couldn't measure. The later of the two wins.
// TODO(kevin): search still takes a ReaderPosition. Moving PassageSearch to
// TextPosition would make this conversion the only one left to remove.
ReaderPosition pageCutoff({
  ReaderPosition? current,
  ReaderPosition? furthest,
  TextPosition? furthestPageText,
}) => searchCutoff(
  current: completedSectionCutoff(current: current, furthest: furthest),
  furthest: furthestPageText == null
      ? null
      : ReaderPosition(
          furthestPageText.sectionIndex,
          furthestPageText.progression,
        ),
);
