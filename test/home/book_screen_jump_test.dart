import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/book_screen.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/reader/reading_position_store.dart';
import 'package:loremark/reading/text_position.dart';
import 'package:loremark/settings/ai_settings.dart';
import 'package:loremark/settings/connection_status.dart';
import 'package:loremark/story_map/story_map_backend.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/story_update/story_updater.dart';

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
  Future<({TextPosition furthest, TextPosition boundary})?> loadProgress(
    String bookId,
  ) async {
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
      ..progress[book.id] = (furthest: read, boundary: read);
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

  testWidgets('reading on moves the boundary without asking', (tester) async {
    await pumpBook(tester);
    await moveTo(tester, const ReaderPosition(2, 0.1));
    expect(find.text('You skipped ahead'), findsNothing);
    expect(store.progressSaves.last, (
      book.id,
      const TextPosition(2, 0.1),
      const TextPosition(2, 0.1),
    ));
  });

  testWidgets('going back neither asks nor saves', (tester) async {
    await pumpBook(tester);
    await moveTo(tester, const ReaderPosition(0, 0.3));
    expect(find.text('You skipped ahead'), findsNothing);
    expect(store.progressSaves, isEmpty);
  });

  group('a jump ahead', () {
    testWidgets('asks first', (tester) async {
      await pumpBook(tester);
      await moveTo(tester, const ReaderPosition(5, 0.2));
      expect(find.text('You skipped ahead'), findsOne);
    });

    testWidgets('moves the boundary on Count as read', (tester) async {
      await pumpBook(tester);
      await moveTo(tester, const ReaderPosition(5, 0.2));
      await tester.tap(find.text('Count as read'));
      await tester.pumpAndSettle();
      expect(store.progressSaves.last, (
        book.id,
        const TextPosition(5, 0.2),
        const TextPosition(5, 0.2),
      ));
    });

    testWidgets('keeps the boundary on Not yet', (tester) async {
      await pumpBook(tester);
      await moveTo(tester, const ReaderPosition(5, 0.2));
      await tester.tap(find.text('Not yet'));
      await tester.pumpAndSettle();
      expect(find.text('You skipped ahead'), findsNothing);
      expect(store.progressSaves.last, (
        book.id,
        const TextPosition(5, 0.2),
        read,
      ));
    });

    testWidgets('made before the progress loads still asks', (tester) async {
      final slow = _SlowStore()
        ..progress[book.id] = (furthest: read, boundary: read);
      await pumpBook(tester, openPositionStore: () async => slow);
      await moveTo(tester, const ReaderPosition(5, 0.2));
      expect(find.text('You skipped ahead'), findsNothing);

      slow.gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('You skipped ahead'), findsOne);
    });
  });

  testWidgets('a book read before the tracker counts as read up to its '
      'saved position', (tester) async {
    store = FakeReadingPositionStore(
      positions: {book.id: const ReaderPosition(4, 0.5)},
    );
    await pumpBook(tester);
    expect(store.progressSaves.single, (
      book.id,
      const TextPosition(4, 0.5),
      const TextPosition(4, 0.5),
    ));
    await moveTo(tester, const ReaderPosition(4, 0.5));
    expect(find.text('You skipped ahead'), findsNothing);
  });

  testWidgets('a store that can’t be opened never keeps the book from '
      'reading', (tester) async {
    await pumpBook(
      tester,
      openPositionStore: () async => throw const FileSystemException('No disk'),
    );
    await moveTo(tester, const ReaderPosition(5, 0.2));
    expect(find.text('Fake reader view'), findsOne);
    expect(find.text('You skipped ahead'), findsNothing);
  });
}
