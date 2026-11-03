import 'dart:math';
import 'dart:typed_data';

import '../library/test_epub.dart';

/// Generated books for benchmarks and device checks, so neither needs a
/// copyrighted EPUB in the repo.
///
/// The text is seeded pseudo-prose: the same arguments always give the same
/// bytes, and word frequencies are skewed like real text so search and
/// statistics behave realistically.

const _common = [
  'the', 'of', 'and', 'to', 'a', 'in', 'was', 'he', 'that', 'it', 'his', //
  'her', 'with', 'as', 'had', 'for', 'she', 'on', 'at', 'not', 'but', 'by',
  'they', 'from', 'were', 'all', 'said', 'one', 'would', 'there', 'their',
];

const _words = [
  'harbor', 'glass', 'lantern', 'river', 'letter', 'window', 'stranger', //
  'shadow', 'morning', 'quiet', 'voice', 'promise', 'storm', 'garden',
  'tower', 'silver', 'memory', 'bridge', 'candle', 'secret', 'winter',
  'distant', 'map', 'door', 'ship', 'island', 'market', 'captain', 'road',
  'forest', 'mirror', 'whisper', 'ember', 'archive', 'compass', 'harvest',
  'thunder', 'meadow', 'raven', 'violet', 'anchor', 'chapel', 'cellar',
  'journey', 'question', 'answer', 'remember', 'forgotten', 'walked',
  'looked', 'turned', 'opened', 'carried', 'waited', 'listened', 'smiled',
  'trembled', 'returned', 'hidden', 'broken', 'golden', 'narrow', 'ancient',
  'restless', 'careful', 'sudden', 'familiar', 'strange', 'patient',
];

const _names = [
  'Tamsin', 'Matthias', 'Ilse', 'Corwin', 'Odette', 'Bram', 'Selka', //
  'Arden', 'Wren', 'Lucan', 'Maren', 'Ezra',
];

/// One paragraph of about [words] words.
String syntheticParagraph(Random random, int words) {
  final out = StringBuffer();
  var sentenceStart = true;
  for (var i = 0; i < words; i++) {
    final roll = random.nextDouble();
    var word = roll < 0.45
        ? _common[random.nextInt(_common.length)]
        : roll < 0.95
        ? _words[random.nextInt(_words.length)]
        : _names[random.nextInt(_names.length)];
    if (sentenceStart) {
      word = word[0].toUpperCase() + word.substring(1);
      sentenceStart = false;
    }
    if (i > 0) out.write(' ');
    out.write(word);
    if (i == words - 1 || random.nextInt(12) == 0) {
      out.write('.');
      sentenceStart = true;
    }
  }
  return out.toString();
}

/// An EPUB of [chapters] chapters of about [wordsPerChapter] words each, in
/// paragraphs of 40 to 120 words, with an `<h1>` title per chapter.
///
/// [markers] puts a unique phrase as the first paragraph of the chapter at
/// that index, so a check can tell which chapter's text reached somewhere it
/// shouldn't.
Uint8List buildSyntheticBook({
  int chapters = 12,
  int wordsPerChapter = 2000,
  int seed = 1,
  Map<int, String> markers = const {},
  String title = 'A Synthetic Harbor',
}) {
  final random = Random(seed);
  return buildEpub(
    title: title,
    author: 'Loremark Test Generator',
    cover: CoverStyle.none,
    chapters: [
      for (var c = 0; c < chapters; c++)
        EpubChapter(
          id: 'ch${c + 1}',
          fileName: 'ch${c + 1}.xhtml',
          body: _chapterBody(random, c, wordsPerChapter, markers[c]),
        ),
    ],
  );
}

String _chapterBody(Random random, int index, int words, String? marker) {
  final out = StringBuffer('<h1>Chapter ${index + 1}</h1>');
  if (marker != null) out.write('<p>$marker</p>');
  var written = 0;
  while (written < words) {
    final length = min(40 + random.nextInt(81), words - written);
    out.write('<p>${syntheticParagraph(random, length)}</p>');
    written += length;
  }
  return out.toString();
}
