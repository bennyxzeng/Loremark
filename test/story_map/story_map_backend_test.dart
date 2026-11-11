import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' hide TextPosition;
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/ask/ask_boundary.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/epub_sections.dart';
import 'package:loremark/reader/page_end.dart';
import 'package:loremark/reader/page_start.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/reader/reading_position_store.dart';
import 'package:loremark/reading/text_position.dart';
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
    final visible = await backend.paragraphs(
      book,
      const StoryReadingProgress(1),
    );
    expect(visible.forEvidence(evidence), isNotEmpty);
    final hidden = await backend.paragraphs(
      book,
      const StoryReadingProgress(0),
    );
    expect(hidden.forEvidence(evidence), isEmpty);

    // Nothing read yet: not even this section counts as finished.
    Future<StoryReadingProgress> progress() =>
        backend.readingProgress(book, model.sections);
    expect((await progress()).finished, 0);
    final positions = await ReadingPositionStore.open();
    // Partway through it, with no page start: nothing of it can be used.
    await positions.save(book.id, const ReaderPosition(1, 0.5));
    expect((await progress()).finished, 0);
    expect(
      (await backend.paragraphs(
        book,
        await progress(),
      )).ofSection('section-002'),
      isEmpty,
    );
    // With the page's start known, the map follows it paragraph by paragraph.
    expect((await progress()).hiddenInNext, isNull);
    await positions.savePageStart(
      book.id,
      const PageStart(1, ':root > :nth-child(2) > :nth-child(3)'),
    );
    expect((await progress()).hiddenInNext, isNotNull);
    // And what can be answered from stops at the same paragraph.
    expect((await progress()).paragraphsReadInNext, greaterThan(0));
    expect(
      (await backend.paragraphs(
        book,
        await progress(),
      )).ofSection('section-002'),
      hasLength((await progress()).paragraphsReadInNext),
    );
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

    // Ask goes to the end of the page, where the map stops at its start.
    Future<AskReach> reach() => backend.askReach(book, model.sections);
    await positions.save(book.id, const ReaderPosition(1, 0.5));
    await positions.savePageStart(
      book.id,
      const PageStart(1, ':root > :nth-child(2) > :nth-child(3)'),
    );
    // Without the page's end, it goes by the start, with no page to show.
    var ask = await reach();
    expect(
      ask.progress.paragraphsReadInNext,
      (await progress()).paragraphsReadInNext,
    );
    expect(ask.page, isNull);
    expect(ask.limit, const TextPosition(1, 0));
    // The page ends five characters into "No one in Greyford knew...", the
    // sixth block: the five before it are all on the page.
    final chapter1 = (await readSectionMarkup(epub.path, 'OEBPS/ch1.xhtml'))!;
    final end = textProgressionOfBlock(chapter1, 5, characters: 5)!;
    await positions.savePageEnd(book.id, PageEnd(1, 5, end));
    ask = await reach();
    expect(ask.progress.paragraphsReadInNext, 5);
    expect(
      (await backend.paragraphs(book, ask.progress)).ofSection('section-002'),
      hasLength(5),
    );
    expect(ask.page!.text, startsWith('CHAPTER 1 THE SIGNAL'));
    expect(ask.page!.text, endsWith('No one'));
    expect(ask.limit, TextPosition(1, end));
    expect(ask.pastMap, isFalse);
    // An answer's recent pages come back from its limit, line for line as
    // they were sent, and each line can be found in the book.
    final recent = (await backend.recentPages(book, ask.limit))!;
    expect([for (final line in recent.lines) line.text], ask.page!.lines);
    expect(recent.sectionIndex, 1);
    final first = recent.target(1);
    expect(first.sectionIndex, 1);
    expect(recent.lines.first.text, startsWith(first.highlight));
    expect(recent.target(recent.lines.length).highlight, 'No one');
    expect(await backend.recentPages(book, const TextPosition(1, 0)), isNull);
    // An end kept from another file says nothing about this page.
    await positions.savePageEnd(book.id, const PageEnd(2, 1, 0.5));
    expect((await reach()).page, isNull);
    // On a file's last page all of it is read, for Ask, not yet for the map.
    await positions.save(book.id, const ReaderPosition(1, 1));
    ask = await reach();
    expect(ask.progress.finished, 1);
    expect(ask.page!.text, endsWith('hunt down the Grey Fox.'));
    expect((await progress()).finished, 0);
    // Further on, the reader is somewhere the map doesn't cover yet.
    await positions.save(book.id, const ReaderPosition(2, 0.3));
    ask = await reach();
    expect(ask.pastMap, isTrue);
    expect(ask.page!.text, startsWith('CHAPTER 2 THE STORM'));

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

  test('remembers that the intro was closed', () async {
    expect(await DeviceStoryMapBackend().introSeen(), isFalse);
    await DeviceStoryMapBackend().markIntroSeen();
    expect(await DeviceStoryMapBackend().introSeen(), isTrue);
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
