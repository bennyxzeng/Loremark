import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../reader/epub_sections.dart';
import '../reader/reader_position.dart';
import 'insights_config.dart';

/// The format of a units cache file. Raise it when counting changes, so old
/// files are counted again.
const unitsCacheVersion = 1;

/// How much there is to read in each section of a book.
///
/// The unit is a whitespace-delimited word or one CJK character, so a page of
/// Chinese and a page of English can be compared on the same scale. Position
/// arithmetic uses cumulative offsets over every spine item: the end of
/// section `s` is the same offset as the start of `s + 1`, which keeps the
/// two positions of a section turn continuous.
class BookUnits {
  /// Builds from per-section [counts] and whether each section is [linear].
  BookUnits({
    required List<int> counts,
    required List<bool> linear,
    this.cjkUnits = 0,
  }) : assert(counts.length == linear.length),
       counts = List.unmodifiable(counts),
       linear = List.unmodifiable(linear),
       _offsets = _prefixSums(counts);

  /// A book with nothing to measure, for when the EPUB can't be read.
  BookUnits.empty() : this(counts: const [], linear: const []);

  /// Counts the words and CJK characters in each of [texts], which are the
  /// sections of a book in spine order. [linear] defaults to all true.
  factory BookUnits.fromTexts(List<String> texts, {List<bool>? linear}) {
    final counts = <int>[];
    var cjk = 0;
    for (final text in texts) {
      final (:units, cjk: sectionCjk) = countUnits(text);
      counts.add(units);
      cjk += sectionCjk;
    }
    return BookUnits(
      counts: counts,
      linear: linear ?? List.filled(texts.length, true),
      cjkUnits: cjk,
    );
  }

  /// Counts the book at [epubPath] off the UI isolate.
  static Future<BookUnits> load(String epubPath) => Isolate.run(() {
    final bytes = File(epubPath).readAsBytesSync();
    return BookUnits.fromTexts(
      sectionTextsFromBytes(bytes),
      linear: [for (final item in spineFromBytes(bytes)) item.linear],
    );
  });

  /// [load], but remembered in [cache] under [bookId], the hash of the EPUB,
  /// so only the first open of a book unzips and counts it. A missing,
  /// damaged or old cache is counted afresh and replaced; a cache that can't
  /// be written costs only the next open some time.
  static Future<BookUnits> loadCached(
    String epubPath, {
    required File cache,
    required String bookId,
  }) async {
    final cached = await _readCache(cache, bookId);
    if (cached != null) return cached;
    final units = await load(epubPath);
    await _writeCache(cache, bookId, units);
    return units;
  }

  static Future<BookUnits?> _readCache(File cache, String bookId) async {
    try {
      final json = jsonDecode(await cache.readAsString());
      if (json is! Map ||
          json['version'] != unitsCacheVersion ||
          json['id'] != bookId) {
        return null;
      }
      final counts = (json['counts'] as List).cast<int>();
      final linear = (json['linear'] as List).cast<bool>();
      final cjk = json['cjk'] as int;
      final total = counts.fold(0, (a, b) => a + b);
      if (counts.isEmpty ||
          counts.length != linear.length ||
          counts.any((count) => count < 0) ||
          cjk < 0 ||
          cjk > total) {
        return null;
      }
      return BookUnits(counts: counts, linear: linear, cjkUnits: cjk);
    } on Object {
      // Missing, unreadable or not what we wrote: count the book again.
      return null;
    }
  }

  static Future<void> _writeCache(
    File cache,
    String bookId,
    BookUnits units,
  ) async {
    try {
      await cache.parent.create(recursive: true);
      final temp = File('${cache.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          'version': unitsCacheVersion,
          'id': bookId,
          'counts': units.counts,
          'linear': units.linear,
          'cjk': units.cjkUnits,
        }),
        flush: true,
      );
      await temp.rename(cache.path);
    } on Object catch (error) {
      debugPrint('Could not save the unit counts of $bookId: $error');
    }
  }

  /// Units in each spine item.
  final List<int> counts;

  /// Whether each spine item is part of the reading order.
  final List<bool> linear;

  /// How many of the units are CJK characters.
  final int cjkUnits;

  final List<double> _offsets;

  int get sectionCount => counts.length;
  bool get isEmpty => counts.isEmpty;
  double get total => _offsets.last;

  /// Whether a unit in this book is a character rather than a word.
  bool countsCharacters(InsightsConfig config) =>
      total > 0 && cjkUnits > total * config.cjkMajority;

  /// Reading speed to assume before the reader's own is known.
  double defaultUnitsPerMinute(InsightsConfig config) =>
      countsCharacters(config)
      ? config.defaultCjkUnitsPerMinute
      : config.defaultLatinUnitsPerMinute;

  /// A page's length to assume before page turns say otherwise.
  double defaultPageUnits(InsightsConfig config) => countsCharacters(config)
      ? config.defaultCjkPageUnits
      : config.defaultPageUnits;

  /// Where [position] is, counted in units from the start of the book.
  double offsetOf(ReaderPosition position) =>
      offsetAt(position.sectionIndex, position.progression);

  double offsetAt(int section, double progression) {
    if (counts.isEmpty) return 0;
    if (section >= counts.length) return total;
    return _offsets[section] + progression * counts[section];
  }

  /// The position at [offset], the inverse of [offsetOf]. An offset on a
  /// section border is the start of the later section.
  ReaderPosition positionAt(double offset) {
    if (counts.isEmpty) return const ReaderPosition(0, 0);
    if (offset >= total) {
      return ReaderPosition(counts.length - 1, 1);
    }
    var low = 0;
    var high = counts.length - 1;
    // The last section starting at or before the offset, skipping empty ones
    // that share its start.
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_offsets[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    final size = counts[low];
    final progression = size == 0 ? 0.0 : (offset - _offsets[low]) / size;
    return ReaderPosition(low, progression.clamp(0.0, 1.0));
  }

  /// Units from [position] to the start of section [endSection], counting
  /// only linear items (non-linear ones such as footnotes are not paged
  /// through). The section [position] is in always counts, from where the
  /// reader is. Pass the section count for the rest of the book.
  double remaining(ReaderPosition position, int endSection) {
    if (counts.isEmpty || position.sectionIndex >= counts.length) return 0;
    final section = position.sectionIndex;
    var units = (1 - position.progression) * counts[section];
    final end = endSection < counts.length ? endSection : counts.length;
    for (var i = section + 1; i < end; i++) {
      if (linear[i]) units += counts[i];
    }
    return units;
  }

  static List<double> _prefixSums(List<int> counts) {
    final sums = <double>[0];
    for (final count in counts) {
      sums.add(sums.last + count);
    }
    return sums;
  }
}

/// CJK ideographs, kana and hangul: scripts that aren't written with spaces
/// between words, so each character is a unit (as in Brysbaert 2019's
/// characters-per-minute figures for Chinese).
final _cjk = RegExp(
  r'[぀-ヿ㐀-䶿一-鿿가-힯豈-﫿'
  r'\u{20000}-\u{2fa1f}]',
  unicode: true,
);

/// A word: letters and digits, joined by apostrophes and hyphens.
final _word = RegExp(r"[\p{L}\p{N}]+(?:['’-][\p{L}\p{N}]+)*", unicode: true);

/// The units in [text], and how many of them are CJK characters.
({int units, int cjk}) countUnits(String text) {
  final cjk = _cjk.allMatches(text).length;
  // Hiding the CJK characters first keeps a run of them from counting as one
  // word.
  final words = _word.allMatches(cjk == 0 ? text : text.replaceAll(_cjk, ' '));
  return (units: words.length + cjk, cjk: cjk);
}
