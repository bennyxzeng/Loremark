import 'dart:convert';
import 'dart:math';

import 'delta_schema.dart';
import 'story_book.dart';
import 'story_merge.dart';

/// The version of [repairStoryQuotes], kept with each run that it repaired.
const storyQuoteRepairVersion = '1.0';

/// Who the repairs are by, in the lab's `corrected_by`.
const storyQuoteRepairer = 'loremark-quote-repair';

/// How many paragraphs either side of the cited one a near quote may be in.
const _nearbyParagraphs = 2;

/// The share of a quote's characters that may differ from the book's text.
const _maxEditShare = 0.2;

/// A quote shorter than this is only moved, never rewritten: too few
/// characters to tell a slip from a different phrase.
const _minNearQuoteRunes = 12;

/// The validator's limit, which a repair must not break.
const _maxQuoteRunes = 300;

/// A quote of the model's that was put back to the book's own text.
class QuoteRepair {
  const QuoteRepair({
    required this.path,
    required this.kind,
    required this.fromParagraph,
    required this.toParagraph,
    required this.fromQuote,
    required this.toQuote,
    required this.distance,
  });

  /// The evidence item, such as `new_records.names[6].evidence[0]`.
  final String path;

  /// `moved`: the quote is word for word in another paragraph of the section.
  /// `snapped`: the quote differed a little from a nearby span, which replaced
  /// it.
  final String kind;
  final String fromParagraph;
  final String toParagraph;
  final String fromQuote;
  final String toQuote;

  /// Characters added, removed or changed to turn the quote into the book's
  /// text, ignoring quote-mark style, dash style and case. 0 for `moved`.
  final int distance;

  String get message => kind == 'moved'
      ? 'Quote is word for word in $toParagraph, not the cited '
            '$fromParagraph; it now cites $toParagraph'
      : 'Quote differed from the book; replaced with the text of '
            '$toParagraph ("$fromQuote" → "$toQuote")';

  StoryIssue get issue =>
      StoryIssue('warning', 'quote_repaired', path, message);

  /// The repair as the lab records a manual correction: one per changed field.
  List<JsonMap> corrections(String at) => [
    if (fromParagraph != toParagraph)
      _correction('paragraph_id', fromParagraph, toParagraph, at),
    if (fromQuote != toQuote) _correction('quote', fromQuote, toQuote, at),
  ];

  JsonMap _correction(String field, String from, String to, String at) => {
    'path': '$path.$field',
    'from': from,
    'to': to,
    'reason': message,
    'corrected_by': storyQuoteRepairer,
    'corrected_at': at,
  };
}

/// Puts the quotes of [candidate], a model's answer for [chapter], back to the
/// book's own text where they slipped, before it is checked.
///
/// Models copy quotes well but not perfectly: they cite the paragraph next to
/// the right one, drop or add a word, or change the quote marks. With Strict
/// quote check on, each such slip used to fail the whole update, and off, it was
/// kept unchecked. Here a quote that isn't in its paragraph is:
/// 1. moved to the nearest paragraph of the section holding it word for word;
/// 2. else, replaced with the closest span of the cited paragraph or the
///    [_nearbyParagraphs] either side, if at most a fifth of its characters
///    differ, ignoring quote-mark style, dash style and case;
/// 3. else, left for the validator to report.
/// So every quote kept is still the book's exact text. The lab has no such
/// step: its validator, which `validateUpdate` ports, runs after this unchanged.
///
/// Only well-formed evidence of this section is looked at; the rest is left for
/// the validator. Returns [candidate] itself if nothing was repaired, otherwise a
/// copy.
(Object?, List<QuoteRepair>) repairStoryQuotes(
  Object? candidate,
  JsonMap chapter,
) {
  if (candidate is! Map) return (candidate, const []);
  final copy = jsonDecode(jsonEncode(candidate)) as JsonMap;
  final book = _Section(chapter);
  final repairs = [
    for (final (path, evidence) in deltaEvidence(copy))
      ?book.repair(path, evidence),
  ];
  return repairs.isEmpty ? (candidate, const []) : (copy, repairs);
}

/// Each evidence item of [delta], a model's answer, with its path such as
/// `new_records.names[6].evidence[0]`, skipping whatever isn't shaped as the
/// schema says.
Iterable<(String, Object?)> deltaEvidence(Object? delta) sync* {
  if (delta is! Map) return;
  Iterable<(String, Object?)> of(String path, Object? item) sync* {
    if (item is! Map) return;
    final evidence = item['evidence'];
    if (evidence is! List) return;
    for (var j = 0; j < evidence.length; j++) {
      yield ('$path.evidence[$j]', evidence[j]);
    }
  }

  final records = delta['new_records'];
  if (records is Map) {
    for (final collection in storyCollections) {
      final items = records[collection];
      if (items is! List) continue;
      for (var i = 0; i < items.length; i++) {
        yield* of('new_records.$collection[$i]', items[i]);
      }
    }
  }
  final transitions = delta['transitions'];
  if (transitions is List) {
    for (var i = 0; i < transitions.length; i++) {
      yield* of('transitions[$i]', transitions[i]);
    }
  }
}

class _Section {
  _Section(JsonMap chapter)
    : sectionId = chapter['section_id'] as String,
      ids = [
        for (final p in (chapter['paragraphs'] as List).cast<JsonMap>())
          p['id'] as String,
      ],
      texts = [
        for (final p in (chapter['paragraphs'] as List).cast<JsonMap>())
          p['text'] as String,
      ];

  final String sectionId;
  final List<String> ids;
  final List<String> texts;
  late final _indexOf = {for (var i = 0; i < ids.length; i++) ids[i]: i};
  final _folded = <int, List<int>>{};

  List<int> folded(int index) =>
      _folded[index] ??= _fold(texts[index].runes.toList());

  /// Repairs [evidence] in place, or returns null if it needn't or can't be.
  QuoteRepair? repair(String path, Object? evidence) {
    if (evidence is! Map) return null;
    final section = evidence['section_id'];
    final paragraph = evidence['paragraph_id'];
    final quote = evidence['quote'];
    if (section != sectionId || paragraph is! String || quote is! String) {
      return null;
    }
    final quoteRunes = quote.runes.toList();
    if (pyStrip(quote).isEmpty || quoteRunes.length > _maxQuoteRunes) {
      return null;
    }
    final cited = _indexOf[paragraph];
    if (cited != null && texts[cited].contains(quote)) return null;

    final QuoteRepair? found =
        _moved(path, paragraph, cited, quote) ??
        (cited == null ? null : _snapped(path, cited, quote, quoteRunes));
    if (found != null) {
      evidence['paragraph_id'] = found.toParagraph;
      evidence['quote'] = found.toQuote;
    }
    return found;
  }

  /// The nearest paragraph holding [quote] word for word; the first one if the
  /// cited paragraph isn't in the section.
  QuoteRepair? _moved(String path, String paragraph, int? cited, String quote) {
    int? best;
    for (var i = 0; i < texts.length; i++) {
      if (!texts[i].contains(quote)) continue;
      if (best == null ||
          (cited != null && (i - cited).abs() < (best - cited).abs())) {
        best = i;
      }
    }
    if (best == null) return null;
    return QuoteRepair(
      path: path,
      kind: 'moved',
      fromParagraph: paragraph,
      toParagraph: ids[best],
      fromQuote: quote,
      toQuote: quote,
      distance: 0,
    );
  }

  QuoteRepair? _snapped(
    String path,
    int cited,
    String quote,
    List<int> quoteRunes,
  ) {
    if (quoteRunes.length < _minNearQuoteRunes) return null;
    final limit = max(1, (quoteRunes.length * _maxEditShare).floor());
    final query = _fold(quoteRunes);
    _Match? best;
    var bestIndex = cited;
    final first = max(0, cited - _nearbyParagraphs);
    final last = min(texts.length - 1, cited + _nearbyParagraphs);
    // Nearest first, so that a tie goes to the nearer paragraph.
    final order = [for (var i = first; i <= last; i++) i]
      ..sort((a, b) => (a - cited).abs().compareTo((b - cited).abs()));
    for (final i in order) {
      final match = _closestSpan(query, folded(i), limit);
      if (match != null && (best == null || match.beats(best))) {
        best = match;
        bestIndex = i;
      }
    }
    if (best == null) return null;
    final text = texts[bestIndex].runes.toList();
    final span = pyStrip(
      String.fromCharCodes(_wholeWords(text, best.start, best.end)),
    );
    if (span.isEmpty || span.runes.length > _maxQuoteRunes) return null;
    return QuoteRepair(
      path: path,
      kind: 'snapped',
      fromParagraph: ids[cited],
      toParagraph: ids[bestIndex],
      fromQuote: quote,
      toQuote: span,
      distance: best.distance,
    );
  }
}

class _Match {
  const _Match(this.distance, this.start, this.end);

  final int distance;
  final int start;
  final int end;

  /// Fewer edits first, then the shorter span.
  bool beats(_Match other) =>
      distance < other.distance ||
      (distance == other.distance && end - start < other.end - other.start);
}

/// The span of [text] that [query] is fewest edits from (adding, removing or
/// changing a character each count one), if at most [limit]. Of equally near
/// spans, the shortest, then the first.
///
/// Sellers' algorithm: edit distance where the span may start and end anywhere
/// in [text] for free. Each cell keeps where its best alignment started, the
/// latest start winning a tie, which favors the shorter span.
_Match? _closestSpan(List<int> query, List<int> text, int limit) {
  final m = text.length;
  var costs = List<int>.filled(m + 1, 0);
  var starts = List<int>.generate(m + 1, (j) => j);
  var nextCosts = List<int>.filled(m + 1, 0);
  var nextStarts = List<int>.filled(m + 1, 0);
  for (var i = 1; i <= query.length; i++) {
    nextCosts[0] = i;
    nextStarts[0] = 0;
    var rowBest = i;
    final rune = query[i - 1];
    for (var j = 1; j <= m; j++) {
      // Keeping or changing a character...
      var cost = costs[j - 1] + (rune == text[j - 1] ? 0 : 1);
      var start = starts[j - 1];
      // ...dropping one of the quote's...
      final dropped = costs[j] + 1;
      if (dropped < cost || (dropped == cost && starts[j] > start)) {
        cost = dropped;
        start = starts[j];
      }
      // ...or adding one of the book's.
      final added = nextCosts[j - 1] + 1;
      if (added < cost || (added == cost && nextStarts[j - 1] > start)) {
        cost = added;
        start = nextStarts[j - 1];
      }
      nextCosts[j] = cost;
      nextStarts[j] = start;
      if (cost < rowBest) rowBest = cost;
    }
    // No span can come back under the limit once a whole row is over it.
    if (rowBest > limit) return null;
    (costs, nextCosts) = (nextCosts, costs);
    (starts, nextStarts) = (nextStarts, starts);
  }
  _Match? best;
  for (var j = 1; j <= m; j++) {
    if (costs[j] > limit || starts[j] >= j) continue;
    final match = _Match(costs[j], starts[j], j);
    if (best == null || match.beats(best)) best = match;
  }
  return best;
}

/// Quote marks, then dashes, that a quote may have in a different style.
const _quoteMarks = '"\'“”„‟‘’‚‛「」『』«»‹›＂＇';
const _dashes = '‐‑‒–—―−﹣－';
final _quoteMarkRunes = _quoteMarks.runes.toSet();
final _dashRunes = _dashes.runes.toSet();
final _space = RegExp(r'\s', unicode: true);

/// [runes] with quote marks, dashes and spaces each made one kind, and letters
/// lowercased where that keeps them one character, so that positions still
/// match the original.
List<int> _fold(List<int> runes) => [for (final rune in runes) _foldRune(rune)];

int _foldRune(int rune) {
  if (_quoteMarkRunes.contains(rune)) return 0x22; // "
  if (_dashRunes.contains(rune)) return 0x2D; // -
  final char = String.fromCharCode(rune);
  if (_space.hasMatch(char)) return 0x20;
  final lower = char.toLowerCase().runes;
  return lower.length == 1 ? lower.first : rune;
}

final _wordChar = RegExp(r'[\p{L}\p{M}\p{N}]', unicode: true);

/// Scripts written without spaces between words, where a span may end anywhere.
final _unspacedScript = RegExp(
  r'[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Thai}'
  r'\p{Script=Lao}\p{Script=Khmer}\p{Script=Myanmar}]',
  unicode: true,
);
const _apostrophes = {0x27, 0x2019};

bool _isWordRune(int rune) {
  final char = String.fromCharCode(rune);
  return _wordChar.hasMatch(char) && !_unspacedScript.hasMatch(char);
}

/// [start]..[end] of [text] widened so it doesn't cut a word in two, counting
/// an apostrophe inside a word (as in "who’d") as part of it.
List<int> _wholeWords(List<int> text, int start, int end) {
  bool word(int i) => i >= 0 && i < text.length && _isWordRune(text[i]);
  bool apostrophe(int i) =>
      i >= 0 && i < text.length && _apostrophes.contains(text[i]);
  var s = start;
  while (word(s)) {
    if (word(s - 1)) {
      s--;
    } else if (apostrophe(s - 1) && word(s - 2)) {
      s -= 2;
    } else {
      break;
    }
  }
  var e = end;
  while (word(e - 1)) {
    if (word(e)) {
      e++;
    } else if (apostrophe(e) && word(e + 1)) {
      e += 2;
    } else {
      break;
    }
  }
  return text.sublist(s, e);
}
