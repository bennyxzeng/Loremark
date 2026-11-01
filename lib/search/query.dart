import 'tokenizer.dart';

/// One thing a query asks for.
class QueryPart {
  const QueryPart({
    this.tokens = const [],
    this.phrase = false,
    this.required = false,
    this.prefixText,
    this.substring,
  });

  /// The tokens of the part, in order. Empty for a [substring] part.
  final List<Token> tokens;

  /// True if the [tokens] must follow each other in the text.
  final bool phrase;

  /// True if a paragraph without the phrase is no match at all. Only quoted
  /// phrases are required; a run of CJK characters is only a phrase.
  final bool required;

  /// For the word being typed: the folded letters so far, which also match
  /// longer words.
  final String? prefixText;

  /// A single CJK character, which no bigram contains on its own, so it is
  /// searched for as plain text.
  final String? substring;

  @override
  String toString() =>
      'QueryPart(${substring ?? tokens.map((t) => t.term).join(' ')}'
      '${phrase ? ', phrase' : ''}${required ? ', required' : ''}'
      '${prefixText == null ? '' : ', prefix $prefixText'})';
}

/// Splits [query] into the parts that are searched for.
///
/// Text in double quotes is a required phrase. The word being typed, the
/// last one, also matches longer words. A run of Chinese, Japanese or Korean
/// text is a phrase of its bigrams. Common words are left out of questions
/// such as "where did Ryn first show up", unless they are all there is.
List<QueryPart> parseQuery(
  String query,
  Tokenizer tokenizer, {
  required bool Function(String term) isStopTerm,
}) {
  final segments = _segments(query);
  final parts = <QueryPart>[];
  // Unquoted plain words, which may be common words to leave out.
  final words = <QueryPart>{};
  for (var i = 0; i < segments.length; i++) {
    final (text, quoted) = segments[i];
    final tokens = tokenizer.tokenize(text);
    if (tokens.isEmpty) continue;
    if (quoted) {
      parts.add(_quoted(tokens));
      continue;
    }
    final typing =
        i == segments.length - 1 &&
        !_noWordBeingTyped(query) &&
        tokens.last.end == text.length;
    var at = 0;
    while (at < tokens.length) {
      var end = at + 1;
      if (tokens[at].cjk) {
        while (end < tokens.length &&
            tokens[end].cjk &&
            tokens[end].start < tokens[end - 1].end) {
          end++;
        }
        parts.add(_run(tokens.sublist(at, end)));
      } else {
        final token = tokens[at];
        final surface = text.substring(token.start, token.end);
        final prefix = tokenizer.fold(surface);
        final word = QueryPart(
          tokens: [token],
          prefixText: end == tokens.length && typing && prefix.length >= 2
              ? prefix
              : null,
        );
        words.add(word);
        parts.add(word);
      }
      at = end;
    }
  }
  bool isCommon(QueryPart part) =>
      words.contains(part) && isStopTerm(part.tokens.single.term);
  final hasContent = parts.any((part) => !isCommon(part));
  final seen = <String>{};
  final kept = <QueryPart>[];
  for (final part in parts) {
    if (!words.contains(part)) {
      kept.add(part);
    } else if ((!hasContent || !isCommon(part)) &&
        seen.add(part.tokens.single.term)) {
      kept.add(part);
    }
  }
  return kept;
}

QueryPart _quoted(List<Token> tokens) => tokens.length > 1
    ? QueryPart(tokens: tokens, phrase: true, required: true)
    : _single(tokens.single);

/// A run of overlapping CJK bigrams from the text, or a lone character.
QueryPart _run(List<Token> tokens) => tokens.length > 1
    ? QueryPart(tokens: tokens, phrase: true)
    : _single(tokens.single);

QueryPart _single(Token token) => token.cjk && token.term.runes.length == 1
    ? QueryPart(substring: token.term)
    : QueryPart(tokens: [token]);

/// Whether the query ends in a space or a closing quote, so no word is being
/// typed.
bool _noWordBeingTyped(String query) {
  if (query.isEmpty) return true;
  final last = query[query.length - 1];
  return last.trim().isEmpty || _quotes.contains(last);
}

const _quotes = '"“”„';

/// The pieces of [query] between quotes, each with whether it was quoted. An
/// unclosed quote runs to the end.
List<(String, bool)> _segments(String query) {
  final out = <(String, bool)>[];
  final buffer = StringBuffer();
  var quoted = false;
  void flush() {
    final text = buffer.toString();
    buffer.clear();
    if (text.trim().isNotEmpty) out.add((text, quoted));
  }

  for (final unit in query.split('')) {
    if (_quotes.contains(unit)) {
      flush();
      quoted = !quoted;
    } else {
      buffer.write(unit);
    }
  }
  flush();
  return out;
}
