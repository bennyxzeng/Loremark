import 'dart:async';

import 'package:flutter/material.dart';

import '../ask/ask_backend.dart';
import '../ask/ask_controller.dart';
import '../library/book.dart';
import '../notes/annotation_service.dart';
import '../reader/epub_reader_service.dart';
import '../reader/readium_reader_service.dart';
import '../recap/recap_backend.dart';
import '../recap/recap_controller.dart';
import '../recap/recap_source.dart';
import '../settings/ai_lock.dart';
import '../settings/ai_settings.dart';
import '../settings/connection_status.dart';
import '../search/search_index_store.dart';
import '../story_map/story_map_backend.dart';
import '../story_map/story_map_tab.dart';
import '../theme/loremark_theme.dart';
import 'ask_screen.dart';
import 'notes_screen.dart';
import 'offline_banner.dart';
import 'read_screen.dart';
import 'reader_header.dart';
import 'recap_panel.dart';
import 'swipe_hint.dart';
import 'welcome_back_card.dart';

/// One open book: the Read, Ask, Notes, and Story Map tabs for [book].
class BookScreen extends StatefulWidget {
  const BookScreen({
    super.key,
    required this.book,
    this.storyMapBackend,
    this.askBackend,
    this.recapBackend,
  });

  final Book book;

  /// Where the Story Map tab gets its data; tests replace the device's.
  final StoryMapBackend? storyMapBackend;

  /// Where the Ask tab gets its data; tests replace the device's.
  final AskBackend? askBackend;

  /// Where the opening recap gets its data; tests replace the device's.
  final RecapBackend? recapBackend;

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  static const _readTab = 0;
  static const _askTab = 1;
  static const _storyMapTab = 3;

  int _selectedTab = _readTab;
  late final StoryMapBackend _storyMapBackend =
      widget.storyMapBackend ?? DeviceStoryMapBackend();

  /// The Ask conversation. Kept here, above the lock, so going offline and
  /// back doesn't lose a question under way or one being written.
  late final AskController _ask = AskController(
    book: widget.book,
    backend: widget.askBackend ?? DeviceStoryMapBackend(),
  );

  Future<void> _openPassage(PassageTarget target) async {
    _selectTab(_readTab);
    await _noteJumps.showPassage(target);
  }

  /// The book's notes, shared by the Read tab, which adds and draws them, and
  /// the Notes tab, which lists them.
  late final Future<AnnotationService> _notes = AnnotationService.openForBook(
    widget.book.id,
  );

  /// Sends the Read tab to a note tapped in the Notes tab.
  final _noteJumps = NoteJumpController();

  /// Sends the Read tab to a passage behind a recap moment, with a way back to
  /// the reader's page.
  final _passageJumps = PassageJumpController();

  /// The opening recap, shared by the welcome-back pop-up over the Read tab
  /// and the top of the Ask tab, where it shows.
  late final RecapController _recap = RecapController(
    book: widget.book,
    // The Story Map tab's backend, so the recap stops where the map does.
    backend:
        widget.recapBackend ?? DeviceRecapBackend(storyMap: _storyMapBackend),
  );

  /// Whether the recap has looked for the reader's place since the book opened.
  /// It waits for an API key, since there is nothing to offer without one.
  bool _recapLooked = false;

  /// Whether the welcome back was offered, or passed over, for this opening.
  /// It is offered once each time the book opens.
  bool _welcomeOffered = false;

  @override
  void initState() {
    super.initState();
    _recap.addListener(_offerWelcomeBack);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_recapLooked && AiSettingsScope.of(context).hasKey) {
      _recapLooked = true;
      unawaited(_recap.prepare());
    }
  }

  @override
  void dispose() {
    _ask.dispose();
    _recap
      ..removeListener(_offerWelcomeBack)
      ..dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    setState(() {
      _selectedTab = index;
    });
  }

  /// Writes the recap and opens the Ask tab, where it shows at the top.
  void _catchUp(AiCredentials credentials) {
    unawaited(_recap.write(credentials));
    _selectTab(_askTab);
  }

  /// The first time the recap knows where the reader stopped after the book
  /// opens, pops up the welcome back over the Read tab: once the reader has
  /// read some of what the Story Map covers and a recap could be written right
  /// now.
  void _offerWelcomeBack() {
    if (_welcomeOffered || !_recap.prepared || !mounted) return;
    _welcomeOffered = true;
    final source = _recap.source;
    if (source == null ||
        _selectedTab != _readTab ||
        !AiSettingsScope.of(context).hasKey ||
        !ConnectionScope.of(context).isOnline ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    unawaited(_welcomeBack(source));
  }

  Future<void> _welcomeBack(RecapSource source) async {
    final catchUp = await showWelcomeBack(
      context,
      sectionTitle: source.sectionTitle,
      partway: source.partway,
    );
    if (!catchUp) return;
    if (!mounted) return;
    final credentials = AiSettingsScope.of(context).credentials;
    if (credentials != null) _catchUp(credentials);
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
                      SwipeHint(
                        child: ReadScreen(
                          book: widget.book,
                          readerService: const ReadiumReaderService(),
                          openSearch: () => openPassageSearch(
                            bookId: widget.book.id,
                            epubPath: widget.book.epubPath,
                          ),
                          notes: _notes,
                          noteJumps: _noteJumps,
                          passageJumps: _passageJumps,
                        ),
                      ),
                      AiLock(
                        feature: 'Ask',
                        needsConnection: true,
                        child: AskScreen(
                          controller: _ask,
                          active: _selectedTab == _askTab,
                          onOpenStoryMap: () => _selectTab(_storyMapTab),
                          onOpenPassage: _openPassage,
                          // The welcome-back recap, above the conversation,
                          // so a follow-up question is right below it.
                          recap: RecapPanel(
                            controller: _recap,
                            active: _selectedTab == _askTab,
                            onBackToBook: () => _selectTab(_readTab),
                            onOpenStoryMap: () => _selectTab(_storyMapTab),
                            // A recap's passage opens in the Read tab, with a
                            // way back to the reader's page.
                            onOpenPassage: (target) {
                              _selectTab(_readTab);
                              unawaited(_passageJumps.show(target));
                            },
                          ),
                        ),
                      ),
                      // Tapping a note goes back to the Read tab, at its passage.
                      NotesScreen(
                        notes: _notes,
                        onOpenNote: (note) {
                          _selectTab(_readTab);
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
