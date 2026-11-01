import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/search/query.dart';
import 'package:loremark/search/stemmer.dart';
import 'package:loremark/search/tokenizer.dart';

List<QueryPart> parse(String query) => parseQuery(
  query,
  Tokenizer(stem: porter2Stem),
  isStopTerm: {'the', 'where', 'did', 'is', 'of', 'a'}.contains,
);

String describe(QueryPart part) => part.toString();

void main() {
  test('plain words are separate parts', () {
    expect(parse('ryn harbor ').map(describe), [
      'QueryPart(ryn)',
      'QueryPart(harbor)',
    ]);
  });

  test('the word being typed carries its prefix', () {
    expect(parse('ryn har').map(describe), [
      'QueryPart(ryn)',
      'QueryPart(har, prefix har)',
    ]);
  });

  test('the prefix keeps what was typed, not the stem', () {
    final part = parse('running').single;
    expect(part.tokens.single.term, 'run');
    expect(part.prefixText, 'running');
  });

  test('a one-letter word is not a prefix', () {
    expect(parse('r').single.prefixText, isNull);
  });

  test('a trailing space, quote or symbol means no word is being typed', () {
    expect(parse('har ').single.prefixText, isNull);
    expect(parse('har!').single.prefixText, isNull);
    expect(parse('"har"').single.prefixText, isNull);
  });

  test('quoted text is a required phrase', () {
    final parts = parse('who "Glass Harbor" map');
    expect(parts.map(describe), [
      'QueryPart(who)',
      'QueryPart(glass harbor, phrase, required)',
      'QueryPart(map, prefix map)',
    ]);
  });

  test('curly quotes work too', () {
    expect(parse('“glass harbor”').single.required, isTrue);
  });

  test('an unclosed quote is a phrase to the end', () {
    final part = parse('"glass harbor').single;
    expect(part.phrase && part.required, isTrue);
    expect(part.prefixText, isNull);
  });

  test('a quoted single word remains required', () {
    final part = parse('"harbor"').single;
    expect(part.phrase, isFalse);
    expect(part.required, isTrue);
  });

  test('common words are dropped when there is something else', () {
    expect(parse('where did Ryn go ').map(describe), [
      'QueryPart(ryn)',
      'QueryPart(go)',
    ]);
  });

  test('common words are kept when there is nothing else', () {
    expect(parse('where is the ').map(describe), [
      'QueryPart(where)',
      'QueryPart(is)',
      'QueryPart(the)',
    ]);
  });

  test('common words inside quotes stay', () {
    expect(parse('"map of the harbor"').single.tokens, hasLength(4));
  });

  test('a repeated word counts once', () {
    expect(parse('ryn Ryn ryn ').length, 1);
  });

  test('a CJK run is a phrase of its bigrams', () {
    final part = parse('克莱恩').single;
    expect(part.phrase, isTrue);
    expect(part.required, isFalse);
    expect(part.tokens.map((t) => t.term), ['克莱', '莱恩']);
  });

  test('a two-character CJK word is one term', () {
    final part = parse('愚者').single;
    expect(part.phrase, isFalse);
    expect(part.tokens.single.term, '愚者');
  });

  test('a lone CJK character is searched as text', () {
    final part = parse('魔').single;
    expect(part.substring, '魔');
    expect(part.tokens, isEmpty);
  });

  test('separate CJK runs are separate parts', () {
    expect(parse('愚者 克莱恩').map(describe), [
      'QueryPart(愚者)',
      'QueryPart(克莱 莱恩, phrase)',
    ]);
  });

  test('nothing to search for gives no parts', () {
    expect(parse(''), isEmpty);
    expect(parse(' ?! '), isEmpty);
  });
}
