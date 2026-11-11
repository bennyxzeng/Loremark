import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/epub_sections.dart';
import 'package:loremark/recap/recap_backend.dart';
import 'package:loremark/story_model/story_snapshot.dart';
import 'package:loremark/story_update/story_store.dart';

import 'recap_test_book.dart';

void main() {
  late FakeStoryMap storyMap;
  late DeviceRecapBackend backend;

  setUp(() {
    storyMap = FakeStoryMap(model: recapTestModel());
    backend = DeviceRecapBackend(
      storyMap: storyMap,
      readSpineOf: (_) async => recapTestSpine,
    );
  });

  test('without a Story Map, there is nothing to recap from', () async {
    storyMap.model = null;

    expect(await backend.prepare(recapTestBook), isA<RecapNeedsStoryMap>());
    expect(storyMap.paragraphsAskedFor, isEmpty);
  });

  test('before the reader has read any of the map, there is nothing', () async {
    storyMap.progress = const StoryReadingProgress(0);

    expect(await backend.prepare(recapTestBook), isA<RecapNeedsReading>());
    // Not even the text is read.
    expect(storyMap.paragraphsAskedFor, isEmpty);
  });

  test('facts and text come from one look at the reader’s place', () async {
    final progress = partwayThroughChapter2(2);
    storyMap.progress = progress;

    final start = await backend.prepare(recapTestBook);

    expect(storyMap.progressLooks, 1);
    expect(storyMap.paragraphsAskedFor.single, same(progress));
    final source = (start as RecapCanStart).source;
    expect(source.place, (finished: 1, paragraphsRead: 2, revision: 2));
    expect(source.stopsAt, 'your page in Chapter 2: The Letter');
  });

  test('text that can’t be read fails the recap', () async {
    storyMap
      ..progress = partwayThroughChapter2(2)
      ..paragraphsError = const StoryStoreError('missing section text');

    await expectLater(
      backend.prepare(recapTestBook),
      throwsA(isA<StoryStoreError>()),
    );
  });

  test('without the book’s spine, passages show but can’t be opened', () async {
    storyMap.progress = const StoryReadingProgress(1);
    final noSpine = DeviceRecapBackend(
      storyMap: storyMap,
      readSpineOf: (_) async => throw const FormatException('bad zip'),
    );

    final start = await noSpine.prepare(recapTestBook);

    final passage = (start as RecapCanStart).source.events.single.passages;
    expect(passage.single.target, isNull);
  });

  test('the spine is read once per book', () async {
    var reads = 0;
    final counting = DeviceRecapBackend(
      storyMap: storyMap..progress = const StoryReadingProgress(1),
      readSpineOf: (_) async {
        reads++;
        return const <SpineItem>[];
      },
    );

    await counting.prepare(recapTestBook);
    await counting.prepare(recapTestBook);

    expect(reads, 1);
  });
}
