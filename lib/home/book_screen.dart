import 'dart:async';

import 'package:flutter/material.dart';

import '../library/book.dart';
import '../notes/annotation_service.dart';
import '../notes/note_list.dart';
import '../reader/epub_sections.dart';
import '../reader/reader_position.dart';
import '../reader/readium_reader_service.dart';
import '../search/search_cutoff.dart';
import '../settings/ai_lock.dart';
import '../settings/ai_settings.dart';
import '../settings/connection_status.dart';
import '../search/search_index_store.dart';
import '../story_map/story_map_backend.dart';
import '../story_map/story_map_tab.dart';
import '../theme/loremark_theme.dart';
import '../theories/theory_checker.dart';
import 'ask_screen.dart';
import 'notes_screen.dart';
import 'offline_banner.dart';
import 'read_screen.dart';
import 'reader_header.dart';

/// One open book: the Read, Ask, Notes, and Story Map tabs for [book].
class BookScreen extends StatefulWidget {
  const BookScreen({
    super.key,
    required this.book,
    this.storyMapBackend,
    this.checkerFactory,
    this.openNotes,
  });

  final Book book;

  /// Makes the theory checker for the book's notes; tests replace the one
  /// that reads the book file and calls the reader's AI provider.
  final TheoryChecker Function(AnnotationService notes)? checkerFactory;

  /// Opens the book's notes; tests replace the device's files.
  final Future<AnnotationService> Function(String bookId)? openNotes;

  /// Where the Story Map tab gets its data; tests replace the device's.
  final StoryMapBackend? storyMapBackend;

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  static const _notesTab = 2;
  static const _storyMapTab = 3;

  int _selectedTab = 0;
  late final StoryMapBackend _storyMapBackend =
      widget.storyMapBackend ?? DeviceStoryMapBackend();

  /// The book's notes, shared by the Read tab, which adds and draws them, and
  /// the Notes tab, which lists them.
  late final Future<AnnotationService> _notes =
      (widget.openNotes ?? AnnotationService.openForBook)(widget.book.id);

  /// Sends the Read tab to a note tapped in the Notes tab.
  final _noteJumps = NoteJumpController();

  /// Scrolls the Notes tab to one note. [showNoteInNotesTab] uses it.
  final _noteFocus = NoteFocusController();

  /// Opens the Notes tab with the note of the given id scrolled to and
  /// briefly outlined. The theory banner uses this to show a theory.
  void showNoteInNotesTab(String noteId) {
    _selectTab(_notesTab);
    _noteFocus.focus(noteId);
  }

  late AiSettings _ai;
  late ConnectionStatus _connection;
  AnnotationService? _notesService;
  TheoryChecker? _checker;
  StreamSubscription<TheoryStatusChange>? _changes;

  /// Where the reader is and the furthest they got this session, for the
  /// theory checker's spoiler boundary.
  ReaderPosition? _current;
  ReaderPosition? _furthest;
  int _finishedSections = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_startTheoryChecks());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ai = AiSettingsScope.of(context);
    _connection = ConnectionScope.of(context);
  }

  /// Creates the theory checker once the notes open, and runs it. If the
  /// notes fail to open, reading is unaffected and nothing is checked.
  Future<void> _startTheoryChecks() async {
    final AnnotationService notes;
    try {
      notes = await _notes;
    } on Object {
      return;
    }
    if (!mounted) return;
    final checker =
        widget.checkerFactory?.call(notes) ??
        TheoryChecker(
          annotations: notes,
          loadSectionTexts: () => readSectionTexts(widget.book.epubPath),
          credentials: () => _ai.credentials,
          isOnline: () => _connection.isOnline,
        );
    _notesService = notes;
    _checker = checker;
    _changes = checker.changes.listen(_showTheoryBanner);
    notes.addListener(_onNotesChanged);
    _runChecker();
  }

  void _runChecker() {
    unawaited(_checker?.run(current: _current, furthest: _furthest));
  }

  /// A theory that was just saved or edited has no sub-theories yet, so it is
  /// split. The checker's own saves never leave one unsplit, so they don't
  /// start another run.
  void _onNotesChanged() {
    final notes = _notesService;
    if (notes != null &&
        notes.theories.any((note) => note.theory!.subTheories.isEmpty)) {
      _runChecker();
    }
  }

  /// Runs a check when a section was finished since the last one.
  void _onPosition(ReaderPosition position) {
    _current = position;
    _furthest = searchCutoff(current: position, furthest: _furthest);
    final finished = finishedSectionCount(
      current: _current,
      furthest: _furthest,
    );
    if (finished > _finishedSections) {
      _finishedSections = finished;
      _runChecker();
    }
  }

  void _showTheoryBanner(TheoryStatusChange change) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(change.bannerText),
        // Floating, so it sits above the tab bar instead of covering it.
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => showNoteInNotesTab(change.noteId),
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    _notesService?.removeListener(_onNotesChanged);
    _checker?.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    setState(() {
      _selectedTab = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ReaderHeader(
              book: widget.book,
              onOpenLibrary: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Stack(
                children: [
                  IndexedStack(
                    index: _selectedTab,
                    children: [
                      ReadScreen(
                        book: widget.book,
                        readerService: const ReadiumReaderService(),
                        openSearch: () => openPassageSearch(
                          bookId: widget.book.id,
                          epubPath: widget.book.epubPath,
                        ),
                        notes: _notes,
                        noteJumps: _noteJumps,
                        onPositionChanged: _onPosition,
                      ),
                      const AiLock(
                        feature: 'Ask',
                        needsConnection: true,
                        child: AskScreen(),
                      ),
                      // Tapping a note goes back to the Read tab, at its passage.
                      NotesScreen(
                        notes: _notes,
                        focusController: _noteFocus,
                        onOpenNote: (note) {
                          _selectTab(0);
                          unawaited(_noteJumps.show(note));
                        },
                      ),
                      // A map is stored data, so looking at one needs neither
                      // a key nor a connection. Only adding to it does.
                      StoryMapTab(
                        book: widget.book,
                        backend: _storyMapBackend,
                        active: _selectedTab == _storyMapTab,
                      ),
                    ],
                  ),
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: OfflineBanner(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: LoremarkColors.navBorder)),
        ),
        child: NavigationBar(
          selectedIndex: _selectedTab,
          onDestinationSelected: _selectTab,
          // The labels are always showing, so tooltips would only repeat them.
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Read',
              tooltip: '',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: 'Ask',
              tooltip: '',
            ),
            NavigationDestination(
              icon: Icon(Icons.edit_note),
              label: 'Notes',
              tooltip: '',
            ),
            NavigationDestination(
              icon: Icon(Icons.hub_outlined),
              selectedIcon: Icon(Icons.hub),
              label: 'Story Map',
              tooltip: '',
            ),
          ],
        ),
      ),
    );
  }
}
