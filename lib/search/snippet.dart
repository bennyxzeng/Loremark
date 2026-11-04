import 'dart:math';

import '../reader/epub_reader_service.dart';
import 'passage_search.dart';

/// Where a query matched in a paragraph, and which part of the query it was,
/// so a window with more distinct parts can win.
class TextMatch {
  const TextMatch(this.start, this.end, this.key);

  /// Character offsets into the paragraph, end exclusive.
  final int start;
  final int end;
  final int key;
}

/// A short stretch of a paragraph to show under a result.
class Snippet {
  const Snippet(
    this.text,
    this.spans, {
    this.focusStart = 0,
    this.focusEnd = 0,
  });

  final String text;
  final List<MatchSpan> spans;

  /// The first match in the window, as offsets into the paragraph, which is
  /// where a jump to this result should land.
  final int focusStart;
  final int focusEnd;
}

/// Characters in a snippet window for words separated by spaces, and for
/// Chinese, Japanese and Korean, where a character carries more.
const snippetWidth = 180;
const snippetWidthCjk = 80;

// A window on the paragraph is picked the way SQLite FTS5's snippet() does
// (ext/fts5/fts5_aux.c, public domain): the window with the most distinct
// query parts wins, one that starts a sentence gets a bonus, and the winner
// is re-centered on its matches. Ours measures the window in characters, not
// tokens, so one rule serves every script.
const _newPart = 1000;
const _sentenceStart = 100;
const _textStart = 120;

/// A window of [paragraph] around [matches], with `…` where text was cut and
/// the matches inside it as spans into [Snippet.text].
///
/// Reads only [paragraph], so a caller that passes visible text can't leak
/// anything past it. Line breaks become spaces; lengths don't change.
Snippet buildSnippet(String paragraph, List<TextMatch> matches, {int? width}) {
  final text = paragraph.replaceAll('\n', ' ');
  final sorted = [...matches]..sort((a, b) => a.start.compareTo(b.start));
  final size =
      width ??
      (sorted.isNotEmpty && _isCjk(text.codeUnitAt(sorted.first.start))
          ? snippetWidthCjk
          : snippetWidth);
  if (text.length <= size + size ~/ 4 || sorted.isEmpty) {
    return Snippet(
      text,
      sorted.isEmpty ? const [] : _spans(sorted, 0, text.length, 0),
      focusStart: sorted.isEmpty ? 0 : sorted.first.start,
      focusEnd: sorted.isEmpty ? 0 : sorted.first.end,
    );
  }

  var best = 0;
  var bestScore = -1;
  final starts = {
    ...sorted.map((m) => m.start),
    ..._sentenceStarts(text, sorted, size),
  };
  for (final start in starts.toList()..sort()) {
    final end = start + size;
    final seen = <int>{};
    var score = 0;
    for (final match in sorted) {
      if (match.start < start || match.end > end) continue;
      score += seen.add(match.key) ? _newPart : 1;
    }
    if (start == 0) {
      score += _textStart;
    } else if (_startsSentence(text, start)) {
      score += _sentenceStart;
    }
    if (score > bestScore) {
      bestScore = score;
      best = start;
    }
  }

  // Re-center on the matches the window holds.
  final inside = sorted.where((m) => m.start >= best && m.end <= best + size);
  final first = inside.isEmpty ? sorted.first : inside.first;
  final lastEnd = inside.isEmpty
      ? first.end
      : inside.map((m) => m.end).reduce(max);
  final span = lastEnd - first.start;
  var start = span >= size ? first.start : first.start - (size - span) ~/ 2;
  start = start.clamp(0, max(0, text.length - size));
  var end = min(text.length, start + size);
  start = _wordStart(text, start);
  end = _wordEnd(text, end);
  while (start < end && text.codeUnitAt(start) == 0x20) {
    start++;
  }
  while (end > start && text.codeUnitAt(end - 1) == 0x20) {
    end--;
  }

  final prefix = start > 0 ? '…' : '';
  final suffix = end < text.length ? '…' : '';
  final shown = sorted.where((m) => m.end > start && m.start < end);
  return Snippet(
    '$prefix${text.substring(start, end)}$suffix',
    _spans(sorted, start, end, prefix.length),
    focusStart: shown.isEmpty ? first.start : shown.first.start,
    focusEnd: shown.isEmpty ? first.end : shown.first.end,
  );
}

/// The matches that fall in `[start, end)`, clipped to it, as spans into a
/// snippet whose text begins with [prefix] extra characters.
List<MatchSpan> _spans(List<TextMatch> sorted, int start, int end, int prefix) {
  final spans = <MatchSpan>[];
  for (final match in sorted) {
    if (match.end <= start || match.start >= end) continue;
    final from = max(match.start, start) - start + prefix;
    final to = min(match.end, end) - start + prefix;
    if (spans.isNotEmpty && from <= spans.last.end) {
      final last = spans.removeLast();
      spans.add(MatchSpan(last.start, max(last.end, to)));
    } else {
      spans.add(MatchSpan(from, to));
    }
  }
  return spans;
}

/// Offsets that begin a sentence close enough before a match for a window
/// starting there to hold it.
Iterable<int> _sentenceStarts(
  String text,
  List<TextMatch> sorted,
  int size,
) sync* {
  final from = max(0, sorted.first.start - size);
  final to = sorted.last.start;
  for (var i = from; i <= to; i++) {
    if (_startsSentence(text, i)) yield i;
  }
}

bool _startsSentence(String text, int at) {
  if (at == 0) return true;
  var i = at - 1;
  var spaces = 0;
  while (i >= 0 && text.codeUnitAt(i) == 0x20) {
    i--;
    spaces++;
  }
  if (i < 0 || at >= text.length || text.codeUnitAt(at) == 0x20) return false;
  final mark = text.codeUnitAt(i);
  // Latin terminators need a space after them; CJK ones don't.
  return (spaces > 0 && '.!?:'.codeUnits.contains(mark)) ||
      mark == 0x3002 || // 。
      mark == 0xFF01 || // ！
      mark == 0xFF1F; // ？
}

bool _isWordUnit(int unit) =>
    (unit >= 0x30 && unit <= 0x39) ||
    (unit >= 0x41 && unit <= 0x5A) ||
    (unit >= 0x61 && unit <= 0x7A) ||
    unit == 0x27 ||
    unit == 0x2019 ||
    unit == 0xAD ||
    (unit >= 0xC0 && !_isCjk(unit) && !_isPunctuation(unit));

bool _isPunctuation(int unit) =>
    (unit >= 0x2000 && unit <= 0x206F && unit != 0x2019) ||
    (unit >= 0x3000 && unit <= 0x303F) ||
    (unit >= 0xFF00 && unit <= 0xFF0F) ||
    unit == 0xD7 ||
    unit == 0xF7;

bool _isCjk(int unit) =>
    (unit >= 0x3040 && unit <= 0x30FF) ||
    (unit >= 0x3400 && unit <= 0x9FFF) ||
    (unit >= 0xAC00 && unit <= 0xD7AF) ||
    (unit >= 0xF900 && unit <= 0xFAFF) ||
    (unit >= 0xFF66 && unit <= 0xFF9F) ||
    (unit >= 0xD800 && unit <= 0xDFFF);

bool _splitsWord(String text, int at) =>
    at > 0 &&
    at < text.length &&
    _isWordUnit(text.codeUnitAt(at - 1)) &&
    _isWordUnit(text.codeUnitAt(at));

bool _splitsPair(String text, int at) =>
    at > 0 &&
    at < text.length &&
    text.codeUnitAt(at - 1) >= 0xD800 &&
    text.codeUnitAt(at - 1) <= 0xDBFF &&
    text.codeUnitAt(at) >= 0xDC00 &&
    text.codeUnitAt(at) <= 0xDFFF;

const _maxSnap = 24;

int _wordStart(String text, int at) {
  var i = at;
  while (at - i < _maxSnap && _splitsWord(text, i)) {
    i--;
  }
  return _splitsWord(text, i) ? at : (_splitsPair(text, i) ? i - 1 : i);
}

int _wordEnd(String text, int at) {
  var i = at;
  while (i - at < _maxSnap && _splitsWord(text, i)) {
    i++;
  }
  return _splitsWord(text, i) ? at : (_splitsPair(text, i) ? i + 1 : i);
}

/// The shortest and longest text sent to the renderer to find a passage by.
/// Shorter risks matching somewhere else; longer risks differing from the
/// page where whitespace is laid out differently.
const minQuoteLength = 40;
const maxQuoteLength = 120;

/// How much text before and after the quote is sent to tell repeated lines
/// apart. The same length Hypothesis' text-quote anchoring uses.
const quoteContext = 32;

/// What the renderer needs to find and highlight the match at
/// `[matchStart, matchEnd)` in [sectionText].
///
/// The quote is one line of one paragraph (`[paragraphStart,
/// paragraphEnd)`), cut at word boundaries and [minQuoteLength] to
/// [maxQuoteLength] characters long, or the whole line if it is shorter. The
/// context around it may cross into the neighbouring paragraphs, but never
/// past [visibleEnd], the end of the last paragraph the reader has passed.
PassageTarget buildPassageTarget({
  required int sectionIndex,
  required String sectionText,
  required int paragraphStart,
  required int paragraphEnd,
  required int matchStart,
  required int matchEnd,
  required int visibleEnd,
}) {
  final text = sectionText;
  var lineStart = matchStart > 0
      ? text.lastIndexOf('\n', matchStart - 1) + 1
      : 0;
  lineStart = max(lineStart, paragraphStart);
  var lineEnd = text.indexOf('\n', matchStart);
  if (lineEnd == -1 || lineEnd > paragraphEnd) lineEnd = paragraphEnd;
  while (lineStart < lineEnd && text.codeUnitAt(lineStart) == 0x20) {
    lineStart++;
  }
  while (lineEnd > lineStart && text.codeUnitAt(lineEnd - 1) == 0x20) {
    lineEnd--;
  }

  var start = lineStart;
  var end = lineEnd;
  if (lineEnd - lineStart > minQuoteLength) {
    final a = matchStart.clamp(lineStart, lineEnd);
    var b = matchEnd.clamp(a, lineEnd);
    if (b - a > maxQuoteLength) b = a + maxQuoteLength;
    start = a;
    end = b;
    if (end - start < minQuoteLength) {
      final need = minQuoteLength - (end - start);
      start = max(lineStart, a - need ~/ 2);
      end = min(lineEnd, b + need - (a - start));
      if (end - start < minQuoteLength) {
        start = max(lineStart, end - minQuoteLength);
      }
    }
    start = max(lineStart, _wordStart(text, start));
    end = min(lineEnd, _wordEnd(text, end));
    if (end - start > maxQuoteLength) {
      end = _cutAtSpace(text, start, start + maxQuoteLength);
    }
    while (start < end && text.codeUnitAt(start) == 0x20) {
      start++;
    }
    while (end > start && text.codeUnitAt(end - 1) == 0x20) {
      end--;
    }
    if (end - start < minQuoteLength) {
      end = min(lineEnd, start + minQuoteLength);
      start = max(lineStart, end - minQuoteLength);
    }
  }

  var beforeStart = max(0, start - quoteContext);
  if (_splitsPair(text, beforeStart)) beforeStart++;
  var afterEnd = max(end, min(visibleEnd, end + quoteContext));
  if (_splitsPair(text, afterEnd)) afterEnd--;
  return PassageTarget(
    sectionIndex: sectionIndex,
    progression: text.isEmpty ? 0 : start / text.length,
    highlight: text.substring(start, end),
    before: text.substring(beforeStart, start),
    after: text.substring(end, afterEnd),
  );
}

/// The end of the last whole word that fits before [limit], or [limit] if
/// the text has no space to cut at.
int _cutAtSpace(String text, int start, int limit) {
  for (var i = limit; i > start + minQuoteLength; i--) {
    if (text.codeUnitAt(i) == 0x20) return i;
  }
  return _splitsPair(text, limit) ? limit - 1 : limit;
}
