// Start-to-finish tests: they run the real app on a device or emulator, with
// the real EPUB reader, and tap through it like a person would.
//
//   flutter test integration_test -d <device id>
//
// Only three things are replaced, so the tests need no files, keys or network:
// the file picker (returns a generated book), the key store (kept in memory)
// and the API key check (answers by itself). See docs/testing.md.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:loremark/library/book_repository.dart';
import 'package:loremark/main.dart';
import 'package:loremark/settings/ai_settings.dart';
import 'package:loremark/settings/connection_status.dart';

import '../test/support/synthetic_book.dart';

// Unique words, so a search can tell which chapter's text it found.
const _inFirstChapter = 'Zephyrquill kept the lantern.';
const _inLastChapter = 'Ravenhollow kept the lantern.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late String epubPath;
  late BookRepository repository;
  late ConnectionStatus connection;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('loremark_e2e_');
    // A new seed every run gives a new book id, so reading positions and notes
    // saved by an earlier run on the same device cannot leak into this one.
    final seed = DateTime.now().microsecondsSinceEpoch % 1000000;
    final file = File('${temp.path}/book.epub');
    await file.writeAsBytes(
      buildSyntheticBook(
        chapters: 3,
        wordsPerChapter: 1500,
        seed: seed,
        title: 'The Test Harbor',
        markers: {0: _inFirstChapter, 2: _inLastChapter},
      ),
    );
    epubPath = file.path;
    repository = BookRepository(Directory('${temp.path}/library'));
    connection = ConnectionStatus();
  });

  tearDown(() => temp.delete(recursive: true));

  /// Starts the app. [store] is what the keychain holds; [keyCheck] is what
  /// the AI provider would answer when a key is saved.
  Future<void> launch(
    WidgetTester tester, {
    Map<String, String>? store,
    KeyCheck keyCheck = KeyCheck.valid,
  }) async {
    final settings = AiSettings(
      MemorySecretStore(store),
      verify: (provider, key) async => keyCheck,
    );
    await settings.load();
    await tester.pumpWidget(
      LoremarkApp(
        repository: Future.value(repository),
        settings: Future.value(settings),
        connection: connection,
        pickEpub: () async => epubPath,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Waits for [finder], pumping real time. The reader draws on the device,
  /// so some screens take a few seconds and `pumpAndSettle` cannot be used.
  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    int seconds = 120,
  }) async {
    for (var i = 0; i < seconds * 4; i++) {
      if (finder.evaluate().isNotEmpty) return;
      await tester.pump(const Duration(milliseconds: 250));
    }
    fail('Timed out after $seconds s waiting for $finder');
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> openTab(WidgetTester tester, String label) => tap(
    tester,
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );

  Future<void> importBook(WidgetTester tester) async {
    await tap(tester, find.text('Import EPUB'));
    // The reader view appears once the book is unpacked and drawn.
    await waitFor(tester, find.byKey(const ValueKey('progress-label')));
  }

  Future<void> skipKeyScreen(WidgetTester tester) async {
    await tap(tester, find.text('Skip for now'));
    await tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Skip for now'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> saveKey(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), 'sk-test-key');
    await tester.pump();
    await tap(tester, find.text('Save key'));
    await waitFor(tester, find.text('Import EPUB'));
  }

  String progress(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('progress-label'))).data ??
      '';

  Finder searchHits() => find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey && '${key.value}'.startsWith('search-hit-');
  });

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byKey(const ValueKey('search-field')), query);
    await tester.pump();
  }

  testWidgets('a reader without an API key can import, read, search and '
      'see notes, while Ask and Story Map stay locked', (tester) async {
    await launch(tester);

    // First launch asks for a key; the reader skips it.
    expect(find.text('Connect an AI provider'), findsOne);
    await skipKeyScreen(tester);
    expect(find.text('Books'), findsOne);

    // Import opens the book in the reader.
    await importBook(tester);
    expect(repository.books, hasLength(1));
    expect(find.text('CURRENTLY READING'), findsOne);
    final start = progress(tester);

    // Turning pages moves the reading position.
    for (var i = 0; i < 3; i++) {
      await tap(tester, find.byTooltip('Next page'));
      await tester.pump(const Duration(seconds: 1));
    }
    await waitFor(tester, find.byKey(const ValueKey('progress-label')));
    expect(progress(tester), isNot(start));

    // Search finds text the reader has passed...
    await tap(tester, find.byTooltip('Search'));
    await waitFor(tester, find.byKey(const ValueKey('search-field')));
    await search(tester, 'Zephyrquill');
    await waitFor(tester, searchHits());

    // ...and says nothing about text further on, not even that it exists.
    await search(tester, 'Ravenhollow');
    await waitFor(tester, find.byKey(const ValueKey('search-empty')));
    expect(searchHits(), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // Notes starts empty.
    await openTab(tester, 'Notes');
    expect(
      find.text(
        'No notes yet.\nYour notes and highlights for this book '
        'will appear here.',
      ),
      findsOne,
    );

    // Without a key, the AI tabs are locked.
    await openTab(tester, 'Ask');
    expect(find.text('Ask needs an API key'), findsOne);
    await openTab(tester, 'Story Map');
    expect(find.text('Story Map needs an API key'), findsOne);

    // Back to the library, where the book is now the last one opened.
    await openTab(tester, 'Read');
    await tap(tester, find.text('CURRENTLY READING'));
    await tester.pumpAndSettle();
    expect(find.text('LAST OPENED'), findsOne);
  });

  testWidgets('a rejected API key keeps the reader on the key screen', (
    tester,
  ) async {
    await launch(tester, keyCheck: KeyCheck.rejected);

    await tester.enterText(find.byType(TextField), 'sk-wrong');
    await tester.pump();
    await tap(tester, find.text('Save key'));
    await tester.pumpAndSettle();

    expect(find.text('Connect an AI provider'), findsOne);
    expect(find.text('Books'), findsNothing);
  });

  testWidgets('a valid API key unlocks Ask and Story Map', (tester) async {
    await launch(tester);
    await saveKey(tester);
    await importBook(tester);

    await openTab(tester, 'Ask');
    expect(find.text('Where we left off.'), findsOne);
    expect(find.text('Ask needs an API key'), findsNothing);

    await openTab(tester, 'Story Map');
    await waitFor(tester, find.textContaining('Known by the end of'));
    expect(find.byType(Slider), findsOne);
    expect(find.text('Story Map needs an API key'), findsNothing);
  });

  testWidgets('offline, Ask locks but Story Map stays readable, and Ask '
      'unlocks again when the connection returns', (tester) async {
    await launch(tester);
    await saveKey(tester);
    await importBook(tester);

    connection.isOnline = false;
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('You’re offline'), findsOne);

    await openTab(tester, 'Ask');
    expect(find.text('Ask needs a connection'), findsOne);

    await openTab(tester, 'Story Map');
    await waitFor(tester, find.textContaining('Known by the end of'));
    expect(find.text('Story Map needs a connection'), findsNothing);

    connection.isOnline = true;
    await tester.pump(const Duration(milliseconds: 500));
    await openTab(tester, 'Ask');
    expect(find.text('Where we left off.'), findsOne);
  });
}
