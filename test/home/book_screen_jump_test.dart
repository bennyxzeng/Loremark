import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/book_screen.dart';
import 'package:loremark/home/boundary_bar.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/reader/reading_position_store.dart';
import 'package:loremark/reading/text_position.dart';
import 'package:loremark/settings/ai_settings.dart';
import 'package:loremark/settings/connection_status.dart';
import 'package:loremark/story_map/story_map_backend.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/story_update/story_updater.dart';
import 'package:loremark/theme/loremark_theme.dart';

import 'fake_epub_reader_service.dart';

/// A book with no Story Map, on a tab that isn't open.
class _StoryMapBackend implements StoryMapBackend {
  @override
  Future<StoryModel?> loadModel(Book book) async => null;

  @override
  RunningStoryBatch? running(Book book) => null;

  @override
  Future<bool> introSeen() async => true;

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A store whose saved progress is read only once [gate] completes.
class _SlowStore extends FakeReadingPositionStore {
  final gate = Completer<void>();

  @override
  Future<SavedProgress?> loadProgress(String bookId) async {
    await gate.future;
    return super.loadProgress(bookId);
  }
}

void main() {
  final book = Book(
    id: 'book-1',
    title: 'The Glass Harbor',
    author: null,
    epubPath: 'unused.epub',
    coverPath: null,
    importedAt: DateTime(2026),
  );
  const read = TextPosition(1, 0.5);

  late FakeEpubReaderService reader;
  late FakeReadingPositionStore store;

  setUp(() {
    reader = FakeEpubReaderService();
    store = FakeReadingPositionStore()
      ..progress[book.id] = (
        furthest: read,
        boundary: read,
        boundaryTotal: 0.2,
      );
  });

  Future<void> pumpBook(
    WidgetTester tester, {
    Future<ReadingPositionStore> Function()? openPositionStore,
  }) async {
    final settings = AiSettings(
      MemorySecretStore({'ai_onboarding_seen': 'true'}),
    );
    await settings.load();
    await tester.pumpWidget(
      AiSettingsScope(
        settings: settings,
        child: ConnectionScope(
          status: ConnectionStatus(),
          child: MaterialApp(
            home: BookScreen(
              book: book,
              readerService: reader,
              openPositionStore: openPositionStore ?? () async => store,
              storyMapBackend: _StoryMapBackend(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> moveTo(WidgetTester tester, ReaderPosition position) async {
    reader.sessions.single.emit(position);
    await tester.pumpAndSettle();
  }

  const banner = 'You’re ahead of where you’ve read';

  testWidgets('reading on moves the boundary with no banner', (tester) async {
    await pumpBook(tester);
    await moveTo(tester, const ReaderPosition(2, 0.1, totalProgression: 0.3));
    expect(find.text(banner), findsNothing);
    expect(store.progressSaves.last, (
      book.id,
      const TextPosition(2, 0.1),
      const TextPosition(2, 0.1),
      0.3,
    ));
  });

  testWidgets('going back shows no banner and saves nothing', (tester) async {
    await pumpBook(tester);
    await moveTo(tester, const ReaderPosition(0, 0.3));
    expect(find.text(banner), findsNothing);
    expect(store.progressSaves, isEmpty);
  });

  group('a jump ahead', () {
    testWidgets('shows the banner and keeps the boundary', (tester) async {
      await pumpBook(tester);
      await moveTo(tester, const ReaderPosition(5, 0.2));
      expect(find.text(banner), findsOne);
      expect(store.progressSaves.last, (
        book.id,
        const TextPosition(5, 0.2),
        read,
        0.2,
      ));
    });

    testWidgets('keeps the banner while the reader reads on, into the next '
        'section too', (tester) async {
      await pumpBook(tester);
      for (final position in const [
        ReaderPosition(5, 0.2),
        ReaderPosition(5, 0.6),
        ReaderPosition(6, 0),
      ]) {
        await moveTo(tester, position);
        expect(find.text(banner), findsOne);
      }
      expect(store.progressSaves.last.$3, read);
    });

    testWidgets('moves the boundary and hides the banner on Count as read', (
      tester,
    ) async {
      await pumpBook(tester);
      await moveTo(tester, const ReaderPosition(5, 0.2, totalProgression: 0.6));
      await tester.tap(find.text('Count as read'));
      await tester.pumpAndSettle();
      expect(find.text(banner), findsNothing);
      expect(store.progressSaves.last, (
        book.id,
        const TextPosition(5, 0.2),
        const TextPosition(5, 0.2),
        0.6,
      ));

      await moveTo(tester, const ReaderPosition(5, 0.4));
      expect(find.text(banner), findsNothing);
    });

    testWidgets('goes back to where the reader was on Go back, and the banner '
        'goes once they are there', (tester) async {
      await pumpBook(tester);
      await moveTo(tester, const ReaderPosition(1, 0.5));
      await moveTo(tester, const ReaderPosition(5, 0.2));
      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(reader.sessions.single.goToPositionCalls, [
        const ReaderPosition(1, 0.5),
      ]);
      expect(find.text(banner), findsOne);

      await moveTo(tester, const ReaderPosition(1, 0.5));
      expect(find.text(banner), findsNothing);
      expect(store.progressSaves.last.$3, read);
    });

    testWidgets('of many pages in one chapter shows the banner', (
      tester,
    ) async {
      const page54 = TextPosition(1, 54 / 120);
      store.progress[book.id] = (
        furthest: page54,
        boundary: page54,
        boundaryTotal: null,
      );
      await pumpBook(tester);
      await moveTo(
        tester,
        const ReaderPosition(1, 87 / 120, sectionPages: 120),
      );
      expect(find.text(banner), findsOne);
    });

    testWidgets('made before the progress loads shows the banner once it has', (
      tester,
    ) async {
      final slow = _SlowStore()
        ..progress[book.id] = (
          furthest: read,
          boundary: read,
          boundaryTotal: 0.2,
        );
      await pumpBook(tester, openPositionStore: () async => slow);
      await moveTo(tester, const ReaderPosition(5, 0.2));
      expect(find.text(banner), findsNothing);

      slow.gate.complete();
      await tester.pumpAndSettle();
      expect(find.text(banner), findsOne);
    });
  });

  testWidgets('a book left past the boundary shows the banner on open, and Go '
      'back goes to the boundary', (tester) async {
    const left = ReaderPosition(5, 0.2);
    store = FakeReadingPositionStore(positions: {book.id: left})
      ..progress[book.id] = (
        furthest: const TextPosition(5, 0.2),
        boundary: read,
        boundaryTotal: 0.2,
      );
    await pumpBook(tester);
    expect(find.text(banner), findsOne);

    // The book opens where it was left.
    await moveTo(tester, left);
    expect(find.text(banner), findsOne);
    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    expect(reader.sessions.single.goToPositionCalls, [
      const ReaderPosition(1, 0.5),
    ]);
  });

  testWidgets('a book read before the tracker counts as read up to its '
      'saved position', (tester) async {
    store = FakeReadingPositionStore(
      positions: {book.id: const ReaderPosition(4, 0.5, totalProgression: 0.4)},
    );
    await pumpBook(tester);
    expect(store.progressSaves.single, (
      book.id,
      const TextPosition(4, 0.5),
      const TextPosition(4, 0.5),
      0.4,
    ));
    await moveTo(tester, const ReaderPosition(4, 0.5));
    expect(find.text(banner), findsNothing);
  });

  testWidgets('a store that can’t be opened never keeps the book from '
      'reading', (tester) async {
    await pumpBook(
      tester,
      openPositionStore: () async => throw const FileSystemException('No disk'),
    );
    await moveTo(tester, const ReaderPosition(5, 0.2));
    expect(find.text('Fake reader view'), findsOne);
    expect(find.text(banner), findsNothing);
    expect(find.byType(BoundaryBar), findsNothing);
  });

  group('the bar by the page count', () {
    double barWidth(WidgetTester tester) =>
        tester.getSize(find.byType(BoundaryBar)).width;

    double widthOf(WidgetTester tester, String key) =>
        tester.getSize(find.byKey(ValueKey(key))).width;

    Color markerColor(WidgetTester tester) {
      final marker = tester.widget<Container>(
        find.byKey(const ValueKey('reader-marker')),
      );
      return (marker.decoration! as BoxDecoration).color!;
    }

    testWidgets('fills up to the boundary, with a marker where the reader is', (
      tester,
    ) async {
      await pumpBook(tester);
      expect(
        widthOf(tester, 'boundary-fill'),
        closeTo(0.2 * barWidth(tester), 0.01),
      );
      // No marker until the reader says where they are.
      expect(find.byKey(const ValueKey('reader-marker')), findsNothing);

      await moveTo(
        tester,
        const ReaderPosition(1, 0.3, totalProgression: 0.15),
      );
      expect(markerColor(tester), LoremarkColors.ink);
      expect(find.byKey(const ValueKey('skipped')), findsNothing);
    });

    testWidgets('after a jump shows the skipped stretch and a green marker', (
      tester,
    ) async {
      await pumpBook(tester);
      await moveTo(tester, const ReaderPosition(5, 0.2, totalProgression: 0.6));
      expect(
        widthOf(tester, 'boundary-fill'),
        closeTo(0.2 * barWidth(tester), 0.01),
      );
      expect(widthOf(tester, 'skipped'), closeTo(0.4 * barWidth(tester), 0.01));
      expect(markerColor(tester), LoremarkColors.safeDot);
    });

    testWidgets('fills up to the reader on Count as read', (tester) async {
      await pumpBook(tester);
      await moveTo(tester, const ReaderPosition(5, 0.2, totalProgression: 0.6));
      await tester.tap(find.text('Count as read'));
      await tester.pumpAndSettle();
      expect(
        widthOf(tester, 'boundary-fill'),
        closeTo(0.6 * barWidth(tester), 0.01),
      );
      expect(find.byKey(const ValueKey('skipped')), findsNothing);
      expect(markerColor(tester), LoremarkColors.ink);
    });

    testWidgets('shows a jump the book was left on as soon as it opens', (
      tester,
    ) async {
      store =
          FakeReadingPositionStore(
              positions: {
                book.id: const ReaderPosition(5, 0.2, totalProgression: 0.6),
              },
            )
            ..progress[book.id] = (
              furthest: const TextPosition(5, 0.2),
              boundary: read,
              boundaryTotal: 0.2,
            );
      await pumpBook(tester);
      expect(widthOf(tester, 'skipped'), closeTo(0.4 * barWidth(tester), 0.01));
      expect(markerColor(tester), LoremarkColors.safeDot);
    });
  });
}
