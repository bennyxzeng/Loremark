import 'dart:async';

import 'package:flutter/material.dart';

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
/// starts at the beginning and stops saving.
class ReadScreen extends StatefulWidget {
  const ReadScreen({
    super.key,
    required this.book,
    required this.readerService,
    this.openPositionStore = ReadingPositionStore.open,
    this.onPositionChanged,
  });

  final Book book;
  final EpubReaderService readerService;

  /// Opens where [book]'s position is saved and resumed from. If it fails,
  /// the book still opens, at the beginning.
  final Future<ReadingPositionStore> Function() openPositionStore;

  /// Called with every position the reader moves to, for reading progress.
  final ValueChanged<ReaderPosition>? onPositionChanged;

  @override
  State<ReadScreen> createState() => _ReadScreenState();
}

class _ReadScreenState extends State<ReadScreen> {
  EpubReaderSession? _session;

  /// Built once per session: rebuilding it on a page turn would recreate the
  /// platform view.
  Widget? _view;
  StreamSubscription<ReaderPosition>? _positionSubscription;
  ReadingPositionStore? _store;
  ReaderPosition? _position;
  Object? _error;

  /// Identifies the latest open, so a slow earlier one can tell it was
  /// replaced or the screen was disposed.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void didUpdateWidget(ReadScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.id != widget.book.id) {
      unawaited(_open());
    }
  }

  @override
  void dispose() {
    _generation++;
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

  void _releaseSession() {
    unawaited(_positionSubscription?.cancel());
    _positionSubscription = null;
    final session = _session;
    _session = null;
    _view = null;
    if (session != null) {
      unawaited(_close(session));
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
    await _navigate(() => session.goTo(chosen));
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
        ),
        Expanded(child: view),
        _PageControls(
          progress: _position?.totalProgression,
          onPrevious: () => unawaited(_navigate(session.goBackward)),
          onNext: () => unawaited(_navigate(session.goForward)),
        ),
      ],
    );
  }
}

/// The chapter being read, with the button that opens the contents.
class _ChapterBar extends StatelessWidget {
  const _ChapterBar({required this.title, required this.onOpenContents});

  final String title;
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
