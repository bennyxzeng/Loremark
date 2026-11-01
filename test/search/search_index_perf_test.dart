import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/search/search_index.dart';
import 'package:loremark/search/search_index_codec.dart';

/// A book of about [words] words with a Zipf-like vocabulary, in 40 sections.
List<String> generatedBook(int words, Random random) {
  const letters = 'abcdefghijklmnopqrstuvwxyz';
  final vocabulary = List.generate(12000, (i) {
    final length = 3 + random.nextInt(7);
    return String.fromCharCodes(
      List.generate(length, (_) => letters.codeUnitAt(random.nextInt(26))),
    );
  });
  // Rank r is drawn with probability about 1 / r.
  String word() =>
      vocabulary[(exp(random.nextDouble() * log(12000))).floor() - 1];

  final perSection = words ~/ 40;
  return [
    for (var s = 0; s < 40; s++)
      [
        for (var left = perSection; left > 0;) ...[
          () {
            final n = min(left, 20 + random.nextInt(60));
            left -= n;
            return List.generate(n, (_) => word()).join(' ');
          }(),
        ],
      ].join('\n\n'),
  ];
}

void main() {
  // Roughly a sixth of the size of the 500,000-word book of the scalability
  // target, built in well under a second on a laptop. The bounds are loose so
  // a slow CI machine passes; they exist to catch a change that makes
  // indexing or querying quadratic.
  test('indexes 100,000 words and answers queries quickly', () {
    final texts = generatedBook(100000, Random(1));

    final build = Stopwatch()..start();
    final index = SearchIndex.build(
      bookId: 'perf',
      sectionTexts: texts,
      stem: true,
    );
    build.stop();

    final encoded = Stopwatch()..start();
    final bytes = encodeSearchIndex(index);
    encoded.stop();
    final decoded = Stopwatch()..start();
    decodeSearchIndex(bytes, bookId: 'perf');
    decoded.stop();

    const cutoff = ReaderPosition(30, 0.5);
    final random = Random(2);
    final latencies = <int>[];
    final sample = texts[3].split(' ');
    for (var i = 0; i < 100; i++) {
      final query = switch (i % 4) {
        0 => sample[random.nextInt(sample.length)],
        1 =>
          '${sample[random.nextInt(sample.length)]} '
              '${sample[random.nextInt(sample.length)]}',
        2 => sample[random.nextInt(sample.length)].substring(0, 3),
        _ => '"${sample[10]} ${sample[11]}"',
      };
      final timer = Stopwatch()..start();
      index.search(query, cutoff: cutoff);
      latencies.add(timer.elapsedMicroseconds);
    }
    latencies.sort();

    // ignore: avoid_print
    print(
      'search perf: ${index.paragraphCount} paragraphs, ${index.termCount} '
      'terms; build ${build.elapsedMilliseconds} ms; encode '
      '${encoded.elapsedMilliseconds} ms (${bytes.length ~/ 1024} KiB); '
      'decode ${decoded.elapsedMilliseconds} ms; query p50 '
      '${latencies[50] / 1000} ms, p95 ${latencies[95] / 1000} ms',
    );
    expect(build.elapsedMilliseconds, lessThan(15000));
    expect(decoded.elapsedMilliseconds, lessThan(5000));
    expect(latencies[95], lessThan(500 * 1000));
  });
}
