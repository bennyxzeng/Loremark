import 'package:flutter/material.dart';

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
            const Center(
              child: Text('Your notes and theories will appear here.'),
            ),
            const Center(
              child: Text('Your character relationships will appear here.'),
            ),
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
        const Text(
          'He pushed the letter across the table. '
          '“You’re my sister, Mara. You should have trusted me.”',
          style: TextStyle(fontSize: 18, height: 1.7),
        ),
      ],
    );
  }
}
