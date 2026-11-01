import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../reader/epub_reader_service.dart';
import '../reader/reader_position.dart';
import '../theme/loremark_theme.dart';
import 'passage_search.dart';

/// How long typing must pause before a search runs, so each keystroke doesn't
/// search the whole book.
const searchDebounce = Duration(milliseconds: 150);

/// How many hits one search asks for.
const _hitLimit = 40;

/// Lets code outside the Read tab open its search sheet, such as a future
/// "Search this chapter" action.
///
/// Give one to `ReadScreen.searchController`; [open] then shows the sheet on
/// that screen. It does nothing while no screen is attached or search is
/// unavailable.
class SearchSheetController {
  Future<void> Function(String initialQuery)? _opener;

  /// Called by the screen that owns the sheet. [detach] undoes it.
  void attach(Future<void> Function(String initialQuery) opener) =>
      _opener = opener;

  void detach(Future<void> Function(String initialQuery) opener) {
    if (_opener == opener) _opener = null;
  }

  /// Opens the sheet with [initialQuery] already typed and searched.
  Future<void> open({String initialQuery = ''}) async =>
      _opener?.call(initialQuery);
}

/// Shows the search sheet and returns the hit the reader taps, or null if they
/// dismiss it.
///
/// [openSearch] is called when the sheet opens and again on "Try again", so
/// the caller can cache the opened search. [cutoff] is read on every search,
/// and a change re-runs the current query, so results never lag the reader's
/// position.
Future<SearchHit?> showSearchSheet(
  BuildContext context, {
  required Future<PassageSearch> Function() openSearch,
  required ValueListenable<ReaderPosition> cutoff,
  required List<TocEntry> entries,
  String initialQuery = '',
}) {
  return showModalBottomSheet<SearchHit>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final size = MediaQuery.sizeOf(context);
      final keyboard = MediaQuery.viewInsetsOf(context).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SizedBox(
          // A fixed height keeps the sheet from jumping as results come and
          // go. It shrinks to leave room for the keyboard.
          height: (size.height * 0.85 - keyboard).clamp(240.0, size.height),
          child: SearchSheet(
            openSearch: openSearch,
            cutoff: cutoff,
            entries: entries,
            initialQuery: initialQuery,
          ),
        ),
      );
    },
  );
}

/// The search field, the cutoff note, and the results grouped by chapter.
///
/// Pops with the tapped [SearchHit].
class SearchSheet extends StatefulWidget {
  const SearchSheet({
    super.key,
    required this.openSearch,
    required this.cutoff,
    required this.entries,
    this.initialQuery = '',
  });

  final Future<PassageSearch> Function() openSearch;
  final ValueListenable<ReaderPosition> cutoff;

  /// Table of contents entries inside the spine, in reading order, to name
  /// chapters.
  final List<TocEntry> entries;
  final String initialQuery;

  @override
  State<SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<SearchSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );
  Timer? _debounce;
  PassageSearch? _search;
  bool _failed = false;

  /// What the shown results are for, or null before any search ran.
  String? _searchedQuery;
  SearchResults _results = SearchResults.empty;
  bool _searchFailed = false;

  @override
  void initState() {
    super.initState();
    widget.cutoff.addListener(_onCutoffChanged);
    unawaited(_open());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.cutoff.removeListener(_onCutoffChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() => _failed = false);
    try {
      final search = await widget.openSearch();
      if (!mounted) return;
      setState(() => _search = search);
      _runSearch();
    } on Object catch (error) {
      debugPrint('Could not open search: $error');
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(searchDebounce, _runSearch);
  }

  void _onCutoffChanged() {
    if (_search != null) _runSearch();
  }

  /// Searches for the field's text with the cutoff as it is right now.
  void _runSearch() {
    _debounce?.cancel();
    final search = _search;
    if (search == null) return;
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchedQuery = null;
        _results = SearchResults.empty;
        _searchFailed = false;
      });
      return;
    }
    SearchResults results;
    var failed = false;
    try {
      results = search.search(
        query,
        cutoff: widget.cutoff.value,
        limit: _hitLimit,
      );
    } on Object catch (error) {
      debugPrint('Search failed: $error');
      results = SearchResults.empty;
      failed = true;
    }
    setState(() {
      _searchedQuery = query;
      _results = results;
      _searchFailed = failed;
    });
  }

  /// The last table of contents entry that starts at or before [section].
  TocEntry? _entryFor(int section) {
    TocEntry? current;
    for (final entry in widget.entries) {
      if (entry.sectionIndex! <= section) current = entry;
    }
    return current;
  }

  String _chapterTitle(int section) {
    final title = _entryFor(section)?.title.trim() ?? '';
    return title.isEmpty ? 'Section ${section + 1}' : title;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: Text('SEARCH', style: kicker()),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: TextField(
            key: const ValueKey('search-field'),
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _onQueryChanged,
            onSubmitted: (_) => _runSearch(),
            style: serif(16),
            decoration: InputDecoration(
              hintText: 'Search the book',
              helperText: 'Use "quotes" to find an exact phrase',
              helperStyle: const TextStyle(
                fontSize: 11,
                color: LoremarkColors.muted,
              ),
              prefixIcon: const Icon(
                Icons.search,
                size: 20,
                color: LoremarkColors.muted,
              ),
              isDense: true,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
          child: ValueListenableBuilder<ReaderPosition>(
            valueListenable: widget.cutoff,
            builder: (context, cutoff, _) => Text(
              _cutoffNote(cutoff),
              key: const ValueKey('search-cutoff-note'),
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: LoremarkColors.muted,
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildBody()),
      ],
    );
  }

  String _cutoffNote(ReaderPosition cutoff) {
    final entry = _entryFor(cutoff.sectionIndex);
    final title = entry?.title.trim() ?? '';
    return title.isEmpty
        ? "Searching what you've read"
        : "Searching what you've read, up to $title";
  }

  Widget _buildBody() {
    if (_failed) {
      return _Notice(
        key: const ValueKey('search-error'),
        message: "Search isn't available for this book right now.",
        action: TextButton(
          onPressed: () => unawaited(_open()),
          child: const Text('Try again'),
        ),
      );
    }
    if (_search == null) {
      return const _Notice(message: 'Getting the book ready…');
    }
    if (_searchFailed) {
      return const _Notice(
        key: ValueKey('search-error'),
        message: 'Something went wrong with that search.',
      );
    }
    final query = _searchedQuery;
    if (query == null) {
      return const _Notice(
        message: 'Find a name, a place, or a line from what you have read.',
      );
    }
    final hits = _results.hits;
    final hidden = _results.hiddenMatches;
    if (hits.isEmpty) {
      return _Notice(
        key: const ValueKey('search-empty'),
        message: "No matches in what you've read so far",
        footer: hidden > 0 ? _HiddenMatches(count: hidden) : null,
      );
    }
    final groups = _groupByChapter(hits);
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 4),
            child: Text(
              group.title.toUpperCase(),
              key: ValueKey('search-chapter-${group.title}'),
              style: kicker(color: LoremarkColors.muted, size: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          for (final hit in group.hits) _HitTile(hit: hit),
        ],
        if (hidden > 0) _HiddenMatches(count: hidden),
      ],
    );
  }

  /// Chapters in book order, each with its hits best first.
  List<_ChapterGroup> _groupByChapter(List<SearchHit> hits) {
    final groups = <String, _ChapterGroup>{};
    for (final hit in hits) {
      final section = hit.passage.sectionIndex;
      final entry = _entryFor(section);
      final title = _chapterTitle(section);
      // Sections without a chapter are told apart by number; chapters by
      // entry, so two entries with one title stay separate.
      final key = entry == null ? 'section $section' : 'entry ${entry.href}';
      (groups[key] ??= _ChapterGroup(title, section)).hits.add(hit);
      if (section < groups[key]!.firstSection) {
        groups[key]!.firstSection = section;
      }
    }
    return groups.values.toList()
      ..sort((a, b) => a.firstSection.compareTo(b.firstSection));
  }
}

class _ChapterGroup {
  _ChapterGroup(this.title, this.firstSection);

  final String title;
  int firstSection;
  final List<SearchHit> hits = [];
}

/// A centered message, such as an empty state, with an optional action.
class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.message, this.action, this.footer});

  final String message;
  final Widget? action;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 16),
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            height: 1.6,
            color: LoremarkColors.muted,
          ),
        ),
        if (action != null) Center(child: action),
        ?footer,
      ],
    );
  }
}

/// How many matches wait past the reader's position, with no detail.
class _HiddenMatches extends StatelessWidget {
  const _HiddenMatches({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final noun = count == 1 ? 'match' : 'matches';
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
      child: Text(
        "$count more $noun in chapters you haven't reached yet",
        key: const ValueKey('search-hidden'),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: LoremarkColors.muted),
      ),
    );
  }
}

/// One result: its snippet with the matched words highlighted.
class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit});

  final SearchHit hit;

  @override
  Widget build(BuildContext context) {
    final style = serif(15, color: LoremarkColors.ink, height: 1.45);
    return InkWell(
      key: ValueKey(
        'search-hit-${hit.passage.sectionIndex}-${hit.passage.paragraphIndex}',
      ),
      onTap: () => Navigator.pop(context, hit),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        child: Text.rich(
          highlightedSnippet(hit.snippet, hit.matches, style),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// [snippet] as a [TextSpan] with each of [matches] on a highlight
/// background.
///
/// Spans are clamped to the snippet and overlapping ones merged, so a bad
/// offset from the engine can't throw while drawing.
@visibleForTesting
TextSpan highlightedSnippet(
  String snippet,
  List<MatchSpan> matches,
  TextStyle style,
) {
  final ordered = [...matches]..sort((a, b) => a.start.compareTo(b.start));
  final children = <TextSpan>[];
  var cursor = 0;
  for (final match in ordered) {
    final start = match.start.clamp(cursor, snippet.length);
    final end = match.end.clamp(start, snippet.length);
    if (end == start) continue;
    if (start > cursor) {
      children.add(TextSpan(text: snippet.substring(cursor, start)));
    }
    children.add(
      TextSpan(
        text: snippet.substring(start, end),
        style: TextStyle(
          backgroundColor: LoremarkColors.gold.withValues(alpha: 0.3),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    cursor = end;
  }
  if (cursor < snippet.length) {
    children.add(TextSpan(text: snippet.substring(cursor)));
  }
  return TextSpan(style: style, children: children);
}
