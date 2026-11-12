import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/epub_sections.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/story_map/story_map_backend.dart';
import 'package:loremark/story_map/story_map_status.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/story_update/story_updater.dart';

final _book = Book(
  id: 'book-1',
  title: 'The Test Book',
  author: null,
  epubPath: '/nowhere.epub',
  coverPath: null,
  importedAt: DateTime.utc(2026),
);

/// Only what the status asks of a backend.
class _Backend implements StoryMapBackend {
  RunningStoryBatch? runningUpdate;
  final spineRead = Completer<List<SpineItem>>();
  var spineReads = 0;

  @override
  RunningStoryBatch? running(Book book) => runningUpdate;

  @override
  Future<List<SpineItem>> spine(Book book) {
    spineReads++;
    return spineRead.future;
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Documents `c0.xhtml` to `c5.xhtml`.
final _spine = [
  for (var i = 0; i < 6; i++) SpineItem(path: 'OEBPS/c$i.xhtml', linear: true),
];

/// Sections in documents 1 and 2.
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
  late _Backend backend;
  late StoryMapStatusController status;
  late int notices;

  setUp(() {
    backend = _Backend();
    status = StoryMapStatusController(book: _book, backend: backend);
    notices = 0;
    status.addListener(() => notices++);
  });

  tearDown(() => status.dispose());

  group('an update', () {
    test('already running is there from the start', () async {
      final first = Completer<StoryUpdateOutcome>();
      final batch = RunningStoryBatch(
        [
          for (final id in ['s1', 's2', 's3'])
            StorySectionChoice(id, 'Section $id', 30),
        ],
        (section) => section.sectionId == 's1'
            ? first.future
            : Completer<StoryUpdateOutcome>().future,
      );
      backend.runningUpdate = batch;
      first.complete(const StoryUpdateOutcome('committed'));
      await pumpEventQueue();
      batch.stopAfterCurrent();

      final picked = StoryMapStatusController(book: _book, backend: backend);
      addTearDown(picked.dispose);
      expect(picked.updateStartedAt, batch.currentStartedAt);
      expect(picked.step, 1);
      expect(picked.total, 3);
      expect(picked.stopping, isTrue);
    });

    test('counts the sections of several', () {
      final first = DateTime.utc(2026);
      final second = first.add(const Duration(minutes: 3));
      status.updateStarted(first, total: 3);
      expect((status.step, status.total), (0, 3));

      status.updateStarted(second, step: 1, total: 3);
      expect(status.updateStartedAt, second);
      expect((status.step, status.total), (1, 3));

      // Told again of the same section, nothing changes.
      status.updateStarted(second, step: 1, total: 3);
      expect(notices, 2);

      status.stopRequested();
      expect(status.stopping, isTrue);

      status.updateEnded();
      expect(status.updateStartedAt, isNull);
      expect((status.step, status.total, status.stopping), (0, 1, false));
      expect(notices, 4);
    });

    test('goes from started to cancelling to ended', () {
      final started = DateTime.utc(2026);
      expect(status.updateStartedAt, isNull);

      status.updateStarted(started);
      expect(status.updateStartedAt, started);
      expect(status.cancelling, isFalse);

      status.cancelRequested();
      expect(status.cancelling, isTrue);

      status.updateEnded();
      expect(status.updateStartedAt, isNull);
      expect(status.cancelling, isFalse);
      expect(notices, 3);
    });

    test('can\'t be cancelled when none is running', () {
      status.cancelRequested();
      status.updateEnded();
      expect(status.cancelling, isFalse);
      expect(notices, 0);
    });
  });

  group('where the page is', () {
    test('is unknown until the map is read', () async {
      status.readerMoved(const ReaderPosition(1, 0));
      expect(status.coverage, isNull);
      expect(notices, 0);
    });

    test('with no map, needs no page', () {
      status.mapLoaded(null);
      expect(status.coverage, StoryCoverage.none);
      expect(notices, 1);
      expect(backend.spineReads, 0);
    });

    test('is unknown until the page is', () async {
      status.mapLoaded(_sections);
      backend.spineRead.complete(_spine);
      await pumpEventQueue();
      expect(status.coverage, isNull);

      status.readerMoved(const ReaderPosition(2, 0.5));
      expect(status.coverage, StoryCoverage.inMap);
    });

    test('waits for the spine, read once', () async {
      status.readerMoved(const ReaderPosition(4, 0));
      status.mapLoaded(_sections);
      status.mapLoaded(_sections);
      expect(status.coverage, isNull);

      backend.spineRead.complete(_spine);
      await pumpEventQueue();
      expect(status.coverage, StoryCoverage.ahead);
      expect(backend.spineReads, 1);
    });

    test('follows the reader from document to document', () async {
      status.mapLoaded(_sections);
      backend.spineRead.complete(_spine);
      await pumpEventQueue();

      status.readerMoved(const ReaderPosition(0, 0));
      expect(status.coverage, StoryCoverage.before);
      status.readerMoved(const ReaderPosition(1, 0));
      expect(status.coverage, StoryCoverage.inMap);
      status.readerMoved(const ReaderPosition(3, 0));
      expect(status.coverage, StoryCoverage.ahead);
      expect(notices, 3);
    });

    test('says nothing for pages turned within a document', () async {
      status.mapLoaded(_sections);
      backend.spineRead.complete(_spine);
      await pumpEventQueue();
      status.readerMoved(const ReaderPosition(1, 0));
      final before = notices;

      status.readerMoved(const ReaderPosition(1, 0.3));
      status.readerMoved(const ReaderPosition(1, 0.9));
      // Another document, still in the map.
      status.readerMoved(const ReaderPosition(2, 0));
      expect(notices, before);
    });

    test('moves with the map', () async {
      status.mapLoaded(_sections.sublist(0, 1));
      backend.spineRead.complete(_spine);
      status.readerMoved(const ReaderPosition(2, 0));
      await pumpEventQueue();
      expect(status.coverage, StoryCoverage.ahead);

      status.mapLoaded(_sections);
      expect(status.coverage, StoryCoverage.inMap);
    });

    test('is unknown again if the map can\'t be read', () async {
      status.mapLoaded(null);
      status.mapUnreadable();
      expect(status.coverage, isNull);
    });

    test('stays unknown if the spine can\'t be read', () async {
      status.mapLoaded(_sections);
      status.readerMoved(const ReaderPosition(1, 0));
      backend.spineRead.completeError(StateError('no book'));
      await pumpEventQueue();
      expect(status.coverage, isNull);
    });

    test('a spine read after closing the book is dropped', () async {
      final closing = StoryMapStatusController(book: _book, backend: backend);
      closing.mapLoaded(_sections);
      closing.dispose();
      backend.spineRead.complete(_spine);
      await pumpEventQueue();
    });
  });
}
