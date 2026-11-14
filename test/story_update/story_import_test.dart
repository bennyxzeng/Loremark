import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/story_update/story_api_client.dart';
import 'package:loremark/story_update/story_archive.dart';
import 'package:loremark/story_update/story_book.dart';
import 'package:loremark/story_update/story_import.dart';
import 'package:loremark/story_update/story_model_choice.dart';
import 'package:loremark/story_update/story_run_folder.dart';
import 'package:loremark/story_update/story_store.dart';
import 'package:loremark/story_update/story_updater.dart';

import 'golden.dart';

const _epub = '$goldenDir/story.epub';

String _responseBody(Object? output) => jsonEncode({
  'status': 'completed',
  'output': [
    {
      'type': 'message',
      'content': [
        {'type': 'output_text', 'text': jsonEncode(output)},
      ],
    },
  ],
});

void main() {
  final golden = readValidationGolden();
  final chapter1Delta = (golden['first'] as JsonMap)['candidate'] as JsonMap;
  final chapter2Delta =
      (golden['cases'] as List).cast<JsonMap>().firstWhere(
            (item) => item['name'] == 'clean',
          )['candidate']
          as JsonMap;
  final prompt = File('assets/story_update/$updatePromptName')
      .readAsStringSync();
  final schemaText = File('assets/story_update/story_delta.schema.json')
      .readAsStringSync();

  late Directory temp;

  /// A book's store, which [build] fills.
  late String sourcePath;

  /// Another device's store for the same book, which files are loaded into.
  late String targetPath;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('story_import_');
    sourcePath = '${temp.path}/source/book';
    targetPath = '${temp.path}/target/book';
    Directory('${temp.path}/source').createSync();
    Directory('${temp.path}/target').createSync();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<StoryUpdateOutcome> update(
    String storePath,
    Object? answer, {
    String? section,
  }) => StoryUpdater.run(
    StoryUpdateRequest(
      epubPath: _epub,
      storePath: storePath,
      runsPath: storyRunsPath(storePath),
      model: StoryModelChoice.deepseekFlash,
      effort: StoryEffort.high,
      checkQuotes: false,
      prompt: prompt,
      schemaText: schemaText,
      sectionId: section,
    ),
    bookId: storePath,
    apiKey: 'sk-test',
    post: (u, h, b) async => StoryHttpResponse(200, _responseBody(answer)),
  );

  Future<void> build(String storePath) async {
    final outcome = await update(
      storePath,
      chapter1Delta,
      section: 'section-002',
    );
    expect(outcome.status, 'committed', reason: '${outcome.issues}');
  }

  Map<String, String> treeOf(String path) {
    final folder = Directory(path);
    if (!folder.existsSync()) return const {};
    return {
      for (final file in folder.listSync(recursive: true).whereType<File>())
        file.path.substring(path.length + 1): sha256OfBytes(
          file.readAsBytesSync(),
        ),
    };
  }

  String fileWith(List<int> bytes, [String name = 'picked.zip']) {
    final file = File('${temp.path}/$name')..writeAsBytesSync(bytes);
    return file.path;
  }

  /// The file names and contents of [storePath]'s folder, under [prefix].
  Map<String, List<int>> entriesOf(String storePath, String prefix) => {
    for (final file in Directory(
      storePath,
    ).listSync(recursive: true).whereType<File>())
      '$prefix${file.path.substring(storePath.length + 1)}': file
          .readAsBytesSync(),
  };

  Uint8List zipOf(Map<String, List<int>> entries) {
    final archive = Archive();
    entries.forEach((name, data) {
      archive.addFile(ArchiveFile.bytes(name, Uint8List.fromList(data)));
    });
    return ZipEncoder().encodeBytes(archive);
  }

  StagedStoryImport stage(
    String filePath, {
    int? maxFileBytes,
    int? maxUnpackedBytes,
  }) => stageStoryImport(
    filePath: filePath,
    epubPath: _epub,
    storePath: targetPath,
    maxFileBytes: maxFileBytes ?? 1 << 30,
    maxUnpackedBytes: maxUnpackedBytes ?? 1 << 30,
  );

  group('exporting', () {
    test('zips the store and the runs', () async {
      await build(sourcePath);
      final archive = ZipDecoder().decodeBytes(buildStoryArchive(sourcePath)!);
      final names = [for (final file in archive) file.name];
      expect(names, contains('store/story_model.json'));
      expect(
        names.where((n) => n.startsWith('store/revisions/')),
        hasLength(1),
      );
      expect(names.where((n) => n.startsWith('store/inputs/')), hasLength(1));
      expect(names.where((n) => n.startsWith('store/provenance/')), isNotEmpty);
      expect(names.where((n) => n.endsWith('/response.json')), hasLength(1));
      expect(names.where((n) => n.endsWith('/run.json')), hasLength(1));
      expect(names.where((n) => n.startsWith('runs/')), isNotEmpty);

      final stored = archive.findFile('store/story_model.json')!;
      expect(
        stored.content,
        File('$sourcePath/story_model.json').readAsBytesSync(),
      );
    });

    test('leaves out unfinished writes', () async {
      await build(sourcePath);
      File('$sourcePath/story_model.json.abc.tmp').writeAsStringSync('partial');
      final archive = ZipDecoder().decodeBytes(buildStoryArchive(sourcePath)!);
      expect(archive.any((file) => file.name.endsWith('.tmp')), isFalse);
    });

    test('works with only a failed first update', () async {
      final runs = storyRunsPath(sourcePath);
      File('$runs/run-1/run.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
      final archive = ZipDecoder().decodeBytes(buildStoryArchive(sourcePath)!);
      expect([for (final file in archive) file.name], ['runs/run-1/run.json']);
    });

    test('has nothing to give for a book with no files', () {
      expect(buildStoryArchive(sourcePath), isNull);
    });

    test('names the file after the book', () {
      expect(
        storyArchiveName('86—EIGHTY-SIX, Vol. 1', DateTime(2026, 3, 9)),
        '86—EIGHTY-SIX, Vol. 1 Story Map 2026-03-09.zip',
      );
      expect(
        storyArchiveName('Who/What: "Why?"', DateTime(2026, 11, 25)),
        'Who-What- -Why-- Story Map 2026-11-25.zip',
      );
      expect(storyArchiveName(' / '.trim(), DateTime(2026)), startsWith('- '));
      expect(storyArchiveName('', DateTime(2026)), startsWith('Book '));
    });
  });

  group('loading an exported zip', () {
    test('gives back the same store and runs, ready to continue', () async {
      await build(sourcePath);
      final staged = stage(fileWith(buildStoryArchive(sourcePath)!));
      expect(staged.viewOnly, isFalse);
      expect(staged.revision, 1);
      expect(staged.sectionCount, 1);
      // Nothing is in place until the reader agrees.
      expect(Directory(targetPath).existsSync(), isFalse);

      commitStoryImport(staged, targetPath);
      expect(treeOf(targetPath), treeOf(sourcePath));
      expect(
        treeOf(storyRunsPath(targetPath)),
        treeOf(storyRunsPath(sourcePath)),
      );
      expect(Directory(staged.path).existsSync(), isFalse);

      final status = inspectStoryUpdate(_epub, targetPath);
      expect(status.isReady, isTrue);
      final outcome = await update(targetPath, chapter2Delta);
      expect(outcome.status, 'committed', reason: '${outcome.issues}');
      expect(
        StoryStore(Directory(targetPath)).load().model['processed_sections'],
        hasLength(2),
      );
    });

    test('replaces a map, keeping the runs already here', () async {
      await build(sourcePath);
      await update(sourcePath, chapter2Delta);
      await build(targetPath);
      final existingRuns = treeOf(storyRunsPath(targetPath));

      commitStoryImport(
        stage(fileWith(buildStoryArchive(sourcePath)!)),
        targetPath,
      );
      expect(treeOf(targetPath), treeOf(sourcePath));
      expect(Directory(replacedStorePath(targetPath)).existsSync(), isFalse);
      expect(
        treeOf(storyRunsPath(targetPath)).keys,
        containsAll(existingRuns.keys),
      );
      expect(
        treeOf(storyRunsPath(targetPath)).keys,
        containsAll(treeOf(storyRunsPath(sourcePath)).keys),
      );
    });

    test('never overwrites a run already here', () async {
      await build(sourcePath);
      final runName = Directory(storyRunsPath(sourcePath))
          .listSync()
          .single
          .uri
          .pathSegments
          .lastWhere((s) => s.isNotEmpty);
      final mine = File('${storyRunsPath(targetPath)}/$runName/run.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('mine');
      commitStoryImport(
        stage(fileWith(buildStoryArchive(sourcePath)!)),
        targetPath,
      );
      expect(mine.readAsStringSync(), 'mine');
    });
  });

  group('loading a store zipped on a computer', () {
    test(
      'finds it in its folder, and ignores what the computer added',
      () async {
        await build(sourcePath);
        final staged = stage(
          fileWith(
            zipOf({
              ...entriesOf(sourcePath, '86v1/'),
              '86v1/.lock': const [],
              '86v1/.DS_Store': const [1, 2, 3],
              '86v1/provenance/.DS_Store': const [1, 2, 3],
              '__MACOSX/86v1/._story_model.json': const [1, 2, 3],
            }),
          ),
        );
        expect(staged.viewOnly, isFalse);
        commitStoryImport(staged, targetPath);
        expect(treeOf(targetPath), treeOf(sourcePath));
        expect(File('$targetPath/.lock').existsSync(), isFalse);
        expect(inspectStoryUpdate(_epub, targetPath).isReady, isTrue);
      },
    );

    test('finds it at the top of the zip', () async {
      await build(sourcePath);
      final staged = stage(fileWith(zipOf(entriesOf(sourcePath, ''))));
      commitStoryImport(staged, targetPath);
      expect(treeOf(targetPath), treeOf(sourcePath));
    });
  });

  group('loading only a story_model.json', () {
    test('can be viewed but not updated', () async {
      await build(sourcePath);
      final staged = stage(File('$sourcePath/story_model.json').path);
      expect(staged.viewOnly, isTrue);
      expect(staged.sectionCount, 1);
      commitStoryImport(staged, targetPath);

      expect(readStoryModel(targetPath), isNotNull);
      final status = inspectStoryUpdate(_epub, targetPath);
      expect(status.blocked, storyViewOnlyReason);
      expect(status.canChoose, isFalse);
      expect(status.isReady, isFalse);

      final outcome = await update(targetPath, chapter2Delta);
      expect(outcome.committed, isFalse);
    });

    test('in a zip of its own, too', () async {
      await build(sourcePath);
      final staged = stage(
        fileWith(
          zipOf({
            'story_model.json': File('$sourcePath/story_model.json')
                .readAsBytesSync(),
          }),
        ),
      );
      expect(staged.viewOnly, isTrue);
    });

    test('can be replaced with the full zip, to update again', () async {
      await build(sourcePath);
      commitStoryImport(stage('$sourcePath/story_model.json'), targetPath);
      commitStoryImport(
        stage(fileWith(buildStoryArchive(sourcePath)!)),
        targetPath,
      );
      expect(inspectStoryUpdate(_epub, targetPath).isReady, isTrue);
    });

    test('must hold true of this book’s text', () async {
      await build(sourcePath);
      final model = jsonDecode(
        File('$sourcePath/story_model.json').readAsStringSync(),
      ) as JsonMap;
      final names = (model['records'] as JsonMap)['names'] as List;
      final evidence = (names[0] as JsonMap)['evidence'] as List;
      (evidence[0] as JsonMap)['paragraph_id'] = 'p99999';
      expect(
        () => stage(fileWith(utf8.encode(jsonEncode(model)), 'edited.json')),
        throwsA(
          isA<StoryImportError>().having(
            (error) => error.message,
            'message',
            contains('failed 1 check'),
          ),
        ),
      );
    });
  });

  group('refusing a file', () {
    late Map<String, String> before;
    late Map<String, List<int>> good;

    setUp(() async {
      await build(sourcePath);
      await build(targetPath);
      before = treeOf(targetPath);
      good = entriesOf(sourcePath, 'store/');
    });

    void expectRefused(String path, String message) {
      expect(
        () => stage(path),
        throwsA(
          isA<StoryImportError>().having(
            (error) => error.message,
            'message',
            contains(message),
          ),
        ),
      );
      expect(treeOf(targetPath), before, reason: 'The map here stays');
      expect(Directory('$targetPath.importing').existsSync(), isFalse);
    }

    test('for another EPUB', () {
      final model = jsonDecode(
        File('$sourcePath/story_model.json').readAsStringSync(),
      ) as JsonMap;
      (model['book'] as JsonMap)['epub_sha256'] = '0' * 64;
      expectRefused(
        fileWith(utf8.encode(jsonEncode(model)), 'other.json'),
        'different EPUB',
      );
    });

    test('that isn’t JSON', () {
      expectRefused(
        fileWith(utf8.encode('Not JSON'), 'a.json'),
        'isn’t a Story',
      );
    });

    test('that is some other JSON', () {
      expectRefused(fileWith(utf8.encode('[1, 2]'), 'a.json'), 'isn’t a Story');
      expectRefused(
        fileWith(utf8.encode('{"a": 1}'), 'b.json'),
        'isn’t a Story',
      );
    });

    test('that isn’t a model this version reads', () {
      final model = jsonDecode(
        File('$sourcePath/story_model.json').readAsStringSync(),
      ) as JsonMap;
      model['schema_version'] = '9.0';
      expectRefused(
        fileWith(utf8.encode(jsonEncode(model)), 'future.json'),
        'can’t read',
      );
    });

    test('that has no model in it', () {
      expectRefused(
        fileWith(
          zipOf({
            'a/b.txt': const [1],
          }),
        ),
        'isn’t a Story',
      );
    });

    test('that holds two maps', () {
      expectRefused(
        fileWith(
          zipOf({
            'one/story_model.json': const [1],
            'two/story_model.json': const [1],
          }),
        ),
        'more than one',
      );
    });

    test('that is a broken zip', () {
      final bytes = zipOf(good);
      expectRefused(
        fileWith(bytes.sublist(0, bytes.length ~/ 2)),
        'isn’t a Story',
      );
    });

    test('whose store was changed', () {
      final latest = (good['store/story_model.json']!).toList();
      expectRefused(
        fileWith(
          zipOf({
            ...good,
            'store/story_model.json': [...latest, 0x20],
          }),
        ),
        'damaged',
      );
    });

    test('whose saved text was changed', () {
      final input = good.keys.firstWhere((n) => n.contains('/inputs/'));
      expectRefused(
        fileWith(zipOf({...good, input: utf8.encode('{"changed": true}')})),
        'damaged',
      );
    });

    test('that is missing a revision', () {
      expectRefused(
        fileWith(
          zipOf(Map.of(good)..removeWhere((n, _) => n.contains('/revisions/'))),
        ),
        'damaged',
      );
    });

    for (final name in const [
      '../outside.txt',
      'store/../../outside.txt',
      '/outside.txt',
      r'store\..\outside.txt',
      'store//outside.txt',
    ]) {
      test('with a file outside its folder: $name', () {
        expectRefused(
          fileWith(zipOf({...good, name: utf8.encode('Escaped')})),
          'won’t unpack',
        );
        expect(File('${temp.path}/target/outside.txt').existsSync(), isFalse);
        expect(File('${temp.path}/outside.txt').existsSync(), isFalse);
      });
    }

    test('with a symbolic link', () {
      final archive = Archive();
      good.forEach((name, data) {
        archive.addFile(ArchiveFile.bytes(name, Uint8List.fromList(data)));
      });
      // The encoder can't write a link as such, but a link is only a file marked
      // as one, whose content is where it points.
      archive.addFile(
        ArchiveFile.bytes('store/link', utf8.encode('/etc/passwd'))
          ..mode = 0xA1FF,
      );
      final bytes = ZipEncoder().encodeBytes(archive);
      // And links only count from a Unix system, as each central entry records.
      for (var i = 0; i + 5 < bytes.length; i++) {
        if (bytes[i] == 0x50 &&
            bytes[i + 1] == 0x4b &&
            bytes[i + 2] == 0x01 &&
            bytes[i + 3] == 0x02) {
          bytes[i + 5] = 3;
        }
      }
      expect(
        ZipDecoder().decodeBytes(bytes).findFile('store/link')!.isSymbolicLink,
        isTrue,
        reason: 'This test needs a real link',
      );
      expectRefused(fileWith(bytes), 'won’t unpack');
    });

    test('that is too large', () {
      final path = fileWith(zipOf(good));
      expect(
        () => stage(path, maxFileBytes: 10),
        throwsA(isA<StoryImportError>()),
      );
      expect(treeOf(targetPath), before);
    });

    test('that unpacks too large', () {
      final path = fileWith(zipOf({...good, 'store/big': Uint8List(1 << 20)}));
      expect(File(path).lengthSync(), lessThan(1 << 20));
      expect(
        () => stage(path, maxUnpackedBytes: 1 << 20),
        throwsA(
          isA<StoryImportError>().having(
            (error) => error.message,
            'message',
            contains('too large'),
          ),
        ),
      );
      expect(treeOf(targetPath), before);
    });

    test('that can’t be found', () {
      expectRefused('${temp.path}/missing.zip', 'Couldn’t read');
    });
  });

  test('backing out leaves the map as it was', () async {
    await build(sourcePath);
    await build(targetPath);
    final before = treeOf(targetPath);
    final staged = stage(fileWith(buildStoryArchive(sourcePath)!));
    discardStoryImport(staged);
    expect(treeOf(targetPath), before);
    expect(Directory(staged.path).existsSync(), isFalse);
  });

  group('stopping partway through replacing a map', () {
    test('before the new map is in place, brings the old one back', () async {
      await build(targetPath);
      final before = treeOf(targetPath);
      Directory(targetPath).renameSync(replacedStorePath(targetPath));
      expect(readStoryModel(targetPath), isNotNull);
      expect(treeOf(targetPath), before);
      expect(Directory(replacedStorePath(targetPath)).existsSync(), isFalse);
    });

    test('after the new map is in place, clears the old one', () async {
      await build(targetPath);
      final before = treeOf(targetPath);
      File('${replacedStorePath(targetPath)}/story_model.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
      expect(readStoryModel(targetPath), isNotNull);
      expect(treeOf(targetPath), before);
      expect(Directory(replacedStorePath(targetPath)).existsSync(), isFalse);
    });
  });
}
