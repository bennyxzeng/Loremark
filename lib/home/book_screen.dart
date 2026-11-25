import 'dart:async';

import 'package:flutter/material.dart';

import '../ask/ask_backend.dart';
import '../ask/ask_controller.dart';
import '../library/book.dart';
import '../notes/annotation_service.dart';
import '../reader/epub_reader_service.dart';
import '../reader/reader_position.dart';
import '../reader/reading_position_store.dart';
import '../reader/readium_reader_service.dart';
import '../reading/jump_confirmation.dart';
import '../reading/reading_progress_tracker.dart';
import '../reading/text_position.dart';
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
import 'boundary_bar.dart';
import 'eased_keyboard.dart';
import 'notes_screen.dart';
import 'offline_banner.dart';
import 'read_screen.dart';
import 'skipped_ahead_button.dart';
import 'reader_header.dart';
import 'story_update_banner.dart';
import 'swipe_hint.dart';
import 'welcome_back_card.dart';

/// One open book: the Read, Ask, Notes, and Story Map tabs for [book].
class BookScreen extends StatefulWidget {
  const BookScreen({
    super.key,
    required this.book,
    this.readerService = const ReadiumReaderService(),
    this.openPositionStore = ReadingPositionStore.open,
    this.storyMapBackend,
    this.askBackend,
    this.recapBackend,
    this.now = DateTime.now,
  });

  final Book book;

  /// Shows the book in the Read tab; tests replace the native reader.
  final EpubReaderService readerService;

  /// Opens where the reading position and how far the reader has read are
  /// saved; tests replace the device's.
  final Future<ReadingPositionStore> Function() openPositionStore;

  /// Where the Story Map tab gets its data; tests replace the device's.
  final StoryMapBackend? storyMapBackend;

  /// Where the Ask tab gets its data; tests replace the device's.
  final AskBackend? askBackend;

  /// Where the welcome back finds where the reader stopped; tests replace the
  /// device's.
  final RecapBackend? recapBackend;

  /// When the reader turns a page, to tell reading from flipping through;
  /// tests replace the clock.
  final DateTime Function() now;

  /// The books whose welcome back has popped up since the app started. Each
  /// book offers it once a session: after that, a recap is a question away in
  /// Ask.
  static final _welcomed = <String>{};

  /// Forgets which books have welcomed the reader back, as if the app had just
  /// started.
  @visibleForTesting
  static void forgetWelcomes() => _welcomed.clear();

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
  StoryBatchOutcome? _finishedUpdate;
  bool _showsFinishedUpdate = false;
  Timer? _bannerTimer;

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _place.dispose();
    _storyMapStatus.dispose();
    _ask.dispose();
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
  final _readerSelection = ReaderSelectionController();

  /// Sends the Read tab to a passage an Ask answer cites, with a way back to
  /// the reader's page.
  final _passageJumps = PassageJumpController();

  /// Sends the Read tab back to where the reader was before a jump.
  final _positionJumps = PositionJumpController();

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
  /// It is offered at most once each time the book opens, and only if it
  /// hasn't popped up for this book yet this session.
  bool _welcomeOffered = false;

  /// How far the reader has read, so a jump ahead doesn't count as read until
  /// they say so. Null until it loads, and for good if the store can't be
  /// read.
  ReadingProgressTracker? _progress;
  late ReadingPositionStore _progressStore;

  /// Where and when the reader moved before [_progress] loaded, checked once
  /// it has.
  ({ReaderPosition position, DateTime at})? _movedBeforeLoad;

  /// What the bar by the page count shows: how far into the book the boundary
  /// and the reader are, and whether the reader jumped past the boundary and
  /// is still there, which also shows the Skipped ahead button. Only they
  /// listen, so the reader isn't rebuilt on every page. Null until
  /// [_progress] loads.
  final _place =
      ValueNotifier<({double? boundary, double? current, bool ahead})?>(null);

  @override
  void initState() {
    super.initState();
    _recap.addListener(_offerWelcomeBack);
    unawaited(_loadProgress());
  }

  Future<void> _loadProgress() async {
    final ReadingProgressTracker progress;
    try {
      _progressStore = await widget.openPositionStore();
      progress = await loadTracker(_progressStore, widget.book.id);
    } on Object catch (error) {
      // The book still reads; the boundary just stays where it was saved.
      debugPrint(
        'Could not load how far ${widget.book.title} was read: $error',
      );
      return;
    }
    if (!mounted) return;
    _progress = progress;
    // A book left past the boundary shows that on the bar, without asking
    // again.
    _showPlace(progress);
    final moved = _movedBeforeLoad;
    _movedBeforeLoad = null;
    if (moved != null) _trackProgress(progress, moved.position, moved.at);
  }

  void _readerMoved(ReaderPosition position) {
    _storyMapStatus.readerMoved(position);
    final at = widget.now();
    final progress = _progress;
    if (progress == null) {
      _movedBeforeLoad = (position: position, at: at);
    } else {
      _trackProgress(progress, position, at);
    }
  }

  /// Moves the boundary with the reader and saves it when it or the furthest
  /// position changes. A jump too far ahead is asked about once, as it
  /// happens; reading on past it only shows on the bar. So do pages flipped
  /// through, since the reader knows they flipped.
  void _trackProgress(
    ReadingProgressTracker progress,
    ReaderPosition position,
    DateTime at,
  ) {
    final furthest = progress.furthest;
    final boundary = progress.boundary;
    final wasAhead = progress.pendingJump != null;
    progress.updatePosition(
      TextPosition(position.sectionIndex, position.progression),
      sectionPages: position.sectionPages,
      totalProgression: position.totalProgression,
      at: at,
    );
    if (progress.furthest != furthest || progress.boundary != boundary) {
      unawaited(_saveProgress(progress));
    }
    _showPlace(progress);
    if (!wasAhead && progress.pendingJump != null && !progress.flippedAhead) {
      unawaited(_confirmJump());
    }
  }

  Future<void> _confirmJump() async {
    final answer = await confirmSkippedChapters(context);
    if (!mounted) return;
    switch (answer) {
      case JumpAnswer.countAsRead:
        _countAsRead();
      case JumpAnswer.goBack:
        _goBack();
      case JumpAnswer.keepReading:
        break;
    }
  }

  void _showPlace(ReadingProgressTracker progress) {
    _place.value = (
      boundary: progress.boundaryTotal,
      current: progress.currentTotal,
      ahead: progress.pendingJump != null,
    );
  }

  /// The bar by the page count, and while the reader is ahead of the
  /// boundary, the Skipped ahead button beside it. Both ask again about the
  /// jump.
  Widget _progressBar(({double? boundary, double? current, bool ahead}) place) {
    final bar = BoundaryBar(
      boundary: place.boundary,
      current: place.current,
      ahead: place.ahead,
      onTap: place.ahead ? () => unawaited(_confirmJump()) : null,
    );
    if (!place.ahead) return bar;
    return Row(
      children: [
        Expanded(child: bar),
        const SizedBox(width: 8),
        SkippedAheadButton(onPressed: () => unawaited(_confirmJump())),
      ],
    );
  }

  void _countAsRead() {
    final progress = _progress!;
    progress.confirmJump();
    _showPlace(progress);
    unawaited(_saveProgress(progress));
  }

  /// Once the reader is there, behind the boundary, the jump is dropped. If
  /// going back fails, it still waits.
  void _goBack() {
    final from = _progress!.jumpedFrom;
    unawaited(
      _positionJumps.goTo(ReaderPosition(from.sectionIndex, from.progression)),
    );
  }

  Future<void> _saveProgress(ReadingProgressTracker progress) async {
    try {
      await _progressStore.saveProgress(
        widget.book.id,
        furthest: progress.furthest,
        boundary: progress.boundary,
        boundaryTotal: progress.boundaryTotal,
      );
    } on Object catch (error) {
      debugPrint(
        'Could not save how far ${widget.book.title} was read: $error',
      );
    }
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
    // The Read tab stays alive behind the others, and on Android the menu over
    // selected text is drawn above the whole app. So leaving the Read tab
    // clears the selection, which closes the menu (issue #99).
    if (_selectedTab == _readTab && index != _readTab) {
      unawaited(_readerSelection.clear());
    }
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
        BookScreen._welcomed.contains(widget.book.id) ||
        _selectedTab != _readTab ||
        !AiSettingsScope.of(context).hasKey ||
        !ConnectionScope.of(context).isOnline ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    unawaited(_welcomeBack(stop));
  }

  Future<void> _welcomeBack(RecapStop stop) async {
    // Counted only once it has really popped up: an opening that passed it
    // over, offline say, leaves it for the next.
    BookScreen._welcomed.add(widget.book.id);
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
                            readerService: widget.readerService,
                            openPositionStore: widget.openPositionStore,
                            openSearch: () => openPassageSearch(
                              bookId: widget.book.id,
                              epubPath: widget.book.epubPath,
                            ),
                            notes: _notes,
                            noteJumps: _noteJumps,
                            selection: _readerSelection,
                            passageJumps: _passageJumps,
                            positionJumps: _positionJumps,
                            onPositionChanged: _readerMoved,
                            progressBar: ValueListenableBuilder(
                              valueListenable: _place,
                              builder: (context, place, _) => place == null
                                  ? const SizedBox.shrink()
                                  : _progressBar(place),
                            ),
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
