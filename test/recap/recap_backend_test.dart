import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/recap/recap_backend.dart';
import 'package:loremark/story_model/story_snapshot.dart';

import 'recap_test_book.dart';

void main() {
  late FakeStoryMap storyMap;
  late DeviceRecapBackend backend;

  setUp(() {
    storyMap = FakeStoryMap(model: recapTestModel());
    backend = DeviceRecapBackend(storyMap: storyMap);
  });

  test('without a Story Map, there is no recap to offer', () async {
    storyMap.model = null;

    expect(await backend.prepare(recapTestBook), isA<RecapNeedsStoryMap>());
    expect(storyMap.progressLooks, 0);
  });

  test('before the reader has read any of the map, there is none', () async {
    storyMap.progress = const StoryReadingProgress(0);

    expect(await backend.prepare(recapTestBook), isA<RecapNeedsReading>());
  });

  test('says where the reader stopped, from the map\'s progress', () async {
    storyMap.progress = partwayThroughChapter2(2);

    final start = await backend.prepare(recapTestBook);

    expect(storyMap.progressLooks, 1);
    final stop = (start as RecapCanStart).stop;
    expect(stop.sectionTitle, 'Chapter 2: The Letter');
    expect(stop.partway, isTrue);
  });
}
