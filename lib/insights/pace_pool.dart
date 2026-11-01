import 'dart:convert';
import 'dart:io';

import 'insights_config.dart';
import 'reading_timeline.dart';

/// What one book's log adds to the others: its recent pace samples and its
/// reading time per day.
///
/// A book's pace needs its section sizes to compute, so other books' logs
/// can't be read without their EPUBs. Instead each book leaves a small
/// summary beside its log, `<book id>.stats.json`, and a new book reads its
/// siblings' to start with the reader's usual speed, and to count today and
/// the streak across the whole library.
class PoolData {
  const PoolData({this.samples = const [], this.days = const {}});

  /// Samples from other books, oldest first.
  final List<PaceSample> samples;

  /// Active reading milliseconds per local day, summed over the other books.
  final Map<String, int> days;
}

const _statsSuffix = '.stats.json';

File statsFile(Directory root, String bookId) =>
    File('${root.path}/reading_log/$bookId$_statsSuffix');

/// Writes a book's summary: the newest [InsightsConfig.poolWindow] [samples]
/// and the milliseconds read on each of [days]. Atomic, so a crash leaves
/// the old summary.
Future<void> writeStats(
  File file, {
  required List<PaceSample> samples,
  required Map<String, int> days,
  InsightsConfig config = const InsightsConfig(),
}) async {
  final recent = samples.length > config.poolWindow
      ? samples.sublist(samples.length - config.poolWindow)
      : samples;
  await file.parent.create(recursive: true);
  final temp = File('${file.path}.tmp');
  await temp.writeAsString(
    jsonEncode({
      'version': 1,
      'samples': [for (final s in recent) s.toJson()],
      'days': days,
    }),
    flush: true,
  );
  await temp.rename(file.path);
}

/// The summaries of every book but [excludeId] in the library folder
/// [root]. A missing or broken file reads as nothing.
Future<PoolData> loadPool(
  Directory root, {
  required String excludeId,
  InsightsConfig config = const InsightsConfig(),
}) async {
  final directory = Directory('${root.path}/reading_log');
  final samples = <PaceSample>[];
  final days = <String, int>{};
  try {
    if (!await directory.exists()) return const PoolData();
    await for (final entry in directory.list()) {
      if (entry is! File || !entry.path.endsWith(_statsSuffix)) continue;
      final name = entry.uri.pathSegments.last;
      if (name == '$excludeId$_statsSuffix') continue;
      try {
        final json = jsonDecode(await entry.readAsString());
        if (json is! Map || json['version'] != 1) continue;
        for (final raw in (json['samples'] as List? ?? const [])) {
          final sample = PaceSample.fromJson(raw);
          if (sample != null) samples.add(sample);
        }
        final byDay = json['days'];
        if (byDay is Map) {
          for (final MapEntry(:key, :value) in byDay.entries) {
            if (key is String && value is int) {
              days.update(key, (ms) => ms + value, ifAbsent: () => value);
            }
          }
        }
      } on Object {
        // One bad summary must not hide the others.
      }
    }
  } on FileSystemException {
    return const PoolData();
  }
  samples.sort((a, b) => a.t.compareTo(b.t));
  return PoolData(
    samples: samples.length > config.poolWindow
        ? samples.sublist(samples.length - config.poolWindow)
        : samples,
    days: days,
  );
}
