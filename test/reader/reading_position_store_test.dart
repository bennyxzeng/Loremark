import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/page_start.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/reader/reading_position_store.dart';

void main() {
  late Directory temp;
  late ReadingPositionStore store;

  const bookA = 'a1b2c3';
  const bookB = 'd4e5f6';

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('loremark_position_');
    store = ReadingPositionStore(Directory('${temp.path}/library'));
  });

  tearDown(() => temp.delete(recursive: true));

  File fileFor(String id) => File('${store.root.path}/reading_state/$id.json');

  Future<void> writeRaw(String id, String contents) async {
    await fileFor(id).parent.create(recursive: true);
    await fileFor(id).writeAsString(contents);
  }

  test('keeps the position across restarts', () async {
    const position = ReaderPosition(4, 0.37, totalProgression: 0.5);

    await store.save(bookA, position);
    final restarted = ReadingPositionStore(store.root);

    expect(await restarted.load(bookA), position);
  });

  group('where the page starts', () {
    const start = PageStart(3, ':root > :nth-child(2) > :nth-child(9)');

    test('is kept across restarts', () async {
      await store.savePageStart(bookA, start);
      expect(
        await ReadingPositionStore(store.root).loadPageStart(bookA),
        start,
      );
    });

    test('and the position don\'t disturb each other', () async {
      const position = ReaderPosition(3, 0.4);
      await store.save(bookA, position);
      await store.savePageStart(bookA, start);
      expect(await store.load(bookA), position);
      expect(await store.loadPageStart(bookA), start);

      const later = ReaderPosition(3, 0.5);
      await store.save(bookA, later);
      expect(await store.load(bookA), later);
      expect(await store.loadPageStart(bookA), start);
    });

    test('saved together with the position, both are written', () async {
      const position = ReaderPosition(3, 0.4);
      await Future.wait([
        store.save(bookA, position),
        store.savePageStart(bookA, start),
        store.save(bookA, position),
      ]);
      expect(await store.load(bookA), position);
      expect(await store.loadPageStart(bookA), start);
    });

    test('is null with none saved', () async {
      expect(await store.loadPageStart(bookA), isNull);
      await store.save(bookA, const ReaderPosition(1, 0.5));
      expect(await store.loadPageStart(bookA), isNull);
    });

    test('is null when it can\'t be read', () async {
      await writeRaw(
        bookA,
        '{"version":1,"pageStart":{"sectionIndex":-1,"cssSelector":"p"}}',
      );
      expect(await store.loadPageStart(bookA), isNull);
      await writeRaw(bookA, 'not json');
      expect(await store.loadPageStart(bookA), isNull);
    });
  });

  test('writes the version and the current position', () async {
    await store.save(bookA, const ReaderPosition(1, 0.5));

    expect(jsonDecode(await fileFor(bookA).readAsString()), {
      'version': 1,
      'current': {'sectionIndex': 1, 'progression': 0.5},
    });
  });

  test('keeps each book separate', () async {
    await store.save(bookA, const ReaderPosition(1, 0.1));
    await store.save(bookB, const ReaderPosition(2, 0.2));

    expect(await store.load(bookA), const ReaderPosition(1, 0.1));
    expect(await store.load(bookB), const ReaderPosition(2, 0.2));
  });

  test('overwrites the previous position', () async {
    await store.save(bookA, const ReaderPosition(1, 0.1));
    await store.save(bookA, const ReaderPosition(1, 0.9));

    expect(await store.load(bookA), const ReaderPosition(1, 0.9));
  });

  test('has no position for a book never saved', () async {
    expect(await store.load(bookA), isNull);
  });

  group('a file that cannot be read', () {
    Future<void> expectsNull(String contents) async {
      await writeRaw(bookA, contents);
      expect(await store.load(bookA), isNull);
    }

    test('is ignored when it is not JSON', () => expectsNull('{"version": 1,'));
    test('is ignored when it is empty', () => expectsNull(''));
    test('is ignored when it is not an object', () => expectsNull('[1, 2]'));
    test(
      'is ignored when current is missing',
      () => expectsNull('{"version": 1}'),
    );
    test(
      'is ignored when current has the wrong shape',
      () => expectsNull('{"version": 1, "current": "page 4"}'),
    );
    test(
      'is ignored when a field has the wrong type',
      () => expectsNull(
        '{"version": 1, "current": {"sectionIndex": "1", "progression": 0.5}}',
      ),
    );
    test(
      'is ignored when progression is out of range',
      () => expectsNull(
        '{"version": 1, "current": {"sectionIndex": 1, "progression": 1.5}}',
      ),
    );
    test(
      'is ignored when the version is unknown',
      () => expectsNull(
        '{"version": 2, "current": {"sectionIndex": 1, "progression": 0.5}}',
      ),
    );

    test('is ignored when it is not valid UTF-8', () async {
      await fileFor(bookA).parent.create(recursive: true);
      await fileFor(bookA).writeAsBytes([0xff, 0xfe, 0xfd]);

      expect(await store.load(bookA), isNull);
    });

    test('is ignored when it is a directory', () async {
      await Directory(fileFor(bookA).path).create(recursive: true);

      expect(await store.load(bookA), isNull);
    });
  });

  test('ignores a leftover temporary file', () async {
    await store.save(bookA, const ReaderPosition(1, 0.5));
    await File('${fileFor(bookA).path}.tmp')
        .writeAsString('{"version": 1, "cur');
    await File('${fileFor(bookB).path}.tmp').writeAsString(
      '{"version": 1, "current": {"sectionIndex": 9, "progression": 0.9}}',
    );

    expect(await store.load(bookA), const ReaderPosition(1, 0.5));
    expect(await store.load(bookB), isNull);
  });

  test('a later save replaces a leftover temporary file', () async {
    final temp = File('${fileFor(bookA).path}.tmp');
    await temp.parent.create(recursive: true);
    await temp.writeAsString('stale');

    await store.save(bookA, const ReaderPosition(2, 0.3));

    expect(await store.load(bookA), const ReaderPosition(2, 0.3));
    expect(await temp.exists(), isFalse);
  });

  group('other keys', () {
    test('survive a save', () async {
      await writeRaw(
        bookA,
        jsonEncode({
          'version': 1,
          'current': {'sectionIndex': 0, 'progression': 0.1},
          'furthest': {'sectionIndex': 3, 'progression': 0.5},
          'boundary': 7,
        }),
      );

      await store.save(bookA, const ReaderPosition(1, 0.5));

      expect(jsonDecode(await fileFor(bookA).readAsString()), {
        'version': 1,
        'current': {'sectionIndex': 1, 'progression': 0.5},
        'furthest': {'sectionIndex': 3, 'progression': 0.5},
        'boundary': 7,
      });
    });

    test('survive many saves', () async {
      await writeRaw(bookA, jsonEncode({'version': 1, 'furthest': 'kept'}));

      for (var i = 0; i < 5; i++) {
        await store.save(bookA, ReaderPosition(i, 0));
      }

      final json = jsonDecode(await fileFor(bookA).readAsString());
      expect(json['furthest'], 'kept');
      expect(json['current']['sectionIndex'], 4);
    });

    test('are dropped with a file of another version', () async {
      await writeRaw(bookA, jsonEncode({'version': 2, 'furthest': 'old'}));

      await store.save(bookA, const ReaderPosition(1, 0.5));

      expect(jsonDecode(await fileFor(bookA).readAsString()), {
        'version': 1,
        'current': {'sectionIndex': 1, 'progression': 0.5},
      });
    });

    test('are dropped with a corrupt file', () async {
      await writeRaw(bookA, '{"version": 1, "furth');

      await store.save(bookA, const ReaderPosition(1, 0.5));

      expect(await store.load(bookA), const ReaderPosition(1, 0.5));
      expect(jsonDecode(await fileFor(bookA).readAsString()), {
        'version': 1,
        'current': {'sectionIndex': 1, 'progression': 0.5},
      });
    });

    test('are dropped when the file is not a JSON object', () async {
      await writeRaw(bookA, '[1, 2]');

      await store.save(bookA, const ReaderPosition(1, 0.5));

      expect(await store.load(bookA), const ReaderPosition(1, 0.5));
    });
  });

  group('rapid saves', () {
    test('end with the newest position on disk', () async {
      final saves = [
        for (var i = 0; i <= 200; i++)
          store.save(bookA, ReaderPosition(i ~/ 50, (i % 50) / 50)),
      ];
      await Future.wait(saves);

      expect(await store.load(bookA), const ReaderPosition(4, 0));
    });

    test(
      'complete only once their position or a newer one is on disk',
      () async {
        final seen = <ReaderPosition?>[];
        final saves = [
          for (var i = 0; i < 20; i++)
            store.save(bookA, ReaderPosition(0, i / 20)).then((_) async {
              seen.add(await store.load(bookA));
            }),
        ];
        await Future.wait(saves);

        for (var i = 0; i < 20; i++) {
          expect(seen[i], isNotNull);
          expect(seen[i]!.progression, greaterThanOrEqualTo(i / 20));
        }
      },
    );

    test('are all written when they are for different books', () async {
      await Future.wait([
        for (var i = 0; i < 10; i++) ...[
          store.save(bookA, ReaderPosition(i, 0.5)),
          store.save(bookB, ReaderPosition(0, i / 10)),
        ],
      ]);

      expect(await store.load(bookA), const ReaderPosition(9, 0.5));
      expect(await store.load(bookB), const ReaderPosition(0, 0.9));
    });

    test('leave no temporary file behind', () async {
      await Future.wait([
        for (var i = 0; i < 20; i++)
          store.save(bookA, ReaderPosition(0, i / 20)),
      ]);
      await store.saved;

      final names = fileFor(bookA).parent.listSync().map((e) => e.path);
      expect(names.where((path) => path.endsWith('.tmp')), isEmpty);
    });

    test('are written once `saved` completes', () async {
      for (var i = 0; i < 10; i++) {
        store.save(bookA, ReaderPosition(0, i / 10)).ignore();
      }
      await store.saved;

      expect(await store.load(bookA), const ReaderPosition(0, 0.9));
    });
  });

  group('a failed write', () {
    late ReadingPositionStore broken;

    setUp(() async {
      // The root is a file, so nothing can be created under it.
      final file = File('${temp.path}/not_a_directory');
      await file.writeAsString('');
      broken = ReadingPositionStore(Directory(file.path));
    });

    test('throws to its caller', () async {
      await expectLater(
        broken.save(bookA, const ReaderPosition(1, 0.5)),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('does not block later saves', () async {
      final failed = broken.save(bookA, const ReaderPosition(1, 0.5));
      final worked = store.save(bookA, const ReaderPosition(2, 0.5));

      await expectLater(failed, throwsA(isA<FileSystemException>()));
      await worked;
      await expectLater(
        broken.save(bookB, const ReaderPosition(1, 0.5)),
        throwsA(isA<FileSystemException>()),
      );
      expect(await store.load(bookA), const ReaderPosition(2, 0.5));
    });

    test('lets a later save on the same store succeed', () async {
      // A directory in the way makes the final rename fail.
      await Directory(fileFor(bookA).path).create(recursive: true);
      await expectLater(
        store.save(bookA, const ReaderPosition(1, 0.5)),
        throwsA(isA<FileSystemException>()),
      );
      await Directory(fileFor(bookA).path).delete();

      await store.save(bookA, const ReaderPosition(3, 0.5));

      expect(await store.load(bookA), const ReaderPosition(3, 0.5));
    });

    test('does not make `saved` fail', () async {
      broken.save(bookA, const ReaderPosition(1, 0.5)).ignore();

      await broken.saved;
    });
  });

  group('an invalid book id', () {
    for (final id in [
      '',
      '..',
      '.',
      '../escape',
      'a/b',
      r'a\b',
      'a..b/c',
      'name.json',
      '/etc/passwd',
    ]) {
      test('"$id" is rejected', () async {
        await expectLater(
          store.save(id, const ReaderPosition(0, 0)),
          throwsArgumentError,
        );
        await expectLater(store.load(id), throwsArgumentError);
        expect(await temp.list(recursive: true).toList(), isEmpty);
      });
    }

    test('does not stop a valid save', () async {
      await expectLater(
        store.save('../escape', const ReaderPosition(0, 0)),
        throwsArgumentError,
      );

      await store.save(bookA, const ReaderPosition(1, 0.5));

      expect(await store.load(bookA), const ReaderPosition(1, 0.5));
    });
  });
}
