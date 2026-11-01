import 'dart:async';

import 'package:flutter/material.dart';

import '../insights/insights_sheet.dart';
import '../insights/reading_insights.dart';
import '../insights/reading_nudge.dart';
import '../insights/reading_time_text.dart';
import '../library/book.dart';
import '../library/library_screen.dart';
import '../reader/epub_reader_service.dart';
import '../reader/reader_position.dart';
import '../reader/reading_position_store.dart';
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
    this.onPositionChanged,
    this.onOpenStoryMap,
    this.onSearchChapter,
    this.controller,
  });

  final Book book;
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

class _ReadScreenState extends State<ReadScreen> {
  /// How long after asking to move a position still counts as the result.
  static const _causeWindow = Duration(milliseconds: 1500);

  EpubReaderSession? _session;

  /// Built once per session: rebuilding it on a page turn would recreate the
  /// platform view.
  Widget? _view;
  StreamSubscription<ReaderPosition>? _positionSubscription;
  ReadingPositionStore? _store;
  ReadingInsights? _insights;
  late final AppLifecycleListener _lifecycle;
  ReaderPosition? _position;
  Object? _error;
  _LabelMode _labelMode = _LabelMode.chapterLeft;

  /// Why the reader is about to move, set right before we ask it to. Cleared
  /// by the position it causes, or by [_causeTimer] if none arrives.
  NavigationCause? _pendingCause;
  Timer? _causeTimer;

  /// Whether the next position is the first since the book opened.
  bool _firstPosition = true;

  /// Identifies the latest open, so a slow earlier one can tell it was
  /// replaced or the screen was disposed.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.controller?._jump = _jumpTo;
    _lifecycle = AppLifecycleListener(
      onHide: () => _tellInsights((insights) => insights.recordHidden()),
      onShow: () => _tellInsights((insights) => insights.recordShown()),
    );
    unawaited(_open());
  }

  @override
  void didUpdateWidget(ReadScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._jump = null;
      widget.controller?._jump = _jumpTo;
    }
    if (oldWidget.book.id != widget.book.id) {
      unawaited(_open());
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.controller?._jump = null;
    _lifecycle.dispose();
    _releaseSession();
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
    _error = null;
    _firstPosition = true;

    final book = widget.book;
    final sessionFuture = _openSession(book);
    final savedFuture = _loadSavedPosition(book);
    final insightsFuture = _openInsights(book);

    final EpubReaderSession session;
    try {
      session = await sessionFuture;
    } on Object catch (error) {
      debugPrint('Could not open ${book.title}: $error');
      unawaited(_closeInsights(await insightsFuture));
      if (mounted && generation == _generation) {
        setState(() => _error = error);
      }
      return;
    }
    // Neither of these throws, so skipping them above can't leave an
    // unhandled error.
    final (:store, :position) = await savedFuture;
    final insights = await insightsFuture;
    if (!mounted || generation != _generation) {
      unawaited(_close(session));
      unawaited(_closeInsights(insights));
      return;
    }

    setState(() {
      _session = session;
      _store = store;
      _insights = insights;
      _position = position;
      _positionSubscription = session.positions.listen(_onPosition);
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

  void _releaseSession() {
    unawaited(_positionSubscription?.cancel());
    _positionSubscription = null;
    _causeTimer?.cancel();
    _pendingCause = null;
    final session = _session;
    _session = null;
    _view = null;
    if (session != null) {
      unawaited(_close(session));
    }
    unawaited(_closeInsights(_insights));
    _insights = null;
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
    _tellInsights((insights) => insights.recordPosition(position, cause));
    setState(() => _position = position);
    final store = _store;
    if (store != null) {
      unawaited(_save(store, position));
    }
    widget.onPositionChanged?.call(position);
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

  /// The last chapter that starts at or before the reader's section.
  TocEntry? _currentEntry(List<TocEntry> entries) {
    final position = _position;
    if (position == null) {
      return null;
    }
    TocEntry? current;
    for (final entry in entries) {
      if (entry.sectionIndex! <= position.sectionIndex) {
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
    await showInsightsSheet(
      context,
      insights: insights,
      timeLeft: _timeLeft(_usableEntries(session)),
    );
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
    await _navigate(NavigationCause.tocJump, () => session.goTo(chosen));
  }

  Future<void> _jumpTo(ReaderPosition position, NavigationCause cause) {
    final session = _session;
    if (session == null) {
      return Future.value();
    }
    return _navigate(cause, () => session.goToPosition(position));
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
    if (insights == null) {
      return _buildReaderBody(session, view, null);
    }
    // Insights change on their own (a new estimate, a nudge), not only when
    // the reader moves.
    return ListenableBuilder(
      listenable: insights,
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
        ),
        Expanded(child: view),
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
                  onOpenStoryMap: widget.onOpenStoryMap,
                  onSearchChapter: widget.onSearchChapter,
                ),
        ),
        _PageControls(
          progress: _position?.totalProgression,
          timeLeft: _timeLeft(entries),
          mode: _labelMode,
          onCycleLabel: _cycleLabel,
          onPrevious: () => unawaited(
            _navigate(NavigationCause.pageBackward, session.goBackward),
          ),
          onNext: () => unawaited(
            _navigate(NavigationCause.pageForward, session.goForward),
          ),
        ),
      ],
    );
  }
}

/// The chapter being read, with the buttons for its insights and contents.
class _ChapterBar extends StatelessWidget {
  const _ChapterBar({
    required this.title,
    required this.onOpenInsights,
    required this.onOpenContents,
  });

  final String title;

  /// Null while there are no reading insights, which hides the button.
  final VoidCallback? onOpenInsights;
  final VoidCallback? onOpenContents;

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
