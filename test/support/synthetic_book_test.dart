import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/epub_sections.dart';

import 'synthetic_book.dart';

void main() {
  test('builds the same readable book for the same seed', () {
    final bytes = buildSyntheticBook(
      chapters: 3,
      wordsPerChapter: 300,
      markers: {1: 'MARKER-ONE'},
    );
    expect(
      buildSyntheticBook(
        chapters: 3,
        wordsPerChapter: 300,
        markers: {1: 'MARKER-ONE'},
      ),
      bytes,
    );

    final texts = sectionTextsFromBytes(bytes);
    expect(texts, hasLength(3));
    expect(texts[0], startsWith('Chapter 1'));
    expect(texts[1], contains('MARKER-ONE'));
    expect(texts[0], isNot(contains('MARKER-ONE')));
    final words = texts[2].split(RegExp(r'\s+')).length;
    expect(words, inInclusiveRange(300, 310));
  });
}
