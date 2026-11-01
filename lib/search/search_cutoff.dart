import '../reader/reader_position.dart';

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

/// The Read tab's search boundary: everything before the start of the
/// furthest page the reader reached.
///
/// [furthestPageText] is a text position (`EpubReaderSession.pageTextStarts`),
/// exact to the character. [current] and [furthest] are renderer positions,
/// which only count whole finished sections ([completedSectionCutoff]); they
/// cover pages whose start couldn't be located. The later of the two wins.
ReaderPosition pageCutoff({
  ReaderPosition? current,
  ReaderPosition? furthest,
  ReaderPosition? furthestPageText,
}) => searchCutoff(
  current: completedSectionCutoff(current: current, furthest: furthest),
  furthest: furthestPageText,
);
