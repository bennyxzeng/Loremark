import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/book_screen.dart';
import 'package:loremark/home/boundary_bar.dart';
import 'package:loremark/home/skipped_ahead_button.dart';
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
  late DateTime clock;

  setUp(() {
    clock = DateTime(2026, 11, 19, 20);
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
              now: () => clock,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Moves the reader [after] the last move, by default long enough to have
  /// read the page.
  Future<void> moveTo(
    WidgetTester tester,
    ReaderPosition position, {
    Duration after = const Duration(seconds: 30),
  }) async {
    clock = clock.add(after);
    reader.sessions.single.emit(position);
    await tester.pumpAndSettle();
  }

  const question = 'You skipped ahead';

  Future<void> answer(WidgetTester tester, String button) async {
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();
  }

  Future<void> tapBar(WidgetTester tester) async {
    await tester.tap(find.byType(BoundaryBar));
    await tester.pumpAndSettle();
  }

  testWidgets('reading on moves the boundary without asking', (tester) async {
    await pumpBook(tester);
    await moveTo(tester, const ReaderPosition(1, 0.6, totalProgression: 0.3));
    expect(find.text(question), findsNothing);
    expect(store.progressSaves.last, (
      book.id,
      const TextPosition(1, 0.6),
      const TextPosition(1, 0.6),
      0.3,
    ));
  });

  testWidgets('going back neither asks nor saves', (tester) async {
    await pumpBook(tester);
    await moveTo(tester, const ReaderPosition(0, 0.3));
    expect(find.text(question), findsNothing);
    expect(store.progressSaves, isEmpty);
  });

  group('a jump ahead', () {
    testWidgets('asks and keeps the boundary', (tester) async {
      await pumpBook(tester);
      await moveTo(tester, const ReaderPosition(5, 0.2));
      expect(find.text(question), findsOne);
      expect(store.progressSaves.last, (
        book.id,
        const TextPosition(5, 0.2),
        read,
        0.2,
      ));
    });

    testWidgets('to the next chapter from the middle of this one asks', (
      tester,
    ) async {
      await pumpBook(tester);
      await moveTo(tester, const ReaderPosition(2, 0));
      expect(find.text(question), findsOne);
      expect(store.progressSaves.last.$3, read);
    });

    testWidgets('on Keep reading leaves nothing over the page and isn’t asked '
        'about again as the reader reads on', (tester) async {
      await pumpBook(tester);
      await moveTo(tester, const ReaderPosition(5, 0.2));
      await answer(tester, 'Keep reading');
      expect(find.text(question), findsNothing);
      expect(find.text('Count as read'), findsNothing);

      for (final position in const [
        ReaderPosition(5, 0.6),
        ReaderPosition(6, 0),
        ReaderPosition(12, 0),
      ]) {
        await moveTo(tester, position);
        expect(find.text(question), findsNothing);
      }
      expect(store.progressSaves.last.$3, read);
    });

    testWidgets('moves the boundary on Count as read', (tester) async {
      await pumpBook(tester);
      await moveTo(tester, const ReaderPosition(5, 0.2, totalProgression: 0.6));
      await answer(tester, 'Count as read');
      expect(store.progressSaves.last, (
        book.id,
        const TextPosition(5, 0.2),
        const TextPosition(5, 0.2),
        0.6,
      ));

      await moveTo(tester, const ReaderPosition(5, 0.4));
      expect(find.text(question), findsNothing);
    });

    testWidgets('goes back to where the reader was on Go back', (tester) async {
      await pumpBook(tester);
      await moveTo(tester, const ReaderPosition(1, 0.5));
      await moveTo(tester, const ReaderPosition(5, 0.2));
      await answer(tester, 'Go back');
      expect(reader.sessions.single.goToPositionCalls, [
        const ReaderPosition(1, 0.5),
      ]);

      // Arriving there drops the jump; the boundary never moved.
      await moveTo(tester, const ReaderPosition(1, 0.5));
      expect(find.text(question), findsNothing);
      expect(store.progressSaves.last.$3, read);
    });

    testWidgets('of many pages in one chapter asks', (tester) async {
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
      expect(find.text(question), findsOne);
    });

    testWidgets('made before the progress loads asks once it has', (
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
      expect(find.text(question), findsNothing);

      slow.gate.complete();
      await tester.pumpAndSettle();
      expect(find.text(question), findsOne);
    });

    testWidgets('is asked about again on a tap on the bar', (tester) async {
      await pumpBook(tester);
      await moveTo(tester, const ReaderPosition(5, 0.2, totalProgression: 0.6));
      await answer(tester, 'Keep reading');

      await tapBar(tester);
      expect(find.text(question), findsOne);
      await answer(tester, 'Count as read');
      expect(store.progressSaves.last.$3, const TextPosition(5, 0.2));
    });
  });

  testWidgets('a tap on the bar with no jump asks nothing', (tester) async {
    await pumpBook(tester);
    await moveTo(tester, const ReaderPosition(1, 0.5, totalProgression: 0.2));
    await tapBar(tester);
    expect(find.text(question), findsNothing);
  });

  testWidgets('a book left past the boundary isn’t asked about on open, but a '
      'tap on the bar asks, and Go back goes to the boundary', (tester) async {
    const left = ReaderPosition(5, 0.2, totalProgression: 0.6);
    store = FakeReadingPositionStore(positions: {book.id: left})
      ..progress[book.id] = (
        furthest: const TextPosition(5, 0.2),
        boundary: read,
        boundaryTotal: 0.2,
      );
    await pumpBook(tester);
    expect(find.text(question), findsNothing);

    // The book opens where it was left.
    await moveTo(tester, left);
    expect(find.text(question), findsNothing);

    await tapBar(tester);
    await answer(tester, 'Go back');
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
    expect(find.text(question), findsNothing);
  });

  testWidgets('a store that can’t be opened never keeps the book from '
      'reading', (tester) async {
    await pumpBook(
      tester,
      openPositionStore: () async => throw const FileSystemException('No disk'),
    );
    await moveTo(tester, const ReaderPosition(5, 0.2));
    expect(find.text('Fake reader view'), findsOne);
    expect(find.text(question), findsNothing);
    expect(find.byType(BoundaryBar), findsNothing);
  });

  group('the Skipped ahead button', () {
    const button = 'SKIPPED AHEAD';

    testWidgets('isn’t there without a jump', (tester) async {
      await pumpBook(tester);
      await moveTo(tester, const ReaderPosition(1, 0.6));
      expect(find.text(button), findsNothing);
    });

    testWidgets('shows after Keep reading and asks again', (tester) async {
      await pumpBook(tester);
      await moveTo(tester, const ReaderPosition(5, 0.2));
      await answer(tester, 'Keep reading');
      expect(find.text(button), findsOne);

      await answer(tester, button);
      expect(find.text(question), findsOne);
      expect(find.text('Keep reading'), findsOne);
      expect(find.text('Go back'), findsOne);
      expect(find.text('Count as read'), findsOne);
    });

    testWidgets('sits by the bar, below the page, without moving it', (
      tester,
    ) async {
      const label = ValueKey('progress-label');
      await pumpBook(tester);
      final labelBefore = tester.getRect(find.byKey(label));
      await moveTo(tester, const ReaderPosition(5, 0.2, totalProgression: 0.6));
      await answer(tester, 'Keep reading');

      final pill = tester.getRect(find.byType(SkippedAheadButton));
      final bar = tester.getRect(find.byType(BoundaryBar));
      expect(pill.center.dy, bar.center.dy);
      expect(pill.left, greaterThanOrEqualTo(bar.right));
      expect(
        pill.right,
        lessThanOrEqualTo(tester.getRect(find.byKey(label)).left),
      );
      // The row of page buttons is no taller, so the page doesn't move.
      expect(
        tester.getRect(find.byKey(label)).center.dy,
        labelBefore.center.dy,
      );
    });

    testWidgets('fits beside the bar on a narrow phone', (tester) async {
      // 360 is the narrowest common phone. The test font draws every letter
      // as wide as it is tall, about a third wider than a real one.
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpBook(tester);
      await moveTo(tester, const ReaderPosition(5, 0.2, totalProgression: 0.6));
      await answer(tester, 'Keep reading');
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(BoundaryBar)).width, greaterThan(0));
    });

    testWidgets('a bar squeezed narrower than its marker still draws', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 6,
              child: BoundaryBar(boundary: 0.2, current: 0.6, ahead: true),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('goes on Count as read', (tester) async {
      await pumpBook(tester);
      await moveTo(tester, const ReaderPosition(5, 0.2));
      await answer(tester, 'Keep reading');
      await answer(tester, button);
      await answer(tester, 'Count as read');
      expect(find.text(button), findsNothing);
      expect(store.progressSaves.last.$3, const TextPosition(5, 0.2));
    });

    testWidgets('goes on Go back once the reader is there', (tester) async {
      await pumpBook(tester);
      await moveTo(tester, const ReaderPosition(1, 0.5));
      await moveTo(tester, const ReaderPosition(5, 0.2));
      await answer(tester, 'Keep reading');
      await answer(tester, button);
      await answer(tester, 'Go back');
      expect(reader.sessions.single.goToPositionCalls, [
        const ReaderPosition(1, 0.5),
      ]);

      await moveTo(tester, const ReaderPosition(1, 0.5));
      expect(find.text(button), findsNothing);
    });

    testWidgets('shows when the book opens past the boundary, without asking', (
      tester,
    ) async {
      store =
          FakeReadingPositionStore(
              positions: {book.id: const ReaderPosition(5, 0.2)},
            )
            ..progress[book.id] = (
              furthest: const TextPosition(5, 0.2),
              boundary: read,
              boundaryTotal: 0.2,
            );
      await pumpBook(tester);
      expect(find.text(button), findsOne);
      expect(find.text(question), findsNothing);
    });
  });

  group('flipping through pages', () {
    const button = 'SKIPPED AHEAD';

    // The book's boundary is page 10 of 20 in section 1.
    ReaderPosition page(int index) => ReaderPosition(
      1,
      index / 20,
      sectionPages: 20,
      totalProgression: index / 50,
    );

    /// Reads page 10, then flips through pages 11 to 15 on to 16.
    Future<void> flipToPage16(WidgetTester tester) async {
      await moveTo(tester, page(11));
      for (var index = 12; index <= 16; index++) {
        await moveTo(tester, page(index), after: const Duration(seconds: 1));
      }
    }

    testWidgets('shows the Skipped ahead button and the skipped stretch '
        'without asking', (tester) async {
      await pumpBook(tester);
      await flipToPage16(tester);
      expect(find.text(question), findsNothing);
      expect(find.text(button), findsOne);
      expect(find.byKey(const ValueKey('skipped')), findsOne);
    });

    testWidgets('saves the boundary where the flipping began', (tester) async {
      await pumpBook(tester);
      await flipToPage16(tester);
      expect(store.progressSaves.last, (
        book.id,
        const TextPosition(1, 16 / 20),
        const TextPosition(1, 11 / 20),
        11 / 50,
      ));
    });

    testWidgets('Go back goes to where the flipping began', (tester) async {
      await pumpBook(tester);
      await flipToPage16(tester);
      await answer(tester, button);
      await answer(tester, 'Go back');
      expect(reader.sessions.single.goToPositionCalls, [
        const ReaderPosition(1, 11 / 20),
      ]);
    });

    testWidgets('Count as read counts the pages flipped through', (
      tester,
    ) async {
      await pumpBook(tester);
      await flipToPage16(tester);
      await answer(tester, button);
      await answer(tester, 'Count as read');
      expect(find.text(button), findsNothing);
      expect(store.progressSaves.last.$3, const TextPosition(1, 16 / 20));
    });

    testWidgets('reading page by page shows nothing', (tester) async {
      await pumpBook(tester);
      for (var index = 11; index <= 16; index++) {
        await moveTo(tester, page(index));
      }
      expect(find.text(button), findsNothing);
      expect(store.progressSaves.last.$3, const TextPosition(1, 16 / 20));
    });
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
