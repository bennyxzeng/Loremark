import 'package:loremark/reader/epub_reader_service.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/search/passage_search.dart';

/// A [PassageSearch] for widget tests: answers from [onSearch] and records
/// every call, so tests can check which cutoff the UI passed.
class FakePassageSearch implements PassageSearch {
  FakePassageSearch({this.onSearch});

  /// What [search] returns for a query, or [SearchResults.empty].
  SearchResults Function(String query)? onSearch;

  /// Every [search] call, oldest first.
  final List<({String query, ReaderPosition cutoff})> searches = [];

  /// The cutoff of the latest [search].
  ReaderPosition? get lastCutoff => searches.lastOrNull?.cutoff;

  @override
  SearchResults search(
    String query, {
    required ReaderPosition cutoff,
    int limit = 20,
  }) {
    searches.add((query: query, cutoff: cutoff));
    return onSearch?.call(query) ?? SearchResults.empty;
  }

  @override
  List<Passage> retrievePassages(
    String query, {
    required ReaderPosition cutoff,
    int limit = 5,
  }) => const [];
}

/// A hit in [sectionIndex] whose snippet has [matches] marked, for tests.
SearchHit fakeHit({
  required int sectionIndex,
  int paragraphIndex = 0,
  String snippet = 'The grey cat sat on the wall',
  List<MatchSpan> matches = const [MatchSpan(4, 12)],
  double score = 1,
  double progression = 0.25,
  String highlight = 'grey cat',
}) => SearchHit(
  passage: Passage(
    sectionIndex: sectionIndex,
    paragraphIndex: paragraphIndex,
    text: snippet,
    startProgression: progression,
    endProgression: progression + 0.1,
  ),
  score: score,
  snippet: snippet,
  matches: matches,
  target: PassageTarget(
    sectionIndex: sectionIndex,
    progression: progression,
    highlight: highlight,
  ),
);
