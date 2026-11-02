@Tags(['corpus'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/epub_sections.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/reader/toc_builder.dart';
import 'package:loremark/search/paragraph_index.dart';
import 'package:loremark/search/search_index.dart';
import 'package:loremark/search/search_index_codec.dart';
import 'package:loremark/search/stemmer.dart';
import 'package:loremark/search/tokenizer.dart';
import 'package:xml/xml.dart';

/// Runs the app's own code over a folder of real EPUBs and checks what it
/// promises: the book opens, its text is found, a book with no usable table
/// of contents gets sections, search never shows text past the cutoff and
/// does show text before it, and the page-end position maps to the right
/// place in the text. See docs/testing.md.
///
///     LOREMARK_CORPUS=<dir> LOREMARK_CORPUS_OUT=<file.jsonl> \
///       flutter test --tags corpus test/corpus
///
/// Queries are quoted so that the last word is not also a prefix.
///
/// The folder holds `raw/ID/book.epub` and `variants/ID-KIND/book.epub`.
void main() {
  final root = Platform.environment['LOREMARK_CORPUS'];
  final outPath = Platform.environment['LOREMARK_CORPUS_OUT'];
  if (root == null) {
    test('corpus', () {}, skip: 'set LOREMARK_CORPUS to a folder of EPUBs');
    return;
  }

  final books = <File>[];
  for (final group in ['raw', 'variants']) {
    final dir = Directory('$root/$group');
    if (!dir.existsSync()) continue;
    for (final entry in dir.listSync().whereType<Directory>()) {
      final file = File('${entry.path}/book.epub');
      if (file.existsSync()) books.add(file);
    }
  }
  books.sort((a, b) => a.lengthSync().compareTo(b.lengthSync()));
  final selected = Platform.environment['LOREMARK_CORPUS_ONLY']?.split(',');

  for (final file in books) {
    final id = file.parent.uri.pathSegments.lastWhere(
      (segment) => segment.isNotEmpty,
    );
    if (selected != null && !selected.contains(id)) continue;
    test('book $id', () {
      final problems = <String>[];
      final result = <String, Object?>{'id': id};
      try {
        _checkBook(file, id, result, problems);
      } on Object catch (error, stack) {
        problems.add('crashed: $error\n$stack');
      }
      result['problems'] = problems;
      if (outPath != null) {
        File(
          outPath,
        ).writeAsStringSync('${jsonEncode(result)}\n', mode: FileMode.append);
      }
      expect(problems, isEmpty, reason: id);
    }, timeout: const Timeout(Duration(minutes: 10)));
  }
}

bool _isWhitespace(int unit) =>
    (unit >= 0x09 && unit <= 0x0D) ||
    unit == 0x20 ||
    unit == 0xA0 ||
    unit == 0x1680 ||
    (unit >= 0x2000 && unit <= 0x200A) ||
    unit == 0x2028 ||
    unit == 0x2029 ||
    unit == 0x202F ||
    unit == 0x205F ||
    unit == 0x3000 ||
    unit == 0xFEFF;

final _han = RegExp(r'[㐀-䶿一-鿿぀-ヿ가-힯]');

int _ms(Stopwatch watch) {
  final value = watch.elapsedMilliseconds;
  watch
    ..reset()
    ..start();
  return value;
}

void _checkBook(
  File file,
  String id,
  Map<String, Object?> result,
  List<String> problems,
) {
  final damaged = id.endsWith('-truncated') || id.startsWith('notepub');
  final bytes = file.readAsBytesSync();
  result['bytes'] = bytes.length;
  final watch = Stopwatch()..start();

  // Opening.
  final List<SpineItem> spine;
  try {
    spine = spineFromBytes(bytes);
  } on Object catch (error) {
    result['openError'] = error.runtimeType.toString();
    if (!damaged) problems.add('did not open: $error');
    // The app turns only a FormatException into "can't open this book".
    if (damaged && error is! FormatException) {
      problems.add(
        'damaged file threw ${error.runtimeType}, not FormatException',
      );
    }
    return;
  }
  if (damaged) {
    problems.add('a damaged file opened');
    return;
  }
  result['spineMs'] = _ms(watch);
  result['spine'] = spine.length;

  // Text.
  final texts = sectionTextsFromBytes(bytes);
  result['textMs'] = _ms(watch);
  if (texts.length != spine.length) {
    problems.add('${texts.length} texts for ${spine.length} spine items');
  }
  var units = 0.0;
  var chars = 0;
  var empty = 0;
  var replacement = 0;
  for (var i = 0; i < texts.length; i++) {
    chars += texts[i].length;
    if (texts[i].trim().isEmpty) empty++;
    units += spine[i].linear ? readingUnits(texts[i]) : 0;
    replacement += '�'.allMatches(texts[i]).length;
  }
  result
    ..['sections'] = texts.length
    ..['linear'] = spine.where((item) => item.linear).length
    ..['emptySections'] = empty
    ..['chars'] = chars
    ..['words'] = units.round()
    ..['replacementChars'] = replacement
    ..['countMs'] = _ms(watch);
  if (units < 50) {
    problems.add('almost no text (${units.round()} words)');
    return;
  }
  if (replacement > chars * 0.001) {
    problems.add('many undecodable characters: $replacement');
  }

  // Sections for a book with no table of contents.
  final sections = sectionsWithoutToc(texts, spine);
  result['sectionBuildMs'] = _ms(watch);
  result['syntheticSections'] = sections.length;
  final expected = (units / wordsPerSection).round();
  if (expected >= 2 && sections.isEmpty) {
    problems.add('no sections for ${units.round()} words');
  }
  if (expected >= 2 && (sections.length - expected).abs() > 1) {
    problems.add('${sections.length} sections, expected about $expected');
  }
  ReaderPosition? previous;
  for (final entry in sections) {
    final position = entry.position!;
    if (!spine[position.sectionIndex].linear) {
      problems.add('section starts in a non-linear file');
    }
    if (position.progression < 0 || position.progression >= 1) {
      problems.add('section progression ${position.progression}');
    }
    if (previous != null) {
      final later =
          position.sectionIndex > previous.sectionIndex ||
          (position.sectionIndex == previous.sectionIndex &&
              position.progression > previous.progression);
      if (!later) problems.add('sections out of order: $previous, $position');
    }
    previous = position;
  }

  // Search index: build, save, load.
  final linear = [for (final item in spine) item.linear];
  final index = SearchIndex.build(
    bookId: id,
    sectionTexts: texts,
    linear: linear,
  );
  result['indexMs'] = _ms(watch);
  final encoded = encodeSearchIndex(index);
  result['encodeMs'] = _ms(watch);
  result['indexBytes'] = encoded.length;
  final loaded = decodeSearchIndex(encoded, bookId: id);
  result['decodeMs'] = _ms(watch);
  result['paragraphs'] = index.paragraphCount;

  // Paragraphs cover the text exactly, in order.
  final paragraphs = ParagraphIndex(texts, linear: linear);
  if (paragraphs.count != index.paragraphCount) {
    problems.add('paragraph count differs between the index and its parts');
  }
  var longest = 0;
  var over600 = 0;
  final lengths = <int>[];
  for (var s = 0; s < texts.length; s++) {
    final text = linear[s] ? texts[s] : '';
    final joined = StringBuffer();
    var last = -1;
    for (
      var id = paragraphs.firstIdOf(s);
      id < paragraphs.firstIdOf(s + 1);
      id++
    ) {
      if (paragraphs.startOf(id) < last) problems.add('paragraphs overlap');
      last = paragraphs.endOf(id);
      final piece = paragraphs.textOf(id);
      joined.write(piece);
      lengths.add(piece.length);
      longest = max(longest, piece.length);
      if (piece.length > 600) over600++;
    }
    if (_withoutSpace(joined.toString()) != _withoutSpace(text)) {
      problems.add('paragraphs of section $s do not cover its text');
      break;
    }
  }
  lengths.sort();
  result
    ..['longestParagraph'] = longest
    ..['paragraphsOver600'] = over600
    ..['medianParagraph'] = lengths.isEmpty ? 0 : lengths[lengths.length ~/ 2];
  watch.reset();

  _checkSearch(id, texts, paragraphs, index, loaded, result, problems);
  result['searchChecksMs'] = _ms(watch);

  _checkPageEnds(bytes, spine, texts, result, problems);
  result['pageEndChecksMs'] = _ms(watch);
}

String _withoutSpace(String text) {
  final out = StringBuffer();
  for (final unit in text.codeUnits) {
    if (!_isWhitespace(unit)) out.writeCharCode(unit);
  }
  return out.toString();
}

/// Words (or, for Chinese, Japanese and Korean, pairs of characters) whose
/// indexed term occurs in exactly one paragraph, with that paragraph's id.
///
/// Rarity is judged by the term the index uses, after stemming and folding,
/// so a hit for one of these words can only be that paragraph.
Map<String, int> _rareWords(ParagraphIndex paragraphs) {
  final tokenizer = Tokenizer(stem: porter2Stem);
  final counts = <String, int>{};
  final owner = <String, int>{};
  final surface = <String, String>{};
  for (var id = 0; id < paragraphs.count; id++) {
    final text = paragraphs.textOf(id);
    final seen = <String>{};
    for (final token in tokenizer.tokenize(text)) {
      if (seen.add(token.term)) {
        counts[token.term] = (counts[token.term] ?? 0) + 1;
        owner[token.term] = id;
        surface[token.term] = text.substring(token.start, token.end);
      }
    }
  }
  return {
    for (final entry in counts.entries)
      if (entry.value == 1 &&
          (surface[entry.key]!.length >= 5 ||
              _han.hasMatch(surface[entry.key]!)))
        surface[entry.key]!: owner[entry.key]!,
  };
}

void _checkSearch(
  String bookId,
  List<String> texts,
  ParagraphIndex paragraphs,
  SearchIndex index,
  SearchIndex loaded,
  Map<String, Object?> result,
  List<String> problems,
) {
  if (paragraphs.count < 20) return;
  final rare = _rareWords(paragraphs);
  result['rareWords'] = rare.length;
  if (rare.length < 10) {
    result['searchSkipped'] = 'too few words that occur once';
    return;
  }
  final byParagraph = <int, List<String>>{};
  for (final entry in rare.entries) {
    (byParagraph[entry.value] ??= []).add(entry.key);
  }
  final owners = byParagraph.keys.toList()..sort();
  final random = Random(bookId.hashCode);
  var checked = 0;
  var found = 0;
  var hiddenClean = 0;
  var boundary = 0;
  final failures = <String>[];

  ReaderPosition after(int id, {int shortBy = 0}) {
    final section = paragraphs.sectionOf(id);
    final length = texts[section].length;
    final at = paragraphs.endOf(id) - shortBy;
    // The end of a section is a finished section, as the reader reports it.
    if (at >= length) return ReaderPosition(section, 1);
    return ReaderPosition(section, (at + 0.25) / length);
  }

  final times = <int>[];
  for (var trial = 0; trial < 40; trial++) {
    final visibleOwners = owners.toList();
    // A cutoff just after paragraph j-1.
    final j = 2 + random.nextInt(paragraphs.count - 3);
    final cutoff = after(j - 1);
    if (index.visibleParagraphCount(cutoff) != j) {
      failures.add(
        'cutoff after paragraph ${j - 1} shows '
        '${index.visibleParagraphCount(cutoff)} paragraphs, not $j',
      );
      continue;
    }
    final before = visibleOwners.where((id) => id < j).toList();
    final later = visibleOwners.where((id) => id >= j).toList();
    if (before.isEmpty || later.isEmpty) continue;

    final seenId = before[random.nextInt(before.length)];
    final seenWord = byParagraph[seenId]!.first;
    final watch = Stopwatch()..start();
    final seen = index.search('"$seenWord"', cutoff: cutoff, limit: 20);
    times.add(watch.elapsedMicroseconds);
    checked++;
    final expectedText = paragraphs.textOf(seenId);
    if (seen.hits.any((hit) => hit.passage.text == expectedText)) {
      found++;
    } else {
      failures.add(
        '"$seenWord" before the cutoff was not found '
        '(paragraph $seenId, cutoff after ${j - 1})',
      );
    }

    final hiddenId = later[random.nextInt(later.length)];
    final hiddenWord = byParagraph[hiddenId]!.first;
    final hidden = index.search('"$hiddenWord"', cutoff: cutoff, limit: 20);
    // The term occurs in this one paragraph only, so any hit is a leak.
    if (hidden.hits.isEmpty) {
      hiddenClean++;
    } else {
      failures.add(
        '"$hiddenWord" past the cutoff was found '
        '(paragraph $hiddenId, cutoff after ${j - 1})',
      );
    }
    // Nothing returned may be past the cutoff, whatever was asked.
    for (final hit in [...seen.hits, ...hidden.hits]) {
      final id = paragraphs.idOf(
        hit.passage.sectionIndex,
        hit.passage.paragraphIndex,
      );
      if (id == null || id >= j) {
        failures.add(
          'a hit for "$seenWord"/"$hiddenWord" is paragraph $id, past $j',
        );
      }
    }

    // One character short of the end of paragraph j-1 hides it.
    final shortCut = after(j - 1, shortBy: 1);
    final lastWords = byParagraph[j - 1];
    if (lastWords != null) {
      boundary++;
      final r = index.search(
        '"${lastWords.first}"',
        cutoff: shortCut,
        limit: 20,
      );
      if (r.hits.any((hit) => hit.passage.text == paragraphs.textOf(j - 1))) {
        failures.add('paragraph ${j - 1} shown one character before its end');
      }
      final exact = index.search(
        '"${lastWords.first}"',
        cutoff: cutoff,
        limit: 20,
      );
      if (!exact.hits.any(
        (hit) => hit.passage.text == paragraphs.textOf(j - 1),
      )) {
        failures.add('paragraph ${j - 1} hidden at its exact end');
      }
    }

    // The index read back from disk answers the same.
    final again = loaded.search('"$seenWord"', cutoff: cutoff, limit: 20);
    if (again.hits.length != seen.hits.length ||
        (again.hits.isNotEmpty &&
            again.hits.first.passage.text != seen.hits.first.passage.text)) {
      failures.add('a saved index answers "$seenWord" differently');
    }
  }
  times.sort();
  result
    ..['searchTrials'] = checked
    ..['searchFound'] = found
    ..['searchHiddenClean'] = hiddenClean
    ..['searchBoundaryChecks'] = boundary
    ..['queryP50Us'] = times.isEmpty ? 0 : times[times.length ~/ 2]
    ..['queryMaxUs'] = times.isEmpty ? 0 : times.last;
  for (final failure in failures.take(6)) {
    problems.add('search: $failure');
  }
  if (failures.length > 6) problems.add('search: ${failures.length - 6} more');
}

/// Where in a document's plain text the page ends, worked out a different
/// way from the app: count the non-whitespace characters in front of the
/// block in the markup, then find that many in the plain text.
int? _expectedEnd(
  XmlDocument document,
  XmlElement target,
  int characters,
  String text,
) {
  var count = 0;
  var done = false;
  const skipped = {'head', 'script', 'style', 'svg', 'rt', 'rp'};
  void walk(XmlNode node) {
    if (done) return;
    if (node is XmlText || node is XmlCDATA) {
      for (final unit in node.value!.codeUnits) {
        if (!_isWhitespace(unit)) count++;
      }
    } else if (node is XmlElement) {
      if (identical(node, target)) {
        done = true;
        return;
      }
      if (skipped.contains(node.name.local.toLowerCase())) return;
      node.children.forEach(walk);
    }
  }

  final body = document.findAllElements('body').firstOrNull;
  if (body == null) return null;
  walk(body);
  final want = count + characters;
  var seen = 0;
  for (var i = 0; i < text.length; i++) {
    if (_isWhitespace(text.codeUnitAt(i))) continue;
    if (seen == want) return i;
    seen++;
  }
  return null;
}

/// How many non-whitespace characters of [element] are in the plain text,
/// which leaves out ruby readings, scripts and the like.
int _plainSize(XmlElement element) {
  const skipped = {'head', 'script', 'style', 'svg', 'rt', 'rp'};
  var count = 0;
  void walk(XmlNode node) {
    if (node is XmlText || node is XmlCDATA) {
      for (final unit in node.value!.codeUnits) {
        if (!_isWhitespace(unit)) count++;
      }
    } else if (node is XmlElement) {
      if (skipped.contains(node.name.local.toLowerCase())) return;
      node.children.forEach(walk);
    }
  }

  element.children.forEach(walk);
  return count;
}

String _tail(String text, int end) {
  final units = <int>[];
  for (var i = end - 1; i >= 0 && units.length < tailLength; i--) {
    if (!_isWhitespace(text.codeUnitAt(i))) units.add(text.codeUnitAt(i));
  }
  return String.fromCharCodes(units.reversed);
}

void _checkPageEnds(
  List<int> bytes,
  List<SpineItem> spine,
  List<String> texts,
  Map<String, Object?> result,
  List<String> problems,
) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final candidates = [
    for (var i = 0; i < spine.length; i++)
      if (spine[i].linear && texts[i].length > 300) i,
  ];
  if (candidates.isEmpty) return;
  candidates.sort((a, b) => texts[b].length.compareTo(texts[a].length));
  final random = Random(bytes.length);
  final chosen = <int>{
    ...candidates.take(2),
    for (var i = 0; i < 3 && i < candidates.length; i++)
      candidates[random.nextInt(candidates.length)],
  };
  var checked = 0;
  var mismatches = 0;
  var blocksTotal = 0;
  for (final s in chosen) {
    final file = archive.findFile(spine[s].path);
    if (file == null) continue;
    final xhtml = utf8
        .decode(file.content, allowMalformed: true)
        .replaceFirst('﻿', '');
    final XmlDocument document;
    try {
      document = XmlDocument.parse(
        xhtml,
        entityMapping: const XmlDefaultEntityMapping.html5(),
      );
    } on XmlException {
      result['pageEndSkipped'] = 'section $s is not well-formed XML';
      continue;
    }
    final body = document.findAllElements('body').firstOrNull;
    if (body == null) continue;
    final blocks = textBlocks(body).toList();
    blocksTotal += blocks.length;
    if (blocks.isEmpty) continue;
    final text = texts[s];
    final samples = <(int, int)>[];
    for (var t = 0; t < 30; t++) {
      final n = random.nextInt(blocks.length);
      final size = _plainSize(blocks[n]);
      if (size == 0) continue;
      // A position inside the block: a one-character block has only 0.
      final k = [0, 1, size - 1, random.nextInt(size)][t % 4];
      samples.add((n, min(k, size - 1)));
    }
    samples
      ..add((0, 0))
      ..add((blocks.length - 1, 0));
    double? last;
    for (final (n, k) in samples) {
      final expected = _expectedEnd(document, blocks[n], k, text);
      final actual = textProgressionOfBlock(xhtml, n, characters: k);
      checked++;
      if (expected == null) {
        if (actual != null) {
          mismatches++;
          problems.add('page end $s:$n:$k found where none expected');
        }
        continue;
      }
      final want = (expected + 0.25) / text.length;
      if (actual == null || (actual - want).abs() > 1e-12) {
        mismatches++;
        if (mismatches <= 5) {
          problems.add('page end $s:$n:$k is $actual, expected $want');
        }
        continue;
      }
      // The tail check accepts the true tail and rejects a wrong one.
      final tail = _tail(text, expected);
      if (tail.isNotEmpty) {
        final good = textProgressionOfBlock(
          xhtml,
          n,
          characters: k,
          tail: tail,
        );
        final bad = textProgressionOfBlock(
          xhtml,
          n,
          characters: k,
          tail: '${tail.substring(0, tail.length - 1)}\u0001',
        );
        if (good == null) problems.add('true tail refused at $s:$n:$k');
        if (bad != null) problems.add('wrong tail accepted at $s:$n:$k');
      }
      last = actual;
    }
    // Reading on never moves back: later (block, characters) are later.
    var previous = -1.0;
    for (var n = 0; n < min(blocks.length, 40); n++) {
      final p = textProgressionOfBlock(xhtml, n, characters: 0);
      if (p == null) continue;
      if (p <= previous) problems.add('page end $s:$n:0 does not move forward');
      previous = p;
    }
    if (last == null && samples.isNotEmpty) {
      result['pageEndNote'] = 'no sample mapped in section $s';
    }
  }
  result
    ..['pageEndChecks'] = checked
    ..['pageEndMismatches'] = mismatches
    ..['textBlocksSampled'] = blocksTotal;
}
