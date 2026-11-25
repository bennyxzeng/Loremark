import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' hide TextPosition;
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/epub_sections.dart';
import 'package:loremark/reader/page_end.dart';
import 'package:loremark/reader/page_start.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/reader/reading_position_store.dart';
import 'package:loremark/reading/text_position.dart';
import 'package:loremark/story_map/story_map_backend.dart';
import 'package:loremark/story_model/story_model.dart';

import '../story_update/golden.dart';

// Story Map, the welcome back and Ask go by the knowledge boundary saved
// beside the reader's position, not by the position itself (issue #53).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late ReadingPositionStore positions;
  final epub = '$goldenDir/story.epub';
  // In story.epub, spine item 1 is chapter 1 and item 2 is chapter 2.
  const sections = [
    StorySection(
      id: 'section-002',
      order: 1,
      chapterNumber: 1,
      title: 'Chapter 1',
      href: 'OEBPS/ch1.xhtml',
    ),
  ];
  const selector = ':root > :nth-child(2) > :nth-child(3)';

  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('story_boundary_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => temp.path,
        );
    positions = await ReadingPositionStore.open();
  });
  tearDownAll(() => temp.deleteSync(recursive: true));

  Book book(String id) => Book(
    id: id,
    title: 'Synthetic Story',
    author: null,
    epubPath: epub,
    coverPath: null,
    importedAt: DateTime.utc(2026),
  );

  /// Where the page in chapter 1 ends: five characters into its sixth block.
  Future<double> chapter1PageEnd() async {
    final chapter1 = (await readSectionMarkup(epub, 'OEBPS/ch1.xhtml'))!;
    return textProgressionOfBlock(chapter1, 5, characters: 5)!;
  }

  /// Saves the reader at [current] with their page measured there, and
  /// [boundary] as how far they have read.
  Future<void> saveReader(
    String id, {
    required ReaderPosition current,
    required PageEnd pageEnd,
    TextPosition? boundary,
  }) async {
    await positions.save(id, current);
    await positions.savePageStart(
      id,
      PageStart(current.sectionIndex, selector),
    );
    await positions.savePageEnd(id, pageEnd);
    if (boundary != null) {
      await positions.saveProgress(
        id,
        furthest: TextPosition(current.sectionIndex, current.progression),
        boundary: boundary,
        boundaryTotal: null,
      );
    }
  }

  test('after a jump to a later chapter that was not counted as read, '
      'stops at the boundary', () async {
    final skipped = book('skipped-chapter');
    await saveReader(
      skipped.id,
      current: const ReaderPosition(2, 0.3),
      pageEnd: const PageEnd(2, 1, 0.5),
      boundary: const TextPosition(1, 0.5),
    );
    final backend = DeviceStoryMapBackend();

    final progress = await backend.readingProgress(skipped, sections);
    expect(progress.finished, 0);
    expect(progress.hiddenInNext, isNull);

    final ask = await backend.askReach(skipped, sections);
    expect(ask.progress.finished, 0);
    expect(ask.page, isNull);
    expect(ask.limit, const TextPosition(1, 0));
    expect(ask.pastMap, isFalse);
  });

  test('after a jump within the chapter, the page past the boundary is not '
      'used', () async {
    final skipped = book('skipped-pages');
    await saveReader(
      skipped.id,
      current: const ReaderPosition(1, 0.8),
      pageEnd: PageEnd(1, 5, await chapter1PageEnd()),
      boundary: const TextPosition(1, 0.2),
    );
    final backend = DeviceStoryMapBackend();

    final progress = await backend.readingProgress(skipped, sections);
    expect(progress.finished, 0);
    expect(progress.hiddenInNext, isNull);

    final ask = await backend.askReach(skipped, sections);
    expect(ask.progress.hiddenInNext, isNull);
    expect(ask.page, isNull);
    expect(ask.limit, const TextPosition(1, 0));
  });

  test('Count as read moves it to the new place without reopening', () async {
    final counted = book('counted-as-read');
    await saveReader(
      counted.id,
      current: const ReaderPosition(2, 0.3),
      pageEnd: const PageEnd(2, 1, 0.5),
      boundary: const TextPosition(1, 0.5),
    );
    final backend = DeviceStoryMapBackend();
    expect((await backend.readingProgress(counted, sections)).finished, 0);

    // Not awaited, as BookScreen saves it: the backend waits for the store.
    unawaited(
      positions.saveProgress(
        counted.id,
        furthest: const TextPosition(2, 0.3),
        boundary: const TextPosition(2, 0.3),
        boundaryTotal: null,
      ),
    );

    expect((await backend.readingProgress(counted, sections)).finished, 1);
    final ask = await backend.askReach(counted, sections);
    expect(ask.progress.finished, 1);
    expect(ask.page!.text, startsWith('CHAPTER 2 THE STORM'));
    expect(ask.limit, const TextPosition(2, 0.5));
    expect(ask.pastMap, isTrue);
  });

  test('with no boundary saved, goes by the reader position', () async {
    final old = book('no-boundary');
    await saveReader(
      old.id,
      current: const ReaderPosition(2, 0.3),
      pageEnd: const PageEnd(2, 1, 0.5),
    );
    final backend = DeviceStoryMapBackend();

    expect((await backend.readingProgress(old, sections)).finished, 1);
    final ask = await backend.askReach(old, sections);
    expect(ask.progress.finished, 1);
    expect(ask.page!.text, startsWith('CHAPTER 2 THE STORM'));
    expect(ask.limit, const TextPosition(2, 0.5));
  });

  test('rereading behind the boundary keeps what was read, and Ask still '
      'sees the page', () async {
    final rereading = book('rereading');
    final end = await chapter1PageEnd();
    await saveReader(
      rereading.id,
      current: const ReaderPosition(1, 0.5),
      pageEnd: PageEnd(1, 5, end),
      boundary: const TextPosition(2, 0.3),
    );
    final backend = DeviceStoryMapBackend();

    expect((await backend.readingProgress(rereading, sections)).finished, 1);
    final ask = await backend.askReach(rereading, sections);
    expect(ask.progress.finished, 1);
    expect(ask.page!.text, startsWith('CHAPTER 1 THE SIGNAL'));
    expect(ask.page!.text, endsWith('No one'));
    expect(ask.limit, TextPosition(1, end));
    expect(ask.pastMap, isFalse);
  });
}
