import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../library/epub_package.dart';

/// One `itemref` of an EPUB spine.
class SpineItem {
  const SpineItem({required this.path, required this.linear});

  /// The item's path inside the archive, such as `OEBPS/ch1.xhtml`.
  final String path;

  /// False for `linear="no"` items, such as footnotes, which renderers skip
  /// when turning pages.
  final bool linear;

  @override
  String toString() => 'SpineItem($path, linear: $linear)';
}

/// Every spine item of the EPUB in [bytes], in spine order, including
/// non-linear items, so index `i` is section `i`.
///
/// Throws a [FormatException] if [bytes] is not an EPUB.
List<SpineItem> spineFromBytes(Uint8List bytes) =>
    _spine(EpubPackage.fromBytes(bytes));

/// Plain text of every spine item of the EPUB in [bytes], in spine order.
///
/// Element `i` is the text of section `i`, the same index the reader reports
/// in `ReaderPosition.sectionIndex`. Throws a [FormatException] if [bytes] is
/// not an EPUB.
List<String> sectionTextsFromBytes(Uint8List bytes) {
  final package = EpubPackage.fromBytes(bytes);
  return [for (final item in _spine(package)) _sectionText(package, item.path)];
}

/// [spineFromBytes] for the file at [epubPath], parsed off the UI isolate.
Future<List<SpineItem>> readSpine(String epubPath) =>
    // Reading inside the isolate saves copying the whole book across.
    Isolate.run(() => spineFromBytes(File(epubPath).readAsBytesSync()));

/// [sectionTextsFromBytes] for the file at [epubPath], parsed off the UI
/// isolate.
Future<List<String>> readSectionTexts(String epubPath) =>
    Isolate.run(() => sectionTextsFromBytes(File(epubPath).readAsBytesSync()));

/// The index in [spine] of the item [href] points to, or null.
///
/// [href] may have a leading `/`, a `#fragment` or `?query`, and
/// percent-encoding, as renderers report it.
int? spineIndexOf(List<SpineItem> spine, String href) {
  var path = href;
  for (final separator in ['#', '?']) {
    final at = path.indexOf(separator);
    if (at != -1) path = path.substring(0, at);
  }
  path = decodeEpubPath(path);
  while (path.startsWith('/')) {
    path = path.substring(1);
  }
  // Items missing from the manifest have an empty path; they match nothing.
  if (path.isEmpty) return null;
  final index = spine.indexWhere((item) => item.path == path);
  return index == -1 ? null : index;
}

/// The spine of [package]. An `itemref` whose id is not in the manifest keeps
/// its place with an empty path, so indexes still line up with the reader's.
List<SpineItem> _spine(EpubPackage package) => [
  for (final ref in package.spine)
    SpineItem(
      path: package.manifest[ref.idref]?.path ?? '',
      linear: ref.linear,
    ),
];

/// The text of the file at [path], or an empty string if it is missing or
/// unreadable, so one bad chapter does not lose the book.
String _sectionText(EpubPackage package, String path) {
  final file = package.archive.findFile(path);
  if (path.isEmpty || file == null) return '';
  try {
    final xhtml = utf8
        .decode(file.content, allowMalformed: true)
        .replaceFirst('\uFEFF', '');
    try {
      return _bodyText(xhtml);
    } on XmlException {
      return _stripTags(xhtml);
    }
  } on Object {
    return '';
  }
}

/// Elements whose content is not text the reader sees. `rt` and `rp` are
/// ruby readings, which would otherwise run into the words they annotate.
const _skipped = {'head', 'script', 'style', 'svg', 'rt', 'rp'};

/// Elements that start a new paragraph, set off from the text around them by
/// a blank line.
const _paragraphBreaks = {
  'address',
  'article',
  'aside',
  'blockquote',
  'caption',
  'details',
  'div',
  'dl',
  'figcaption',
  'figure',
  'footer',
  'form',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hr',
  'main',
  'nav',
  'ol',
  'p',
  'pre',
  'section',
  'summary',
  'table',
  'ul',
};

/// Elements that start a new line, with no blank line.
const _lineBreaks = {'br', 'dd', 'dt', 'li', 'tr'};

String _bodyText(String xhtml) {
  final document = XmlDocument.parse(
    xhtml,
    entityMapping: const XmlDefaultEntityMapping.html5(),
  );
  final text = _TextBuilder();
  void walk(XmlNode node) {
    switch (node) {
      case XmlText(:final value) || XmlCDATA(:final value):
        text.add(value);
      case XmlElement(:final name, :final children):
        final tag = name.local.toLowerCase();
        if (_skipped.contains(tag)) return;
        final gap = _paragraphBreaks.contains(tag)
            ? 2
            : _lineBreaks.contains(tag)
            ? 1
            : 0;
        text.breakLines(gap);
        children.forEach(walk);
        text.breakLines(gap);
        if (tag == 'td' || tag == 'th') text.add(' ');
      default:
    }
  }

  walk(document.findAllElements('body').firstOrNull ?? document.rootElement);
  return text.toString();
}

/// Collects text with whitespace collapsed to single spaces and line breaks
/// kept as the widest one requested between two pieces of text.
class _TextBuilder {
  final _out = StringBuffer();
  var _gap = 0;
  var _space = false;

  void add(String text) {
    final collapsed = text.replaceAll(RegExp(r'\s+'), ' ');
    final word = collapsed.trim();
    if (word.isEmpty) {
      if (collapsed.isNotEmpty) _space = true;
      return;
    }
    if (_out.isNotEmpty) {
      if (_gap > 0) {
        _out.write('\n' * _gap);
      } else if (_space || collapsed.startsWith(' ')) {
        _out.write(' ');
      }
    }
    _out.write(word);
    _gap = 0;
    _space = collapsed.endsWith(' ');
  }

  void breakLines(int count) => _gap = max(_gap, count);

  @override
  String toString() => _out.toString();
}

/// A rough reading of [html] for chapters that are not well-formed XML.
String _stripTags(String html) {
  final body = RegExp(
    r'<body\b[^>]*>([\s\S]*)</body>',
    caseSensitive: false,
  ).firstMatch(html)?[1];
  final text = (body ?? html)
      .replaceAll(
        RegExp(
          r'<(script|style)\b[\s\S]*?</\1\s*>|<!--[\s\S]*?-->',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          '</?(${[..._paragraphBreaks, ..._lineBreaks].join('|')})\\b[^>]*>',
          caseSensitive: false,
        ),
        '\n\n',
      )
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAllMapped(
        RegExp(r'&([#\w]+);'),
        (match) =>
            const XmlDefaultEntityMapping.html5().decodeEntity(match[1]!) ??
            match[0]!,
      );
  return text
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
