import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/insights/pace_pool.dart';
import 'package:loremark/insights/reading_timeline.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('loremark_pool_');
  });

  tearDown(() => temp.delete(recursive: true));

  List<PaceSample> samples(int count, {int from = 0, double sec = 40}) => [
    for (var i = 0; i < count; i++)
      PaceSample(t: from + i, units: 200, sec: sec),
  ];

  test('reads the other books, not this one', () async {
    await writeStats(
      statsFile(temp, 'other'),
      samples: samples(10),
      days: {'2026-10-04': 600000},
    );
    await writeStats(
      statsFile(temp, 'mine'),
      samples: samples(50, sec: 99),
      days: {'2026-10-05': 1},
    );

    final pool = await loadPool(temp, excludeId: 'mine');

    expect(pool.samples, hasLength(10));
    expect(pool.samples.first.sec, 40);
    expect(pool.days, {'2026-10-04': 600000});
  });

  test(
    'adds up the days of several books and merges samples by time',
    () async {
      await writeStats(
        statsFile(temp, 'a'),
        samples: samples(3, from: 0),
        days: {'2026-10-04': 100, '2026-10-03': 5},
      );
      await writeStats(
        statsFile(temp, 'b'),
        samples: samples(3, from: 1, sec: 50),
        days: {'2026-10-04': 200},
      );

      final pool = await loadPool(temp, excludeId: 'c');

      expect(pool.days, {'2026-10-04': 300, '2026-10-03': 5});
      expect(pool.samples.map((s) => s.t), [0, 1, 1, 2, 2, 3]);
    },
  );

  test('keeps the newest 100 samples', () async {
    await writeStats(
      statsFile(temp, 'a'),
      samples: samples(150),
      days: const {},
    );
    await writeStats(
      statsFile(temp, 'b'),
      samples: samples(150, from: 1000),
      days: const {},
    );

    final pool = await loadPool(temp, excludeId: 'c');

    expect(pool.samples, hasLength(100));
    expect(pool.samples.first.t, greaterThanOrEqualTo(1000));
  });

  test('a book keeps only its newest 100 samples in the summary', () async {
    await writeStats(
      statsFile(temp, 'a'),
      samples: samples(150),
      days: const {},
    );

    final json = jsonDecode(await statsFile(temp, 'a').readAsString());

    expect((json['samples'] as List), hasLength(100));
    expect((json['samples'] as List).first[0], 50);
  });

  test('skips broken, foreign and temporary files', () async {
    final folder = Directory('${temp.path}/reading_log')..createSync();
    File('${folder.path}/broken.stats.json').writeAsStringSync('{nope');
    File('${folder.path}/future.stats.json').writeAsStringSync(
      jsonEncode({
        'version': 2,
        'samples': [
          [1, 200, 40],
        ],
      }),
    );
    File('${folder.path}/odd.stats.json').writeAsStringSync(
      jsonEncode({
        'version': 1,
        'samples': [
          [1, 200, 40],
          'junk',
          [2, -5, 40],
          [3, 200],
        ],
        'days': {'2026-10-01': 5, 'bad': 'x', '2026-10-02': 1.5},
      }),
    );
    File('${folder.path}/x.stats.json.tmp').writeAsStringSync('{}');
    File('${folder.path}/other.jsonl').writeAsStringSync('{}');
    File('${folder.path}/settings.json').writeAsStringSync('{}');

    final pool = await loadPool(temp, excludeId: 'me');

    expect(pool.samples, hasLength(1));
    expect(pool.days, {'2026-10-01': 5});
  });

  test('a library with no reading folder has an empty pool', () async {
    final pool = await loadPool(temp, excludeId: 'me');

    expect(pool.samples, isEmpty);
    expect(pool.days, isEmpty);
  });

  test('replaces a book\'s summary atomically', () async {
    final file = statsFile(temp, 'a');
    await writeStats(file, samples: samples(1), days: {'2026-10-01': 1});
    await writeStats(file, samples: samples(2), days: {'2026-10-01': 2});

    final pool = await loadPool(temp, excludeId: 'me');

    expect(pool.samples, hasLength(2));
    expect(pool.days, {'2026-10-01': 2});
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });
}
