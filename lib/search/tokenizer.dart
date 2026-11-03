/// Bump when tokenizing, folding or stemming changes in a way that alters
/// terms, so a saved index is rebuilt instead of read with the wrong rules.
const tokenizerVersion = 2;

/// One searchable unit of a text.
class Token {
  const Token(this.term, this.start, this.end, {this.cjk = false});

  /// The normalized form that is indexed and looked up.
  final String term;

  /// Where the token sits in the original text, in UTF-16 code units, end
  /// exclusive. The text itself is never folded, so these stay valid.
  final int start;
  final int end;

  /// True for Han, kana and Hangul tokens, which are character bigrams (or a
  /// lone character) rather than words.
  final bool cjk;

  @override
  String toString() => 'Token($term, $start..$end${cjk ? ', cjk' : ''})';
}

// Han, kana (plus the prolonged sound mark, which is script Common) and
// Hangul. These scripts don't put spaces between words.
const _cjk =
    r'\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}'
    r'ー';

// Soft hyphen, zero-width space, joiners, word joiner and BOM. They are
// invisible, so they must not split a word the reader sees as one.
const _invisible = r'­​‌‍⁠﻿';

// Straight, curly and modifier apostrophes.
const _apostrophes = '\'’ʼ';

final _scanner = RegExp(
  '([$_cjk]+)'
  '|'
  '((?![$_cjk])[\\p{L}\\p{N}\\p{M}]'
  '(?:(?![$_cjk])[\\p{L}\\p{N}\\p{M}$_invisible]'
  '|[$_apostrophes](?=(?![$_cjk])\\p{L}))*)',
  unicode: true,
);

final _invisibleChars = RegExp('[$_invisible]', unicode: true);
final _plainWord = RegExp(r"^[a-z0-9']+$");
final _stemmable = RegExp(r'^[a-z]+$');

/// Turns text into [Token]s: words for most scripts and overlapping
/// character bigrams for Chinese, Japanese and Korean.
///
/// The text is scanned as it is and only each token is folded (lowercase,
/// accents removed), so offsets always point at the original characters.
/// Indexing and querying use the same instance type, which is what keeps
/// their terms identical.
class Tokenizer {
  /// A tokenizer that reduces English words with [stem] after folding.
  Tokenizer({this.stem});

  final String Function(String word)? stem;
  final _stems = <String, String>{};

  /// The tokens of [text], in order.
  ///
  /// A word with a single-letter elision (`l'homme`) is indexed as the word
  /// after the apostrophe, and a possessive (`Klein's`) as the owner, which
  /// is what readers type.
  List<Token> tokenize(String text) {
    final tokens = <Token>[];
    for (final match in _scanner.allMatches(text)) {
      final run = match[1];
      if (run != null) {
        _bigrams(run, match.start, tokens);
      } else {
        _word(match[2]!, match.start, tokens);
      }
    }
    return tokens;
  }

  /// [word] lowercased with accents removed, as a word token is before
  /// stemming. Used to expand typed prefixes against indexed terms.
  String fold(String word) => foldWord(word);

  /// The term a Latin [word] is indexed under, after folding and stemming.
  String termFor(String word) => _finish(foldWord(word));

  void _word(String raw, int start, List<Token> out) {
    var folded = foldWord(raw);
    var from = start;
    // Elision: l'homme, d'accord. Only a single letter, so that don't and
    // o'clock-like contractions of English stay whole words.
    if (folded.length > 3 && folded.codeUnitAt(1) == 0x27) {
      from = start + _indexOfApostrophe(raw) + 1;
      folded = folded.substring(2);
    }
    if (folded.endsWith("'s")) {
      folded = folded.substring(0, folded.length - 2);
    }
    if (folded.isEmpty) return;
    out.add(Token(_finish(folded), from, start + raw.length));
  }

  int _indexOfApostrophe(String raw) {
    for (var i = 0; i < raw.length; i++) {
      if (_apostrophes.contains(raw[i])) return i;
    }
    return 0;
  }

  String _finish(String folded) {
    final stem = this.stem;
    if (stem == null || !_stemmable.hasMatch(folded)) return folded;
    return _stems[folded] ??= stem(folded);
  }

  /// A run of CJK characters becomes its overlapping bigrams. A lone
  /// character has no neighbour to pair with, so it is a token of its own.
  void _bigrams(String run, int start, List<Token> out) {
    final offsets = <int>[]; // UTF-16 offset of each character
    var at = 0;
    for (final rune in run.runes) {
      offsets.add(at);
      at += rune > 0xFFFF ? 2 : 1;
    }
    offsets.add(at);
    final count = offsets.length - 1;
    if (count == 1) {
      out.add(Token(run, start, start + run.length, cjk: true));
      return;
    }
    for (var i = 0; i + 1 < count; i++) {
      final from = offsets[i];
      final to = offsets[i + 2];
      out.add(
        Token(run.substring(from, to), start + from, start + to, cjk: true),
      );
    }
  }
}

/// Lowercases [word], removes accents and invisible characters, and maps
/// look-alike letters (`ß`, `æ`, full-width forms) to plain ASCII.
///
/// Idempotent: folding a folded word changes nothing.
String foldWord(String word) {
  if (_plainWord.hasMatch(word)) return word;
  final lower = word.replaceAll(_invisibleChars, '').toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    // Combining marks: accents written as separate characters.
    if (rune >= 0x300 && rune <= 0x36F) continue;
    if (rune == 0x2019 || rune == 0x2BC) {
      out.write("'");
    } else if (rune >= 0xFF41 && rune <= 0xFF5A ||
        rune >= 0xFF10 && rune <= 0xFF19) {
      // Full-width Latin letters and digits (capitals were lowercased above).
      out.writeCharCode(rune - 0xFEE0);
    } else {
      out.write(_asciiFold[rune] ?? String.fromCharCode(rune));
    }
  }
  return out.toString();
}

/// Lowercase letters and what they fold to. Lowercasing happens first, so
/// capitals are not listed. Covers Latin-1, Latin Extended-A/B and the
/// Vietnamese block of Latin Extended Additional.
const _foldGroups = {
  'a': 'àáâãäåāăąǎǟǡǻȁȃȧạảấầẩẫậắằẳẵặ',
  'b': 'ƀɓḃḅḇ',
  'c': 'çćĉċčƈ',
  'd': 'ďđɗḋḍḏḑḓ',
  'e': 'èéêëēĕėęěȅȇȩẹẻẽếềểễệ',
  'f': 'ƒḟ',
  'g': 'ĝğġģǥǧǵɠḡ',
  'h': 'ĥħȟḣḥḧḩḫ',
  'i': 'ìíîïĩīĭįǐȉȋỉịı',
  'j': 'ĵǰ',
  'k': 'ķƙǩḱḳḵ',
  'l': 'ĺļľŀłḷḻ',
  'm': 'ḿṁṃ',
  'n': 'ñńņňŉŋǹṅṇṉ',
  'o': 'òóôõöøōŏőơǒǫǭǿȍȏȫȭȯȱọỏốồổỗộớờởỡợ',
  'p': 'ƥṕṗ',
  'r': 'ŕŗřȑȓṙṛṟ',
  's': 'śŝşšșṡṣ',
  't': 'ţťŧțṫṭṯ',
  'u': 'ùúûüũūŭůűųưǔǖǘǚǜȕȗụủứừửữự',
  'v': 'ṽṿ',
  'w': 'ŵẁẃẅẇ',
  'x': 'ẋẍ',
  'y': 'ýÿŷƴȳẏỳỵỷỹ',
  'z': 'źżžƶẑẓẕ',
  'ss': 'ß',
  'ae': 'æǣǽ',
  'oe': 'œ',
  'th': 'þ',
};

final Map<int, String> _asciiFold = {
  for (final MapEntry(:key, :value) in _foldGroups.entries)
    for (final rune in value.runes) rune: key,
};
