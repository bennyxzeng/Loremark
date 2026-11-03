import 'dart:math';
import 'dart:typed_data';

import '../reader/reader_position.dart';
import 'paragraph_index.dart';
import 'passage_search.dart';
import 'query.dart';
import 'snippet.dart';
import 'stemmer.dart';
import 'tokenizer.dart';

/// What a [SearchIndex] keeps on disk, and nothing else, so the codec can
/// write and read an index without a way into its search internals.
///
/// Section texts are part of it so loading an index never re-parses the
/// EPUB. This is for persistence only; searching goes through
/// [PassageSearch].
class SearchIndexData {
  const SearchIndexData({
    required this.bookId,
    required this.stemmed,
    required this.sectionTexts,
    required this.linear,
    required this.tokenCounts,
    required this.terms,
    required this.termStarts,
    required this.postings,
  });

  final String bookId;

  /// Whether English stemming was applied to the terms.
  final bool stemmed;

  /// Plain text per spine item, empty for non-linear ones.
  final List<String> sectionTexts;
  final List<bool> linear;

  /// Tokens in each paragraph, by paragraph id.
  final Int32List tokenCounts;

  /// Every term of the book, sorted.
  final List<String> terms;

  /// Where each term's postings start in [postings], with one extra entry for
  /// the end. Counts ints, so every value is even.
  final Int32List termStarts;

  /// `(paragraph id, term frequency)` pairs, sorted by paragraph id within a
  /// term.
  final Int32List postings;
}

/// Full-text search over one book with the spoiler cutoff built in.
///
/// An inverted index over paragraphs ranked with BM25 (as in Lucene, Tantivy
/// and MiniSearch: k1 1.2, b 0.75, idf `ln(1 + (N - n + 0.5) / (n + 0.5))`).
/// Postings are sorted by paragraph id and paragraphs are numbered in reading
/// order, so everything the reader has passed is a prefix of the ids. The
/// number of paragraphs, each term's document frequency and the average
/// length are all taken over that prefix, which makes every score exactly the
/// score of a book that ends at the cutoff: nothing about unread text leaks
/// into the ranking. See docs/search.md.
class SearchIndex implements PassageSearch {
  /// Indexes [sectionTexts] (one per spine item, in order).
  ///
  /// [stem] chooses English stemming (on by default). It must not be
  /// inferred from unread text, which would change visible search results.
  factory SearchIndex.build({
    required String bookId,
    required List<String> sectionTexts,
    List<bool>? linear,
    bool? stem,
  }) {
    final isLinear = linear ?? List.filled(sectionTexts.length, true);
    final paragraphs = ParagraphIndex(sectionTexts, linear: isLinear);
    final stemmed = stem ?? true;
    final tokenizer = Tokenizer(stem: stemmed ? porter2Stem : null);

    final counts = Int32List(paragraphs.count);
    final builders = <String, List<int>>{};
    final frequencies = <String, int>{};
    for (var id = 0; id < paragraphs.count; id++) {
      final tokens = tokenizer.tokenize(paragraphs.textOf(id));
      counts[id] = tokens.length;
      frequencies.clear();
      for (final token in tokens) {
        frequencies[token.term] = (frequencies[token.term] ?? 0) + 1;
      }
      for (final MapEntry(:key, :value) in frequencies.entries) {
        (builders[key] ??= []).addAll([id, value]);
      }
    }
    final terms = builders.keys.toList()..sort();
    final starts = Int32List(terms.length + 1);
    var total = 0;
    for (var i = 0; i < terms.length; i++) {
      starts[i] = total;
      total += builders[terms[i]]!.length;
    }
    starts[terms.length] = total;
    final postings = Int32List(total);
    for (var i = 0; i < terms.length; i++) {
      postings.setAll(starts[i], builders[terms[i]]!);
    }
    return SearchIndex.fromData(
      SearchIndexData(
        bookId: bookId,
        stemmed: stemmed,
        sectionTexts: paragraphs.sectionTexts,
        linear: isLinear,
        tokenCounts: counts,
        terms: terms,
        termStarts: starts,
        postings: postings,
      ),
    );
  }

  /// Rebuilds an index from what [toData] gave. Throws a [FormatException]
  /// if the parts don't fit together.
  factory SearchIndex.fromData(SearchIndexData data) {
    final paragraphs = ParagraphIndex(data.sectionTexts, linear: data.linear);
    if (data.tokenCounts.length != paragraphs.count ||
        data.termStarts.length != data.terms.length + 1 ||
        data.termStarts.last != data.postings.length) {
      throw const FormatException('Search index parts do not fit together');
    }
    if (data.termStarts.first != 0 || data.postings.length.isOdd) {
      throw const FormatException('Invalid search postings offsets');
    }
    for (var term = 0; term < data.terms.length; term++) {
      final start = data.termStarts[term];
      final end = data.termStarts[term + 1];
      if (data.terms[term].isEmpty ||
          (term > 0 && data.terms[term - 1].compareTo(data.terms[term]) >= 0) ||
          start < 0 ||
          start.isOdd ||
          end <= start ||
          end.isOdd ||
          end > data.postings.length) {
        throw const FormatException('Invalid search term or postings range');
      }
      var previous = -1;
      for (var i = start; i < end; i += 2) {
        final id = data.postings[i];
        final frequency = data.postings[i + 1];
        if (id <= previous ||
            id >= paragraphs.count ||
            frequency <= 0 ||
            frequency > data.tokenCounts[id]) {
          throw const FormatException('Invalid search posting');
        }
        previous = id;
      }
    }
    final cumulative = Int32List(paragraphs.count + 1);
    for (var i = 0; i < paragraphs.count; i++) {
      if (data.tokenCounts[i] < 0) {
        throw const FormatException('Invalid paragraph token count');
      }
      cumulative[i + 1] = cumulative[i] + data.tokenCounts[i];
    }
    return SearchIndex._(data, paragraphs, cumulative);
  }

  SearchIndex._(this._data, this._paragraphs, this._cumulative)
    : _tokenizer = Tokenizer(stem: _data.stemmed ? porter2Stem : null) {
    _stopTerms = {
      for (final word in _stopWords) ...[word, _tokenizer.termFor(word)],
    };
  }

  final SearchIndexData _data;
  final ParagraphIndex _paragraphs;

  /// Tokens in paragraphs `[0, i)`, to get the average length of any prefix.
  final Int32List _cumulative;
  final Tokenizer _tokenizer;
  late final Set<String> _stopTerms;

  static const _k1 = 1.2;
  static const _b = 0.75;

  /// How many results a prefix such as `kl` may borrow terms for.
  static const _maxPrefixTerms = 50;

  /// Candidates re-checked for phrases and adjacency per search, at least.
  static const _verifyAtLeast = 60;
  static const _verifyAtMost = 2000;

  String get bookId => _data.bookId;
  bool get stemmed => _data.stemmed;
  int get paragraphCount => _paragraphs.count;
  int get termCount => _data.terms.length;

  /// How many paragraphs a reader at [cutoff] has fully passed.
  int visibleParagraphCount(ReaderPosition cutoff) =>
      _paragraphs.visibleCount(cutoff);

  /// The parts to save, for the codec.
  SearchIndexData toData() => _data;

  @override
  SearchResults search(
    String query, {
    required ReaderPosition cutoff,
    int limit = 50,
  }) {
    final k = _paragraphs.visibleCount(cutoff);
    final units = _plan(query, k);
    if (units.isEmpty) return SearchResults.empty;
    final hidden = _hiddenMatches(units, k);
    if (limit <= 0 || k == 0) {
      return SearchResults(hits: const [], hiddenMatches: hidden);
    }
    return SearchResults(
      hits: [for (final r in _rank(units, k, limit)) _hit(units, r, k)],
      hiddenMatches: hidden,
    );
  }

  @override
  List<Passage> retrievePassages(
    String query, {
    required ReaderPosition cutoff,
    int limit = 8,
  }) {
    final k = _paragraphs.visibleCount(cutoff);
    final units = _plan(query, k);
    if (units.isEmpty || limit <= 0 || k == 0) return const [];
    return [for (final r in _rank(units, k, limit)) _paragraphs.passage(r.id)];
  }

  // ---- Planning: from query text to postings ranges ----

  List<_Unit> _plan(String query, int k) {
    final parts = parseQuery(
      query,
      _tokenizer,
      isStopTerm: _stopTerms.contains,
    );
    final units = <_Unit>[];
    for (final part in parts) {
      if (part.substring != null) {
        units.add(_Unit(part, const [], const {}));
      } else if (part.phrase) {
        final ids = [for (final token in part.tokens) _find(token.term)];
        units.add(
          _Unit(
            part,
            ids.contains(-1) ? const [] : [_Component(ids.toSet().toList(), 1)],
            {for (final token in part.tokens) token.term},
          ),
        );
      } else {
        final token = part.tokens.single;
        final components = <_Component>[];
        final terms = <String>{};
        final exact = _find(token.term);
        if (exact != -1) {
          components.add(_Component([exact], 1));
          terms.add(token.term);
        }
        final prefix = part.prefixText;
        if (prefix != null) {
          for (final (id, weight) in _expand(prefix, exact, k)) {
            components.add(_Component([id], weight));
            terms.add(_data.terms[id]);
          }
        }
        units.add(_Unit(part, components, terms));
      }
    }
    return units;
  }

  /// Terms that start with [prefix] and occur before the cutoff, best first
  /// by how many paragraphs they are in. Terms that first appear after the
  /// cutoff are left out, so typing `kl` can't reveal a late character.
  ///
  /// Weights follow MiniSearch (MIT): `0.375 * len / (len + 0.3 * extra)`,
  /// where `extra` is how many letters the term adds to what was typed.
  List<(int, double)> _expand(String prefix, int exact, int k) {
    final terms = _data.terms;
    final found = <(int, int)>[]; // (term, visible document frequency)
    for (var i = _lowerBound(prefix); i < terms.length; i++) {
      if (!terms[i].startsWith(prefix)) break;
      if (i == exact || _data.postings[_data.termStarts[i]] >= k) continue;
      found.add((i, _visibleEnd(i, k) - _data.termStarts[i]));
    }
    found.sort((a, b) {
      final byFrequency = b.$2.compareTo(a.$2);
      return byFrequency != 0 ? byFrequency : a.$1.compareTo(b.$1);
    });
    return [
      for (final (id, _) in found.take(_maxPrefixTerms))
        (
          id,
          0.375 *
              prefix.length /
              (prefix.length + 0.3 * (terms[id].length - prefix.length)),
        ),
    ];
  }

  int _find(String term) {
    final at = _lowerBound(term);
    return at < _data.terms.length && _data.terms[at] == term ? at : -1;
  }

  int _lowerBound(String term) {
    var low = 0;
    var high = _data.terms.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_data.terms[middle].compareTo(term) < 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  /// Where the postings of [term] that come before paragraph [k] end: the
  /// first posting at or after [k], found by binary search, since postings
  /// are sorted by paragraph id.
  int _visibleEnd(int term, int k) {
    var low = _data.termStarts[term] >> 1;
    var high = _data.termStarts[term + 1] >> 1;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_data.postings[middle << 1] < k) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low << 1;
  }

  /// The term frequency of [term] in paragraph [id], or 0.
  int _frequency(int term, int id, int end) {
    var low = _data.termStarts[term] >> 1;
    var high = end >> 1;
    while (low < high) {
      final middle = (low + high) >> 1;
      final found = _data.postings[middle << 1];
      if (found == id) return _data.postings[(middle << 1) + 1];
      if (found < id) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return 0;
  }

  // ---- Scoring ----

  double _idf(int total, int containing) =>
      log(1 + (total - containing + 0.5) / (containing + 0.5));

  /// The BM25 term-frequency part. A paragraph shorter than half the average
  /// is scored as if it were that long: a three-word line of dialogue
  /// shouldn't beat a real paragraph just for being short. (Our own tweak;
  /// the libraries don't do it.)
  double _tfNorm(int frequency, int length, double averageLength) {
    final scored = max(length.toDouble(), 0.5 * averageLength);
    return frequency *
        (_k1 + 1) /
        (frequency + _k1 * (1 - _b + _b * scored / averageLength));
  }

  /// Paragraph id to score for one query unit, over paragraphs before [k]
  /// only. Document frequencies, the paragraph count and the average length
  /// are all those of the prefix, so unread text can't influence a score.
  Map<int, double> _scoreUnit(_Unit unit, int k, double averageLength) {
    final scores = <int, double>{};
    final substring = unit.part.substring;
    if (substring != null) {
      final counts = _substringCounts(substring, 0, k);
      final idf = _idf(k, counts.length);
      for (final MapEntry(:key, :value) in counts.entries) {
        scores[key] =
            idf * _tfNorm(value, _data.tokenCounts[key], averageLength);
      }
      return scores;
    }
    for (final component in unit.components) {
      final terms = component.terms;
      final ends = [for (final term in terms) _visibleEnd(term, k)];
      if (terms.length == 1) {
        final start = _data.termStarts[terms.first];
        final idf = _idf(k, (ends.first - start) >> 1);
        for (var i = start; i < ends.first; i += 2) {
          final id = _data.postings[i];
          scores[id] =
              (scores[id] ?? 0) +
              component.weight *
                  idf *
                  _tfNorm(
                    _data.postings[i + 1],
                    _data.tokenCounts[id],
                    averageLength,
                  );
        }
        continue;
      }
      // A phrase: only paragraphs holding every term. Walk the rarest term.
      var rarest = 0;
      for (var j = 1; j < terms.length; j++) {
        if (ends[j] - _data.termStarts[terms[j]] <
            ends[rarest] - _data.termStarts[terms[rarest]]) {
          rarest = j;
        }
      }
      final idfs = [
        for (var j = 0; j < terms.length; j++)
          _idf(k, (ends[j] - _data.termStarts[terms[j]]) >> 1),
      ];
      for (var i = _data.termStarts[terms[rarest]]; i < ends[rarest]; i += 2) {
        final id = _data.postings[i];
        var score = 0.0;
        for (var j = 0; j < terms.length; j++) {
          final frequency = j == rarest
              ? _data.postings[i + 1]
              : _frequency(terms[j], id, ends[j]);
          if (frequency == 0) {
            score = -1;
            break;
          }
          score +=
              idfs[j] *
              _tfNorm(frequency, _data.tokenCounts[id], averageLength);
        }
        if (score >= 0) scores[id] = (scores[id] ?? 0) + score;
      }
    }
    return scores;
  }

  /// How many times the single character [text] occurs in each paragraph of
  /// ids `[from, to)`. A single CJK character is in no bigram, so it can only
  /// be found by scanning.
  Map<int, int> _substringCounts(String text, int from, int to) {
    final counts = <int, int>{};
    if (from >= to) return counts;
    for (
      var section = _paragraphs.sectionOf(from);
      section < _paragraphs.sectionCount && _paragraphs.firstIdOf(section) < to;
      section++
    ) {
      final first = max(from, _paragraphs.firstIdOf(section));
      final last = min(to, _paragraphs.firstIdOf(section + 1));
      if (first >= last) continue;
      final source = _paragraphs.sectionTexts[section];
      var id = first;
      var at = source.indexOf(text, _paragraphs.startOf(first));
      while (at != -1 && id < last) {
        while (id < last && _paragraphs.endOf(id) <= at) {
          id++;
        }
        if (id >= last) break;
        if (at >= _paragraphs.startOf(id)) {
          counts[id] = (counts[id] ?? 0) + 1;
        }
        at = source.indexOf(text, at + text.length);
      }
    }
    return counts;
  }

  // ---- Ranking ----

  List<_Ranked> _rank(List<_Unit> units, int k, int limit) {
    final averageLength = _cumulative[k] / k;
    final scores = [
      for (final unit in units) _scoreUnit(unit, k, averageLength),
    ];
    final required = [
      for (var u = 0; u < units.length; u++)
        if (units[u].part.required) u,
    ];
    final candidates = <_Ranked>[];
    final ids = <int>{for (final unitScores in scores) ...unitScores.keys};
    for (final id in ids) {
      if (required.any((u) => !scores[u].containsKey(id))) continue;
      final matched = <int>[
        for (var u = 0; u < units.length; u++)
          if (scores[u].containsKey(id)) u,
      ];
      candidates.add(
        _Ranked(
          id,
          _combine(
            [for (final u in matched) scores[u][id]!],
            matched.length,
            units.length,
          ),
          matched,
        ),
      );
    }
    candidates.sort(_byScore);

    final checkAdjacency = units.length >= 2 && units.every(_isPlainWord);
    if (!units.any((u) => u.part.phrase) && !checkAdjacency) {
      return candidates.take(limit).toList();
    }

    // Phrases and adjacency need the paragraph's own tokens, so only the best
    // candidates are checked, in order, until enough survive.
    final wanted = max(limit * 3, _verifyAtLeast);
    final survivors = <_Ranked>[];
    var visited = 0;
    for (final candidate in candidates) {
      if (survivors.length >= wanted || visited >= _verifyAtMost) break;
      visited++;
      final tokens = _tokenizer.tokenize(_paragraphs.textOf(candidate.id));
      final matched = <int>[];
      final phrases = <int, List<int>>{};
      var dropped = false;
      for (final u in candidate.matched) {
        if (!units[u].part.phrase) {
          matched.add(u);
          continue;
        }
        final starts = _phraseStarts(tokens, units[u].part.tokens);
        if (starts.isNotEmpty) {
          matched.add(u);
          phrases[u] = starts;
        } else if (units[u].part.required) {
          dropped = true;
          break;
        }
      }
      if (dropped || matched.isEmpty) continue;
      var score = _combine(
        [for (final u in matched) scores[u][candidate.id]!],
        matched.length,
        units.length,
      );
      if (checkAdjacency && _adjacent(tokens, units)) score *= 1.5;
      survivors.add(_Ranked(candidate.id, score, matched, tokens, phrases));
    }
    survivors.sort(_byScore);
    return survivors.take(limit).toList();
  }

  /// Sum of the parts' scores, scaled by the square of the share of the query
  /// the paragraph matches: Lucene's old coordination factor, which keeps a
  /// paragraph with one rare word from beating one with all of them.
  double _combine(List<double> parts, int matched, int total) {
    final share = matched / total;
    return parts.fold(0.0, (a, b) => a + b) * share * share;
  }

  static int _byScore(_Ranked a, _Ranked b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.id.compareTo(b.id);
  }

  static bool _isPlainWord(_Unit unit) =>
      !unit.part.phrase && unit.part.substring == null && !unit.part.required;

  /// Where in [tokens] the [phrase] occurs. Bigrams of one CJK run must also
  /// overlap in the text, so two runs that end and begin alike don't count.
  List<int> _phraseStarts(List<Token> tokens, List<Token> phrase) {
    final starts = <int>[];
    for (var i = 0; i + phrase.length <= tokens.length; i++) {
      var all = true;
      for (var j = 0; j < phrase.length && all; j++) {
        all = tokens[i + j].term == phrase[j].term;
        if (all &&
            j > 0 &&
            phrase[j].cjk &&
            phrase[j - 1].cjk &&
            phrase[j].start < phrase[j - 1].end) {
          all = tokens[i + j].start < tokens[i + j - 1].end;
        }
      }
      if (all) starts.add(i);
    }
    return starts;
  }

  /// Whether the query's words occur one after another, in order.
  bool _adjacent(List<Token> tokens, List<_Unit> units) {
    for (var i = 0; i + units.length <= tokens.length; i++) {
      var all = true;
      for (var j = 0; j < units.length && all; j++) {
        all = units[j].matchTerms.contains(tokens[i + j].term);
      }
      if (all) return true;
    }
    return false;
  }

  // ---- Results ----

  SearchHit _hit(List<_Unit> units, _Ranked ranked, int k) {
    final id = ranked.id;
    final text = _paragraphs.textOf(id);
    final tokens = ranked.tokens ?? _tokenizer.tokenize(text);
    final matches = <TextMatch>[];
    for (final u in ranked.matched) {
      final unit = units[u];
      final substring = unit.part.substring;
      if (substring != null) {
        for (var at = text.indexOf(substring); at != -1;) {
          matches.add(TextMatch(at, at + substring.length, u));
          at = text.indexOf(substring, at + substring.length);
        }
      } else if (unit.part.phrase) {
        final length = unit.part.tokens.length;
        for (final start
            in ranked.phrases[u] ?? _phraseStarts(tokens, unit.part.tokens)) {
          matches.add(
            TextMatch(tokens[start].start, tokens[start + length - 1].end, u),
          );
        }
      } else {
        for (final token in tokens) {
          if (unit.matchTerms.contains(token.term)) {
            matches.add(TextMatch(token.start, token.end, u));
          }
        }
      }
    }
    final snippet = buildSnippet(text, matches);
    final section = _paragraphs.sectionOf(id);
    final start = _paragraphs.startOf(id);
    return SearchHit(
      passage: _paragraphs.passage(id),
      score: ranked.score,
      snippet: snippet.text,
      matches: snippet.spans,
      target: buildPassageTarget(
        sectionIndex: section,
        sectionText: _paragraphs.sectionTexts[section],
        paragraphStart: start,
        paragraphEnd: _paragraphs.endOf(id),
        matchStart: start + snippet.focusStart,
        matchEnd: start + max(snippet.focusEnd, snippet.focusStart),
        visibleEnd: _paragraphs.visibleTextEnd(id, k),
      ),
    );
  }

  // ---- Counting what the reader hasn't reached ----

  /// How many paragraphs from [k] on contain the query's terms.
  ///
  /// Counted from the tails of the postings lists, and by scanning for lone
  /// CJK characters, without scoring, verifying phrases or touching a word of
  /// the text. A paragraph counts if it holds every part of each required
  /// phrase and at least one part of the query. Prefix terms are the ones
  /// that appear before the cutoff.
  int _hiddenMatches(List<_Unit> units, int k) {
    if (k >= _paragraphs.count) return 0;
    Set<int>? required;
    final any = <int>{};
    for (final unit in units) {
      final hits = _hiddenHits(unit, k);
      any.addAll(hits);
      if (unit.part.required) {
        required = required == null ? hits : required.intersection(hits);
      }
    }
    return (required ?? any).length;
  }

  Set<int> _hiddenHits(_Unit unit, int k) {
    final substring = unit.part.substring;
    if (substring != null) {
      return _substringCounts(substring, k, _paragraphs.count).keys.toSet();
    }
    final hits = <int>{};
    for (final component in unit.components) {
      Set<int>? all;
      for (final term in component.terms) {
        final tail = <int>{
          for (
            var i = _visibleEnd(term, k);
            i < _data.termStarts[term + 1];
            i += 2
          )
            _data.postings[i],
        };
        all = all == null ? tail : all.intersection(tail);
      }
      hits.addAll(all ?? const {});
    }
    return hits;
  }
}

/// A term, or terms that must all be in a paragraph, with how much a match
/// counts.
class _Component {
  _Component(this.terms, this.weight);

  final List<int> terms;
  final double weight;
}

class _Unit {
  _Unit(this.part, this.components, this.matchTerms);

  final QueryPart part;
  final List<_Component> components;

  /// Terms whose tokens count as a match, for highlighting.
  final Set<String> matchTerms;
}

class _Ranked {
  _Ranked(
    this.id,
    this.score,
    this.matched, [
    this.tokens,
    this.phrases = const {},
  ]);

  final int id;
  final double score;

  /// The query units the paragraph matched.
  final List<int> matched;
  final List<Token>? tokens;

  /// For phrase units, the token index each occurrence starts at.
  final Map<int, List<int>> phrases;
}

/// Common English words that are not worth ranking by in a question. They
/// stay in the index, so quoted phrases such as "to be or not to be" work.
const _stopWords = [
  'a',
  'an',
  'and',
  'are',
  'as',
  'at',
  'be',
  'but',
  'by',
  'did',
  'do',
  'does',
  'for',
  'from',
  'had',
  'has',
  'have',
  'how',
  'if',
  'in',
  'into',
  'is',
  'it',
  'its',
  'of',
  'on',
  'or',
  'such',
  'than',
  'that',
  'the',
  'their',
  'then',
  'there',
  'these',
  'they',
  'this',
  'to',
  'up',
  'was',
  'were',
  'what',
  'when',
  'where',
  'which',
  'who',
  'why',
  'will',
  'with',
  'll',
  'm',
  's',
  't',
  'd',
  're',
  've',
];
