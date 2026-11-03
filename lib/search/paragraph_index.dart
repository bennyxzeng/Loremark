import 'dart:typed_data';

import '../reader/reader_position.dart';
import 'passage_search.dart';

/// Where paragraphs are in a book and how much of it a reader has passed.
///
/// A paragraph is a run of text between blank lines in a section's plain
/// text, which is what `readSectionTexts` produces, cut into sentence-sized
/// pieces when it is long ([maxParagraphChars]). Paragraphs get ids in
/// reading order (section by section, then top to bottom), so "everything the
/// reader has fully passed" is always the prefix `[0, visibleCount)` and
/// every cutoff question becomes one integer.
///
/// Non-linear spine items, such as footnotes, have no paragraphs: the reader
/// can't navigate to them, so a hit there could not be shown.
class ParagraphIndex {
  /// Splits [sectionTexts] (one per spine item, in order) into paragraphs.
  ///
  /// [linear] says which spine items the reader turns pages through; it
  /// defaults to all of them.
  factory ParagraphIndex(List<String> sectionTexts, {List<bool>? linear}) {
    final isLinear = linear ?? List.filled(sectionTexts.length, true);
    if (isLinear.length != sectionTexts.length) {
      throw ArgumentError('linear must have one flag per section');
    }
    final texts = [
      for (var i = 0; i < sectionTexts.length; i++)
        isLinear[i] ? sectionTexts[i] : '',
    ];
    final sections = <int>[];
    final starts = <int>[];
    final ends = <int>[];
    final ordinals = <int>[];
    final firsts = Int32List(texts.length + 1);
    for (var s = 0; s < texts.length; s++) {
      firsts[s] = sections.length;
      var ordinal = 0;
      for (final (start, end) in _paragraphBounds(texts[s])) {
        sections.add(s);
        starts.add(start);
        ends.add(end);
        ordinals.add(ordinal++);
      }
    }
    firsts[texts.length] = sections.length;
    return ParagraphIndex._(
      texts,
      isLinear,
      Int32List.fromList(sections),
      Int32List.fromList(starts),
      Int32List.fromList(ends),
      Int32List.fromList(ordinals),
      firsts,
    );
  }

  ParagraphIndex._(
    this.sectionTexts,
    this.linear,
    this._section,
    this._start,
    this._end,
    this._ordinal,
    this._firsts,
  );

  /// The plain text of every section, empty for non-linear ones.
  final List<String> sectionTexts;
  final List<bool> linear;
  final Int32List _section;
  final Int32List _start;
  final Int32List _end;
  final Int32List _ordinal;

  /// Id of the first paragraph of each section, then the total, so section
  /// `s` owns ids `[_firsts[s], _firsts[s + 1])`.
  final Int32List _firsts;

  int get count => _section.length;
  int get sectionCount => sectionTexts.length;

  int sectionOf(int id) => _section[id];

  /// Position of paragraph [id] within its section, from 0.
  int ordinalOf(int id) => _ordinal[id];

  /// Character offsets of paragraph [id] in its section's text, end
  /// exclusive.
  int startOf(int id) => _start[id];
  int endOf(int id) => _end[id];

  String textOf(int id) =>
      sectionTexts[_section[id]].substring(_start[id], _end[id]);

  /// The id of the first paragraph of [sectionIndex]; the next section's
  /// first id if it has none.
  int firstIdOf(int sectionIndex) => _firsts[sectionIndex];

  /// The paragraph with [paragraphIndex] in [sectionIndex], or null.
  int? idOf(int sectionIndex, int paragraphIndex) {
    if (sectionIndex < 0 || sectionIndex >= sectionCount) return null;
    final id = _firsts[sectionIndex] + paragraphIndex;
    return paragraphIndex >= 0 && id < _firsts[sectionIndex + 1] ? id : null;
  }

  /// Where paragraph [id] starts and ends in its section, from 0.0 to 1.0, by
  /// characters of the section's plain text.
  double startProgression(int id) =>
      _start[id] / sectionTexts[_section[id]].length;
  double endProgression(int id) => _end[id] / sectionTexts[_section[id]].length;

  Passage passage(int id) => Passage(
    sectionIndex: _section[id],
    paragraphIndex: _ordinal[id],
    text: textOf(id),
    startProgression: startProgression(id),
    endProgression: endProgression(id),
  );

  /// How many leading paragraphs the reader has fully passed at [cutoff].
  ///
  /// Those are all paragraphs of earlier sections, and in the current section
  /// the ones that end at or before `floor(progression * length)`. Whole
  /// numbers, not float comparisons, so no paragraph can round its way across
  /// the line, and a paragraph the cutoff falls inside is not counted. A
  /// section at exactly 1.0 is finished, and one at 0.0 has nothing read.
  int visibleCount(ReaderPosition cutoff) {
    final section = cutoff.sectionIndex;
    if (section < 0) return 0;
    if (section >= sectionCount) return count;
    final first = _firsts[section];
    final next = _firsts[section + 1];
    final progression = cutoff.progression;
    if (progression >= 1) return next;
    if (!(progression > 0) || first == next) return first;
    final limit = (progression * sectionTexts[section].length).floor();
    // The first paragraph in the section that ends after [limit].
    var low = first;
    var high = next;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_end[middle] <= limit) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  /// Where the visible text of [id]'s section ends, in characters, given
  /// that the first [visible] paragraphs are visible and [id] is one of them.
  /// Context around a hit must stop there.
  int visibleTextEnd(int id, int visible) {
    final next = _firsts[_section[id] + 1];
    return _end[(visible < next ? visible : next) - 1];
  }
}

final _blankLine = RegExp(r'\n\s*\n');

/// Paragraphs longer than this many characters are cut into pieces at
/// sentence ends.
///
/// A page break inside a long paragraph then hides only the piece it falls
/// in, a few lines, instead of the whole paragraph; novels often have
/// paragraphs longer than a page.
const maxParagraphChars = 500;

/// Pieces of a long paragraph end at the first sentence end past this many
/// characters, so a piece is a few sentences, enough for ranking to work on.
const _pieceChars = 250;

/// A piece shorter than this is joined to the one before it.
const _minPieceChars = 60;

/// The end of a sentence: closing punctuation with the space after it, or a
/// CJK full stop, which has none.
final _sentenceEnd = RegExp(
  '[.!?…]+["\'”’)\\]]*\\s+'
  '|[。！？]+[」』）]*',
);

/// The `(start, end)` of each non-empty paragraph of [text], without the
/// whitespace around it, with long ones cut into pieces.
Iterable<(int, int)> _paragraphBounds(String text) sync* {
  var from = 0;
  for (final gap in _blankLine.allMatches(text)) {
    final bounds = _trimmed(text, from, gap.start);
    if (bounds != null) yield* _pieces(text, bounds);
    from = gap.end;
  }
  final last = _trimmed(text, from, text.length);
  if (last != null) yield* _pieces(text, last);
}

/// [paragraph] as is if it is short, otherwise cut after sentence ends.
Iterable<(int, int)> _pieces(String text, (int, int) paragraph) {
  final (start, end) = paragraph;
  if (end - start <= maxParagraphChars) return [paragraph];
  final pieces = <(int, int)>[];
  var pieceStart = start;
  for (final match in _sentenceEnd.allMatches(text, start)) {
    if (match.end >= end) break;
    if (match.end - pieceStart < _pieceChars) continue;
    pieces.add(_trimmed(text, pieceStart, match.end)!);
    pieceStart = match.end;
  }
  final rest = _trimmed(text, pieceStart, end)!;
  if (pieces.isNotEmpty && rest.$2 - rest.$1 < _minPieceChars) {
    pieces[pieces.length - 1] = (pieces.last.$1, rest.$2);
  } else {
    pieces.add(rest);
  }
  return pieces;
}

(int, int)? _trimmed(String text, int start, int end) {
  while (start < end && _isSpace(text.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _isSpace(text.codeUnitAt(end - 1))) {
    end--;
  }
  return start < end ? (start, end) : null;
}

bool _isSpace(int unit) =>
    unit == 0x20 ||
    unit == 0x0A ||
    unit == 0x09 ||
    unit == 0x0D ||
    unit == 0xA0 ||
    unit == 0x3000;
