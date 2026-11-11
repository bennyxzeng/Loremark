import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/reader_header.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/epub_sections.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/settings/connection_status.dart';
import 'package:loremark/story_map/story_map_backend.dart';
import 'package:loremark/story_map/story_map_status.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/story_update/story_updater.dart';

Book _book(String title) => Book(
  id: 'book-1',
  title: title,
  author: null,
  epubPath: '/nowhere.epub',
  coverPath: null,
  importedAt: DateTime.utc(2026),
);

/// Only what the status asks of a backend: documents `c0` to `c5`.
class _Backend implements StoryMapBackend {
  @override
  RunningStoryUpdate? running(Book book) => null;

  @override
  Future<List<SpineItem>> spine(Book book) async => [
    for (var i = 0; i < 6; i++)
      SpineItem(path: 'OEBPS/c$i.xhtml', linear: true),
  ];

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A map of documents 1 and 2.
final _sections = [
  for (final index in [1, 2])
    StorySection(
      id: 's$index',
      order: index,
      chapterNumber: index,
      title: 'Chapter $index',
      href: 'OEBPS/c$index.xhtml',
    ),
];

void main() {
  late StoryMapStatusController status;
  late int libraryTaps;
  late int storyMapTaps;
  late DateTime now;

  setUp(() {
    status = StoryMapStatusController(book: _book('x'), backend: _Backend());
    libraryTaps = 0;
    storyMapTaps = 0;
    now = DateTime.utc(2026);
  });

  tearDown(() => status.dispose());

  Future<void> pumpHeader(
    WidgetTester tester, {
    bool withStatus = true,
    bool online = true,
    String title = 'The Glass Harbor',
  }) async {
    await tester.pumpWidget(
      ConnectionScope(
        status: ConnectionStatus(online: online),
        child: MaterialApp(
          home: Scaffold(
            body: ReaderHeader(
              book: _book(title),
              onOpenLibrary: () => libraryTaps++,
              storyMap: withStatus ? status : null,
              onOpenStoryMap: () => storyMapTaps++,
              now: () => now,
            ),
          ),
        ),
      ),
    );
  }

  /// Puts the reader at document [index], next to the two-section map.
  Future<void> readAt(WidgetTester tester, int index) async {
    status
      ..mapLoaded(_sections)
      ..readerMoved(ReaderPosition(index, 0));
    await tester.pumpAndSettle();
  }

  final libraryIcon = find.byIcon(Icons.local_library_outlined);

  testWidgets('without a status, is just the book', (tester) async {
    await pumpHeader(tester, withStatus: false);
    expect(libraryIcon, findsOne);
    expect(find.byIcon(Icons.hub), findsNothing);
  });

  testWidgets('shows nothing of the map until the page is placed', (
    tester,
  ) async {
    await pumpHeader(tester);
    status.mapLoaded(_sections);
    await tester.pumpAndSettle();
    expect(libraryIcon, findsOne);
    expect(find.byIcon(Icons.hub), findsNothing);
  });

  group('says where the page is:', () {
    for (final (index, label) in [
      (0, 'NOT IN MAP'),
      (1, 'IN MAP'),
      (2, 'IN MAP'),
      (3, 'NEEDS UPDATE'),
    ]) {
      testWidgets('document $index is $label', (tester) async {
        await pumpHeader(tester);
        await readAt(tester, index);
        expect(find.text(label), findsOne);
        expect(libraryIcon, findsNothing);
      });
    }

    testWidgets('no map yet', (tester) async {
      await pumpHeader(tester);
      status.mapLoaded(null);
      await tester.pumpAndSettle();
      expect(find.text('NO MAP YET'), findsOne);
    });

    testWidgets('and follows the reader', (tester) async {
      await pumpHeader(tester);
      await readAt(tester, 2);
      expect(find.text('IN MAP'), findsOne);
      status.readerMoved(const ReaderPosition(3, 0));
      await tester.pumpAndSettle();
      expect(find.text('NEEDS UPDATE'), findsOne);
    });
  });

  group('while updating', () {
    testWidgets('says so, and how long it has run', (tester) async {
      await pumpHeader(tester);
      await readAt(tester, 3);
      status.updateStarted(now);
      await tester.pump();
      expect(find.text('UPDATING'), findsOne);
      expect(find.text('0:00'), findsOne);
      expect(find.text('NEEDS UPDATE'), findsNothing);

      now = now.add(const Duration(seconds: 83));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1:23'), findsOne);

      status.updateEnded();
      await tester.pump();
      expect(find.text('UPDATING'), findsNothing);
      expect(find.text('NEEDS UPDATE'), findsOne);
    });

    testWidgets('shows even before the page is placed', (tester) async {
      await pumpHeader(tester);
      status.updateStarted(now);
      await tester.pump();
      expect(find.text('UPDATING'), findsOne);
      expect(libraryIcon, findsNothing);
      status.updateEnded();
      await tester.pump();
    });

    testWidgets('says when it is being cancelled', (tester) async {
      await pumpHeader(tester);
      status
        ..updateStarted(now)
        ..cancelRequested();
      await tester.pump();
      expect(find.text('CANCELLING'), findsOne);
      status.updateEnded();
      await tester.pump();
    });
  });

  group('tapping', () {
    testWidgets('the status opens the Story Map', (tester) async {
      await pumpHeader(tester);
      await readAt(tester, 1);
      await tester.tap(find.text('IN MAP'));
      expect(storyMapTaps, 1);
      expect(libraryTaps, 0);
    });

    testWidgets('the book still goes back to the library', (tester) async {
      await pumpHeader(tester);
      await readAt(tester, 1);
      await tester.tap(find.text('The Glass Harbor'));
      await tester.tap(find.byIcon(Icons.chevron_left));
      expect(libraryTaps, 2);
      expect(storyMapTaps, 0);
    });
  });

  testWidgets('the status is a button that says what it means', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpHeader(tester);
    await readAt(tester, 3);
    expect(
      find.bySemanticsLabel(
        'Story Map: needs an update to reach this page. Opens the Story Map.',
      ),
      findsOne,
    );
    // The book's title and kicker go with it.
    expect(find.bySemanticsLabel(RegExp('^Library')), findsOne);
    semantics.dispose();
  });

  testWidgets('offline, the chip says so in full until there is a status', (
    tester,
  ) async {
    await pumpHeader(tester, online: false);
    expect(find.text('OFFLINE'), findsOne);
    await readAt(tester, 1);
    expect(find.text('OFFLINE'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Offline')), findsOne);
  });

  testWidgets('a small phone fits the title, offline and updating', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpHeader(
      tester,
      online: false,
      title: 'A very long book title that goes on and on',
    );
    status.updateStarted(now.subtract(const Duration(minutes: 12)));
    await tester.pump();
    // The offline chip makes room: the banner has said what it means.
    expect(find.text('OFFLINE'), findsNothing);
    expect(find.byIcon(Icons.wifi_off), findsOne);
    expect(find.text('UPDATING'), findsOne);
    expect(tester.takeException(), isNull);
    // The title isn't squeezed out, even in the test font, whose letters are
    // all as wide as they are tall.
    expect(
      tester.getSize(find.textContaining('A very long')).width,
      greaterThan(0),
    );
    status.updateEnded();
    await tester.pump();
  });
}
