import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/search/passage_search.dart';
import 'package:loremark/search/search_index.dart';

import 'search_fixtures.dart';

List<String> ids(SearchResults results) => [
  for (final hit in results.hits)
    '${hit.passage.sectionIndex}:${hit.passage.paragraphIndex}',
];

void main() {
  final index = storyIndex();

  SearchResults search(String query, {ReaderPosition? cutoff, int? limit}) =>
      index.search(query, cutoff: cutoff ?? endOfStory, limit: limit ?? 50);

  group('ranking', () {
    test('finds the paragraphs with the word', () {
      expect(ids(search('lamp')), ['0:2']);
    });

    test('a paragraph repeating the word beats one that mentions it once', () {
      // Ryn: three times in 0:2, once in 0:3.
      expect(ids(search('ryn')), ['0:2', '0:3']);
    });

    test('a rare word counts for more than a common one', () {
      final results = search('harbor lamp');
      expect(results.hits.first.passage.sectionIndex, 0);
      expect(results.hits.first.passage.paragraphIndex, 2);
    });

    test('a paragraph with every query word beats one with a single word', () {
      final results = search('klein dalia harbor');
      // 2:0 has all three; 0:0 and 0:3 have klein (0:3 also harbor).
      expect(ids(results).first, '2:0');
    });

    test('length counts for no more below half the average', () {
      // A one-word line and a two-word line are both scored as if they had
      // four words: the average is about eight.
      final book = SearchIndex.build(
        bookId: 'short',
        stem: false,
        sectionTexts: [
          [
            'Ryn.',
            'Ryn again.',
            ...List.filled(
              6,
              'Nothing about anything at all happened here today.',
            ),
          ].join('\n\n'),
        ],
      );
      final hits = book.search('ryn', cutoff: const ReaderPosition(1, 0)).hits;
      expect(hits, hasLength(2));
      expect(hits[0].score, closeTo(hits[1].score, 1e-12));
    });

    test('scores fall in rank order and are positive', () {
      final scores = [for (final hit in search('harbor').hits) hit.score];
      expect(scores, isNotEmpty);
      expect(
        scores,
        orderedEquals([...scores]..sort((a, b) => b.compareTo(a))),
      );
      expect(scores.every((s) => s > 0), isTrue);
    });

    test('ignores case and accents', () {
      final accented = SearchIndex.build(
        bookId: 'a',
        sectionTexts: ['Un café très chaud.\n\nAutre chose.'],
        stem: false,
      );
      const end = ReaderPosition(1, 0);
      expect(accented.search('CAFE', cutoff: end).hits, hasLength(1));
      expect(accented.search('très', cutoff: end).hits, hasLength(1));
      expect(accented.search('tres', cutoff: end).hits, hasLength(1));
    });

    test('stems both the text and the query', () {
      expect(ids(search('running')), ids(search('runs')));
      expect(ids(search('keepers')), ids(search('keeper')));
      final unstemmed = storyIndex(stem: false);
      expect(unstemmed.search('runs', cutoff: endOfStory).hits, isEmpty);
    });

    test('common words in a question do not drown the content words', () {
      expect(ids(search('where is the lamp')), ['0:2']);
      expect(ids(search('where did dalia give the map')).first, '2:1');
    });

    test('a query of only common words still searches', () {
      expect(search('to be or not').hits, isNotEmpty);
    });

    test('an empty or symbol-only query finds nothing', () {
      expect(search('').hits, isEmpty);
      expect(search('   ').hits, isEmpty);
      expect(search('?!').hits, isEmpty);
      expect(search('"').hits, isEmpty);
    });

    test('respects the limit', () {
      expect(search('the harbor', limit: 2).hits, hasLength(2));
      expect(search('the harbor', limit: 0).hits, isEmpty);
    });

    test('breaks ties by reading order', () {
      final twin = SearchIndex.build(
        bookId: 't',
        sectionTexts: ['Alpha beta.\n\nAlpha beta.\n\nGamma delta epsilon.'],
        stem: false,
      );
      final hits = twin.search('alpha', cutoff: const ReaderPosition(1, 0));
      expect(ids(hits), ['0:0', '0:1']);
    });
  });

  group('prefix', () {
    test('the word being typed matches longer words', () {
      expect(ids(search('lam')), ['0:2']);
      expect(ids(search('kle')), ids(search('klein')));
    });

    test('only the last word is a prefix', () {
      // "lam" is not the word being typed, so it matches nothing, and the
      // query is a worse match for the harbor paragraphs than "harbor".
      final partial = search('lam harbor');
      final alone = search('harbor');
      expect(ids(partial).toSet(), ids(alone).toSet());
      expect(partial.hits.first.score, lessThan(alone.hits.first.score));
    });

    test('a trailing space ends the word', () {
      expect(search('lam ').hits, isEmpty);
      expect(search('lamp ').hits, isNotEmpty);
    });

    test('a complete word beats words that only start with it', () {
      final book = SearchIndex.build(
        bookId: 'p',
        stem: false,
        sectionTexts: [
          'The tower stood alone.\n\nTowers rose by the sea.\n\nNothing here.',
        ],
      );
      final hits = book.search('tower', cutoff: const ReaderPosition(1, 0));
      expect(ids(hits), ['0:0', '0:1']);
      expect(hits.hits[0].score, greaterThan(hits.hits[1].score));
    });

    test('a single letter is not expanded', () {
      expect(search('l').hits, isEmpty);
    });

    test('an exact word and its longer forms are all found', () {
      expect(ids(search('ship')), containsAll(['0:2', '2:2']));
    });
  });

  group('phrases', () {
    test('a quoted phrase must appear in order', () {
      expect(ids(search('"old keeper"')), ['0:2']);
      expect(search('"keeper old"').hits, isEmpty);
    });

    test('the words of a quoted phrase must be next to each other', () {
      // Both words are in 0:2, but not together.
      expect(search('"lamp keeper"').hits, isEmpty);
      expect(ids(search('"map of the glass harbor"')), ['2:1']);
    });

    test('common words count inside a quoted phrase', () {
      expect(ids(search('"to be or not to be"')), ['2:1']);
      expect(search('"to be or not to run"').hits, isEmpty);
    });

    test('a phrase matches through punctuation and case', () {
      expect(ids(search('"GLASS harbor"')), ['2:1']);
    });

    test('stemming applies inside the phrase', () {
      expect(ids(search('"ships were run"')), ['2:2']);
    });

    test('an unquoted query ranks the words in a row first', () {
      final book = SearchIndex.build(
        bookId: 'ph',
        stem: false,
        sectionTexts: [
          [
            'Dark harbor at dawn with gulls crying over the grey water.',
            'Dark gulls near the harbor.',
            'Nothing happens here today at all.',
            'Nothing happens there either.',
            'Gulls cry.',
          ].join('\n\n'),
        ],
      );
      final results = book.search(
        'dark harbor',
        cutoff: const ReaderPosition(1, 0),
      );
      expect(ids(results), ['0:0', '0:1']);
      // The shorter paragraph would win on length alone.
      final reversed = book.search(
        'harbor dark',
        cutoff: const ReaderPosition(1, 0),
      );
      expect(ids(reversed), ['0:1', '0:0']);
    });

    test('a one-word phrase is an ordinary word', () {
      expect(ids(search('"lamp"')), ['0:2']);
    });

    test('an unclosed quote runs to the end', () {
      expect(ids(search('"old keeper')), ['0:2']);
    });
  });

  group('Chinese', () {
    final book = SearchIndex.build(
      bookId: 'zh',
      stem: false,
      sectionTexts: [
        '克莱恩在陌生的房间里醒来。\n\n'
            '他想起了愚者。\n\n'
            '克莱门特是另一个人，他不认识克莱恩。\n\n'
            '魔药的配方很复杂。\n\n'
            '克莱门特来了。',
      ],
    );
    const end = ReaderPosition(1, 0);

    test('finds a name by its bigrams', () {
      expect(ids(book.search('克莱恩', cutoff: end)), containsAll(['0:0', '0:2']));
    });

    test('a name needs all its characters in a row', () {
      // 克莱门特 shares 克莱 with 克莱恩 but not 莱恩.
      final both = unorderedEquals(['0:0', '0:2']);
      expect(ids(book.search('克莱恩', cutoff: end)), both);
      expect(ids(book.search('莱恩', cutoff: end)), both);
      expect(ids(book.search('克莱', cutoff: end)), hasLength(3));
    });

    test('a two-character word is one bigram', () {
      expect(ids(book.search('愚者', cutoff: end)), ['0:1']);
    });

    test('a single character is found as plain text', () {
      expect(ids(book.search('魔', cutoff: end)), ['0:3']);
      expect(ids(book.search('者', cutoff: end)), ['0:1']);
    });

    test('Chinese and English can be searched together', () {
      final mixed = SearchIndex.build(
        bookId: 'mix',
        stem: false,
        sectionTexts: ['Klein 克莱恩 woke.\n\nOnly Klein.\n\nOnly 克莱恩.'],
      );
      final hits = mixed.search(
        'klein 克莱恩',
        cutoff: const ReaderPosition(1, 0),
      );
      expect(ids(hits).first, '0:0');
      expect(hits.hits, hasLength(3));
    });

    test('highlights the whole name as one span', () {
      final hit = book.search('克莱恩', cutoff: end).hits.first;
      expect(hit.matches, hasLength(1));
      expect(
        hit.snippet.substring(hit.matches.single.start, hit.matches.single.end),
        '克莱恩',
      );
    });
  });

  group('snippets and spans', () {
    test('spans cover the matched words, case and accents as written', () {
      final book = SearchIndex.build(
        bookId: 's',
        stem: true,
        sectionTexts: [
          'Klein ran to the Café, and Klein sat down in the café.',
        ],
      );
      final hit = book
          .search('cafe', cutoff: const ReaderPosition(1, 0))
          .hits
          .single;
      final shown = [
        for (final span in hit.matches)
          hit.snippet.substring(span.start, span.end),
      ];
      expect(shown, ['Café', 'café']);
    });

    test('a short paragraph is shown whole', () {
      final hit = search('lamp').hits.single;
      expect(hit.snippet, hit.passage.text);
    });

    test('a long paragraph is cut around the match with ellipses', () {
      final filler = List.filled(40, 'plain words go on and on').join(' ');
      final book = SearchIndex.build(
        bookId: 'long',
        stem: false,
        sectionTexts: ['$filler dragon $filler.'],
      );
      final hit = book
          .search('dragon', cutoff: const ReaderPosition(1, 0))
          .hits
          .single;
      expect(hit.snippet.length, lessThan(300));
      expect(hit.snippet, startsWith('…'));
      expect(hit.snippet, endsWith('…'));
      expect(hit.snippet, contains('dragon'));
      final span = hit.matches.single;
      expect(hit.snippet.substring(span.start, span.end), 'dragon');
    });

    test('the window prefers the stretch with the most distinct words', () {
      final filler = List.filled(30, 'nothing to see here at all').join(' ');
      final book = SearchIndex.build(
        bookId: 'win',
        stem: false,
        sectionTexts: [
          'alpha $filler alpha $filler alpha $filler alpha beta $filler',
        ],
      );
      final hit = book
          .search('alpha beta', cutoff: const ReaderPosition(1, 0))
          .hits
          .single;
      expect(hit.snippet, contains('alpha beta'));
    });

    test('spans are sorted, inside the snippet and do not overlap', () {
      for (final query in ['the harbor', 'klein ryn', 'ship']) {
        for (final hit in search(query).hits) {
          var end = 0;
          for (final span in hit.matches) {
            expect(span.start, greaterThanOrEqualTo(end));
            expect(span.end, greaterThan(span.start));
            expect(span.end, lessThanOrEqualTo(hit.snippet.length));
            end = span.end;
          }
        }
      }
    });

    test('line breaks in a paragraph show as spaces', () {
      final book = SearchIndex.build(
        bookId: 'br',
        sectionTexts: ['first line\nsecond line has dragon'],
      );
      final hit = book
          .search('dragon', cutoff: const ReaderPosition(1, 0))
          .hits
          .single;
      expect(hit.snippet, 'first line second line has dragon');
    });
  });

  group('hit target', () {
    test('quotes the passage and locates it in the section', () {
      final hit = search('lamp').hits.single;
      final text = storySections[0];
      final target = hit.target;
      expect(target.sectionIndex, 0);
      expect(text, contains(target.highlight));
      expect(target.highlight, contains('lamp'));
      expect(target.highlight.contains('\n'), isFalse);
      expect(
        target.progression,
        closeTo(text.indexOf(target.highlight) / text.length, 1e-9),
      );
      expect(text, contains(target.before + target.highlight + target.after));
    });

    test('a hit in the second chapter targets that section', () {
      final hit = search('dalia').hits.first;
      expect(hit.target.sectionIndex, 2);
      expect(storySections[2], contains(hit.target.highlight));
    });
  });

  group('cutoff', () {
    test('only fully passed paragraphs are returned', () {
      // Section 0 is 4 paragraphs; stop in the middle of the third.
      final text = storySections[0];
      final third = text.indexOf('Ryn walked');
      final cutoff = ReaderPosition(0, (third + 10) / text.length);
      expect(ids(search('ryn', cutoff: cutoff)), isEmpty);
      expect(ids(search('klein', cutoff: cutoff)), ['0:0']);
    });

    test('counts what is past the cutoff without showing it', () {
      final results = search('ryn', cutoff: const ReaderPosition(0, 0));
      expect(results.hits, isEmpty);
      expect(results.hiddenMatches, 2);
    });

    test('hidden count shrinks as the reader advances', () {
      final text = storySections[0];
      final afterThird = text.indexOf('Klein and Ryn') - 1;
      final results = search(
        'ryn',
        cutoff: ReaderPosition(0, afterThird / text.length),
      );
      expect(ids(results), ['0:2']);
      expect(results.hiddenMatches, 1);
      expect(search('ryn').hiddenMatches, 0);
    });

    test('statistics come from the visible text only', () {
      // "harbor" is in 5 of the 7 paragraphs of the whole story but in 2 of
      // the first 4; its scores must be the ones a book that ends there
      // would give.
      final early = SearchIndex.build(
        bookId: 'early',
        stem: true,
        sectionTexts: [storySections[0]],
      );
      final partial = search('harbor', cutoff: const ReaderPosition(1, 0));
      final alone = early.search('harbor', cutoff: const ReaderPosition(1, 0));
      expect(partial.hits.map((h) => h.score), alone.hits.map((h) => h.score));
    });

    test('a prefix does not borrow terms from unread text', () {
      // "dalia" is first used in section 2.
      final before = search('dal', cutoff: const ReaderPosition(2, 0));
      expect(before.hits, isEmpty);
      expect(before.hiddenMatches, 0);
      final exact = search('dalia', cutoff: const ReaderPosition(2, 0));
      expect(exact.hits, isEmpty);
      expect(exact.hiddenMatches, 2);
    });

    test('the footnote section is never searched', () {
      expect(search('founded').hits, isEmpty);
      expect(search('founded').hiddenMatches, 0);
      expect(index.paragraphCount, 7);
    });

    test('nothing is read at the very start', () {
      final results = search('harbor', cutoff: const ReaderPosition(0, 0));
      expect(results.hits, isEmpty);
      expect(results.hiddenMatches, 5);
      expect(
        index.retrievePassages('harbor', cutoff: const ReaderPosition(0, 0)),
        isEmpty,
      );
    });
  });

  group('retrievePassages', () {
    test('returns the best passages with their text and positions', () {
      final passages = index.retrievePassages(
        'old keeper of the harbor',
        cutoff: endOfStory,
        limit: 2,
      );
      expect(passages, hasLength(2));
      expect(passages.first.sectionIndex, 0);
      expect(passages.first.paragraphIndex, 2);
      expect(passages.first.text, startsWith('Ryn walked in'));
      expect(
        passages.first.startProgression,
        lessThan(passages.first.endProgression),
      );
    });

    test('returns the paragraphs search does, in the same order', () {
      for (final query in ['harbor', 'klein ryn', '"glass harbor"', 'dal']) {
        final searched = ids(search(query, limit: 3));
        final retrieved = index
            .retrievePassages(query, cutoff: endOfStory, limit: 3)
            .map((p) => '${p.sectionIndex}:${p.paragraphIndex}');
        expect(retrieved, searched, reason: query);
      }
    });

    test('respects the cutoff', () {
      final passages = index.retrievePassages(
        'dalia',
        cutoff: const ReaderPosition(2, 0),
      );
      expect(passages, isEmpty);
    });
  });
}
