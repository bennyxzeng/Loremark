import 'dart:async';

import 'package:flutter/material.dart';

import '../library/book.dart';
import '../library/library_screen.dart';
import '../reader/epub_reader_service.dart';
import '../reader/reader_position.dart';
import '../reader/reading_position_store.dart';
import '../reading/text_position.dart';
import '../search/passage_search.dart';
import '../search/search_cutoff.dart';
import '../search/search_sheet.dart';
import '../theme/loremark_theme.dart';
import 'table_of_contents_sheet.dart';

/// The Read tab: the book's text, with its table of contents and page
/// controls around it.
///
/// A broken position store never keeps the book closed. The reader just
/// starts at the beginning and stops saving.
class ReadScreen extends StatefulWidget {
  const ReadScreen({
    super.key,
    required this.book,
    required this.readerService,
    this.openPositionStore = ReadingPositionStore.open,
    this.onPositionChanged,
    this.openSearch,
    this.furthestPosition,
    this.searchController,
  });

  final Book book;
  final EpubReaderService readerService;

  /// Opens where [book]'s position is saved and resumed from. If it fails,
  /// the book still opens, at the beginning.
  final Future<ReadingPositionStore> Function() openPositionStore;

  /// Called with every position the reader moves to, for reading progress.
  final ValueChanged<ReaderPosition>? onPositionChanged;

  /// Opens the search for [book], or null if the book can't be searched, which
  /// disables the Search button.
  ///
  /// Called lazily the first time the reader searches and cached for the
  /// book, since building the index can take a while. If it fails, the sheet
  /// says so and offers to try again; reading is unaffected.
  final Future<PassageSearch> Function()? openSearch;

  /// The furthest position the reader has reached, which bounds what search
  /// may show. When null or when it returns null, the current position is
  /// used.
  final ReaderPosition? Function()? furthestPosition;

  /// Lets other code open the search sheet, such as a "Search this chapter"
  /// action.
  final SearchSheetController? searchController;

  @override
  State<ReadScreen> createState() => _ReadScreenState();
}

class _ReadScreenState extends State<ReadScreen> {
  EpubReaderSession? _session;

  /// Built once per session: rebuilding it on a page turn would recreate the
  /// platform view.
  Widget? _view;
  StreamSubscription<ReaderPosition>? _positionSubscription;
  StreamSubscription<TextPosition>? _pageTextSubscription;
  StreamSubscription<TocEntry>? _chapterSubscription;

  /// The chapter the renderer says the reader is in, if it could tell.
  TocEntry? _chapter;

  /// How long after the last move a jump is taken to have landed.
  static const _pickSettleDelay = Duration(milliseconds: 700);

  /// The entry the reader chose from Contents. The bar shows it until they
  /// move off the page the jump landed on: the renderer names a page's
  /// chapter by its first line, which can still be the end of the one before.
  TocEntry? _picked;

  /// Where the jump landed once it settled.
  ReaderPosition? _pickedAt;
  bool _pickSettled = false;

  /// Whether the jump itself is still being made. A jump into another file
  /// is two steps and can take a while, so moves during it are the jump.
  bool _jumping = false;
  Timer? _pickTimer;
  ReadingPositionStore? _store;
  ReaderPosition? _position;

  /// How far the text of the furthest page reached in this session goes, if
  /// the reader could measure it.
  TextPosition? _furthestPageText;
  Object? _error;

  /// The opened search of the current book, kept so the index is built once.
  Future<PassageSearch>? _searchFuture;

  /// What search may look at. The sheet watches it so open results follow the
  /// reader.
  final ValueNotifier<ReaderPosition> _cutoff = ValueNotifier(searchCutoff());

  /// Whether a search highlight is on the page, so it is cleared only when
  /// there is one.
  bool _highlightShown = false;

  /// Identifies the latest open, so a slow earlier one can tell it was
  /// replaced or the screen was disposed.
  int _generation = 0;

  /// How far from the saved progression still counts as having arrived there:
  /// about one page in a long chapter. A reopened page can land a fraction of
  /// a page off (seen on a device as 0.5298 -> 0.5238).
  static const _arrivalTolerance = 0.02;

  /// The saved position the reader was asked to open at, while it has not
  /// shown it yet. Null when nothing was saved or the wait is over.
  ///
  /// Readium can report a first position that is not the saved one, because
  /// it opens at the start and only then jumps. Saving that would overwrite
  /// the good saved position, so saving waits until the reader gets here.
  ReaderPosition? _restoring;

  /// Whether the reader was already sent back to [_restoring] once.
  bool _restoreRetried = false;

  /// How long after the jump back the reader's positions are still the
  /// opening. Readium reports the opening and the jump back as a burst of
  /// positions within about a second; positions in that burst must not count
  /// as the reader moving on.
  static const _restoreSettleTime = Duration(seconds: 2);
  Timer? _restoreSettle;

  /// Whether [_restoreSettleTime] has passed since the jump back.
  bool _restoreSettled = false;

  @override
  void initState() {
    super.initState();
    widget.searchController?.attach(_openSearchSheet);
    unawaited(_open());
  }

  @override
  void didUpdateWidget(ReadScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchController != widget.searchController) {
      oldWidget.searchController?.detach(_openSearchSheet);
      widget.searchController?.attach(_openSearchSheet);
    }
    if (oldWidget.book.id != widget.book.id) {
      unawaited(_open());
    }
  }

  @override
  void dispose() {
    _generation++;
    _pickTimer?.cancel();
    _stopRestoring();
    widget.searchController?.detach(_openSearchSheet);
    _releaseSession();
    _cutoff.dispose();
    super.dispose();
  }

  /// Opens the book and its saved position together.
  ///
  /// Its synchronous part resets the state, so call it inside `setState`
  /// unless a build is about to follow anyway.
  Future<void> _open() async {
    final generation = ++_generation;
    _releaseSession();
    _store = null;
    _position = null;
    _furthestPageText = null;
    _chapter = null;
    _clearPick();
    _stopRestoring();
    _error = null;
    _searchFuture = null;
    _cutoff.value = searchCutoff();

    final book = widget.book;
    final sessionFuture = _openSession(book);
    final savedFuture = _loadSavedPosition(book);

    final EpubReaderSession session;
    try {
      session = await sessionFuture;
    } on Object catch (error) {
      debugPrint('Could not open ${book.title}: $error');
      if (mounted && generation == _generation) {
        setState(() => _error = error);
      }
      return;
    }
    // Never throws, so skipping it above can't leave an unhandled error.
    final (:store, :position) = await savedFuture;
    if (!mounted || generation != _generation) {
      unawaited(_close(session));
      return;
    }

    setState(() {
      _session = session;
      _store = store;
      _position = position;
      _restoring = position;
      _positionSubscription = session.positions.listen(_onPosition);
      _pageTextSubscription = session.pageTextEnds.listen(_onPageTextEnd);
      _chapterSubscription = session.chapterChanges.listen(
        (chapter) => setState(() => _chapter = chapter),
      );
      _view = session.buildView(initialPosition: position);
    });
  }

  /// Wraps [EpubReaderService.open] so a synchronous throw is also a failed
  /// future.
  Future<EpubReaderSession> _openSession(Book book) async =>
      widget.readerService.open(book.epubPath);

  Future<({ReadingPositionStore? store, ReaderPosition? position})>
  _loadSavedPosition(Book book) async {
    ReadingPositionStore? store;
    try {
      store = await widget.openPositionStore();
      return (store: store, position: await store.load(book.id));
    } on Object catch (error) {
      debugPrint('Could not read the saved position of ${book.title}: $error');
      // A store that opened but couldn't load is still good for saving.
      return (store: store, position: null);
    }
  }

  void _releaseSession() {
    unawaited(_positionSubscription?.cancel());
    _positionSubscription = null;
    unawaited(_pageTextSubscription?.cancel());
    _pageTextSubscription = null;
    unawaited(_chapterSubscription?.cancel());
    _chapterSubscription = null;
    final session = _session;
    _session = null;
    _view = null;
    if (session != null) {
      if (_highlightShown) unawaited(_clearHighlight(session));
      unawaited(_close(session));
    }
  }

  /// Takes the search highlight off the page. Best effort: the book is about
  /// to close anyway.
  Future<void> _clearHighlight(EpubReaderSession session) async {
    _highlightShown = false;
    try {
      await session.clearPassageHighlight();
    } on Object catch (error) {
      debugPrint('Could not clear the search highlight: $error');
    }
  }

  Future<void> _close(EpubReaderSession session) async {
    try {
      await session.close();
    } on Object catch (error) {
      debugPrint('Could not close the book: $error');
    }
  }

  void _onPosition(ReaderPosition position) {
    setState(() {
      _position = position;
      _trackPick(position);
    });
    _updateCutoff();
    final store = _store;
    if (store != null && _shouldSave(position)) {
      unawaited(_save(store, position));
    }
    widget.onPositionChanged?.call(position);
  }

  /// Ends the wait for the saved position, whichever way it ends.
  void _stopRestoring() {
    _restoring = null;
    _restoreRetried = false;
    _restoreSettled = false;
    _restoreSettle?.cancel();
    _restoreSettle = null;
  }

  /// Whether [position] may overwrite the saved one.
  ///
  /// While restoring, only a position at the saved one may. If the reader
  /// opened elsewhere it is sent back once, and everything it reports for the
  /// next [_restoreSettleTime] is still the opening, so none of it is saved.
  /// After that, a position that is still elsewhere means the reader really
  /// is somewhere else now, so restoring is given up and saving is never
  /// blocked for good.
  bool _shouldSave(ReaderPosition position) {
    final saved = _restoring;
    if (saved == null) return true;
    if (position.sectionIndex == saved.sectionIndex &&
        (position.progression - saved.progression).abs() <= _arrivalTolerance) {
      _stopRestoring();
      return true;
    }
    if (!_restoreRetried) {
      _restoreRetried = true;
      _restoreSettle = Timer(_restoreSettleTime, () => _restoreSettled = true);
      debugPrint(
        'The reader opened at ${position.sectionIndex}/${position.progression} '
        'instead of the saved ${saved.sectionIndex}/${saved.progression}; '
        'jumping back.',
      );
      final session = _session;
      if (session != null) unawaited(_restore(session, saved));
      return false;
    }
    if (!_restoreSettled) return false;
    debugPrint(
      'The reader is still not at the saved position; giving up restoring it.',
    );
    _stopRestoring();
    return true;
  }

  /// Sends the reader back to the saved position. Best effort: if it fails,
  /// the reader just stays where it is.
  Future<void> _restore(EpubReaderSession session, ReaderPosition saved) async {
    try {
      await session.goToPosition(saved);
    } on Object catch (error) {
      debugPrint('Could not return to the saved position: $error');
    }
  }

  void _onPageTextEnd(TextPosition end) {
    final furthest = _furthestPageText;
    if (furthest == null || end > furthest) _furthestPageText = end;
    _updateCutoff();
  }

  Future<void> _save(
    ReadingPositionStore store,
    ReaderPosition position,
  ) async {
    try {
      await store.save(widget.book.id, position);
    } on Object catch (error) {
      debugPrint('Could not save the reading position: $error');
    }
  }

  /// Entries that point outside the spine can't be jumped to.
  List<TocEntry> _usableEntries(EpubReaderSession session) => [
    for (final entry in session.tableOfContents)
      if (entry.sectionIndex != null) entry,
  ];

  /// The chapter the reader is in.
  ///
  /// The one they just chose from Contents, until they move on. Then the
  /// renderer's own answer when it has one, since several chapters can
  /// share one file. Otherwise, for a book cut into sections by us, the last
  /// section that starts at or before the reader, and for any other book the
  /// last chapter that starts in or before the reader's file.
  TocEntry? _currentEntry(List<TocEntry> entries) {
    final picked = _picked;
    if (picked != null && entries.any((entry) => identical(entry, picked))) {
      return picked;
    }
    final chapter = _chapter;
    if (chapter != null && entries.any((entry) => identical(entry, chapter))) {
      return chapter;
    }
    final position = _position;
    if (position == null) {
      return null;
    }
    TocEntry? current;
    for (final entry in entries) {
      final start = entry.position;
      final started = start == null
          ? entry.sectionIndex! <= position.sectionIndex
          : start.sectionIndex < position.sectionIndex ||
                (start.sectionIndex == position.sectionIndex &&
                    start.progression <= position.progression);
      if (started) {
        current = entry;
      }
    }
    return current;
  }

  void _clearPick() {
    _picked = null;
    _pickedAt = null;
    _pickSettled = false;
    _jumping = false;
    _pickTimer?.cancel();
    _pickTimer = null;
  }

  /// Starts waiting for the jump to settle, or waits again after a move.
  void _waitForPick() {
    _pickTimer?.cancel();
    _pickTimer = Timer(_pickSettleDelay, () => _pickSettled = true);
  }

  /// Keeps the chosen entry until the reader moves off the page it landed on.
  void _trackPick(ReaderPosition position) {
    if (_picked == null) return;
    if (!_pickSettled) {
      _pickedAt = position;
      if (!_jumping) _waitForPick();
    } else if (position != _pickedAt) {
      _clearPick();
    }
  }

  Future<void> _openContents(EpubReaderSession session) async {
    final entries = _usableEntries(session);
    final chosen = await showTableOfContentsSheet(
      context,
      entries: entries,
      current: _currentEntry(entries),
    );
    if (chosen == null || !mounted || !identical(session, _session)) {
      return;
    }
    setState(() {
      // A jump the reader chose beats the saved position.
      _stopRestoring();
      _clearPick();
      _picked = chosen;
      _jumping = true;
    });
    await _navigate(() => session.goTo(chosen));
    if (mounted && identical(chosen, _picked)) {
      _jumping = false;
      _waitForPick();
    }
  }

  /// Recomputes what search may look at, from the reader's position, the
  /// furthest one they reached, and the furthest page start in the text.
  void _updateCutoff() {
    _cutoff.value = pageCutoff(
      current: _position,
      furthest: widget.furthestPosition?.call(),
      furthestPageText: _furthestPageText,
    );
  }

  /// The book's search, opened on first use and then reused. A failure is
  /// forgotten so "Try again" opens it afresh.
  Future<PassageSearch> _search() {
    final future = _searchFuture ??= widget.openSearch!();
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_searchFuture, future)) _searchFuture = null;
        },
      ),
    );
    return future;
  }

  /// Shows the search sheet and jumps to the hit the reader picks, with the
  /// passage highlighted.
  ///
  /// The highlight stays until the next hit replaces it or the book closes.
  Future<void> _openSearchSheet(String initialQuery) async {
    final session = _session;
    if (session == null || widget.openSearch == null || !mounted) return;
    _updateCutoff();
    final hit = await showSearchSheet(
      context,
      openSearch: _search,
      cutoff: _cutoff,
      entries: _usableEntries(session),
      initialQuery: initialQuery,
    );
    if (hit == null || !mounted || !identical(session, _session)) return;
    _stopRestoring();
    _highlightShown = true;
    await _navigate(() => session.showPassage(hit.target));
  }

  /// Turns the page. Like any move the reader starts, it ends the wait for
  /// the saved position.
  Future<void> _turnPage(Future<void> Function() turn) {
    _stopRestoring();
    return _navigate(turn);
  }

  Future<void> _navigate(Future<void> Function() go) async {
    try {
      await go();
    } on Object catch (error) {
      debugPrint('Could not move in the book: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final view = _view;
    if (session != null && view != null) {
      return _buildReader(session, view);
    }
    if (_error case final error?) {
      return _OpenFailure(
        book: widget.book,
        error: error,
        onRetry: () => setState(() => unawaited(_open())),
      );
    }
    return const Center(
      child: Text(
        'Opening book…',
        style: TextStyle(fontSize: 13, color: LoremarkColors.muted),
      ),
    );
  }

  Widget _buildReader(EpubReaderSession session, Widget view) {
    final entries = _usableEntries(session);
    final title = _currentEntry(entries)?.title ?? widget.book.title;
    return Column(
      children: [
        _ChapterBar(
          title: title,
          onOpenContents: entries.isEmpty
              ? null
              : () => unawaited(_openContents(session)),
          onOpenSearch: widget.openSearch == null
              ? null
              : () => unawaited(_openSearchSheet('')),
        ),
        Expanded(child: view),
        _PageControls(
          progress: _position?.totalProgression,
          onPrevious: () => unawaited(_turnPage(session.goBackward)),
          onNext: () => unawaited(_turnPage(session.goForward)),
        ),
      ],
    );
  }
}

/// The chapter being read, with the button that opens the contents.
class _ChapterBar extends StatelessWidget {
  const _ChapterBar({
    required this.title,
    required this.onOpenContents,
    required this.onOpenSearch,
  });

  final String title;
  final VoidCallback? onOpenContents;
  final VoidCallback? onOpenSearch;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: LoremarkColors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 22, right: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                key: const ValueKey('chapter-title'),
                style: serif(14, color: LoremarkColors.readerTitle),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search',
              color: LoremarkColors.muted,
              onPressed: onOpenSearch,
            ),
            IconButton(
              icon: const Icon(Icons.toc),
              tooltip: 'Contents',
              color: LoremarkColors.muted,
              onPressed: onOpenContents,
            ),
          ],
        ),
      ),
    );
  }
}

/// Previous and next page around how far through the book the reader is.
class _PageControls extends StatelessWidget {
  const _PageControls({
    required this.progress,
    required this.onPrevious,
    required this.onNext,
  });

  /// How far into the whole book, if the renderer knows.
  final double? progress;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// Never shows 100% before the very end.
  String _label(double fraction) {
    final percent = (fraction * 100).round();
    return '${fraction < 1 && percent == 100 ? 99 : percent}%';
  }

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: LoremarkColors.line)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous page',
            color: LoremarkColors.muted,
            onPressed: onPrevious,
          ),
          Expanded(
            child: Text(
              progress == null ? '' : _label(progress),
              key: const ValueKey('progress-label'),
              textAlign: TextAlign.center,
              style: kicker(color: LoremarkColors.muted),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next page',
            color: LoremarkColors.muted,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

/// Why the book didn't open, with a way to try again.
class _OpenFailure extends StatelessWidget {
  const _OpenFailure({
    required this.book,
    required this.error,
    required this.onRetry,
  });

  final Book book;
  final Object error;
  final VoidCallback onRetry;

  String get _message => switch (error) {
    EpubOpenException(failure: EpubOpenFailure.missingFile) =>
      "This book's file is missing. Remove it from your library and import it "
          'again.',
    EpubOpenException(failure: EpubOpenFailure.unreadable) =>
      "This file couldn't be opened as an EPUB. It may be damaged.",
    _ => "Couldn't open this book. Please try again.",
  };

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 32, 22, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BookCover(book: book, width: 96),
            const SizedBox(height: 20),
            Text(
              book.title,
              textAlign: TextAlign.center,
              style: serif(22, color: LoremarkColors.readerTitle, height: 1.25),
            ),
            const SizedBox(height: 12),
            Text(
              _message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.6,
                color: LoremarkColors.muted,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
