/// A place an answer cites: a paragraph of the Story Map, or the reader's page.
class AskRef {
  const AskRef(this.sectionId, this.paragraphId);

  /// The current page, which has no paragraph numbers.
  const AskRef.page() : sectionId = null, paragraphId = null;

  final String? sectionId;
  final String? paragraphId;

  bool get isPage => sectionId == null;

  @override
  bool operator ==(Object other) =>
      other is AskRef &&
      other.sectionId == sectionId &&
      other.paragraphId == paragraphId;

  @override
  int get hashCode => Object.hash(sectionId, paragraphId);

  @override
  String toString() => isPage ? 'page' : '$sectionId/$paragraphId';
}

/// A piece of an answer: some text, or the citations that come after a claim.
sealed class AnswerPart {
  const AnswerPart();
}

class AnswerText extends AnswerPart {
  const AnswerText(this.text);

  final String text;
}

class AnswerCitation extends AnswerPart {
  const AnswerCitation(this.refs);

  final List<AskRef> refs;
}

const _ref = r'(?:page|[\w.-]+/[\w.-]+)';

/// A citation as the prompt asks for it: `[section-004/p0012]`, `[page]`, or
/// several in one bracket, separated by commas.
final _citation = RegExp('\\[\\s*($_ref(?:\\s*[,，;；]\\s*$_ref)*)\\s*\\]');

/// The start of a citation that hasn't finished arriving.
final _openCitation = RegExp(r'\[[\w./,，;；\s-]*$');

List<AskRef> _refsIn(String inside) => [
  for (final raw in inside.split(RegExp(r'[,，;；]')))
    if (raw.trim() case final ref when ref.isNotEmpty)
      ref == 'page'
          ? const AskRef.page()
          : AskRef(ref.split('/')[0], ref.split('/')[1]),
];

/// [text] without the references [exists] says aren't real, and without a
/// citation left with none. Run once on a finished answer, against the
/// paragraphs it was answered from, so that what is kept was real then.
String cleanCitations(
  String text,
  bool Function(String sectionId, String paragraphId) exists,
) => text.replaceAllMapped(RegExp('\\s?${_citation.pattern}'), (match) {
  final kept = [
    for (final ref in _refsIn(match[1]!))
      if (ref.isPage || exists(ref.sectionId!, ref.paragraphId!)) ref,
  ];
  if (kept.isEmpty) return '';
  final space = match[0]!.startsWith(RegExp(r'\s')) ? ' ' : '';
  return '$space[${kept.join(', ')}]';
});

/// [text] in pieces, citations apart from the words around them. A bracket
/// that isn't a citation, such as `[sic]`, stays text.
///
/// While an answer is [streaming], a citation still arriving at its end is
/// left out, so it doesn't flash up as text.
List<AnswerPart> splitAnswer(String text, {bool streaming = false}) {
  var body = text;
  if (streaming) {
    final open = _openCitation.firstMatch(body);
    if (open != null) body = body.substring(0, open.start);
  }
  final parts = <AnswerPart>[];
  var at = 0;
  for (final match in _citation.allMatches(body)) {
    if (match.start > at) {
      parts.add(AnswerText(body.substring(at, match.start)));
    }
    parts.add(AnswerCitation(_refsIn(match[1]!)));
    at = match.end;
  }
  if (at < body.length) parts.add(AnswerText(body.substring(at)));
  return parts;
}

/// Whether [parts] cite anything at all.
bool citesAnything(List<AnswerPart> parts) =>
    parts.any((part) => part is AnswerCitation && part.refs.isNotEmpty);
