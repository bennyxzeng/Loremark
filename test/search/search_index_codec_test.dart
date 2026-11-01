import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/search/search_index.dart';
import 'package:loremark/search/search_index_codec.dart';

import 'search_fixtures.dart';

/// The gzip-compressed bytes of [index] after [change] edited the plain
/// bytes, to make files that are well-formed gzip but wrong inside.
Uint8List tamper(SearchIndex index, void Function(Uint8List plain) change) {
  final plain = Uint8List.fromList(gzip.decode(encodeSearchIndex(index)));
  change(plain);
  return Uint8List.fromList(gzip.encode(plain));
}

void main() {
  final index = storyIndex();
  final bytes = encodeSearchIndex(index);

  test('a decoded index gives the same results as the original', () {
    final decoded = decodeSearchIndex(bytes, bookId: 'story');
    expect(decoded.bookId, 'story');
    expect(decoded.stemmed, index.stemmed);
    expect(decoded.paragraphCount, index.paragraphCount);
    expect(decoded.termCount, index.termCount);
    for (final query in [
      'harbor',
      'klein ryn',
      '"glass harbor"',
      'to be or not',
      'dal',
      'where did dalia give the map',
    ]) {
      for (final cutoff in const [
        ReaderPosition(0, 0.3),
        ReaderPosition(2, 0),
        endOfStory,
      ]) {
        final a = index.search(query, cutoff: cutoff);
        final b = decoded.search(query, cutoff: cutoff);
        expect(b.hits.map(describe), a.hits.map(describe), reason: query);
        expect(b.hits.map((h) => h.score), a.hits.map((h) => h.score));
        expect(b.hiddenMatches, a.hiddenMatches, reason: query);
      }
    }
  });

  test('keeps the parts exactly', () {
    final a = index.toData();
    final b = decodeSearchIndex(bytes, bookId: 'story').toData();
    expect(b.sectionTexts, a.sectionTexts);
    expect(b.linear, a.linear);
    expect(b.tokenCounts, a.tokenCounts);
    expect(b.terms, a.terms);
    expect(b.termStarts, a.termStarts);
    expect(b.postings, a.postings);
  });

  test('round trips random books, Chinese and unstemmed ones included', () {
    final random = Random(5);
    for (var i = 0; i < 20; i++) {
      final book = randomBook(random);
      final original = SearchIndex.build(
        bookId: 'r$i',
        sectionTexts: book.texts,
        linear: book.linear,
        stem: random.nextBool(),
      );
      final decoded = decodeSearchIndex(
        encodeSearchIndex(original),
        bookId: 'r$i',
      );
      expect(decoded.stemmed, original.stemmed);
      expect(decoded.toData().postings, original.toData().postings);
      expect(decoded.toData().terms, original.toData().terms);
      expect(decoded.toData().sectionTexts, original.toData().sectionTexts);
    }
  });

  test('round trips a book with no text', () {
    final empty = SearchIndex.build(bookId: 'e', sectionTexts: ['', ' ']);
    final decoded = decodeSearchIndex(encodeSearchIndex(empty), bookId: 'e');
    expect(decoded.paragraphCount, 0);
    expect(
      decoded.search('x', cutoff: const ReaderPosition(0, 0)).hits,
      isEmpty,
    );
  });

  test('is smaller than the text it holds', () {
    final random = Random(9);
    final text = List.generate(
      400,
      (_) => randomParagraph(random),
    ).join('\n\n');
    final big = SearchIndex.build(bookId: 'big', sectionTexts: [text]);
    expect(encodeSearchIndex(big).length, lessThan(utf8.encode(text).length));
  });

  group('rejects what it can not trust', () {
    void expectRejected(Uint8List data, {String bookId = 'story'}) {
      expect(
        () => decodeSearchIndex(data, bookId: bookId),
        throwsA(isA<FormatException>()),
      );
    }

    test('an index written for another book', () {
      expectRejected(bytes, bookId: 'someone-else');
    });

    test('a file that is not gzip, or is empty', () {
      expectRejected(Uint8List(0));
      expectRejected(Uint8List.fromList(utf8.encode('{"not":"an index"}')));
    });

    test('a truncated file', () {
      expectRejected(Uint8List.sublistView(bytes, 0, bytes.length ~/ 2));
      expectRejected(Uint8List.sublistView(bytes, 0, bytes.length - 20));
    });

    test('a damaged file', () {
      for (final at in [20, bytes.length ~/ 2, bytes.length - 12]) {
        final damaged = Uint8List.fromList(bytes)..[at] ^= 0xFF;
        expectRejected(damaged);
      }
    });

    test('gzip data that is not an index', () {
      expectRejected(
        Uint8List.fromList(gzip.encode(utf8.encode('hello, not an index'))),
      );
    });

    test('another format version', () {
      expectRejected(
        tamper(index, (plain) => plain[4] = searchIndexFormatVersion + 1),
      );
    });

    test('another tokenizer version', () {
      final text = utf8.encode('"tokenizer":1');
      expectRejected(
        tamper(index, (plain) {
          final at = _find(plain, text);
          expect(at, isNot(-1));
          plain[at + text.length - 1] = '9'.codeUnitAt(0);
        }),
      );
    });

    test('lengths that point outside the data', () {
      expectRejected(
        tamper(index, (plain) {
          // The header length follows the magic and the version.
          plain[5] = 0x7F;
        }),
      );
    });

    test('extra bytes after the index', () {
      final longer = Uint8List.fromList([...gzip.decode(bytes), 1, 2, 3]);
      expectRejected(Uint8List.fromList(gzip.encode(longer)));
    });
  });
}

int _find(Uint8List haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var all = true;
    for (var j = 0; j < needle.length && all; j++) {
      all = haystack[i + j] == needle[j];
    }
    if (all) return i;
  }
  return -1;
}
