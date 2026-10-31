import 'package:flutter/material.dart';

import '../library/book.dart';
import '../story_map/story_map_screen.dart';
import '../story_model/story_model.dart';
import '../story_model/story_model_loader.dart';
import '../theme/loremark_theme.dart';
import 'ask_screen.dart';
import 'notes_screen.dart';
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
              child: IndexedStack(
                index: _selectedTab,
                children: [
                  ReadScreen(book: widget.book),
                  const AskScreen(),
                  const NotesScreen(),
                  _buildStoryMapTab(),
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
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Read',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: 'Ask',
            ),
            NavigationDestination(icon: Icon(Icons.edit_note), label: 'Notes'),
            NavigationDestination(
              icon: Icon(Icons.hub_outlined),
              selectedIcon: Icon(Icons.hub),
              label: 'Story Map',
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
