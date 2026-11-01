import 'dart:math';

import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/search/search_index.dart';

/// A small English story with known words, for ranking and snippet tests.
/// Section 0 is the first chapter, section 1 a footnote page (non-linear in
/// [storyLinear]) and section 2 the second chapter.
const storySections = [
  // Section 0.
  'Klein woke in a strange room. The room smelled of old paper and cold tea.\n\n'
      '"Where am I?" he asked.\n\n'
      'Ryn walked in with a lamp. Ryn was the old keeper of the harbor, and '
      'Ryn knew every ship that came to the harbor.\n\n'
      'Klein and Ryn talked about the harbor all night.',
  // Section 1: a footnote.
  'Footnote: the harbor was founded long ago.',
  // Section 2.
  'The next morning Klein walked to the harbor alone. Dalia was waiting by '
      'the water.\n\n'
      'Dalia gave him a map of the Glass Harbor. "To be or not to be lost," '
      'she said.\n\n'
      'Ships were running late, but the harbor never slept.',
];

const storyLinear = [true, false, true];

SearchIndex storyIndex({bool stem = true}) => SearchIndex.build(
  bookId: 'story',
  sectionTexts: storySections,
  linear: storyLinear,
  stem: stem,
);

/// A cutoff after the whole story.
const endOfStory = ReaderPosition(2, 1);

/// Words for generated books. Few enough that a two-letter prefix never has
/// more than the 50 terms the engine expands to, and with the awkward
/// cases: accents, a possessive, common words, and Chinese.
const vocabulary = [
  'the', 'of', 'and', 'a', 'to', //
  'harbor', 'harbors', 'lamp', 'lamps', 'keeper', 'keepers', 'ship', 'ships',
  'klein', 'ryn', 'dalia', 'roselle', 'storm', 'storms', 'map', 'maps',
  'café', 'naïve', 'walked', 'walking', 'walks', 'running', 'runs', 'quiet',
  'quietly', 'mystery', 'mysteries', 'tower', 'towers', 'silver', 'golden',
  "klein's", '愚者', '克莱恩', '魔药', '序列',
];

/// A generated book: paragraphs of random vocabulary, joined with blank
/// lines, in a few sections of which some may be non-linear.
({List<String> texts, List<bool> linear}) randomBook(Random random) {
  final sections = 1 + random.nextInt(5);
  final texts = <String>[];
  final linear = <bool>[];
  for (var s = 0; s < sections; s++) {
    linear.add(s == 0 || random.nextInt(6) != 0);
    final paragraphs = 1 + random.nextInt(8);
    texts.add(
      [for (var p = 0; p < paragraphs; p++) randomParagraph(random)]
          .join('\n\n'),
    );
  }
  return (texts: texts, linear: linear);
}

String randomParagraph(Random random) {
  final words = 1 + random.nextInt(random.nextInt(4) == 0 ? 60 : 18);
  final out = StringBuffer();
  for (var i = 0; i < words; i++) {
    if (i > 0) {
      out.write(switch (random.nextInt(14)) {
        0 => ', ',
        1 => '. ',
        2 => '\n',
        _ => ' ',
      });
    }
    out.write(vocabulary[random.nextInt(vocabulary.length)]);
  }
  return out.toString();
}
