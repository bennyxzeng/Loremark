/// A place an answer cites: a paragraph of the Story Map, or a line of the
/// reader's recent pages.
class AskRef {
  const AskRef(this.sectionId, this.paragraphId) : line = null;

  /// The reader's recent pages: line [line] of them, numbered from 1 as the
  /// model saw them, or anywhere in them if null.
  const AskRef.page([this.line]) : sectionId = null, paragraphId = null;

  final String? sectionId;
  final String? paragraphId;
  final int? line;

  bool get isPage => sectionId == null;

  @override
  bool operator ==(Object other) =>
      other is AskRef &&
      other.sectionId == sectionId &&
      other.paragraphId == paragraphId &&
      other.line == line;

  @override
  int get hashCode => Object.hash(sectionId, paragraphId, line);

  @override
  String toString() => isPage
      ? (line == null ? 'page' : 'page/$line')
      : '$sectionId/$paragraphId';
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

const _ref = r'(?:page(?:/\d+)?|[\w.-]+/[\w.-]+)';

/// A citation as the prompt asks for it: `[section-004/p0012]`, `[page/12]`,
/// or several in one bracket, separated by commas. `[page]` is the recent
/// pages with no line, as answers gave them before lines were numbered.
final _citation = RegExp('\\[\\s*($_ref(?:\\s*[,，;；]\\s*$_ref)*)\\s*\\]');

/// The start of a citation that hasn't finished arriving.
final _openCitation = RegExp(r'\[[\w./,，;；\s-]*$');

List<AskRef> _refsIn(String inside) => [
  for (final raw in inside.split(RegExp(r'[,，;；]')))
    if (raw.trim() case final ref when ref.isNotEmpty) _parseRef(ref),
];

AskRef _parseRef(String ref) {
  final [section, paragraph] = ref == 'page' ? ['page', ''] : ref.split('/');
  if (section != 'page') return AskRef(section, paragraph);
  // A number too long to parse is no line, and is cleaned away.
  return AskRef.page(paragraph.isEmpty ? null : int.tryParse(paragraph) ?? 0);
}

/// [text] without the references that weren't real, and without a citation
/// left with none. A paragraph is real if [exists] says so; a line of the
/// recent pages if it is one of the [pageLines] sent, so none is when no page
/// was. Run once on a finished answer, against what it was answered from, so
/// that what is kept was real then.
String cleanCitations(
  String text,
  bool Function(String sectionId, String paragraphId) exists, {
  required int pageLines,
}) => text.replaceAllMapped(RegExp('\\s?${_citation.pattern}'), (match) {
  bool real(AskRef ref) => switch (ref) {
    AskRef(isPage: true, :final line) =>
      pageLines > 0 && (line == null || (line >= 1 && line <= pageLines)),
    AskRef(:final sectionId!, :final paragraphId!) => exists(
      sectionId,
      paragraphId,
    ),
  };
  final kept = [
    for (final ref in _refsIn(match[1]!))
      if (real(ref)) ref,
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
