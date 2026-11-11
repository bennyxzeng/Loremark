import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/recap/recap_stop.dart';
import 'package:loremark/story_model/story_snapshot.dart';

import 'recap_test_book.dart';

void main() {
  final model = recapTestModel();

  test('nothing the Story Map covers read, nowhere to recap to', () {
    expect(recapStopAt(model, const StoryReadingProgress(0)), isNull);
  });

  test('after chapter 1, stops at its end', () {
    final stop = recapStopAt(model, const StoryReadingProgress(1))!;

    expect(stop.sectionTitle, 'Chapter 1: Arrival');
    expect(stop.partway, isFalse);
  });

  test('partway through chapter 2, stops in it', () {
    final stop = recapStopAt(model, partwayThroughChapter2(2))!;

    expect(stop.sectionTitle, 'Chapter 2: The Letter');
    expect(stop.partway, isTrue);
  });

  test('past all the map holds, stops at its last section', () {
    final stop = recapStopAt(model, const StoryReadingProgress(5))!;

    expect(stop.sectionTitle, 'Chapter 2: The Letter');
    expect(stop.partway, isFalse);
  });
}
