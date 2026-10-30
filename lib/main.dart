import 'package:flutter/material.dart';

import 'notes/annotation_service.dart';
import 'notes/note_passage.dart';
import 'notes/note_repository.dart';
import 'notes/notes_screen.dart';
import 'story_map/story_map_screen.dart';
import 'story_model/story_model.dart';
import 'story_model/story_model_loader.dart';

void main() {
  runApp(const LoremarkApp());
}

class LoremarkApp extends StatelessWidget {
  const LoremarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Loremark',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF68734D),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8F5ED),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF8F5ED),
          centerTitle: false,
        ),
      ),
      home: const LoremarkHome(),
    );
  }
}

class LoremarkHome extends StatefulWidget {
  const LoremarkHome({super.key});

  @override
  State<LoremarkHome> createState() => _LoremarkHomeState();
}

class _LoremarkHomeState extends State<LoremarkHome> {
  int _selectedTab = 0;
  late final Future<StoryModel> _storyModel = loadStoryModel(
    demoStoryModelAsset,
  );

  /// This is the id of the sample book until books can be imported.
  static const _sampleBookId = 'glass-harbor';

  /// This loads the saved notes of the sample book once, for the Read and Notes tabs.
  late final Future<AnnotationService> _notes = _openNotes();

  static Future<AnnotationService> _openNotes() async {
    final service = AnnotationService(
      bookId: _sampleBookId,
      repository: await NoteRepository.forBook(_sampleBookId),
    );
    await service.load();
    return service;
  }

  void _selectTab(int index) {
    setState(() {
      _selectedTab = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loremark')),
      body: SafeArea(
        child: IndexedStack(
          index: _selectedTab,
          children: [
            _buildReadScreen(),
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Sample recap · Chapter 8\n\n'
                  'Elian’s letter revealed that he and Mara are siblings.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            _buildNotesTab(),
            _buildStoryMapTab(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            label: 'Read',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Ask',
          ),
          NavigationDestination(icon: Icon(Icons.edit_note), label: 'Notes'),
          NavigationDestination(
            icon: Icon(Icons.hub_outlined),
            label: 'Story Map',
          ),
        ],
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

  Widget _buildReadScreen() {
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Welcome back, Susan', style: textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Ready to return to your story?'),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Glass Harbor', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('Sample book · Chapter 8'),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => _selectTab(1),
                  icon: const Icon(Icons.auto_stories),
                  label: const Text('Recap where I left off'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Chapter 8', style: textTheme.titleLarge),
        const SizedBox(height: 16),
        _buildSamplePassage(),
      ],
    );
  }

  /// This builds the Notes tab once the saved notes are loaded.
  /// Tapping a note goes back to the Read tab. Jumping to the exact passage
  /// will be added together with the Readium reader.
  Widget _buildNotesTab() {
    return FutureBuilder<AnnotationService>(
      future: _notes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not open your notes.'));
        }
        final service = snapshot.data;
        if (service == null) {
          return const Center(child: Text('Loading notes…'));
        }
        return NotesScreen(service: service, onOpenNote: (_) => _selectTab(0));
      },
    );
  }

  /// This builds the sample passage. Once the notes are loaded, the reader can
  /// select words in it to add a highlight or a note.
  Widget _buildSamplePassage() {
    const passage =
        'He pushed the letter across the table. '
        '“You’re my sister, Mara. You should have trusted me.”';
    const style = TextStyle(fontSize: 18, height: 1.7);

    return FutureBuilder<AnnotationService>(
      future: _notes,
      builder: (context, snapshot) {
        final service = snapshot.data;
        if (service == null) return const Text(passage, style: style);
        return NotePassage(
          service: service,
          text: passage,
          sectionIndex: 7,
          chapterLabel: 'Chapter 8',
          style: style,
        );
      },
    );
  }
}
