import 'dart:async';

import 'package:flutter/material.dart';

import '../ask/ask_backend.dart';
import '../ask/ask_controller.dart';
import '../library/book.dart';
import '../notes/annotation_service.dart';
import '../reader/epub_reader_service.dart';
import '../reader/readium_reader_service.dart';
import '../settings/ai_lock.dart';
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

/// One open book: the Read, Ask, Notes, and Story Map tabs for [book].
class BookScreen extends StatefulWidget {
  const BookScreen({
    super.key,
    required this.book,
    this.storyMapBackend,
    this.askBackend,
  });

  final Book book;

  /// Where the Story Map tab gets its data; tests replace the device's.
  final StoryMapBackend? storyMapBackend;

  /// Where the Ask tab gets its data; tests replace the device's.
  final AskBackend? askBackend;

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
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
  StoryUpdateOutcome? _finishedUpdate;
  bool _showsFinishedUpdate = false;
  Timer? _bannerTimer;

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _storyMapStatus.dispose();
    _ask.dispose();
    super.dispose();
  }

  /// Says how an update went, if the reader is somewhere they wouldn't see it.
  /// One they cancelled, they asked for.
  void _updateFinished(StoryUpdateOutcome outcome) {
    if (outcome.status == 'cancelled' || _selectedTab == _storyMapTab) return;
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

  void _selectTab(int index) {
    // The Story Map tab shows how the update went itself.
    if (index == _storyMapTab) _hideFinishedUpdate();
    setState(() {
      _selectedTab = index;
    });
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
