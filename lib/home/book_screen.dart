import 'dart:async';

import 'package:flutter/material.dart';

import '../ask/ask_backend.dart';
import '../ask/ask_controller.dart';
import '../library/book.dart';
import '../notes/annotation_service.dart';
import '../notes/note_list.dart';
import '../reader/epub_reader_service.dart';
import '../reader/readium_reader_service.dart';
import '../recap/recap_backend.dart';
import '../recap/recap_controller.dart';
import '../recap/recap_stop.dart';
import '../settings/ai_lock.dart';
import '../settings/ai_settings.dart';
import '../settings/connection_status.dart';
import '../search/search_index_store.dart';
import '../story_map/story_map_backend.dart';
import '../story_map/story_map_status.dart';
import '../story_map/story_map_tab.dart';
import '../story_update/story_updater.dart';
import '../theme/loremark_theme.dart';
import 'ask_screen.dart';
import 'eased_keyboard.dart';
import 'notes_screen.dart';
import 'offline_banner.dart';
import 'read_screen.dart';
import 'reader_header.dart';
import 'story_update_banner.dart';
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

  /// Where the welcome back finds where the reader stopped; tests replace the
  /// device's.
  final RecapBackend? recapBackend;

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  static const _notesTab = 2;
  static const _readTab = 0;
  static const _askTab = 1;
  static const _storyMapTab = 3;

  int _selectedTab = 0;
  late final StoryMapBackend _storyMapBackend =
      widget.storyMapBackend ?? DeviceStoryMapBackend();

  /// The Ask conversation. Kept here, above the lock, so going offline and
  /// back doesn't lose a question under way or one being written.
  late final AskController _ask = AskController(
    book: widget.book,
    backend: widget.askBackend ?? DeviceStoryMapBackend(),
  );

  /// The Story Map's update under way and where the reader is next to the map,
  /// for the header to show from every tab.
  late final StoryMapStatusController _storyMapStatus =
      StoryMapStatusController(book: widget.book, backend: _storyMapBackend);

  /// How long a finished update's banner stays.
  static const _bannerTime = Duration(seconds: 6);

  /// The last update that ended away from the Story Map tab, kept while its
  /// banner slides away too.
  StoryBatchOutcome? _finishedUpdate;
  bool _showsFinishedUpdate = false;
  Timer? _bannerTimer;

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _storyMapStatus.dispose();
    _ask.dispose();
    _noteFocus.dispose();
    _recap
      ..removeListener(_offerWelcomeBack)
      ..dispose();
    super.dispose();
  }

  /// Says how an update went, if the reader is somewhere they wouldn't see it.
  /// One they cancelled, they asked for.
  void _updateFinished(StoryBatchOutcome outcome) {
    if (outcome.cancelled || _selectedTab == _storyMapTab) return;
    _bannerTimer?.cancel();
    _bannerTimer = Timer(_bannerTime, _hideFinishedUpdate);
    setState(() {
      _finishedUpdate = outcome;
      _showsFinishedUpdate = true;
    });
  }

  void _hideFinishedUpdate() {
    _bannerTimer?.cancel();
    if (!mounted || !_showsFinishedUpdate) return;
    setState(() => _showsFinishedUpdate = false);
  }

  /// Opens a passage an answer cites in the Read tab, with **Back to your
  /// page** to return to where the reader was.
  Future<void> _openPassage(PassageTarget target) async {
    _selectTab(_readTab);
    await _passageJumps.show(target);
  }

  /// The book's notes, shared by the Read tab, which adds and draws them, and
  /// the Notes tab, which lists them.
  late final Future<AnnotationService> _notes = AnnotationService.openForBook(
    widget.book.id,
  );

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

  /// Sends the Read tab to a passage an Ask answer cites, with a way back to
  /// the reader's page.
  final _passageJumps = PassageJumpController();

  /// Where the reader stopped, for the welcome-back pop-up.
  late final RecapController _recap = RecapController(
    book: widget.book,
    // The Story Map tab's backend, so the pop-up names the place the map
    // shows up to.
    backend:
        widget.recapBackend ?? DeviceRecapBackend(storyMap: _storyMapBackend),
  );

  /// Whether the pop-up has looked for the reader's place since the book
  /// opened. It waits for an API key, since there is nothing to offer without
  /// one.
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

  void _selectTab(int index) {
    // The Story Map tab shows how the update went itself.
    if (index == _storyMapTab) _hideFinishedUpdate();
    setState(() {
      _selectedTab = index;
    });
  }

  /// Opens the Ask tab on a new conversation that starts with a recap, so the
  /// reader can ask more about it there.
  void _catchUp(AiSettings settings, AiCredentials credentials) {
    unawaited(
      _ask.catchUp(
        credentials: credentials,
        model: settings.chatModel,
        effort: settings.chatEffort,
      ),
    );
    _selectTab(_askTab);
  }

  /// The first time the recap knows where the reader stopped after the book
  /// opens, pops up the welcome back over the Read tab: once the reader has
  /// read some of what the Story Map covers and a recap could be written right
  /// now.
  void _offerWelcomeBack() {
    if (_welcomeOffered || !_recap.prepared || !mounted) return;
    _welcomeOffered = true;
    final stop = _recap.stop;
    if (stop == null ||
        _selectedTab != _readTab ||
        !AiSettingsScope.of(context).hasKey ||
        !ConnectionScope.of(context).isOnline ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    unawaited(_welcomeBack(stop));
  }

  Future<void> _welcomeBack(RecapStop stop) async {
    final catchUp = await showWelcomeBack(
      context,
      sectionTitle: stop.sectionTitle,
      partway: stop.partway,
    );
    if (!catchUp) return;
    if (!mounted) return;
    final settings = AiSettingsScope.of(context);
    final credentials = settings.credentials;
    if (credentials != null) _catchUp(settings, credentials);
  }

  @override
  Widget build(BuildContext context) {
    return EasedKeyboard(
      // The tab bar, which keeps the home indicator's room under it.
      bar:
          (NavigationBarTheme.of(context).height ?? 80) +
          MediaQuery.viewPaddingOf(context).bottom,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              ReaderHeader(
                book: widget.book,
                onOpenLibrary: () => Navigator.of(context).maybePop(),
                storyMap: _storyMapStatus,
                onOpenStoryMap: () => _selectTab(_storyMapTab),
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
                            onPositionChanged: _storyMapStatus.readerMoved,
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
                          ),
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
                          status: _storyMapStatus,
                          onKeepReading: () => _selectTab(_readTab),
                          onUpdateFinished: _updateFinished,
                        ),
                      ],
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _TopBanners(
                        storyUpdate: StoryUpdateBanner(
                          outcome: _finishedUpdate,
                          visible: _showsFinishedUpdate,
                          onView: () => _selectTab(_storyMapTab),
                          onDismiss: _hideFinishedUpdate,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _KeepsHomeIndicatorRoom(
          child: DecoratedBox(
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
        ),
      ),
    );
  }
}

/// The banners over the top of the tabs, the offline one first. A hidden one
/// gives up its room, so the one under it moves up rather than leave a gap.
class _TopBanners extends StatelessWidget {
  const _TopBanners({required this.storyUpdate});

  final Widget storyUpdate;

  @override
  Widget build(BuildContext context) {
    final offline = ConnectionScope.of(context).showOfflineBanner;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The banner slides away by itself; this only takes back its room.
        TweenAnimationBuilder<double>(
          tween: Tween(end: offline ? 1 : 0),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          builder: (context, room, child) => Align(
            alignment: Alignment.topCenter,
            heightFactor: room,
            child: child,
          ),
          child: const OfflineBanner(),
        ),
        storyUpdate,
      ],
    );
  }
}

/// Keeps the room for an iPhone's home indicator under [child], the tab bar,
/// while the keyboard covers it.
///
/// With the keyboard up the bottom padding is 0, the keyboard being over the
/// home indicator. The bar would lose that room as the keyboard comes and get
/// it back only once it's all the way down; in between, the page, which ends
/// at the keyboard or the bar, whichever is higher, would drop below where it
/// rests and spring back up. Under the keyboard, the room isn't seen.
class _KeepsHomeIndicatorRoom extends StatelessWidget {
  const _KeepsHomeIndicatorRoom({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(bottom: media.viewPadding.bottom),
      ),
      child: child,
    );
  }
}
