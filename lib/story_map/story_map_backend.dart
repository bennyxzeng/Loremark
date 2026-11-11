import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
// Its TextPosition is a caret's; this file means a reader's.
import 'package:flutter/services.dart' hide TextPosition;
import 'package:path_provider/path_provider.dart';

import '../ask/ask_backend.dart';
import '../ask/ask_boundary.dart';
import '../library/book.dart';
import '../reader/epub_reader_service.dart';
import '../reader/epub_sections.dart';
import '../reader/reader_position.dart';
import '../reader/reading_position_store.dart';
import '../reading/text_position.dart';
import '../search/search_cutoff.dart';
import '../settings/ai_settings.dart';
import '../story_model/story_model.dart';
import '../story_model/story_snapshot.dart';
import '../story_update/story_api_client.dart';
import '../story_update/story_archive.dart';
import '../story_update/story_import.dart';
import '../story_update/story_model_choice.dart';
import '../story_update/story_paragraphs.dart';
import '../story_update/story_run_folder.dart';
import '../story_update/story_updater.dart';

/// How many of [sections], counted from the first, the reader has finished at
/// [current]. A section counts only once the reader has turned past the end of
/// its whole document, since a page just turned to hasn't been read yet. The last
/// page of the book has nothing to turn to, so reaching it is enough. Without a
/// position it is none.
///
/// With [wholePage], as Ask counts, the page being read counts as read too, so
/// reaching a document's last page finishes it.
int finishedStorySections(
  List<StorySection> sections,
  List<SpineItem> spine,
  ReaderPosition? current, {
  bool wholePage = false,
}) {
  if (current == null) return 0;
  final onLastPage =
      current.progression == 1 &&
      (wholePage ||
          current.sectionIndex == spine.lastIndexWhere((item) => item.linear));
  // Takes a furthest position too, for when the reader's is kept.
  final cutoff = completedSectionCutoff(
    current: onLastPage ? current : ReaderPosition(current.sectionIndex, 0),
  );
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

/// Whether the spine item at [sectionIndex] comes after the last of
/// [sections], all of which the reader has finished at [progress], so updating
/// the map would reach it.
///
/// A stretch between two of [sections] doesn't count: whatever is there has no
/// text, or was skipped when a later section was added, and sections only go in
/// in reading order, so it can never be added.
bool pastStoryMapEnd(
  List<StorySection> sections,
  List<SpineItem> spine,
  StoryReadingProgress progress,
  int sectionIndex,
) {
  if (sections.isEmpty || progress.finished < sections.length) return false;
  final last = spineIndexOf(spine, sections.last.href ?? '');
  return last != null && sectionIndex > last;
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

  /// How far the reader has got through [sections], down to the paragraph in the
  /// section they are partway through, up to the start of their page. The map
  /// goes by this; Ask takes the rest of the page too (`AskBackend.askReach`).
  Future<StoryReadingProgress> readingProgress(
    Book book,
    List<StorySection> sections,
  );

  /// The paragraphs of [book]'s Story Map that a reader at [progress] has read.
  /// Nothing past them is kept. Throws a `StoryStoreError` or a
  /// `StoryEpubError` if a section's text can't be read.
  Future<StoryParagraphs> paragraphs(Book book, StoryReadingProgress progress);

  /// What pressing Update would do.
  Future<StoryUpdateStatus> inspect(Book book);

  /// The update already running for [book], if any.
  RunningStoryUpdate? running(Book book);

  /// Stops the update running for [book], if it is still waiting for the
  /// provider. Its outcome is then `cancelled`: see [StoryUpdater.cancel].
  void cancelUpdate(Book book);

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

  /// Whether the reader has closed the Story Map intro, in any book.
  Future<bool> introSeen();

  /// Remembers that the reader closed the intro, so it doesn't show again.
  Future<void> markIntroSeen();
}

/// The real thing: the store on disk, the reader's saved position, the provider.
class DeviceStoryMapBackend implements StoryMapBackend, AskBackend {
  DeviceStoryMapBackend({
    this.post,
    this.saveFile = _saveWithDialog,
    this.pickFile = _pickWithDialog,
  });

  /// How requests reach the provider; tests replace the network call. Null for
  /// the network, whose connection cancelling an update drops.
  final StoryHttpPost? post;

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

  /// The reader's saved position in [book], and the book's spine.
  Future<(ReaderPosition?, List<SpineItem>)> _readingPlace(Book book) async {
    final store = await ReadingPositionStore.open();
    await store.saved;
    final position = await store.load(book.id);
    final spine = await (_spines[book.id] ??= readSpine(book.epubPath));
    return (position, spine);
  }

  @override
  Future<StoryReadingProgress> readingProgress(
    Book book,
    List<StorySection> sections,
  ) async {
    final (position, spine) = await _readingPlace(book);
    final finished = finishedStorySections(sections, spine, position);
    final store = await ReadingPositionStore.open();
    final start = await store.loadPageStart(book.id);
    if (start == null || start.sectionIndex != position?.sectionIndex) {
      return StoryReadingProgress(finished);
    }
    final onPage = _sectionsIn(sections, spine, finished, start.sectionIndex);
    if (onPage.isEmpty) return StoryReadingProgress(finished);
    final path = await _storePath(book);
    final epub = book.epubPath;
    final selector = start.cssSelector;
    return Isolate.run(
      () => readStoryProgress(
        path,
        epub,
        finished: finished,
        sectionsOnPage: onPage,
        cssSelector: selector,
      ),
    );
  }

  /// The ids of [sections], from the [finished]th on, whose document is the
  /// spine item at [sectionIndex].
  List<String> _sectionsIn(
    List<StorySection> sections,
    List<SpineItem> spine,
    int finished,
    int sectionIndex,
  ) => [
    for (final section
        in sections
            .skip(finished)
            .takeWhile(
              (section) =>
                  spineIndexOf(spine, section.href ?? '') == sectionIndex,
            ))
      section.id,
  ];

  @override
  Future<AskReach> askReach(Book book, List<StorySection> sections) async {
    final (position, spine) = await _readingPlace(book);
    if (position == null) return AskReach.none;
    final store = await ReadingPositionStore.open();
    final onLastPage = position.progression == 1;
    final saved = onLastPage ? null : await store.loadPageEnd(book.id);
    // A page end kept from another section says nothing about this page.
    final end = saved?.sectionIndex == position.sectionIndex ? saved : null;
    final through = onLastPage
        ? TextPosition(position.sectionIndex, 1)
        : end == null
        ? null
        : TextPosition(end.sectionIndex, end.textProgression);

    var progress = const StoryReadingProgress(0);
    if (sections.isNotEmpty) {
      final finished = finishedStorySections(
        sections,
        spine,
        position,
        wholePage: true,
      );
      if (onLastPage) {
        progress = StoryReadingProgress(finished);
      } else if (end == null) {
        // Unmeasured: where the page starts, as the map goes.
        progress = await readingProgress(book, sections);
      } else {
        final onPage = _sectionsIn(sections, spine, finished, end.sectionIndex);
        final path = await _storePath(book);
        final epub = book.epubPath;
        final block = end.block;
        progress = onPage.isEmpty
            ? StoryReadingProgress(finished)
            : await Isolate.run(
                () => readStoryProgressToPageEnd(
                  path,
                  epub,
                  finished: finished,
                  sectionsOnPage: onPage,
                  endBlock: block,
                ),
              );
      }
    }

    AskPage? page;
    if (through != null && through.sectionIndex < spine.length) {
      final xhtml = await readSectionMarkup(
        book.epubPath,
        spine[through.sectionIndex].path,
      );
      final progression = through.progression;
      final text = xhtml == null
          ? null
          : await Isolate.run(() => textBeforePageEnd(xhtml, progression));
      if (text != null && text.isNotEmpty) page = AskPage(text, through);
    }

    return AskReach(
      progress: progress,
      // Unmeasured, only the section is sure.
      limit: through ?? TextPosition(position.sectionIndex, 0),
      page: page,
      pastMap: pastStoryMapEnd(
        sections,
        spine,
        progress,
        position.sectionIndex,
      ),
    );
  }

  @override
  Future<PassageTarget?> passageTarget(
    Book book,
    StorySection section,
    StoryParagraph paragraph,
  ) async {
    final spine = await (_spines[book.id] ??= readSpine(book.epubPath));
    final index = spineIndexOf(spine, section.href ?? '');
    if (index == null) return null;
    final xhtml = await readSectionMarkup(book.epubPath, spine[index].path);
    if (xhtml == null) return null;
    final text = paragraph.text;
    return Isolate.run(
      () => storyPassageTarget(index, sectionPlainText(xhtml), text),
    );
  }

  @override
  Future<RecentPages?> recentPages(Book book, TextPosition end) async {
    // A page end that wasn't measured sent no page.
    if (end.progression <= 0) return null;
    final spine = await (_spines[book.id] ??= readSpine(book.epubPath));
    if (end.sectionIndex >= spine.length) return null;
    final xhtml = await readSectionMarkup(
      book.epubPath,
      spine[end.sectionIndex].path,
    );
    if (xhtml == null) return null;
    final progression = end.progression;
    final page = await Isolate.run(() => pageTextBefore(xhtml, progression));
    if (page == null || page.lines.isEmpty) return null;
    return RecentPages(end.sectionIndex, page);
  }

  @override
  Future<StoryParagraphs> paragraphs(
    Book book,
    StoryReadingProgress progress,
  ) async {
    final path = await _storePath(book);
    final epub = book.epubPath;
    return Isolate.run(() => readStoryParagraphs(path, epub, progress));
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
  void cancelUpdate(Book book) => StoryUpdater.cancel(book.id);

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

  /// An empty file whose presence means the intro was closed.
  Future<File> _introSeenFile() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/story_map_intro_seen');
  }

  @override
  Future<bool> introSeen() async => (await _introSeenFile()).exists();

  @override
  Future<void> markIntroSeen() async {
    await (await _introSeenFile()).create(recursive: true);
  }
}
