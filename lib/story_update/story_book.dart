import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;
import 'package:xml/xml.dart';

import '../library/epub_package.dart';
import '../reader/css_selector.dart';
import '../reader/epub_sections.dart';
import 'story_section_kind.dart';

/// A JSON object, as stored in a story model and sent to the provider.
typedef JsonMap = Map<String, dynamic>;

/// Version of the paragraph rules below, the same as the lab's.
const extractionVersion = '1.0';

const _maxMemberBytes = 64 * 1024 * 1024;
const _xhtmlMediaTypes = {'application/xhtml+xml', 'text/html'};
const _opsNamespace = 'http://www.idpf.org/2007/ops';

/// Leaf text is grouped into one paragraph per block element; nested blocks
/// split it.
const _blockTags = {
  'address',
  'article',
  'aside',
  'blockquote',
  'body',
  'caption',
  'dd',
  'div', //
  'dl', 'dt', 'figcaption', 'figure', 'footer', 'h1', 'h2', 'h3', 'h4', 'h5',
  'h6', 'header', 'hr', 'li', 'main', 'ol', 'p', 'pre', 'section', 'table',
  'tbody', 'td', 'tfoot', 'th', 'thead', 'tr', 'ul',
};
const _skipTags = {
  'head', 'math', 'nav', 'noscript', 'script', 'style', 'svg', 'template', //
};
const _imageTags = {'img', 'image'};

/// The whitespace Python's `str.split()` splits on, so the same text hashes the
/// same way here and in the lab.
final _whitespace = RegExp(
  '[\\t-\\r\\x1c-\\x20\\x85\\xa0\\u1680\\u2000-\\u200a\\u2028\\u2029'
  '\\u202f\\u205f\\u3000]+',
);
final _chapterTitle = RegExp(
  r'^\s*chapter\s+(\d+|[ivxlcdm]+)\b',
  caseSensitive: false,
);
final _roman = RegExp(
  r'^M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$',
);
const _romanValues = {
  'I': 1,
  'V': 5,
  'X': 10,
  'L': 50,
  'C': 100,
  'D': 500,
  'M': 1000,
};

/// The length taken for a section whose text can't be read, which is too long
/// to be a page of pictures.
const _unknownLength = 1 << 30;

/// The position of a section that starts with its document. Every element
/// inside the body has a position of 0 or more.
const _documentStart = -1;

/// The EPUB cannot be read, or a section cannot be located reliably.
class StoryEpubError implements Exception {
  const StoryEpubError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A section has no text at all, such as a page holding only an illustration.
class StorySectionEmptyError extends StoryEpubError {
  const StorySectionEmptyError(super.message);
}

/// Python's `str.strip()`.
String pyStrip(String text) => text
    .replaceFirst(RegExp('^(?:${_whitespace.pattern})'), '')
    .replaceFirst(RegExp('(?:${_whitespace.pattern})\$'), '');

/// NFC-normalizes [text] and collapses every run of whitespace to one space.
String normalizeStoryText(String text) =>
    pyStrip(unorm.nfc(text).replaceAll(_whitespace, ' '));

/// Hash of the normalized paragraph texts joined by newlines, without their IDs.
String paragraphsSha256(List<dynamic> paragraphs) {
  final joined = paragraphs.map((p) => (p as JsonMap)['text']).join('\n');
  return sha256.convert(utf8.encode(joined)).toString();
}

/// The number in a title such as "Chapter 12" or "CHAPTER IV: Departure".
int? parseChapterNumber(String title) {
  final token = _chapterTitle.firstMatch(title)?.group(1);
  if (token == null) return null;
  final number = int.tryParse(token);
  if (number != null) return number;
  final roman = token.toUpperCase();
  if (!_roman.hasMatch(roman)) return null;
  var total = 0;
  for (var i = 0; i < roman.length; i++) {
    final value = _romanValues[roman[i]]!;
    final next = i + 1 < roman.length ? _romanValues[roman[i + 1]]! : 0;
    total += value < next ? -value : value;
  }
  return total;
}

/// One part of a book in reading order: a table of contents entry, or a spine
/// document the table of contents never starts in.
class StoryBookSection {
  StoryBookSection({
    required this.title,
    required this.href,
    required this.fragment,
    required this.spineIndex,
    required this.inToc,
    this.problem,
  });

  /// `section-001` and so on, in reading order.
  String sectionId = '';
  int order = 0;
  final String title;
  int? chapterNumber;

  /// The document's path inside the EPUB.
  final String href;
  final String? fragment;

  /// 1-based position among the spine's XHTML documents.
  final int spineIndex;
  final bool inToc;

  /// Why this section cannot be cut from its document reliably, if it can't.
  final String? problem;
  final notes = <String>[];

  /// False if the spine lists its document as `linear="no"`: outside the
  /// reading order, such as notes opened from a link.
  bool linear = true;

  /// The types of the landmarks, or EPUB 2 guide entries, that point at this
  /// section, such as `bodymatter` or `afterword`.
  final landmarkTypes = <String>{};
}

/// A landmark, or an EPUB 2 guide entry: where the book says a part of it is.
class _Landmark {
  const _Landmark(this.href, this.fragment, this.types);

  final String href;
  final String? fragment;
  final Set<String> types;
}

class _TocEntry {
  const _TocEntry(this.title, this.href, this.fragment);

  final String title;
  final String href;
  final String? fragment;

  String get resource => fragment == null ? href : '$href#$fragment';
}

/// A book split into the sections a story model is built from.
///
/// Follows the lab's `epub.py`, so a section has the same ID and text in both.
/// The lab parses documents leniently with BeautifulSoup; this parses them as
/// XML like the rest of the app, and flags a document that isn't well-formed
/// instead of guessing at it.
class StoryBook {
  StoryBook._(this.sha256Hash, this.title, this.tocSource, this._package);

  /// Reads the EPUB in [bytes]. Throws a [StoryEpubError] if it can't.
  factory StoryBook.open(Uint8List bytes) {
    final EpubPackage package;
    try {
      package = EpubPackage.fromBytes(bytes);
    } on FormatException catch (error) {
      throw StoryEpubError('Not a readable EPUB: ${error.message}');
    }
    final warnings = <String>[];
    final (spine, ncxId) = _readSpine(package, warnings);
    if (spine.isEmpty) {
      throw const StoryEpubError('The OPF spine contains no XHTML documents');
    }
    final (tocSource, entries) = _readToc(package, ncxId, warnings);
    final book = StoryBook._(
      sha256.convert(bytes).toString(),
      _readTitle(package),
      tocSource,
      package,
    );
    book.warnings.addAll(warnings);
    book.sections.addAll(book._buildSections(spine, entries));
    book._readSemantics(package);
    return book;
  }

  /// SHA-256 of the EPUB file: `Book.id`, and the store's `epub_sha256`.
  final String sha256Hash;
  final String title;

  /// `nav`, `ncx` or `spine`.
  final String tocSource;
  final EpubPackage _package;
  final warnings = <String>[];
  final sections = <StoryBookSection>[];

  /// The order of the section the book's landmarks say its body matter starts
  /// at, if they say.
  int? bodyStartOrder;

  /// The order of the section the book's landmarks say its back matter starts
  /// at, if they say.
  int? backStartOrder;
  final _documents = <String, XmlDocument>{};
  final _documentErrors = <String, String>{};

  /// The parsed document at [href], or null with the reason in
  /// [_documentErrors].
  XmlDocument? _document(String href) {
    final known = _documents[href];
    if (known != null || _documentErrors.containsKey(href)) return known;
    try {
      return _documents[href] = parseXhtml(_readMember(_package, href));
    } on StoryEpubError catch (error) {
      _documentErrors[href] = error.message;
    } on XmlException catch (error) {
      _documentErrors[href] = '$href is not well-formed: ${error.message}';
    }
    return null;
  }

  List<StoryBookSection> _buildSections(
    List<String> spine,
    List<_TocEntry> entries,
  ) {
    final spineIndex = {for (var i = 0; i < spine.length; i++) spine[i]: i + 1};
    final positioned = <(List<int>, StoryBookSection)>[];
    final byDocument = <String, List<(int, _TocEntry)>>{};
    final seen = <String>{};

    for (var tocIndex = 0; tocIndex < entries.length; tocIndex++) {
      final entry = entries[tocIndex];
      if (!spineIndex.containsKey(entry.href)) {
        warnings.add(
          'TOC entry "${entry.title}" points to ${entry.href}, which is not an '
          'XHTML document in the spine; it is not listed',
        );
        continue;
      }
      if (!seen.add(
        '${entry.href}\u0000${entry.fragment}\u0000${entry.title}',
      )) {
        warnings.add(
          'TOC entry "${entry.title}" → ${entry.resource} is listed more than '
          'once; the repeats are ignored',
        );
        continue;
      }
      (byDocument[entry.href] ??= []).add((tocIndex, entry));
    }

    // Boundaries are checked per document before anything is extracted. If one
    // of them cannot be located exactly, no section of that document can be cut
    // reliably, so all are flagged and listed in TOC order.
    for (final MapEntry(key: href, value: documentEntries)
        in byDocument.entries) {
      final document = _document(href);
      final positions = <int, int>{};
      final problems = <String>[];
      if (document == null) {
        problems.add(_documentErrors[href]!);
      } else {
        _boundaryPositions(document, documentEntries, positions, problems);
      }
      final problem = problems.isEmpty
          ? null
          : 'TOC boundaries in $href cannot be located reliably: '
                '${problems.join('; ')}';
      for (final (tocIndex, entry) in documentEntries) {
        final section = StoryBookSection(
          title: entry.title.isNotEmpty
              ? entry.title
              : document == null
              ? _basename(href)
              : _documentTitle(document, href),
          href: href,
          fragment: entry.fragment,
          spineIndex: spineIndex[href]!,
          inToc: true,
          problem: problem,
        );
        final position = problem == null ? positions[tocIndex]! : 0;
        positioned.add(([section.spineIndex, position, tocIndex], section));
      }
    }

    // Spine documents the TOC never starts in are listed on their own, never
    // silently merged into the section before them.
    for (final MapEntry(key: href, value: index) in spineIndex.entries) {
      if (byDocument.containsKey(href)) continue;
      final document = _document(href);
      final section = StoryBookSection(
        title: document == null
            ? _basename(href)
            : _documentTitle(document, href),
        href: href,
        fragment: null,
        spineIndex: index,
        inToc: false,
        problem: document == null ? _documentErrors[href] : null,
      );
      if (tocSource != 'spine') {
        section.notes.add(
          'Spine document not referenced by the table of contents',
        );
      }
      positioned.add((
        [index, _documentStart, entries.length + index],
        section,
      ));
    }

    positioned.sort((a, b) {
      for (var i = 0; i < 3; i++) {
        final order = a.$1[i].compareTo(b.$1[i]);
        if (order != 0) return order;
      }
      return 0;
    });
    final ordered = [for (final (_, section) in positioned) section];
    for (var i = 0; i < ordered.length; i++) {
      ordered[i]
        ..order = i + 1
        ..sectionId = 'section-${'${i + 1}'.padLeft(3, '0')}'
        ..chapterNumber = parseChapterNumber(ordered[i].title);
    }
    for (var i = 0; i + 1 < ordered.length; i++) {
      final following = ordered[i + 1];
      if (ordered[i].inToc && !following.inToc && tocSource != 'spine') {
        ordered[i].notes.add(
          'Followed by ${following.href}, which is not in the TOC; that text '
          'is listed separately as ${following.sectionId} and not included here',
        );
      }
    }
    return ordered;
  }

  /// Notes what the book says about its parts: which documents are outside the
  /// reading order, and where its landmarks point. Sections stay as they are.
  void _readSemantics(EpubPackage package) {
    final linear = <String, bool>{};
    for (final ref in package.spine) {
      final path = package.manifest[ref.idref]?.path;
      if (path != null) linear[path] = (linear[path] ?? false) || ref.linear;
    }
    for (final section in sections) {
      section.linear = linear[section.href] ?? true;
    }
    for (final landmark in _readLandmarks(package)) {
      final section = _sectionAt(landmark.href, landmark.fragment);
      if (section == null) continue;
      section.landmarkTypes.addAll(landmark.types);
      if (landmark.types.contains('bodymatter')) {
        bodyStartOrder ??= section.order;
      }
      if (landmark.types.contains('backmatter')) {
        backStartOrder ??= section.order;
      }
    }
  }

  /// The section [href]`#`[fragment] falls in, if it can be told.
  StoryBookSection? _sectionAt(String href, String? fragment) {
    final inDocument = sections.where((s) => s.href == href).toList();
    if (inDocument.isEmpty) return null;
    if (fragment == null) return inDocument.first;
    final exact = inDocument.where((s) => s.fragment == fragment).firstOrNull;
    if (exact != null || inDocument.length == 1) {
      return exact ?? inDocument.single;
    }
    // An anchor that no section starts at is in the last one starting before it.
    final document = _document(href);
    if (document == null) return null;
    try {
      final ordinals = _elementOrdinals(document);
      int positionOf(String? fragment) {
        final element = _anchorElement(document, fragment);
        return element == null ? _documentStart : ordinals[element] ?? -2;
      }

      final target = positionOf(fragment);
      StoryBookSection? found;
      for (final section in inDocument) {
        if (section.problem != null) return null;
        if (positionOf(section.fragment) <= target) found = section;
      }
      return found;
    } on StoryEpubError {
      return null;
    }
  }

  /// What [section] looks like, given its [chapter] as [extract] gives it.
  /// Without one, as for a section that can't be cut, only what the book says
  /// and the title count.
  StorySectionKind kindOf(StoryBookSection section, JsonMap? chapter) {
    final paragraphs = (chapter?['paragraphs'] as List?)?.cast<JsonMap>();
    return classifyStorySection(
      title: section.title,
      types: {...section.landmarkTypes, ..._structuralTypes(section)},
      order: section.order,
      bodyStart: bodyStartOrder,
      backStart: backStartOrder,
      linear: section.linear,
      textChars: paragraphs == null
          ? _unknownLength
          : paragraphs.fold(
              0,
              (total, paragraph) =>
                  total + (paragraph['text'] as String).length,
            ),
      imageCount: chapter?['omitted_image_count'] as int? ?? 0,
    );
  }

  /// The `epub:type`s and `doc-` roles [section] starts inside: those of its
  /// anchor and every element around it, or for a section starting with its
  /// document, those of the body and the element it starts with.
  Set<String> _structuralTypes(StoryBookSection section) {
    final document = _document(section.href);
    if (document == null) return const {};
    final List<XmlElement> elements;
    try {
      final anchor = section.problem == null
          ? _anchorElement(document, section.fragment)
          : null;
      final body = _bodyOf(document);
      if (anchor != null) {
        elements = [anchor, ...anchor.ancestorElements];
      } else {
        elements = [
          if (body is XmlElement) body,
          ?body.childElements.firstOrNull,
        ];
      }
    } on StoryEpubError {
      return const {};
    }
    return {for (final element in elements) ..._semanticTypes(element)};
  }

  void _boundaryPositions(
    XmlDocument document,
    List<(int, _TocEntry)> entries,
    Map<int, int> positions,
    List<String> problems,
  ) {
    final ordinals = _elementOrdinals(document);
    for (final (tocIndex, entry) in entries) {
      try {
        final element = _anchorElement(document, entry.fragment);
        if (element == null) {
          positions[tocIndex] = _documentStart;
        } else if (ordinals.containsKey(element)) {
          positions[tocIndex] = ordinals[element]!;
        } else {
          problems.add(
            '"${entry.title}" → ${entry.resource}: anchor is outside the '
            'document body',
          );
        }
      } on StoryEpubError catch (error) {
        problems.add('"${entry.title}" → ${entry.resource}: ${error.message}');
      }
    }
    final byPosition = <int, List<_TocEntry>>{};
    final entryByIndex = {for (final (i, entry) in entries) i: entry};
    positions.forEach((tocIndex, position) {
      (byPosition[position] ??= []).add(entryByIndex[tocIndex]!);
    });
    for (final same in byPosition.values) {
      if (same.length > 1) {
        final listed = same
            .map((e) => '"${e.title}" (${e.resource})')
            .join(', ');
        problems.add('TOC entries $listed start at the same position');
      }
    }
  }

  /// The section that ends [section], or null when it runs to the end of its
  /// document. A following section without a reliable start is an error, since
  /// skipping it would extend this section over its text.
  StoryBookSection? _nextInSameDocument(StoryBookSection section) {
    final index = sections.indexOf(section);
    if (index + 1 >= sections.length) return null;
    final following = sections[index + 1];
    if (following.href != section.href) return null;
    if (following.problem != null) {
      throw StoryEpubError(
        '${section.sectionId} has no reliable end: the next section '
        '${following.sectionId} cannot be located (${following.problem})',
      );
    }
    return following;
  }

  /// The section's paragraphs, as a `ChapterInput` of the lab.
  ///
  /// Throws a [StorySectionEmptyError] if it has no text, and a
  /// [StoryEpubError] if it can't be cut from its document reliably.
  JsonMap extract(StoryBookSection section) {
    final collector = _collect(section);
    if (collector.paragraphs.isEmpty) {
      throw StorySectionEmptyError(
        '${section.sectionId} ("${section.title}") contains no body text',
      );
    }

    final width = max(4, '${collector.paragraphs.length}'.length);
    final paragraphs = [
      for (var i = 0; i < collector.paragraphs.length; i++)
        <String, dynamic>{
          'id': 'p${'${i + 1}'.padLeft(width, '0')}',
          'text': collector.paragraphs[i],
        },
    ];
    return {
      'schema_version': '1.0',
      'book_sha256': sha256Hash,
      'book_title': title,
      'section_id': section.sectionId,
      'chapter_number': section.chapterNumber,
      'title': section.title,
      'source_href': section.href,
      'source_fragment': section.fragment,
      'paragraphs': paragraphs,
      'text_sha256': paragraphsSha256(paragraphs),
      'extraction_version': extractionVersion,
      'omitted_image_count': collector.images,
      'extraction_notes': [...section.notes],
    };
  }

  /// How many of [section]'s paragraphs end before the element [cssSelector]
  /// finds, the first one showing on the reader's page. A paragraph that element
  /// is in isn't counted, since it may carry on to the page. All of them if the
  /// element comes after the section, and none if it comes before.
  ///
  /// Null if the selector doesn't find an element in the body. Throws a
  /// [StoryEpubError] if the section can't be cut from its document reliably.
  int? paragraphsBefore(StoryBookSection section, String cssSelector) {
    final document = _documentOf(section);
    final target = firstElementMatching(document, cssSelector);
    final body = _bodyOf(document);
    if (target == null || !target.ancestors.any((a) => identical(a, body))) {
      return null;
    }
    final collector = _collect(section, target: target);
    return collector.beforeTarget ?? collector.paragraphs.length;
  }

  /// How many of [section]'s paragraphs end before text block number [block] of
  /// its document, counted from 0 the way the page script counts them (see
  /// `textBlocks`). That block is the first one not wholly on the reader's page,
  /// so these paragraphs are all on the page or an earlier one. All of them if
  /// the block comes after the section, and none if it comes before.
  ///
  /// Null if the document has no such block. Throws a [StoryEpubError] if the
  /// section can't be cut from its document reliably.
  int? paragraphsBeforeBlock(StoryBookSection section, int block) {
    if (block < 0) return null;
    final document = _documentOf(section);
    // Found the way `textProgressionOfBlock` finds it, so the numbers agree.
    final body = document.findAllElements('body').firstOrNull;
    if (body == null) return null;
    final target = textBlocks(body).skip(block).firstOrNull;
    if (target == null) return null;
    final collector = _collect(section, target: target);
    return collector.beforeTarget ?? collector.paragraphs.length;
  }

  XmlDocument _documentOf(StoryBookSection section) {
    if (section.problem != null) {
      throw StoryEpubError(
        '${section.sectionId} cannot be extracted reliably: ${section.problem}',
      );
    }
    final document = _document(section.href);
    if (document == null) {
      throw StoryEpubError(_documentErrors[section.href]!);
    }
    return document;
  }

  /// Walks [section] of its document. Throws a [StoryEpubError] if it can't be
  /// cut reliably. Notes where [target] falls among the paragraphs, if given.
  _RangeCollector _collect(StoryBookSection section, {XmlElement? target}) {
    final document = _documentOf(section);
    final start = _anchorElement(document, section.fragment);
    XmlElement? end;
    final next = _nextInSameDocument(section);
    if (next != null) {
      end = _anchorElement(document, next.fragment);
      final ordinals = _elementOrdinals(document);
      final startPosition = start == null ? _documentStart : ordinals[start]!;
      if (end == null || ordinals[end]! <= startPosition) {
        throw StoryEpubError(
          '${section.sectionId} has no end boundary after its start: '
          '${next.sectionId} starts at ${next.href}'
          '${next.fragment == null ? '' : '#${next.fragment}'}',
        );
      }
    }

    final collector = _RangeCollector(start, end, target);
    collector.walk(_bodyOf(document));
    collector.flush();
    return collector;
  }
}

String _basename(String href) => href.substring(href.lastIndexOf('/') + 1);

String _readMember(EpubPackage package, String name) {
  final file = package.archive.findFile(name);
  if (file == null) throw StoryEpubError('Missing file inside EPUB: $name');
  if (file.size > _maxMemberBytes) {
    throw StoryEpubError(
      '$name is larger than $_maxMemberBytes bytes; refusing to read it',
    );
  }
  return utf8.decode(file.content, allowMalformed: true).replaceFirst('﻿', '');
}

XmlDocument _parseMember(EpubPackage package, String name) {
  try {
    return parseXhtml(_readMember(package, name));
  } on XmlException catch (error) {
    throw StoryEpubError('Cannot parse XML in $name: ${error.message}');
  }
}

String _tagName(XmlElement element) => element.name.qualified.toLowerCase();

String? _attribute(XmlElement element, String name) {
  for (final attribute in element.attributes) {
    if (attribute.name.qualified.toLowerCase() == name) return attribute.value;
  }
  return null;
}

/// All the text under [node], as ElementTree's `itertext` joins it.
String _allText(XmlNode node) => node.descendants
    .where((child) => child is XmlText || child is XmlCDATA)
    .map((child) => child.value)
    .join();

String _readTitle(EpubPackage package) {
  String? title;
  for (final element in package.opf.descendantElements) {
    if (title == null && element.name.local == 'title') {
      final text = normalizeStoryText(_allText(element));
      if (text.isNotEmpty) title = text;
    }
  }
  return title ?? '(untitled)';
}

(List<String>, String?) _readSpine(EpubPackage package, List<String> warnings) {
  final spine = <String>[];
  final ncxId = package.opf
      .findAllElements('spine', namespaceUri: '*')
      .firstOrNull
      ?.getAttribute('toc');
  for (final ref in package.spine) {
    final item = package.manifest[ref.idref];
    if (item == null) {
      warnings.add('Spine references unknown manifest item "${ref.idref}"');
    } else if (!_xhtmlMediaTypes.contains(item.mediaType)) {
      warnings.add(
        'Skipping non-XHTML spine item ${item.path} (${item.mediaType})',
      );
    } else if (!spine.contains(item.path)) {
      spine.add(item.path);
    }
  }
  return (spine, ncxId);
}

(String, List<_TocEntry>) _readToc(
  EpubPackage package,
  String? ncxId,
  List<String> warnings,
) {
  final navItem = package.manifest.values
      .where((item) => item.properties.contains('nav'))
      .firstOrNull;
  if (navItem != null) {
    try {
      final entries = _readNav(package, navItem.path);
      if (entries.isNotEmpty) return ('nav', entries);
      warnings.add('EPUB 3 nav has no TOC links, trying NCX');
    } on StoryEpubError catch (error) {
      warnings.add('EPUB 3 nav unusable, trying NCX: ${error.message}');
    }
  }

  final ncxItem =
      package.manifest[ncxId ?? ''] ??
      package.manifest.values
          .where((item) => item.mediaType == 'application/x-dtbncx+xml')
          .firstOrNull;
  if (ncxItem != null) {
    try {
      final entries = _readNcx(package, ncxItem.path);
      if (entries.isNotEmpty) return ('ncx', entries);
      warnings.add('NCX has no navPoints');
    } on StoryEpubError catch (error) {
      warnings.add('NCX unusable: ${error.message}');
    }
  }

  warnings.add(
    'No usable table of contents; listing spine documents instead (fallback)',
  );
  return ('spine', const []);
}

List<_TocEntry> _readNav(EpubPackage package, String navHref) {
  final root = _parseMember(package, navHref);
  final toc = root.descendantElements.where((element) {
    if (element.name.local != 'nav') return false;
    final type =
        element.getAttribute('type', namespaceUri: _opsNamespace) ?? '';
    return type.split(_whitespace).contains('toc') ||
        element.getAttribute('role') == 'doc-toc';
  }).firstOrNull;
  if (toc == null) return const [];
  return [
    for (final element in toc.descendantElements)
      if (element.name.local == 'a' &&
          (element.getAttribute('href') ?? '') != '')
        _tocEntry(
          navHref,
          element.getAttribute('href')!,
          normalizeStoryText(_allText(element)),
        ),
  ];
}

List<_TocEntry> _readNcx(EpubPackage package, String ncxHref) {
  final root = _parseMember(package, ncxHref);
  final entries = <_TocEntry>[];
  for (final point in root.descendantElements) {
    if (point.name.local != 'navPoint') continue;
    var title = '';
    String? src;
    for (final child in point.childElements) {
      if (child.name.local == 'navLabel') {
        title = normalizeStoryText(_allText(child));
      } else if (child.name.local == 'content') {
        src = child.getAttribute('src');
      }
    }
    if (src != null && src.isNotEmpty) {
      entries.add(_tocEntry(ncxHref, src, title));
    }
  }
  return entries;
}

/// The landmarks of the EPUB 3 nav, then the EPUB 2 guide's entries.
/// Neither is needed, so one that can't be read is left out.
List<_Landmark> _readLandmarks(EpubPackage package) {
  final landmarks = <_Landmark>[];
  void add(String base, String? href, Set<String> types) {
    if (href == null || href.isEmpty || types.isEmpty) return;
    try {
      final entry = _tocEntry(base, href, '');
      landmarks.add(_Landmark(entry.href, entry.fragment, types));
    } on StoryEpubError {
      // Somewhere outside the book.
    }
  }

  final navItem = package.manifest.values
      .where((item) => item.properties.contains('nav'))
      .firstOrNull;
  if (navItem != null) {
    try {
      final root = _parseMember(package, navItem.path);
      for (final nav in root.descendantElements) {
        if (nav.name.local != 'nav' || !_epubTypes(nav).contains('landmarks')) {
          continue;
        }
        for (final link in nav.descendantElements) {
          if (link.name.local != 'a') continue;
          add(navItem.path, link.getAttribute('href'), _epubTypes(link));
        }
      }
    } on StoryEpubError {
      // The table of contents says what is wrong with the nav.
    }
  }

  final guide = package.opf
      .findAllElements('guide', namespaceUri: '*')
      .firstOrNull;
  for (final reference
      in guide?.findElements('reference', namespaceUri: '*') ??
          const <XmlElement>[]) {
    final type = reference.getAttribute('type')?.trim().toLowerCase() ?? '';
    add(package.opfPath, reference.getAttribute('href'), {
      if (type.isNotEmpty) _guideTypes[type] ?? type.replaceFirst('other.', ''),
    });
  }
  return landmarks;
}

/// EPUB 2 guide types that the EPUB 3 vocabulary names differently.
const _guideTypes = {
  'text': 'bodymatter',
  'title-page': 'titlepage',
  'acknowledgements': 'acknowledgments',
  'notes': 'endnotes',
};

/// The `epub:type`s on [element], without a vocabulary's prefix.
Set<String> _epubTypes(XmlElement element) => {
  for (final type in (_attribute(element, 'epub:type') ?? '').split(
    _whitespace,
  ))
    if (type.isNotEmpty) type.substring(type.indexOf(':') + 1).toLowerCase(),
};

/// The `epub:type`s and `doc-` roles on [element], such as `afterword` for
/// both `epub:type="afterword"` and `role="doc-afterword"`.
Set<String> _semanticTypes(XmlElement element) => {
  ..._epubTypes(element),
  for (final role in (_attribute(element, 'role') ?? '').split(_whitespace))
    if (role.startsWith('doc-')) role.substring(4).toLowerCase(),
};

_TocEntry _tocEntry(String base, String href, String title) {
  if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:').hasMatch(href) ||
      href.startsWith('//')) {
    throw StoryEpubError('External reference is not supported: "$href"');
  }
  final hash = href.indexOf('#');
  final fragment = hash == -1 ? '' : decodeEpubPath(href.substring(hash + 1));
  var path = hash == -1 ? href : href.substring(0, hash);
  final query = path.indexOf('?');
  if (query != -1) path = path.substring(0, query);
  return _TocEntry(
    title,
    path.isEmpty ? base : _resolveMember(base, decodeEpubPath(path)),
    fragment.isEmpty ? null : fragment,
  );
}

String _resolveMember(String base, String path) {
  final slash = base.lastIndexOf('/');
  final parts = <String>[];
  for (final part in '${base.substring(0, slash + 1)}$path'.split('/')) {
    if (part == '..') {
      if (parts.isEmpty) {
        throw StoryEpubError('Refusing path outside the EPUB container: $path');
      }
      parts.removeLast();
    } else if (part != '.' && part.isNotEmpty) {
      parts.add(part);
    }
  }
  return parts.join('/');
}

XmlNode _bodyOf(XmlDocument document) =>
    document.descendantElements
        .where((element) => _tagName(element) == 'body')
        .firstOrNull ??
    document;

/// The element a section starts at; null only for the start of the document.
/// A fragment that cannot be located exactly throws rather than falling back
/// to the start.
XmlElement? _anchorElement(XmlDocument document, String? fragment) {
  if (fragment == null) return null;
  final matches = document.descendantElements
      .where((element) => _attribute(element, 'id') == fragment)
      .toList();
  if (matches.isEmpty) throw StoryEpubError('anchor #$fragment was not found');
  if (matches.length > 1) {
    throw StoryEpubError(
      'id "$fragment" appears ${matches.length} times, so #$fragment is '
      'ambiguous',
    );
  }
  final element = matches.single;
  if (const {'html', 'body'}.contains(_tagName(element))) return null;
  for (final node in [element, ...element.ancestorElements]) {
    final name = _tagName(node);
    if (_skipTags.contains(name)) {
      throw StoryEpubError(
        'anchor #$fragment is inside <$name>, whose text is not extracted',
      );
    }
  }
  return element;
}

Map<XmlElement, int> _elementOrdinals(XmlDocument document) {
  final ordinals = Map<XmlElement, int>.identity();
  var index = 0;
  for (final element in _bodyOf(document).descendantElements) {
    ordinals[element] = index++;
  }
  return ordinals;
}

String _documentTitle(XmlDocument document, String href) {
  for (final name in const ['title', 'h1', 'h2', 'h3']) {
    final element = document.descendantElements
        .where((element) => _tagName(element) == name)
        .firstOrNull;
    if (element == null) continue;
    final text = normalizeStoryText(
      element.descendants
          .where((child) => child is XmlText || child is XmlCDATA)
          .map((child) => child.value)
          .join(' '),
    );
    if (text.isNotEmpty) return text;
  }
  return _basename(href);
}

bool _isPageBreak(XmlElement element) =>
    (_attribute(element, 'epub:type') ?? '')
        .split(_whitespace)
        .contains('pagebreak') ||
    _attribute(element, 'role') == 'doc-pagebreak';

/// Collects paragraph texts between a start element and an end element, in
/// document order.
class _RangeCollector {
  _RangeCollector(this.start, this.end, this.target) : active = start == null;

  final XmlElement? start;
  final XmlElement? end;

  /// An element to find among the paragraphs.
  final XmlElement? target;

  /// How many paragraphs were complete when the walk reached [target], or null
  /// if it never did.
  int? beforeTarget;
  bool active;
  bool done = false;
  int suppressed = 0;
  int images = 0;
  final _buffer = StringBuffer();
  final paragraphs = <String>[];

  void walk(XmlNode node) {
    for (final child in node.children) {
      if (done) return;
      if (child is XmlElement) {
        _visit(child);
      } else if (child is XmlText && active && suppressed == 0) {
        // Visible text only: comments, CDATA and processing instructions are
        // other node types.
        _buffer.write(child.value);
      }
    }
  }

  void flush() {
    final text = normalizeStoryText(_buffer.toString());
    _buffer.clear();
    if (text.isNotEmpty) paragraphs.add(text);
  }

  void _visit(XmlElement element) {
    if (identical(element, end)) {
      flush();
      done = true;
      return;
    }
    if (identical(element, start)) {
      flush();
      active = true;
    }
    final name = _tagName(element);
    if (_imageTags.contains(name) && active) images++;
    final block = _blockTags.contains(name);
    if (block) flush();
    // After that flush, which ends a paragraph before a block; text waiting in
    // the buffer before an inline element is the paragraph it is in.
    if (identical(element, target)) beforeTarget = paragraphs.length;
    if (name == 'br') {
      if (active && suppressed == 0) _buffer.write(' ');
      return;
    }
    final skipped = _skipTags.contains(name) || _isPageBreak(element);
    if (skipped) suppressed++;
    walk(element);
    if (skipped) suppressed--;
    if (block) flush();
  }
}
