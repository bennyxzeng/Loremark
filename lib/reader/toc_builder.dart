import 'dart:io';
import 'dart:isolate';

import 'epub_reader_service.dart';
import 'epub_sections.dart';
import 'reader_position.dart';

/// How long a section of a book without a table of contents is, in words.
const wordsPerSection = 5000;

/// Sections of about [wordsPerSection] words for a book that has no usable
/// table of contents, so the reader still has something to jump through.
///
/// [sectionTexts] is the plain text of every spine item, as
/// `readSectionTexts` gives it, and [spine] says which of them the reader
/// turns pages through. The book is cut into `round(words / wordsPerSection)`
/// equal parts. A cut that falls near the start of a spine item moves to that
/// start, since that is a cleaner place to land; the others fall inside the
/// item, at the share of its words they are at.
///
/// Empty for a book too short to be worth cutting, under about one and a
/// half sections.
List<TocEntry> sectionsWithoutToc(
  List<String> sectionTexts,
  List<SpineItem> spine, {
  int wordsPerSection = wordsPerSection,
}) {
  if (sectionTexts.length != spine.length || wordsPerSection <= 0) {
    throw ArgumentError('one text and one spine item per section');
  }
  final units = [
    for (var i = 0; i < sectionTexts.length; i++)
      spine[i].linear ? readingUnits(sectionTexts[i]) : 0.0,
  ];
  final total = units.fold<double>(0, (sum, value) => sum + value);
  final parts = (total / wordsPerSection).round();
  if (parts < 2) return const [];

  // Where each item starts, in words from the start of the book.
  final starts = <double>[];
  var running = 0.0;
  for (final value in units) {
    starts.add(running);
    running += value;
  }

  final target = total / parts;
  final firstSection = units.indexWhere((value) => value > 0);
  final positions = <ReaderPosition>[ReaderPosition(firstSection, 0)];
  for (var k = 1; k < parts; k++) {
    final want = k * target;
    final position = _positionAt(want, units, starts, snap: 0.2 * target);
    final previous = positions.last;
    final after =
        position.sectionIndex > previous.sectionIndex ||
        (position.sectionIndex == previous.sectionIndex &&
            position.progression > previous.progression);
    if (after) positions.add(position);
  }
  return [
    for (var n = 0; n < positions.length; n++)
      TocEntry(
        title: 'Section ${n + 1}',
        href: '',
        sectionIndex: positions[n].sectionIndex,
        position: positions[n],
      ),
  ];
}

/// The spine position [want] words into the book: the start of an item if
/// one is within [snap] words, otherwise inside the item it falls in.
ReaderPosition _positionAt(
  double want,
  List<double> units,
  List<double> starts, {
  required double snap,
}) {
  var nearest = -1;
  var nearestDistance = snap;
  for (var i = 0; i < units.length; i++) {
    if (units[i] <= 0) continue;
    final distance = (starts[i] - want).abs();
    if (distance <= nearestDistance) {
      nearest = i;
      nearestDistance = distance;
    }
  }
  if (nearest != -1) return ReaderPosition(nearest, 0);
  for (var i = units.length - 1; i >= 0; i--) {
    if (units[i] > 0 && starts[i] <= want) {
      final inside = (want - starts[i]) / units[i];
      return ReaderPosition(i, inside.clamp(0.0, 0.999).toDouble());
    }
  }
  return ReaderPosition(units.indexWhere((value) => value > 0), 0);
}

/// [sectionsWithoutToc] for the EPUB at [epubPath], with the reading and the
/// counting done off the UI isolate: a very long book takes a second or more.
Future<List<TocEntry>> readSectionsWithoutToc(
  String epubPath,
  List<SpineItem> spine,
) => Isolate.run(
  () => sectionsWithoutToc(
    sectionTextsFromBytes(File(epubPath).readAsBytesSync()),
    spine,
  ),
);

final _cjk = RegExp(r'[぀-ヿ㐀-䶿一-鿿가-힯]');

/// How many words [text] is worth for sizing sections: words split by
/// whitespace, with each Chinese, Japanese or Korean character counting as
/// 0.6 of a word, since those scripts have no spaces between words.
double readingUnits(String text) {
  var cjk = 0;
  for (final _ in _cjk.allMatches(text)) {
    cjk++;
  }
  final words = text
      .replaceAll(_cjk, ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .length;
  return words + cjk * 0.6;
}
