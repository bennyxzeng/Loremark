import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/search/paragraph_index.dart';
import 'package:loremark/search/passage_search.dart';
import 'package:loremark/search/query.dart';
import 'package:loremark/search/search_index.dart';
import 'package:loremark/search/stemmer.dart';
import 'package:loremark/search/tokenizer.dart';

import 'search_fixtures.dart';

/// The spoiler guarantee, checked on many random books, queries and cutoffs:
///
/// - every hit's paragraph is fully before the cutoff;
/// - every snippet, span and quote lies inside the visible text;
/// - every score equals the score from an index built on only the first `k`
///   paragraphs, i.e. nothing about unread text reaches the ranking;
/// - `hiddenMatches` equals a count made by brute force;
/// - a prefix never reaches a term first seen after the cutoff;
/// - `retrievePassages` returns exactly the visible hits and nothing else.
///
/// Seeded, so a failure repeats; the failing seed and inputs are in the
/// message.
void main() {
  const seed = 403;
  // The engine's common words, as far as the generated vocabulary has them.
  bool isStop(String term) =>
      const {'the', 'of', 'and', 'a', 'to'}.contains(term);

  test('no result, score, snippet or count depends on text past the cutoff', () {
    final random = Random(seed);
    var hits = 0;
    var hiddenTotal = 0;
    var emptyPrefixes = 0;
    var queries = 0;

    for (var b = 0; b < 40; b++) {
      final book = randomBook(random);
      final stem = random.nextBool();
      final index = SearchIndex.build(
        bookId: 'b$b',
        sectionTexts: book.texts,
        linear: book.linear,
        stem: stem,
      );
      final paragraphs = ParagraphIndex(book.texts, linear: book.linear);
      if (paragraphs.count == 0) continue;
      final tokenizer = Tokenizer(stem: stem ? porter2Stem : null);
      final termSets = [
        for (var id = 0; id < paragraphs.count; id++)
          {for (final t in tokenizer.tokenize(paragraphs.textOf(id))) t.term},
      ];

      for (var c = 0; c < 6; c++) {
        final cutoff = randomCutoff(random, paragraphs);
        final where = 'seed $seed, book $b, cutoff $cutoff';
        final k = index.visibleParagraphCount(cutoff);

        // The same count, one paragraph at a time.
        final fullyBefore = [
          for (var id = 0; id < paragraphs.count; id++)
            isFullyBefore(paragraphs, id, cutoff),
        ];
        expect(k, fullyBefore.where((v) => v).length, reason: where);
        expect(fullyBefore.take(k).every((v) => v), isTrue, reason: where);

        final truncated = SearchIndex.build(
          bookId: 'truncated',
          sectionTexts: truncatedTexts(book.texts, paragraphs, k),
          linear: book.linear,
          stem: stem,
        );
        const everything = ReaderPosition(1000, 0);
        final allTerms = {for (final terms in termSets) ...terms};
        final visibleTerms = {for (var id = 0; id < k; id++) ...termSets[id]};

        for (var q = 0; q < 10; q++) {
          final query = randomQuery(random);
          final why = '$where, query "$query"';
          queries++;

          final results = index.search(query, cutoff: cutoff, limit: 100);
          final expected = truncated.search(
            query,
            cutoff: everything,
            limit: 100,
          );
          hits += results.hits.length;
          hiddenTotal += results.hiddenMatches;

          // 1. Only paragraphs the reader has passed.
          for (final hit in results.hits) {
            final id = paragraphs.idOf(
              hit.passage.sectionIndex,
              hit.passage.paragraphIndex,
            );
            expect(id, isNotNull, reason: why);
            expect(id! < k && fullyBefore[id], isTrue, reason: why);
            expect(paragraphs.textOf(id), hit.passage.text, reason: why);
            expectInsideVisibleText(hit, paragraphs, id, k, why);
          }

          // 2. Scores, order and text as if the book ended at the cutoff.
          expect(
            results.hits.map(describe).toList(),
            expected.hits.map(describe).toList(),
            reason: why,
          );
          for (var i = 0; i < results.hits.length; i++) {
            expect(
              results.hits[i].score,
              closeTo(expected.hits[i].score, 1e-9),
              reason: why,
            );
          }
          expect(expected.hiddenMatches, 0, reason: why);

          // 3. The count of what is past the cutoff.
          expect(
            results.hiddenMatches,
            bruteForceHidden(
              query,
              tokenizer,
              paragraphs,
              termSets,
              visibleTerms,
              k,
              isStop,
            ),
            reason: why,
          );

          // 4. The retrieval API shows no more than search does.
          final passages = index.retrievePassages(
            query,
            cutoff: cutoff,
            limit: 100,
          );
          expect(
            passages.map((p) => '${p.sectionIndex}:${p.paragraphIndex}'),
            results.hits.map(
              (h) => '${h.passage.sectionIndex}:${h.passage.paragraphIndex}',
            ),
            reason: why,
          );
          for (final passage in passages) {
            final id = paragraphs.idOf(
              passage.sectionIndex,
              passage.paragraphIndex,
            );
            expect(id! < k, isTrue, reason: why);
          }
        }

        // 5. A prefix of a word first used after the cutoff finds nothing
        // and counts nothing, unless a word already read starts the same.
        final hiddenOnly = {
          for (var id = k; id < paragraphs.count; id++) ...termSets[id],
        }.difference(visibleTerms);
        for (final term in hiddenOnly) {
          if (!RegExp(r'^[a-z]{4,}$').hasMatch(term)) continue;
          final prefix = term.substring(0, 3);
          if (visibleTerms.any((t) => t.startsWith(prefix))) continue;
          // Typing a whole hidden word is an exact search, which may count it.
          if (allTerms.contains(tokenizer.termFor(prefix))) continue;
          final results = index.search(prefix, cutoff: cutoff);
          expect(results.hits, isEmpty, reason: '$where, prefix $prefix');
          expect(
            results.hiddenMatches,
            0,
            reason: '$where, prefix $prefix leaked a hidden term',
          );
          emptyPrefixes++;
        }
      }
    }

    // The generated cases really exercised the interesting paths.
    expect(queries, greaterThan(1000));
    expect(hits, greaterThan(500));
    expect(hiddenTotal, greaterThan(500));
    expect(emptyPrefixes, greaterThan(20));
  });

  test('a cutoff in the middle of a paragraph excludes the paragraph', () {
    final random = Random(seed + 1);
    for (var b = 0; b < 20; b++) {
      final book = randomBook(random);
      final paragraphs = ParagraphIndex(book.texts, linear: book.linear);
      final index = SearchIndex.build(
        bookId: 'm$b',
        sectionTexts: book.texts,
        linear: book.linear,
        stem: false,
      );
      for (var id = 0; id < paragraphs.count; id++) {
        final length = book.texts[paragraphs.sectionOf(id)].length;
        final start = paragraphs.startOf(id);
        final end = paragraphs.endOf(id);
        if (end - start < 2) continue;
        // One character before the end of the paragraph.
        final inside = ReaderPosition(
          paragraphs.sectionOf(id),
          (end - 0.5) / length,
        );
        expect(
          index.visibleParagraphCount(inside),
          lessThanOrEqualTo(id),
          reason: 'paragraph $id',
        );
        // Exactly its end, written as the largest fraction that floors to it.
        final atEnd = ReaderPosition(
          paragraphs.sectionOf(id),
          (end + 0.5) / length,
        );
        if ((end + 0.5) / length < 1) {
          expect(
            index.visibleParagraphCount(atEnd),
            greaterThan(id),
            reason: 'paragraph $id',
          );
        }
      }
    }
  });
}

/// Fully passed means: an earlier section, or this section finished, or ends
/// at or before the floor of progression times the section's length.
bool isFullyBefore(ParagraphIndex paragraphs, int id, ReaderPosition cutoff) {
  final section = paragraphs.sectionOf(id);
  if (section < cutoff.sectionIndex) return true;
  if (section > cutoff.sectionIndex) return false;
  if (cutoff.progression >= 1) return true;
  final length = paragraphs.sectionTexts[section].length;
  return paragraphs.endOf(id) <= (cutoff.progression * length).floor();
}

ReaderPosition randomCutoff(Random random, ParagraphIndex paragraphs) {
  final section = random.nextInt(paragraphs.sectionCount + 1);
  switch (random.nextInt(5)) {
    case 0:
      return ReaderPosition(section, 0);
    case 1:
      return ReaderPosition(section, 1);
    case 2:
      // Exactly at a paragraph's end, the knife-edge case.
      final id = random.nextInt(paragraphs.count);
      final length = paragraphs.sectionTexts[paragraphs.sectionOf(id)].length;
      return ReaderPosition(
        paragraphs.sectionOf(id),
        paragraphs.endOf(id) / length,
      );
    default:
      return ReaderPosition(section, random.nextDouble());
  }
}

/// The text of a book that ends after the first [k] paragraphs.
List<String> truncatedTexts(
  List<String> texts,
  ParagraphIndex paragraphs,
  int k,
) {
  final result = List.filled(texts.length, '');
  for (var id = 0; id < k; id++) {
    final section = paragraphs.sectionOf(id);
    result[section] = texts[section].substring(0, paragraphs.endOf(id));
  }
  return result;
}

/// Everything shown for [hit] comes from the first [k] paragraphs.
void expectInsideVisibleText(
  SearchHit hit,
  ParagraphIndex paragraphs,
  int id,
  int k,
  String why,
) {
  final paragraph = hit.passage.text.replaceAll('\n', ' ');
  final snippet = hit.snippet;
  expect(paragraph, contains(snippet.replaceAll('…', '').trim()), reason: why);
  for (final span in hit.matches) {
    expect(span.start, inInclusiveRange(0, snippet.length), reason: why);
    expect(span.end, inInclusiveRange(span.start, snippet.length), reason: why);
    expect(paragraph, contains(snippet.substring(span.start, span.end)));
  }

  final section = hit.target.sectionIndex;
  final text = paragraphs.sectionTexts[section];
  final visibleEnd = paragraphs.visibleTextEnd(id, k);
  final target = hit.target;
  final start = (target.progression * text.length).round();
  expect(text.startsWith(target.highlight, start), isTrue, reason: why);
  expect(
    start,
    inInclusiveRange(paragraphs.startOf(id), paragraphs.endOf(id)),
    reason: why,
  );
  expect(
    start + target.highlight.length,
    lessThanOrEqualTo(paragraphs.endOf(id)),
    reason: why,
  );
  expect(start - target.before.length, greaterThanOrEqualTo(0), reason: why);
  expect(
    text.substring(start - target.before.length, start),
    target.before,
    reason: why,
  );
  final end = start + target.highlight.length;
  expect(end + target.after.length, lessThanOrEqualTo(visibleEnd), reason: why);
  expect(text.substring(end, end + target.after.length), target.after);
}

String randomQuery(Random random) {
  String word() => vocabulary[random.nextInt(vocabulary.length)];
  String ascii() {
    while (true) {
      final w = word();
      if (RegExp(r"^[a-zA-Zïé']+$").hasMatch(w)) return w;
    }
  }

  String prefix() {
    final w = ascii();
    return w.substring(0, min(w.length, 2 + random.nextInt(4)));
  }

  String cased(String w) =>
      random.nextInt(5) == 0 ? '${w[0].toUpperCase()}${w.substring(1)}' : w;

  switch (random.nextInt(8)) {
    case 0:
      return cased(word());
    case 1:
      return '${cased(word())} ${word()}';
    case 2:
      return '${word()} ${word()} ${word()}';
    case 3:
      return '"${word()} ${word()}"';
    case 4:
      return prefix();
    case 5:
      return '${word()} ${prefix()}';
    case 6:
      return random.nextBool() ? '魔' : '克莱恩 ${word()}';
    default:
      return '"${word()} ${word()}" ${word()} ${prefix()}';
  }
}

/// The paragraphs from [k] on that would be candidates for [query]: every
/// required phrase has all its terms, and at least one part of the query
/// matches. Worked out paragraph by paragraph from the text.
int bruteForceHidden(
  String query,
  Tokenizer tokenizer,
  ParagraphIndex paragraphs,
  List<Set<String>> termSets,
  Set<String> visibleTerms,
  int k,
  bool Function(String) isStop,
) {
  final parts = parseQuery(query, tokenizer, isStopTerm: isStop);
  var count = 0;
  for (var id = k; id < paragraphs.count; id++) {
    final terms = termSets[id];
    bool has(QueryPart part) {
      final substring = part.substring;
      if (substring != null) return paragraphs.textOf(id).contains(substring);
      if (part.phrase) return part.tokens.every((t) => terms.contains(t.term));
      final term = part.tokens.single.term;
      if (terms.contains(term)) return true;
      final prefix = part.prefixText;
      return prefix != null &&
          terms.any((t) => visibleTerms.contains(t) && t.startsWith(prefix));
    }

    final required = parts.where((p) => p.required);
    if (required.every(has) && parts.any(has)) count++;
  }
  return count;
}
