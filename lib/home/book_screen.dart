import 'dart:async';

import 'package:flutter/material.dart';

import '../library/book.dart';
import '../notes/annotation_service.dart';
import '../reader/readium_reader_service.dart';
import '../settings/ai_lock.dart';
import '../search/search_index_store.dart';
import '../story_map/story_map_screen.dart';
import '../story_model/story_model.dart';
import '../story_model/story_model_loader.dart';
import '../theme/loremark_theme.dart';
import 'ask_screen.dart';
import 'notes_screen.dart';
import 'offline_banner.dart';
import 'read_screen.dart';
import 'reader_header.dart';

/// One open book: the Read, Ask, Notes, and Story Map tabs for [book].
class BookScreen extends StatefulWidget {
  const BookScreen({super.key, required this.book});

  final Book book;

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  int _selectedTab = 0;
  late final Future<StoryModel> _storyModel = loadStoryModel(
    demoStoryModelAsset,
  );

  /// The book's notes, shared by the Read tab, which adds and draws them, and
  /// the Notes tab, which lists them.
  late final Future<AnnotationService> _notes = AnnotationService.openForBook(
    widget.book.id,
  );

  /// Sends the Read tab to a note tapped in the Notes tab.
  final _noteJumps = NoteJumpController();

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
                      ),
                      const AiLock(
                        feature: 'Ask',
                        needsConnection: true,
                        child: AskScreen(),
                      ),
                      // Tapping a note goes back to the Read tab, at its passage.
                      NotesScreen(
                        notes: _notes,
                        onOpenNote: (note) {
                          _selectTab(0);
                          unawaited(_noteJumps.show(note));
                        },
                      ),
                      // A built map is stored data, so it stays readable offline.
                      AiLock(feature: 'Story Map', child: _buildStoryMapTab()),
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

  Widget _buildStoryMapTab() {
    return FutureBuilder<StoryModel>(
      future: _storyModel,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load the story model.\n${snapshot.error}'),
            ),
          );
        }
        final model = snapshot.data;
        // Plain text rather than a spinner: an endless animation would keep
        // widget tests from settling.
        if (model == null) {
          return const Center(child: Text('Loading story model…'));
        }
        return StoryMapScreen(model: model);
      },
    );
  }
}
