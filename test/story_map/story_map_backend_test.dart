import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/page_start.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/reader/reading_position_store.dart';
import 'package:loremark/settings/ai_settings.dart';
import 'package:loremark/story_map/story_map_backend.dart';
import 'package:loremark/story_model/story_snapshot.dart';
import 'package:loremark/story_update/story_api_client.dart';
import 'package:loremark/story_update/story_book.dart';
import 'package:loremark/story_update/story_import.dart';
import 'package:loremark/story_update/story_model_choice.dart';

import '../story_update/golden.dart';

// The path the Update button really takes, from the bundled prompt through to
// the store on disk, with only the provider stood in for.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  final golden = readValidationGolden();
  final chapter1Delta = (golden['first'] as JsonMap)['candidate'];

  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('story_backend_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => temp.path,
        );
  });
  tearDownAll(() => temp.deleteSync(recursive: true));

  test('builds a map and reads it back', () async {
    final epub = File('$goldenDir/story.epub');
    final book = Book(
      id: StoryBook.open(epub.readAsBytesSync()).sha256Hash,
      title: 'Synthetic Story',
      author: null,
      epubPath: epub.path,
      coverPath: null,
      importedAt: DateTime.utc(2026),
    );
    late String sent;
    final backend = DeviceStoryMapBackend(
      post: (url, headers, body) async {
        sent = body;
        return StoryHttpResponse(
          200,
          jsonEncode({
            'status': 'completed',
            'output': [
              {
                'type': 'message',
                'content': [
                  {'type': 'output_text', 'text': jsonEncode(chapter1Delta)},
                ],
              },
            ],
          }),
        );
      },
    );

    expect(await backend.loadModel(book), isNull);
    final status = await backend.inspect(book);
    expect(status.isNewStore, isTrue);

    final outcome = await backend.update(
      book,
      credentials: const AiCredentials(
        provider: AiProvider.deepseek,
        apiKey: 'sk-test',
      ),
      model: StoryModelChoice.deepseekFlash,
      effort: StoryEffort.low,
      checkQuotes: false,
      sectionId: 'section-002',
    );
    expect(outcome.status, 'committed', reason: '${outcome.issues}');
    // The real prompt and schema came out of the app's bundle.
    final body = jsonDecode(sent) as JsonMap;
    expect(
      ((body['input'] as List)[0] as JsonMap)['content'],
      startsWith('You build a cumulative story model'),
    );
    expect(body['reasoning'], {'effort': 'low'});

    final model = (await backend.loadModel(book))!;
    expect(model.sections.single.id, 'section-002');
    expect(model.sections.single.quotesChecked, isFalse);
    expect((await backend.inspect(book)).nextSectionId, 'section-003');

    // The paragraphs its evidence cites can be read back, up to a boundary.
    final evidence = model.allRecords.expand((record) => record.evidence);
    final visible = await backend.paragraphs(book, visibleSections: 1);
    expect(visible.forEvidence(evidence), isNotEmpty);
    final hidden = await backend.paragraphs(book, visibleSections: 0);
    expect(hidden.forEvidence(evidence), isEmpty);

    // Nothing read yet: not even this section counts as finished.
    Future<StoryReadingProgress> progress() =>
        backend.readingProgress(book, model.sections);
    expect((await progress()).finished, 0);
    expect(await backend.reachedSections(book, model.sections), 0);
    final positions = await ReadingPositionStore.open();
    // Partway through it: reached for answering, but not finished for the map.
    await positions.save(book.id, const ReaderPosition(1, 0.5));
    expect((await progress()).finished, 0);
    expect(await backend.reachedSections(book, model.sections), 1);
    // With the page's start known, the map follows it paragraph by paragraph.
    expect((await progress()).hiddenInNext, isNull);
    await positions.savePageStart(
      book.id,
      const PageStart(1, ':root > :nth-child(2) > :nth-child(3)'),
    );
    expect((await progress()).hiddenInNext, isNotNull);
    // A start left over from another file says nothing about this one.
    await positions.savePageStart(
      book.id,
      const PageStart(5, ':root > :nth-child(2) > :nth-child(3)'),
    );
    expect((await progress()).hiddenInNext, isNull);
    // Its last page hasn't been read yet, so turning past it is what counts.
    await positions.save(book.id, const ReaderPosition(1, 1));
    expect((await progress()).finished, 0);
    await positions.save(book.id, const ReaderPosition(2, 0));
    expect((await progress()).finished, 1);

    // That update left a run folder, and exporting takes it and the store.
    final library = '${temp.path}/library/story_models/${book.id}';
    final runs = Directory('$library.runs').listSync().whereType<Directory>();
    final run = runs.single;
    expect(File('${run.path}/response.json').existsSync(), isTrue);
    expect(File('${run.path}/run.json').existsSync(), isTrue);

    String? savedName;
    late Uint8List saved;
    final exporter = DeviceStoryMapBackend(
      saveFile: (name, bytes) async {
        savedName = name;
        saved = bytes;
        return Uri.file('/saved.zip');
      },
    );
    expect(await exporter.exportFiles(book), StoryExportOutcome.saved);
    expect(savedName, startsWith('Synthetic Story Story Map '));
    expect(savedName, endsWith('.zip'));
    final names = [
      for (final file in ZipDecoder().decodeBytes(saved)) file.name,
    ];
    expect(names, contains('store/story_model.json'));
    expect(names.where((name) => name.startsWith('runs/')), isNotEmpty);

    final dialogClosed = DeviceStoryMapBackend(saveFile: (_, _) async => null);
    expect(await dialogClosed.exportFiles(book), StoryExportOutcome.cancelled);

    // Loading it back replaces the map, with no copy left behind.
    final file = File('${temp.path}/picked.zip')..writeAsBytesSync(saved);
    final loader = DeviceStoryMapBackend(pickFile: () async => file.path);
    expect(await loader.pickStoryFile(), file.path);
    final staged = await loader.stageImport(book, file.path);
    expect(staged.viewOnly, isFalse);
    expect(staged.sectionCount, 1);
    await loader.commitImport(book, staged);
    expect((await loader.loadModel(book))!.sections.single.id, 'section-002');
    expect((await loader.inspect(book)).nextSectionId, 'section-003');
    expect(Directory('$library.importing').existsSync(), isFalse);

    // A bad one is refused, and backing out of a good one leaves no trace.
    final notAMap = File('${temp.path}/not_a_map.json')
      ..writeAsStringSync('[]');
    await expectLater(
      loader.stageImport(book, notAMap.path),
      throwsA(isA<StoryImportError>()),
    );
    final again = await loader.stageImport(book, file.path);
    await loader.discardImport(again);
    expect(Directory('$library.importing').existsSync(), isFalse);
    expect((await loader.loadModel(book))!.sections.single.id, 'section-002');
  });

  test('has nothing to export for a book with no files', () async {
    final book = Book(
      id: 'no-files-yet',
      title: 'Empty',
      author: null,
      epubPath: '$goldenDir/story.epub',
      coverPath: null,
      importedAt: DateTime.utc(2026),
    );
    final backend = DeviceStoryMapBackend(
      saveFile: (_, _) async => fail('There is nothing to save'),
    );
    expect(await backend.exportFiles(book), StoryExportOutcome.nothing);
  });
}
