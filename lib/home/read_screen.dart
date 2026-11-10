import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../library/book.dart';
import '../library/library_screen.dart';
import '../notes/add_note_sheet.dart';
import '../notes/annotation_service.dart';
import '../notes/highlight_colors.dart';
import '../notes/note.dart';
import '../notes/note_list.dart';
import '../reader/epub_reader_service.dart';
import '../reader/page_end.dart';
import '../reader/page_start.dart';
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
    this.notes,
    this.noteJumps,
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

  /// The book's notes and highlights. Once they open, they are drawn on the
  /// page, and Highlight and Add note in the menu over selected text save to
  /// them. If they fail to open, reading is unaffected.
  final Future<AnnotationService>? notes;

  /// Lets other code send the reader to a note's passage, such as tapping a
  /// note in the Notes tab.
  final NoteJumpController? noteJumps;

  @override
  State<ReadScreen> createState() => _ReadScreenState();
}

/// Lets other code send the Read tab to a saved note's passage, or to any
/// passage, such as one an answer in Ask cites.
class NoteJumpController {
  Future<void> Function(Note note)? _jumper;
  Future<void> Function(PassageTarget target)? _passageJumper;

  /// Called by the screen that shows the book. [detach] undoes it.
  void attach(Future<void> Function(Note note) jumper) => _jumper = jumper;

  void detach(Future<void> Function(Note note) jumper) {
    if (_jumper == jumper) _jumper = null;
  }

  /// Called by the screen that shows the book. [detachPassages] undoes it.
  void attachPassages(Future<void> Function(PassageTarget target) jumper) =>
      _passageJumper = jumper;

  void detachPassages(Future<void> Function(PassageTarget target) jumper) {
    if (_passageJumper == jumper) _passageJumper = null;
  }

  /// Jumps to [note]'s passage and highlights it, if a book is showing.
  Future<void> show(Note note) async => _jumper?.call(note);

  /// Jumps to [target] and highlights it, if a book is showing.
  Future<void> showPassage(PassageTarget target) async =>
      _passageJumper?.call(target);
}

class _ReadScreenState extends State<ReadScreen> {
  EpubReaderSession? _session;

  /// Built once per session: rebuilding it on a page turn would recreate the
  /// platform view.
  Widget? _view;
  StreamSubscription<ReaderPosition>? _positionSubscription;
  StreamSubscription<TextPosition>? _pageTextSubscription;
  StreamSubscription<PageStart>? _pageStartSubscription;
  StreamSubscription<PageEnd>? _pageEndSubscription;
  StreamSubscription<TocEntry>? _chapterSubscription;
  StreamSubscription<PassageSelection>? _selectionSubscription;
  StreamSubscription<String>? _highlightTapSubscription;

  /// The book's notes, once [ReadScreen.notes] opened them.
  AnnotationService? _notes;

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

  /// The section the reader opened in when it was not the saved one, once it
  /// was sent back to [_restoring]. Null until then, which also means the
  /// jump back has not been made yet.
  int? _landedSection;

  @override
  void initState() {
    super.initState();
    widget.searchController?.attach(_openSearchSheet);
    widget.noteJumps?.attach(_showNote);
    widget.noteJumps?.attachPassages(_showPassage);
    unawaited(_open());
    unawaited(_openNotes());
  }

  @override
  void didUpdateWidget(ReadScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchController != widget.searchController) {
      oldWidget.searchController?.detach(_openSearchSheet);
      widget.searchController?.attach(_openSearchSheet);
    }
    if (oldWidget.noteJumps != widget.noteJumps) {
      oldWidget.noteJumps?.detach(_showNote);
      oldWidget.noteJumps?.detachPassages(_showPassage);
      widget.noteJumps?.attach(_showNote);
      widget.noteJumps?.attachPassages(_showPassage);
    }
    if (oldWidget.book.id != widget.book.id) {
      unawaited(_open());
    }
    if (oldWidget.notes != widget.notes) {
      _setNotes(null);
      unawaited(_openNotes());
    }
  }

  @override
  void dispose() {
    _generation++;
    _pickTimer?.cancel();
    widget.searchController?.detach(_openSearchSheet);
    widget.noteJumps?.detach(_showNote);
    widget.noteJumps?.detachPassages(_showPassage);
    _notes?.removeListener(_drawNoteHighlights);
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
      _pageStartSubscription = session.pageStarts.listen(_onPageStart);
      _pageEndSubscription = session.pageEnds.listen(_onPageEnd);
      _chapterSubscription = session.chapterChanges.listen(
        (chapter) => setState(() => _chapter = chapter),
      );
      _selectionSubscription = session.selections.listen(
        (selection) => unawaited(_onSelection(selection)),
      );
      _highlightTapSubscription = session.highlightTaps.listen(
        (id) => unawaited(_onHighlightTap(id)),
      );
      _view = session.buildView(initialPosition: position);
    });
    _drawNoteHighlights();
  }

  /// Waits for the book's notes, then draws them and redraws them whenever
  /// they change. If they fail to open, the book just shows without them.
  Future<void> _openNotes() async {
    final future = widget.notes;
    if (future == null) return;
    final AnnotationService notes;
    try {
      notes = await future;
    } on Object catch (error) {
      debugPrint('Could not open the notes of ${widget.book.title}: $error');
      return;
    }
    if (!mounted || !identical(future, widget.notes)) return;
    _setNotes(notes);
    _drawNoteHighlights();
  }

  void _setNotes(AnnotationService? notes) {
    _notes?.removeListener(_drawNoteHighlights);
    _notes = notes;
    notes?.addListener(_drawNoteHighlights);
  }

  /// Draws every saved note and highlight on the page, replacing the ones
  /// drawn before. Best effort: the book reads fine without them.
  void _drawNoteHighlights() {
    final session = _session;
    final notes = _notes;
    if (session == null || notes == null) return;
    final highlights = [
      for (final note in notes.notes)
        NoteHighlight(
          id: note.id,
          target: _passageOf(note),
          color: note.color.pageTint,
        ),
    ];
    unawaited(
      session.showNoteHighlights(highlights).catchError((Object error) {
        debugPrint('Could not draw the notes: $error');
      }),
    );
  }

  PassageTarget _passageOf(Note note) => PassageTarget(
    sectionIndex: note.anchor.sectionIndex,
    progression: note.anchor.progression,
    highlight: note.selectedText,
    before: note.textBefore,
    after: note.textAfter,
  );

  /// Does what the reader picked from the menu over the text they selected.
  ///
  /// The chapter is read before the note sheet opens, since the reader can't
  /// turn pages while it is up anyway.
  Future<void> _onSelection(PassageSelection selection) async {
    final session = _session;
    if (session == null) return;
    if (selection.command == SelectionCommand.copy) {
      await Clipboard.setData(ClipboardData(text: selection.text));
      return;
    }
    final notes = _notes;
    if (notes == null || !mounted) return;
    final anchor = NoteAnchor(
      selection.sectionIndex,
      selection.progression.clamp(0.0, 1.0),
    );
    final chapter =
        _currentEntry(_usableEntries(session))?.title ?? widget.book.title;
    if (selection.command == SelectionCommand.highlight) {
      await saveOrReport(
        context,
        () => notes.addHighlight(
          anchor: anchor,
          chapterLabel: chapter,
          selectedText: selection.text,
          textBefore: selection.before,
          textAfter: selection.after,
        ),
        failureMessage: 'Could not save your highlight. Try again.',
      );
      return;
    }
    final result = await showAddNoteSheet(
      context,
      selectedText: selection.text,
    );
    if (result is! AddNoteResult || !mounted) return;
    await saveOrReport(
      context,
      () => notes.addNote(
        anchor: anchor,
        chapterLabel: chapter,
        selectedText: selection.text,
        textBefore: selection.before,
        textAfter: selection.after,
        body: result.body,
        color: result.color,
      ),
      failureMessage: 'Could not save your note. Try again.',
    );
  }

  /// Opens the note behind the highlight the reader tapped, to edit or remove
  /// it. A removed note is taken off the page by [_drawNoteHighlights].
  Future<void> _onHighlightTap(String id) async {
    final notes = _notes;
    if (notes == null || !mounted) return;
    final note = notes.notes.where((note) => note.id == id).firstOrNull;
    if (note == null) return;
    await editNoteWithSheet(context, notes, note);
  }

  /// Jumps to [note]'s passage and highlights it, as a search hit is.
  Future<void> _showNote(Note note) => _showPassage(_passageOf(note));

  /// Jumps to [target] and highlights it.
  Future<void> _showPassage(PassageTarget target) async {
    final session = _session;
    if (session == null || !mounted) return;
    _stopRestoring();
    _highlightShown = true;
    await _navigate(() => session.showPassage(target));
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
    unawaited(_pageStartSubscription?.cancel());
    _pageStartSubscription = null;
    unawaited(_pageEndSubscription?.cancel());
    _pageEndSubscription = null;
    unawaited(_chapterSubscription?.cancel());
    _chapterSubscription = null;
    unawaited(_selectionSubscription?.cancel());
    _selectionSubscription = null;
    unawaited(_highlightTapSubscription?.cancel());
    _highlightTapSubscription = null;
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
    _landedSection = null;
  }

  /// Whether [position] may overwrite the saved one.
  ///
  /// While restoring, only a position at the saved one may. If the reader
  /// opened elsewhere it is sent back once. After that, positions in the
  /// section it opened in or in the saved section are still the opening (or
  /// Readium honouring the jump only partly), so they are held too. A
  /// position in any other section means the reader really moved on, so
  /// restoring is given up and saving is never blocked for good.
  ///
  /// This goes by section and not by time on purpose: Readium sends a bare
  /// locator first and the full locator for the same page can come seconds
  /// later, which on a one-page section reads as progression 1.0. Only the
  /// section tells "same page, more detail" from "the reader moved on".
  ///
  /// Known limit: if the jump back fails and the reader swipes on inside the
  /// opened or saved section without the page buttons, those pages are not
  /// saved until they reach another section or use the controls. That is the
  /// price of never overwriting a good position with an opening one.
  bool _shouldSave(ReaderPosition position) {
    final saved = _restoring;
    if (saved == null) return true;
    if (position.sectionIndex == saved.sectionIndex &&
        (position.progression - saved.progression).abs() <= _arrivalTolerance) {
      _stopRestoring();
      return true;
    }
    final landed = _landedSection;
    if (landed == null) {
      _landedSection = position.sectionIndex;
      debugPrint(
        'The reader opened at ${position.sectionIndex}/${position.progression} '
        'instead of the saved ${saved.sectionIndex}/${saved.progression}; '
        'jumping back.',
      );
      final session = _session;
      if (session != null) unawaited(_restore(session, saved));
      return false;
    }
    if (position.sectionIndex == saved.sectionIndex ||
        position.sectionIndex == landed) {
      return false;
    }
    debugPrint(
      'The reader moved on to section ${position.sectionIndex}; giving up '
      'restoring the saved position.',
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

  /// Keeps where this page starts, for the Story Map. It follows the page being
  /// looked at, so it isn't kept from a page the book only opened on on its way
  /// back to the saved position.
  void _onPageStart(PageStart start) {
    final store = _store;
    if (store == null ||
        _restoring != null ||
        start.sectionIndex != _position?.sectionIndex) {
      return;
    }
    unawaited(_savePageStart(store, start));
  }

  Future<void> _savePageStart(
    ReadingPositionStore store,
    PageStart start,
  ) async {
    try {
      await store.savePageStart(widget.book.id, start);
    } on Object catch (error) {
      debugPrint('Could not save where the page starts: $error');
    }
  }

  /// Keeps where this page ends, for Ask, which may use all of it. Kept the
  /// same way as [_onPageStart].
  void _onPageEnd(PageEnd end) {
    final store = _store;
    if (store == null ||
        _restoring != null ||
        end.sectionIndex != _position?.sectionIndex) {
      return;
    }
    unawaited(_savePageEnd(store, end));
  }

  Future<void> _savePageEnd(ReadingPositionStore store, PageEnd end) async {
    try {
      await store.savePageEnd(widget.book.id, end);
    } on Object catch (error) {
      debugPrint('Could not save where the page ends: $error');
    }
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
