import '../reader/epub_reader_service.dart';
import '../reader/reader_position.dart';

/// One paragraph of a book, as search sees it.
class Passage {
  const Passage({
    required this.sectionIndex,
    required this.paragraphIndex,
    required this.text,
    required this.startProgression,
    required this.endProgression,
  });

  /// The spine index, the same one [ReaderPosition.sectionIndex] uses.
  final int sectionIndex;

  /// Position of the paragraph within its section, from 0.
  final int paragraphIndex;
  final String text;

  /// Where the paragraph starts and ends within its section, from 0.0 to 1.0,
  /// measured in characters of the section's plain text.
  final double startProgression;
  final double endProgression;

  ReaderPosition get start => ReaderPosition(sectionIndex, startProgression);

  @override
  String toString() =>
      'Passage($sectionIndex:$paragraphIndex, '
      '$startProgression..$endProgression)';
}

/// A part of [SearchHit.snippet] that matched the query, for highlighting.
class MatchSpan {
  const MatchSpan(this.start, this.end);

  /// Character offsets into the snippet, end exclusive.
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is MatchSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'MatchSpan($start, $end)';
}

class SearchHit {
  const SearchHit({
    required this.passage,
    required this.score,
    required this.snippet,
    required this.matches,
    required this.target,
  });

  final Passage passage;
  final double score;

  /// A short window of [passage]'s text around the matches, with an ellipsis
  /// where it was cut.
  final String snippet;

  /// Where the query matched within [snippet], in order.
  final List<MatchSpan> matches;

  /// Where to jump to show the hit in the reader.
  final PassageTarget target;
}

class SearchResults {
  const SearchResults({required this.hits, required this.hiddenMatches});

  static const empty = SearchResults(hits: [], hiddenMatches: 0);

  /// Best first.
  final List<SearchHit> hits;

  /// Paragraphs past the cutoff that contain the query's terms. Only counted,
  /// never scored or shown, so a reader can learn that more exists without
  /// seeing it.
  final int hiddenMatches;
}

/// Full-text search over one book that never looks past a cutoff.
///
/// Everything a call returns, and every statistic used to rank it, comes
/// from paragraphs that end at or before the cutoff, as if the book ended
/// there. Non-linear spine items, such as footnotes, are never searched.
abstract interface class PassageSearch {
  /// Paragraphs matching [query] that the reader has fully passed at
  /// [cutoff], best first, with snippets for display.
  SearchResults search(
    String query, {
    required ReaderPosition cutoff,
    int limit,
  });

  /// The paragraphs most relevant to [query] before [cutoff], for building AI
  /// prompts. Unlike [search], it reports nothing about text past the cutoff.
  List<Passage> retrievePassages(
    String query, {
    required ReaderPosition cutoff,
    int limit,
  });
}
