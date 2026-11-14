import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../insights/insights_sheet.dart';
import '../insights/reading_insights.dart';
import '../insights/reading_nudge.dart';
import '../insights/reading_time_text.dart';
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
/// starts at the beginning and stops saving. The same goes for reading
/// insights: without them the bottom bar shows progress as a percentage.
class ReadScreen extends StatefulWidget {
  const ReadScreen({
    super.key,
    required this.book,
    required this.readerService,
    this.openPositionStore = ReadingPositionStore.open,
    this.openInsights,
    this.isActive = true,
    this.onPositionChanged,
    this.onOpenStoryMap,
    this.onSearchChapter,
    this.controller,
    this.openSearch,
    this.furthestPosition,
    this.searchController,
    this.notes,
    this.noteJumps,
    this.passageJumps,
  });

  final Book book;

  /// False when another tab covers the reader. Hidden pages are not reading.
  final bool isActive;
  final EpubReaderService readerService;

  /// Opens where [book]'s position is saved and resumed from. If it fails,
  /// the book still opens, at the beginning.
  final Future<ReadingPositionStore> Function() openPositionStore;

  /// Opens the reading statistics and confusion detection for [book]. If it
  /// is null or fails, there is no time-left label, insights button or nudge.
  final Future<ReadingInsights> Function()? openInsights;

  /// Called with every position the reader moves to, for reading progress.
  final ValueChanged<ReaderPosition>? onPositionChanged;

  /// Shows the Story Map, for the reading nudge to offer.
  final VoidCallback? onOpenStoryMap;

  /// Opens a search of the current chapter, for the reading nudge to offer.
  /// The nudge has no search button without it.
  final VoidCallback? onSearchChapter;

  /// Lets other features move the reader and say why.
  final ReadScreenController? controller;

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

  /// Lets other code send the reader to a passage and offer a way back, such
  /// as **Read it in the book** in a recap.
  final PassageJumpController? passageJumps;

  @override
  State<ReadScreen> createState() => _ReadScreenState();
}

/// How the rest of the app moves the reader while saying why, so the reading
/// log can tell a search jump from a swipe.
class ReadScreenController {
  Future<void> Function(ReaderPosition, NavigationCause)? _jump;

  /// Moves the reader to [position]. Does nothing if no book is open.
  Future<void> goToPosition(
    ReaderPosition position, {
    NavigationCause cause = NavigationCause.searchJump,
  }) async => _jump?.call(position, cause);
}

/// What the progress label in the bottom bar shows. Tapping it cycles.
enum _LabelMode { chapterLeft, bookLeft, percent }

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

/// Lets other code send the Read tab to a passage, keeping the reader's place
/// so **Back to your page** can return them to it.
class PassageJumpController {
  Future<void> Function(PassageTarget target)? _jumper;

  /// Called by the screen that shows the book. [detach] undoes it.
  void attach(Future<void> Function(PassageTarget target) jumper) =>
      _jumper = jumper;

  void detach(Future<void> Function(PassageTarget target) jumper) {
    if (_jumper == jumper) _jumper = null;
  }

  /// Jumps to [target] and highlights it, if a book is showing.
  Future<void> show(PassageTarget target) async => _jumper?.call(target);
}

class _ReadScreenState extends State<ReadScreen> {
  /// How long after asking to move a position still counts as the result.
  static const _causeWindow = Duration(milliseconds: 1500);

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
  ReadingInsights? _insights;
  late final AppLifecycleListener _lifecycle;
  ReaderPosition? _position;

  /// How far the text of the furthest page reached in this session goes, if
  /// the reader could measure it.
  TextPosition? _furthestPageText;
  Object? _error;
  _LabelMode _labelMode = _LabelMode.chapterLeft;

  /// Why the reader is about to move, set right before we ask it to. Cleared
  /// by the position it causes, or by [_causeTimer] if none arrives.
  NavigationCause? _pendingCause;
  Timer? _causeTimer;

  /// Whether the next position is the first since the book opened.
  bool _firstPosition = true;

  /// The opened search of the current book, kept so the index is built once.
  Future<PassageSearch>? _searchFuture;

  /// What search may look at. The sheet watches it so open results follow the
  /// reader.
  final ValueNotifier<ReaderPosition> _cutoff = ValueNotifier(searchCutoff());

  /// Whether a search highlight is on the page, so it is cleared only when
  /// there is one.
  bool _highlightShown = false;

  /// Where the reader was before a [ReadScreen.passageJumps] jump, while
  /// **Back to your page** is offered. A second jump keeps the first place.
  ReaderPosition? _returnTo;

  /// Identifies the latest open, so a slow earlier one can tell it was
  /// replaced or the screen was disposed.
  int _generation = 0;
  bool _appVisible = true;
  bool _insightsVisible = true;
  bool _modalVisible = false;

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
    widget.controller?._jump = _jumpTo;
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _appVisible = false;
        _updateVisibility();
      },
      onShow: () {
        _appVisible = true;
        _updateVisibility();
      },
    );
    widget.searchController?.attach(_openSearchSheet);
    widget.noteJumps?.attach(_showNote);
    widget.noteJumps?.attachPassages(_showPassage);
    widget.passageJumps?.attach(_visitPassage);
    unawaited(_open());
    unawaited(_openNotes());
  }

  @override
  void didUpdateWidget(ReadScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateVisibility();
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._jump = null;
      widget.controller?._jump = _jumpTo;
    }
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
    if (oldWidget.passageJumps != widget.passageJumps) {
      oldWidget.passageJumps?.detach(_visitPassage);
      widget.passageJumps?.attach(_visitPassage);
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
    widget.controller?._jump = null;
    _lifecycle.dispose();
    _pickTimer?.cancel();
    widget.searchController?.detach(_openSearchSheet);
    widget.noteJumps?.detach(_showNote);
    widget.noteJumps?.detachPassages(_showPassage);
    widget.passageJumps?.detach(_visitPassage);
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
    _returnTo = null;
    _furthestPageText = null;
    _chapter = null;
    _clearPick();
    _stopRestoring();
    _error = null;
    _firstPosition = true;
    _searchFuture = null;
    _cutoff.value = searchCutoff();

    final book = widget.book;
    final sessionFuture = _openSession(book);
    final savedFuture = _loadSavedPosition(book);
    // Counting the book and replaying its log can take seconds on a phone,
    // and the text must not wait for statistics. They attach when ready.
    final insightsFuture = _openInsights(book);

    final EpubReaderSession session;
    try {
      session = await sessionFuture;
    } on Object catch (error) {
      debugPrint('Could not open ${book.title}: $error');
      unawaited(insightsFuture.then(_closeInsights));
      if (mounted && generation == _generation) {
        setState(() => _error = error);
      }
      return;
    }
    // Neither of these throws, so skipping them above can't leave an
    // unhandled error.
    final (:store, :position) = await savedFuture;
    if (!mounted || generation != _generation) {
      unawaited(_close(session));
      unawaited(insightsFuture.then(_closeInsights));
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
    unawaited(_attachInsights(generation, insightsFuture));
    _drawNoteHighlights();
  }

  /// Hands the opened insights to the reader, which is already on screen.
  ///
  /// Positions that came before are not in the log. The one the reader is on
  /// is recorded as the open, unless none has arrived yet, in which case the
  /// first one will be.
  Future<void> _attachInsights(
    int generation,
    Future<ReadingInsights?> future,
  ) async {
    final insights = await future;
    if (insights == null) return;
    if (!mounted || generation != _generation) {
      await _closeInsights(insights);
      return;
    }
    setState(() {
      _insights = insights;
      _insightsVisible = true;
      _updateVisibility();
    });
    final position = _position;
    if (_insightsVisible && !_firstPosition && position != null) {
      _tellInsights(
        (insights) => insights.recordPosition(position, NavigationCause.open),
      );
    }
    _updateCutoff();
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
    await _navigate(
      NavigationCause.searchJump,
      () => session.showPassage(target),
    );
  }

  /// Shows [target], keeping the reader's place for **Back to your page**.
  /// Before the saved position has shown, that is where the reader is.
  Future<void> _visitPassage(PassageTarget target) async {
    if (_session == null || !mounted) return;
    setState(() => _returnTo ??= _restoring ?? _position);
    await _showPassage(target);
  }

  /// Keeps the reader at the passage and puts **Back to your page** away. The
  /// passage's highlight goes with it: they have found it.
  Future<void> _stayHere() async {
    final session = _session;
    setState(() => _returnTo = null);
    if (session != null && _highlightShown) await _clearHighlight(session);
  }

  /// Takes the reader back to where they were before [_visitPassage].
  Future<void> _goBack() async {
    final session = _session;
    final returnTo = _returnTo;
    if (session == null || returnTo == null) return;
    setState(() => _returnTo = null);
    if (_highlightShown) await _clearHighlight(session);
    await _navigate(
      NavigationCause.searchJump,
      () => session.goToPosition(returnTo),
    );
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

  Future<ReadingInsights?> _openInsights(Book book) async {
    final open = widget.openInsights;
    if (open == null) {
      return null;
    }
    try {
      return await open();
    } on Object catch (error) {
      debugPrint(
        'Could not open the reading insights of ${book.title}: $error',
      );
      return null;
    }
  }

  void _updateVisibility() {
    final visible = _appVisible && widget.isActive && !_modalVisible;
    if (_insights == null || visible == _insightsVisible) return;
    _insightsVisible = visible;
    _tellInsights((insights) {
      if (visible) {
        insights.recordShown();
        final position = _position;
        if (position != null) {
          insights.recordPosition(position, NavigationCause.open);
        }
      } else {
        insights.recordHidden();
      }
    });
  }

  void _releaseSession() {
    unawaited(_positionSubscription?.cancel());
    _positionSubscription = null;
    _causeTimer?.cancel();
    _pendingCause = null;
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
    unawaited(_closeInsights(_insights));
    _insights = null;
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

  Future<void> _closeInsights(ReadingInsights? insights) async {
    try {
      await insights?.close();
    } on Object catch (error) {
      debugPrint('Could not close the reading insights: $error');
    }
  }

  /// Runs [action] on the open insights, if any. A failure is only logged:
  /// statistics never get in the way of reading.
  void _tellInsights(void Function(ReadingInsights insights) action) {
    final insights = _insights;
    if (insights == null) {
      return;
    }
    try {
      action(insights);
    } on Object catch (error) {
      debugPrint('Reading insights failed: $error');
    }
  }

  /// Works out why the reader moved. Our own requests are known; a position
  /// nobody asked for came from a swipe.
  NavigationCause _takeCause(ReaderPosition position) {
    if (_firstPosition) {
      _firstPosition = false;
      return NavigationCause.open;
    }
    final cause = _pendingCause ?? NavigationCause.swipe;
    // The reader reports a finished section at exactly 1.0, then the start of
    // the next one, and both come from the same request.
    if (position.progression < 1) {
      _pendingCause = null;
      _causeTimer?.cancel();
    }
    return cause;
  }

  void _onPosition(ReaderPosition position) {
    final cause = _takeCause(position);
    if (_insightsVisible) {
      _tellInsights((insights) => insights.recordPosition(position, cause));
    }
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

  /// The section where the next chapter starts, or null in the last one.
  int? _chapterEndSection(List<TocEntry> entries) {
    final position = _position;
    if (position == null) {
      return null;
    }
    int? end;
    for (final entry in entries) {
      final section = entry.sectionIndex!;
      if (section > position.sectionIndex && (end == null || section < end)) {
        end = section;
      }
    }
    return end;
  }

  TimeLeft? _timeLeft(List<TocEntry> entries) {
    final position = _position;
    final insights = _insights;
    if (position == null || insights == null) {
      return null;
    }
    try {
      return insights.timeLeft(
        position,
        chapterEndSection: _chapterEndSection(entries),
      );
    } on Object catch (error) {
      debugPrint('Could not estimate the time left: $error');
      return null;
    }
  }

  Future<void> _openInsightsSheet(EpubReaderSession session) async {
    final insights = _insights;
    if (insights == null) {
      return;
    }
    await _withReaderCovered(
      () => showInsightsSheet(
        context,
        insights: insights,
        timeLeft: _timeLeft(_usableEntries(session)),
      ),
    );
  }

  Future<T> _withReaderCovered<T>(Future<T> Function() show) async {
    _modalVisible = true;
    _updateVisibility();
    try {
      return await show();
    } finally {
      _modalVisible = false;
      if (mounted) _updateVisibility();
    }
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
    final chosen = await _withReaderCovered(
      () => showTableOfContentsSheet(
        context,
        entries: entries,
        current: _currentEntry(entries),
      ),
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
    await _navigate(NavigationCause.tocJump, () => session.goTo(chosen));
    if (mounted && identical(chosen, _picked)) {
      _jumping = false;
      _waitForPick();
    }
  }

  /// Moves the reader to [position] for the rest of the app, saying why.
  Future<void> _jumpTo(ReaderPosition position, NavigationCause cause) {
    final session = _session;
    if (session == null) {
      return Future.value();
    }
    _stopRestoring();
    return _navigate(cause, () => session.goToPosition(position));
  }

  /// Recomputes what search may look at, from the reader's position, the
  /// furthest one they reached (from the reading record when the host gives
  /// none), and the furthest page start in the text.
  void _updateCutoff() {
    final hosted = widget.furthestPosition?.call();
    final recorded = _insights?.furthest;
    _cutoff.value = pageCutoff(
      // With a reading record, the furthest page really read is known, and a
      // jump ahead must not open the chapters it skipped, so where the reader
      // is now only counts when nothing says how far they have read.
      current: hosted == null && recorded != null ? null : _position,
      furthest: hosted ?? recorded,
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
    final hit = await _withReaderCovered(
      () => showSearchSheet(
        context,
        openSearch: _search,
        cutoff: _cutoff,
        entries: _usableEntries(session),
        initialQuery: initialQuery,
      ),
    );
    if (hit == null || !mounted || !identical(session, _session)) return;
    _stopRestoring();
    _highlightShown = true;
    await _navigate(
      NavigationCause.searchJump,
      () => session.showPassage(hit.target),
    );
  }

  /// Turns the page. Like any move the reader starts, it ends the wait for
  /// the saved position.
  Future<void> _turnPage(NavigationCause cause, Future<void> Function() turn) {
    _stopRestoring();
    return _navigate(cause, turn);
  }

  /// Moves the reader, noting [cause] for the position that follows.
  Future<void> _navigate(
    NavigationCause cause,
    Future<void> Function() go,
  ) async {
    _pendingCause = cause;
    _causeTimer?.cancel();
    _causeTimer = Timer(_causeWindow, () => _pendingCause = null);
    try {
      await go();
    } on Object catch (error) {
      debugPrint('Could not move in the book: $error');
      _pendingCause = null;
      _causeTimer?.cancel();
    }
  }

  void _cycleLabel() => setState(() {
    _labelMode = switch (_labelMode) {
      _LabelMode.chapterLeft => _LabelMode.bookLeft,
      _LabelMode.bookLeft => _LabelMode.percent,
      _LabelMode.percent => _LabelMode.chapterLeft,
    };
  });

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
    final insights = _insights;
    // Insights change on their own (a new estimate, a nudge), not only when
    // the reader moves. The builder is there even before they attach, so
    // that attaching doesn't rebuild the reader's platform view.
    return ListenableBuilder(
      listenable: insights ?? const _NeverChanges(),
      builder: (context, _) => _buildReaderBody(session, view, insights),
    );
  }

  Widget _buildReaderBody(
    EpubReaderSession session,
    Widget view,
    ReadingInsights? insights,
  ) {
    final entries = _usableEntries(session);
    final title = _currentEntry(entries)?.title ?? widget.book.title;
    final nudge = insights != null && insights.hintsEnabled
        ? insights.nudge
        : null;
    return Column(
      children: [
        _ChapterBar(
          title: title,
          onOpenInsights: insights == null
              ? null
              : () => unawaited(_openInsightsSheet(session)),
          onOpenContents: entries.isEmpty
              ? null
              : () => unawaited(_openContents(session)),
          onOpenSearch: widget.openSearch == null
              ? null
              : () => unawaited(_openSearchSheet('')),
        ),
        Expanded(
          // Always a stack, so offering the way back never rebuilds the view.
          child: Stack(
            fit: StackFit.expand,
            children: [
              view,
              if (_returnTo != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 14,
                  child: Center(
                    child: _BackToPage(
                      onBack: () => unawaited(_goBack()),
                      onStay: () => unawaited(_stayHere()),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Always in the column, so the reader view keeps its place in it.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: nudge == null
              ? const SizedBox(width: double.infinity)
              : ReadingNudge(
                  key: ObjectKey(nudge),
                  signal: nudge,
                  onDismiss: () =>
                      _tellInsights((insights) => insights.dismissNudge()),
                  onAccept: () =>
                      _tellInsights((insights) => insights.acceptNudge()),
                  onOpenStoryMap: widget.onOpenStoryMap,
                  onSearchChapter:
                      widget.onSearchChapter ??
                      (widget.openSearch == null
                          ? null
                          : () => unawaited(_openSearchSheet(''))),
                ),
        ),
        _PageControls(
          progress: _position?.totalProgression,
          timeLeft: _timeLeft(entries),
          mode: _labelMode,
          onCycleLabel: _cycleLabel,
          onPrevious: () => unawaited(
            _turnPage(NavigationCause.pageBackward, session.goBackward),
          ),
          onNext: () => unawaited(
            _turnPage(NavigationCause.pageForward, session.goForward),
          ),
        ),
      ],
    );
  }
}

/// Stands in for the insights while they are still opening.
class _NeverChanges implements Listenable {
  const _NeverChanges();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// After a jump to a passage, takes the reader back to their page, or lets
/// them stay where they are.
class _BackToPage extends StatelessWidget {
  const _BackToPage({required this.onBack, required this.onStay});

  final VoidCallback onBack;
  final VoidCallback onStay;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LoremarkColors.olive,
      shape: const StadiumBorder(),
      elevation: 4,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onBack,
            customBorder: const StadiumBorder(),
            child: const Padding(
              padding: EdgeInsets.fromLTRB(16, 11, 6, 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.undo, size: 18, color: LoremarkColors.onOlive),
                  SizedBox(width: 8),
                  Text(
                    'Back to your page',
                    style: TextStyle(
                      color: LoremarkColors.onOlive,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: onStay,
            tooltip: 'Stay here',
            icon: const Icon(Icons.close, size: 18),
            color: LoremarkColors.onOlive,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// The chapter being read, with the buttons for its insights and contents.
class _ChapterBar extends StatelessWidget {
  const _ChapterBar({
    required this.title,
    required this.onOpenInsights,
    required this.onOpenContents,
    required this.onOpenSearch,
  });

  final String title;

  /// Null while there are no reading insights, which hides the button.
  final VoidCallback? onOpenInsights;
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
            // More buttons, such as search, belong in this row too.
            if (onOpenInsights != null)
              IconButton(
                icon: const Icon(Icons.insights),
                tooltip: 'Reading insights',
                color: LoremarkColors.muted,
                onPressed: onOpenInsights,
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

/// Previous and next page around how far through the chapter or book the
/// reader is.
class _PageControls extends StatelessWidget {
  const _PageControls({
    required this.progress,
    required this.timeLeft,
    required this.mode,
    required this.onCycleLabel,
    required this.onPrevious,
    required this.onNext,
  });

  /// How far into the whole book, if the renderer knows.
  final double? progress;

  /// Time left at the reader's pace, or null until it is known, when the
  /// label falls back to [progress].
  final TimeLeft? timeLeft;
  final _LabelMode mode;
  final VoidCallback onCycleLabel;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// Never shows 100% before the very end.
  String _percent(double fraction) {
    final percent = (fraction * 100).round();
    return '${fraction < 1 && percent == 100 ? 99 : percent}%';
  }

  /// The label, and the same as a full sentence for screen readers.
  (String, String) _label() {
    final timeLeft = this.timeLeft;
    if (timeLeft != null && mode != _LabelMode.percent) {
      final inChapter = mode == _LabelMode.chapterLeft;
      final time = inChapter ? timeLeft.chapter : timeLeft.book;
      final where = inChapter ? 'chapter' : 'book';
      final spoken = spokenReadingTime(time);
      return (
        time < const Duration(minutes: 1)
            ? 'Less than a minute left'
            : '${formatReadingTime(time)} left in $where',
        '${spoken[0].toUpperCase()}${spoken.substring(1)} left in the $where',
      );
    }
    final progress = this.progress;
    if (progress == null) {
      return ('', '');
    }
    final text = _percent(progress);
    return (text, '$text through the book');
  }

  @override
  Widget build(BuildContext context) {
    final (text, spoken) = _label();
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
            child: Semantics(
              label: spoken,
              button: timeLeft != null,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // There is nothing to cycle through until minutes are known.
                onTap: timeLeft == null ? null : onCycleLabel,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    text,
                    key: const ValueKey('progress-label'),
                    textAlign: TextAlign.center,
                    style: kicker(color: LoremarkColors.muted),
                  ),
                ),
              ),
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
