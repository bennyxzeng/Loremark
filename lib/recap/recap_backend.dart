import '../library/book.dart';
import '../reader/epub_sections.dart';
import '../settings/ai_settings.dart';
import '../story_map/story_map_backend.dart';
import '../story_update/story_api_client.dart';
import 'recap_client.dart';
import 'recap_source.dart';

/// Whether a recap could be written for a book now, and if so from what.
sealed class RecapStart {
  const RecapStart();
}

/// The book has no Story Map. Recaps are built from it, so there is nothing to
/// recap from until one is built.
class RecapNeedsStoryMap extends RecapStart {
  const RecapNeedsStoryMap();
}

/// The reader hasn't read anything the Story Map covers yet.
class RecapNeedsReading extends RecapStart {
  const RecapNeedsReading();
}

/// A recap can be written from [source].
class RecapCanStart extends RecapStart {
  const RecapCanStart(this.source);

  final RecapSource source;
}

/// What the opening recap needs from the device and the network, so tests
/// can stand in for them.
abstract interface class RecapBackend {
  /// Where the reader is in [book], and what a recap of it may use.
  ///
  /// Throws if the Story Map's text of what they read can't be had: a recap is
  /// never built from part of it.
  Future<RecapStart> prepare(Book book);

  /// Asks the provider for a recap of [source]. Never throws: a failure is a
  /// [RecapFailed].
  Future<RecapResult> recap(RecapSource source, AiCredentials credentials);
}

/// The real thing: the book's Story Map and reading progress, its spine, and
/// the reader's provider.
class DeviceRecapBackend implements RecapBackend {
  DeviceRecapBackend({
    required this.storyMap,
    this.readSpineOf = readSpine,
    this.post = postRecapRequest,
  });

  /// The book's Story Map and how far the reader has got through it. The
  /// recap stops where the map does, so it is the one the Story Map tab uses.
  final StoryMapBackend storyMap;

  /// Reads a book's spine, to open the book at a passage; tests replace it.
  final Future<List<SpineItem>> Function(String epubPath) readSpineOf;

  /// How requests reach the provider; tests replace the network call.
  final StoryHttpPost post;

  /// Each book's spine, read once: its file never changes. Only successful
  /// reads are kept, so a failed one is tried again next time.
  final _spines = <String, List<SpineItem>>{};

  @override
  Future<RecapStart> prepare(Book book) async {
    final model = await storyMap.loadModel(book);
    if (model == null) return const RecapNeedsStoryMap();
    // One look at the reader's place, for both the facts and the text, so the
    // two stop at the same paragraph. It waits for the reader's last save, so
    // it sees where they left off even while the book is still opening.
    final progress = await storyMap.readingProgress(book, model.sections);
    if (progress.shown == 0) return const RecapNeedsReading();
    // Throws rather than returning part of what was read.
    final paragraphs = await storyMap.paragraphs(book, progress);
    final source = buildRecapSource(
      model: model,
      progress: progress,
      paragraphs: paragraphs,
      spine: await _spine(book),
    );
    return source == null ? const RecapNeedsReading() : RecapCanStart(source);
  }

  /// The book's spine, or none if it can't be read: passages then show
  /// without a way to open them.
  Future<List<SpineItem>> _spine(Book book) async {
    final known = _spines[book.id];
    if (known != null) return known;
    try {
      return _spines[book.id] = await readSpineOf(book.epubPath);
    } on Object {
      return const [];
    }
  }

  @override
  Future<RecapResult> recap(RecapSource source, AiCredentials credentials) =>
      requestRecap(source, credentials: credentials, post: post);
}
