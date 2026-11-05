import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../library/book.dart';
import '../reader/epub_sections.dart';
import '../reader/reader_position.dart';
import '../reader/reading_position_store.dart';
import '../search/search_cutoff.dart';
import '../settings/ai_settings.dart';
import '../story_model/story_model.dart';
import '../story_update/story_api_client.dart';
import '../story_update/story_archive.dart';
import '../story_update/story_import.dart';
import '../story_update/story_model_choice.dart';
import '../story_update/story_run_folder.dart';
import '../story_update/story_updater.dart';

/// How many of [sections], counted from the first, the reader has finished at
/// [current]. A section counts only once its whole document is finished, since
/// the Story Map shows what is known by the end of a section. Without a position
/// it is none.
int finishedStorySections(
  List<StorySection> sections,
  List<SpineItem> spine,
  ReaderPosition? current,
) {
  if (current == null) return 0;
  // Takes a furthest position too, for when the reader's is kept.
  final cutoff = completedSectionCutoff(current: current);
  final finishedItems = cutoff.progression == 1
      ? cutoff.sectionIndex + 1
      : cutoff.sectionIndex;
  var count = 0;
  for (final section in sections) {
    final index = spineIndexOf(spine, section.href ?? '');
    if (index == null || index >= finishedItems) break;
    count++;
  }
  return count;
}

/// How exporting a book's Story Map files ended.
enum StoryExportOutcome { saved, cancelled, nothing }

/// Saves a file where the reader chooses; null if they back out.
typedef StoryFileSaver = Future<Uri?> Function(String name, Uint8List bytes);

/// Asks the reader for a file; null if they back out.
typedef StoryFilePicker = Future<String?> Function();

Future<Uri?> _saveWithDialog(String name, Uint8List bytes) =>
    FilePicker.saveFile(
      fileName: name,
      bytes: bytes,
      mimeType: 'application/zip',
    );

Future<String?> _pickWithDialog() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['zip', 'json'],
  );
  return file?.path;
}

/// What the Story Map tab needs from the device and the network, so tests can
/// stand in for them.
abstract interface class StoryMapBackend {
  /// The book's story model, or null if none has been built yet.
  Future<StoryModel?> loadModel(Book book);

  /// How many of [sections] the reader has finished.
  Future<int> finishedSections(Book book, List<StorySection> sections);

  /// What pressing Update would do.
  Future<StoryUpdateStatus> inspect(Book book);

  /// The update already running for [book], if any.
  RunningStoryUpdate? running(Book book);

  /// Adds the section called [sectionId], or the next one. Never throws for a
  /// failed update: see the outcome.
  Future<StoryUpdateOutcome> update(
    Book book, {
    required AiCredentials credentials,
    required StoryModelChoice model,
    required StoryEffort effort,
    required bool checkQuotes,
    String? sectionId,
  });

  /// Saves everything kept about [book]'s Story Map where the reader chooses.
  Future<StoryExportOutcome> exportFiles(Book book);

  /// Asks the reader for a file to load a Story Map from.
  Future<String?> pickStoryFile();

  /// Unpacks and checks the file at [path], leaving the map as it is. Throws a
  /// [StoryImportError] if it can't be [book]'s Story Map.
  Future<StagedStoryImport> stageImport(Book book, String path);

  /// Makes [staged] the Story Map of [book].
  Future<void> commitImport(Book book, StagedStoryImport staged);

  /// Throws [staged] away.
  Future<void> discardImport(StagedStoryImport staged);
}

/// The real thing: the store on disk, the reader's saved position, the provider.
class DeviceStoryMapBackend implements StoryMapBackend {
  DeviceStoryMapBackend({
    this.post = postStoryRequest,
    this.saveFile = _saveWithDialog,
    this.pickFile = _pickWithDialog,
  });

  /// How requests reach the provider; tests replace the network call.
  final StoryHttpPost post;

  /// The system's dialogs for files; tests replace them.
  final StoryFileSaver saveFile;
  final StoryFilePicker pickFile;
  final _spines = <String, Future<List<SpineItem>>>{};

  Future<String> _storePath(Book book) async {
    final support = await getApplicationSupportDirectory();
    return storyStorePath('${support.path}/library', book.id);
  }

  @override
  Future<StoryModel?> loadModel(Book book) async {
    final path = await _storePath(book);
    final json = await Isolate.run(() => readStoryModel(path));
    return json == null ? null : StoryModel.fromJson(json);
  }

  @override
  Future<int> finishedSections(Book book, List<StorySection> sections) async {
    final store = await ReadingPositionStore.open();
    await store.saved;
    final position = await store.load(book.id);
    final spine = await (_spines[book.id] ??= readSpine(book.epubPath));
    return finishedStorySections(sections, spine, position);
  }

  @override
  Future<StoryUpdateStatus> inspect(Book book) async {
    final path = await _storePath(book);
    final epub = book.epubPath;
    return Isolate.run(() => inspectStoryUpdate(epub, path));
  }

  @override
  RunningStoryUpdate? running(Book book) => StoryUpdater.running(book.id);

  @override
  Future<StoryUpdateOutcome> update(
    Book book, {
    required AiCredentials credentials,
    required StoryModelChoice model,
    required StoryEffort effort,
    required bool checkQuotes,
    String? sectionId,
  }) async {
    final storePath = await _storePath(book);
    return StoryUpdater.run(
      StoryUpdateRequest(
        epubPath: book.epubPath,
        storePath: storePath,
        runsPath: storyRunsPath(storePath),
        model: model,
        effort: effort,
        checkQuotes: checkQuotes,
        prompt: await rootBundle.loadString(
          'assets/story_update/$updatePromptName',
        ),
        schemaText: await rootBundle.loadString(
          'assets/story_update/story_delta.schema.json',
        ),
        sectionId: sectionId,
      ),
      bookId: book.id,
      apiKey: credentials.apiKey,
      post: post,
    );
  }

  @override
  Future<StoryExportOutcome> exportFiles(Book book) async {
    final path = await _storePath(book);
    final bytes = await Isolate.run(() => buildStoryArchive(path));
    if (bytes == null) return StoryExportOutcome.nothing;
    final saved = await saveFile(
      storyArchiveName(book.title, DateTime.now()),
      bytes,
    );
    return saved == null
        ? StoryExportOutcome.cancelled
        : StoryExportOutcome.saved;
  }

  @override
  Future<String?> pickStoryFile() => pickFile();

  @override
  Future<StagedStoryImport> stageImport(Book book, String path) async {
    final storePath = await _storePath(book);
    final epubPath = book.epubPath;
    return Isolate.run(
      () => stageStoryImport(
        filePath: path,
        epubPath: epubPath,
        storePath: storePath,
      ),
    );
  }

  @override
  Future<void> commitImport(Book book, StagedStoryImport staged) async {
    if (StoryUpdater.running(book.id) != null) {
      throw const StoryImportError('An update is running. Try again after it.');
    }
    final storePath = await _storePath(book);
    await Isolate.run(() => commitStoryImport(staged, storePath));
  }

  @override
  Future<void> discardImport(StagedStoryImport staged) =>
      Isolate.run(() => discardStoryImport(staged));
}
