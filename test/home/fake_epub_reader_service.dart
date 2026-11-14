import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:loremark/reader/epub_reader_service.dart';
import 'package:loremark/reader/page_end.dart';
import 'package:loremark/reader/page_start.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/reader/reading_position_store.dart';
import 'package:loremark/reading/text_position.dart';

/// A reader service that opens [FakeEpubReaderSession]s, so widget tests
/// never touch native code.
class FakeEpubReaderService implements EpubReaderService {
  FakeEpubReaderService({this.error, this.gate, this.toc = defaultToc});

  /// A small book: nested chapters, and an entry outside the spine.
  static const defaultToc = [
    TocEntry(title: 'Chapter One', href: 'c1.xhtml', sectionIndex: 1),
    TocEntry(
      title: 'Section 1.1',
      href: 'c1.xhtml#s1',
      sectionIndex: 2,
      depth: 1,
    ),
    TocEntry(title: 'Chapter Two', href: 'c2.xhtml', sectionIndex: 4),
    TocEntry(
      title: 'Online Notes',
      href: 'https://example.com',
      sectionIndex: null,
    ),
  ];

  /// What [open] fails with, or null to succeed.
  Object? error;

  /// If set, [open] waits for it to complete first.
  Completer<void>? gate;

  /// Like [gate], but for one book, so opens can finish out of order.
  final Map<String, Completer<void>> pathGates = {};

  final List<TocEntry> toc;
  final List<String> openedPaths = [];

  /// Every session opened so far, oldest first.
  final List<FakeEpubReaderSession> sessions = [];

  @override
  Future<EpubReaderSession> open(String epubPath) async {
    openedPaths.add(epubPath);
    await gate?.future;
    await pathGates[epubPath]?.future;
    if (error case final error?) {
      throw error;
    }
    final session = FakeEpubReaderSession(toc: toc, epubPath: epubPath);
    sessions.add(session);
    return session;
  }
}

class FakeEpubReaderSession implements EpubReaderSession {
  FakeEpubReaderSession({
    this.toc = FakeEpubReaderService.defaultToc,
    this.epubPath,
  });

  /// The file this session was opened from.
  final String? epubPath;

  final List<TocEntry> toc;
  final StreamController<ReaderPosition> _positions =
      StreamController<ReaderPosition>.broadcast();

  /// The `initialPosition` of every [buildView] call.
  final List<ReaderPosition?> builtViews = [];
  final List<TocEntry> goToCalls = [];

  /// Every position [goToPosition] was asked to go to.
  final List<ReaderPosition> goToPositionCalls = [];

  /// If set, [goToPosition] fails with it.
  Object? goToPositionError;
  final List<PassageTarget> shownPassages = [];

  /// How often the passage highlight was cleared.
  int clearHighlightCalls = 0;
  int forwardCalls = 0;
  int backwardCalls = 0;
  int closeCalls = 0;

  /// Whether the screen is still listening to [positions].
  bool get hasListener => _positions.hasListener;

  final StreamController<TocEntry> _chapters =
      StreamController<TocEntry>.broadcast();

  /// Reports the chapter the renderer says the reader is in.
  void emitChapter(TocEntry chapter) => _chapters.add(chapter);

  final StreamController<TextPosition> _pageTextEnds =
      StreamController<TextPosition>.broadcast();

  /// Reports how far the text on the page the reader is on goes.
  void emitPageTextEnd(TextPosition end) => _pageTextEnds.add(end);

  final StreamController<PageEnd> _pageEnds =
      StreamController<PageEnd>.broadcast();

  /// Reports where the page the reader is on ends.
  void emitPageEnd(PageEnd end) => _pageEnds.add(end);

  final StreamController<PageStart> _pageStarts =
      StreamController<PageStart>.broadcast();

  /// Reports where the page the reader is on starts.
  void emitPageStart(PageStart start) => _pageStarts.add(start);

  /// Pretends the reader moved to [position].
  void emit(ReaderPosition position) => _positions.add(position);

  final StreamController<PassageSelection> _selections =
      StreamController<PassageSelection>.broadcast();

  /// Pretends the reader picked an action from the selection menu.
  void select(PassageSelection selection) => _selections.add(selection);

  final StreamController<String> _highlightTaps =
      StreamController<String>.broadcast();

  /// Pretends the reader tapped the note highlight with [id].
  void tapHighlight(String id) => _highlightTaps.add(id);

  /// Every list [showNoteHighlights] was given, in order.
  final List<List<NoteHighlight>> shownNoteHighlights = [];

  @override
  List<TocEntry> get tableOfContents => toc;

  @override
  int get sectionCount => 6;

  @override
  Stream<ReaderPosition> get positions => _positions.stream;

  @override
  Stream<TextPosition> get pageTextEnds => _pageTextEnds.stream;

  @override
  Stream<PageEnd> get pageEnds => _pageEnds.stream;

  @override
  Stream<PageStart> get pageStarts => _pageStarts.stream;

  @override
  Stream<TocEntry> get chapterChanges => _chapters.stream;

  @override
  Widget buildView({ReaderPosition? initialPosition}) {
    builtViews.add(initialPosition);
    return const Text('Fake reader view');
  }

  /// If set, [goTo] waits for it before it returns.
  Completer<void>? goToGate;

  @override
  Future<void> goTo(TocEntry entry) async {
    goToCalls.add(entry);
    await goToGate?.future;
  }

  @override
  Future<void> goToPosition(ReaderPosition position) async {
    goToPositionCalls.add(position);
    if (goToPositionError case final error?) {
      throw error;
    }
  }

  @override
  Future<void> showPassage(PassageTarget target) async =>
      shownPassages.add(target);

  @override
  Future<void> clearPassageHighlight() async => clearHighlightCalls++;

  @override
  Stream<PassageSelection> get selections => _selections.stream;

  @override
  Stream<String> get highlightTaps => _highlightTaps.stream;

  @override
  Future<void> showNoteHighlights(List<NoteHighlight> highlights) async =>
      shownNoteHighlights.add(highlights);

  @override
  Future<void> goForward() async => forwardCalls++;

  @override
  Future<void> goBackward() async => backwardCalls++;

  @override
  Future<void> close() async {
    closeCalls++;
    await _positions.close();
    await _pageTextEnds.close();
    await _pageEnds.close();
    await _pageStarts.close();
    await _chapters.close();
    await _selections.close();
    await _highlightTaps.close();
  }
}

/// A position store that keeps everything in memory.
class FakeReadingPositionStore implements ReadingPositionStore {
  FakeReadingPositionStore({this.positions = const {}, this.loadError});

  /// What [load] returns, by book id.
  final Map<String, ReaderPosition> positions;

  /// If set, [load] fails with it.
  final Object? loadError;

  /// Every [save], in order.
  final List<(String, ReaderPosition)> saves = [];

  /// If set, [save] fails with it.
  Object? saveError;

  /// Every [savePageStart], in order.
  final List<(String, PageStart)> pageStartSaves = [];

  @override
  Future<PageStart?> loadPageStart(String bookId) async => null;

  @override
  Future<void> savePageStart(String bookId, PageStart start) async =>
      pageStartSaves.add((bookId, start));

  /// Every [savePageEnd], in order.
  final List<(String, PageEnd)> pageEndSaves = [];

  @override
  Future<PageEnd?> loadPageEnd(String bookId) async => null;

  @override
  Future<void> savePageEnd(String bookId, PageEnd end) async =>
      pageEndSaves.add((bookId, end));

  @override
  Directory get root => Directory('fake');

  @override
  Future<void> get saved async {}

  @override
  Future<ReaderPosition?> load(String bookId) async {
    if (loadError case final error?) {
      throw error;
    }
    return positions[bookId];
  }

  @override
  Future<void> save(String bookId, ReaderPosition position) async {
    if (saveError case final error?) {
      throw error;
    }
    saves.add((bookId, position));
  }
}
