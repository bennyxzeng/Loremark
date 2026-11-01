import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/search/stemmer.dart';
import 'package:loremark/search/tokenizer.dart';

List<String> terms(String text, {bool stem = false}) => [
  for (final token in Tokenizer(
    stem: stem ? porter2Stem : null,
  ).tokenize(text))
    token.term,
];

void main() {
  group('Latin text', () {
    test('lowercases and splits on punctuation and hyphens', () {
      expect(terms('Klein walked, well-known!'), [
        'klein',
        'walked',
        'well',
        'known',
      ]);
    });

    test('keeps offsets into the original text', () {
      const text = '  Ryn’s Café  ';
      final tokens = Tokenizer().tokenize(text);
      expect([for (final t in tokens) text.substring(t.start, t.end)], [
        'Ryn’s',
        'Café',
      ]);
    });

    test('folds diacritics and look-alike letters', () {
      expect(terms('Café naïve Ångström façade Łódź Straße Æon œuvre'), [
        'cafe',
        'naive',
        'angstrom',
        'facade',
        'lodz',
        'strasse',
        'aeon',
        'oeuvre',
      ]);
    });

    test('folds Vietnamese and combining accents', () {
      expect(terms('Việt Nam'), ['viet', 'nam']);
      expect(terms('café'), ['cafe']);
    });

    test('folds full-width letters and digits', () {
      expect(terms('ＡＢＣ１２３'), ['abc123']);
    });

    test('folding is idempotent', () {
      for (final word in ['Café', 'Straße', 'ǅ', 'ＡＢＣ', 'İstanbul', 'ÆØ']) {
        final once = foldWord(word);
        expect(foldWord(once), once, reason: word);
      }
    });

    test('indexes a possessive as its owner and keeps a contraction', () {
      expect(terms("Klein's don't dogs'"), ['klein', "don't", 'dogs']);
    });

    test('drops a one-letter elision', () {
      expect(terms("l'homme d'Artagnan"), ['homme', 'artagnan']);
    });

    test('keeps numbers', () {
      expect(terms('Chapter 12, 3rd'), ['chapter', '12', '3rd']);
    });

    test('does not split on a soft hyphen or zero-width space', () {
      expect(terms('extra­ordinary zero​width'), [
        'extraordinary',
        'zerowidth',
      ]);
      final tokens = Tokenizer().tokenize('extra­ordinary');
      expect(tokens.single.start, 0);
      expect(tokens.single.end, 'extra­ordinary'.length);
    });

    test('stems English words when asked to', () {
      expect(terms('Running runs ran', stem: true), ['run', 'run', 'ran']);
      expect(terms('Roselle', stem: true), ['rosell']);
    });

    test('does not stem words with other letters', () {
      expect(terms('Straße', stem: true), ['strass']);
      expect(terms('привет', stem: true), ['привет']);
    });
  });

  group('Chinese, Japanese and Korean', () {
    test('a run becomes overlapping bigrams', () {
      expect(terms('克莱恩'), ['克莱', '莱恩']);
      final tokens = Tokenizer().tokenize('克莱恩');
      expect(tokens.map((t) => (t.start, t.end)), [(0, 2), (1, 3)]);
      expect(tokens.every((t) => t.cjk), isTrue);
    });

    test('a lone character is a token of its own', () {
      expect(terms('魔, 药'), ['魔', '药']);
    });

    test('punctuation breaks a run', () {
      expect(terms('愚者，克莱恩'), ['愚者', '克莱', '莱恩']);
    });

    test('works for kana and Hangul, and keeps the prolonged sound mark', () {
      expect(terms('カード'), ['カー', 'ード']);
      expect(terms('ひらがな'), ['ひら', 'らが', 'がな']);
      expect(terms('안녕하세요'), ['안녕', '녕하', '하세', '세요']);
    });

    test('handles characters beyond the Basic Multilingual Plane', () {
      const text = '\u{20000}\u{20001}\u{20002}';
      final tokens = Tokenizer().tokenize(text);
      expect(tokens.map((t) => t.term), [
        '\u{20000}\u{20001}',
        '\u{20001}\u{20002}',
      ]);
      expect(tokens.map((t) => (t.start, t.end)), [(0, 4), (2, 6)]);
    });

    test('mixed scripts keep their own rules and offsets', () {
      const text = 'Klein 克莱恩 said café';
      final tokens = Tokenizer().tokenize(text);
      expect(tokens.map((t) => t.term), [
        'klein',
        '克莱',
        '莱恩',
        'said',
        'cafe',
      ]);
      expect(
        tokens.map((t) => text.substring(t.start, t.end)),
        ['Klein', '克莱', '莱恩', 'said', 'café'],
      );
      expect(tokens.map((t) => t.cjk), [false, true, true, false, false]);
    });

    test('a Latin word next to CJK text is separate', () {
      expect(terms('abc克莱def'), ['abc', '克莱', 'def']);
    });
  });
}
