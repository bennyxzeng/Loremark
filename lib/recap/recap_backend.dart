import '../library/book.dart';
import '../reader/epub_sections.dart';
import '../reader/reading_position_store.dart';
import '../settings/ai_settings.dart';
import '../story_map/story_map_backend.dart';
import '../story_model/story_model.dart';
import '../story_update/story_api_client.dart';
import 'recap_client.dart';
import 'recap_source.dart';

/// What the Ask tab's recap needs from the device and the network, so tests
/// can stand in for them.
abstract interface class RecapBackend {
  /// What a recap of [book] may use, or null if the reader hasn't finished a
  /// section yet.
  Future<RecapSource?> prepare(Book book);

  /// Asks the provider for a recap of [source]. Never throws: a failure is a
  /// [RecapFailed].
  Future<RecapResult> recap(RecapSource source, AiCredentials credentials);
}

/// The real thing: the saved position, the EPUB, the Story Map on disk and the
/// reader's provider.
class DeviceRecapBackend implements RecapBackend {
  DeviceRecapBackend({StoryMapBackend? storyMap, this.post = postRecapRequest})
    : storyMap = storyMap ?? DeviceStoryMapBackend();

  /// Where the book's Story Map comes from, if one was built.
  final StoryMapBackend storyMap;

  /// How requests reach the provider; tests replace the network call.
  final StoryHttpPost post;

  /// Each book's spine and text, read once: a long book takes a second or more
  /// to read, and its file never changes. Only successful reads are kept, so a
  /// failed one is tried again next time.
  final _spines = <String, List<SpineItem>>{};
  final _texts = <String, List<String>>{};

  @override
  Future<RecapSource?> prepare(Book book) async {
    final store = await ReadingPositionStore.open();
    await store.saved;
    // The saved position is where the reader is now. Once the progress
    // tracker (#53) keeps the furthest position, pass it here too, so turning
    // back to reread doesn't move the recap back.
    final position = await store.load(book.id);
    if (position == null) return null;
    final spine = _spines[book.id] ??= await readSpine(book.epubPath);
    // As in the Story Map (`finishedStorySections`): a section is finished
    // once the reader has turned past its end, since a page just turned to
    // hasn't been read yet. The book's last page has nothing to turn to.
    final atBookEnd =
        position.progression == 1 &&
        position.sectionIndex == spine.lastIndexWhere((item) => item.linear);
    final finishedSpineItems = atBookEnd
        ? position.sectionIndex + 1
        : position.sectionIndex;
    if (finishedSpineItems <= 0) return null;

    final sectionTexts = _texts[book.id] ??= await readSectionTexts(
      book.epubPath,
    );
    final model = await _loadModel(book);
    final sections = model == null
        ? const <StorySection>[]
        : ([...model.sections]..sort((a, b) => a.order.compareTo(b.order)));
    final finishedStory = finishedStorySections(sections, spine, position);
    return buildRecapSource(
      spine: spine,
      sectionTexts: sectionTexts,
      finishedSpineItems: finishedSpineItems,
      model: model,
      finishedStorySections: finishedStory,
    );
  }

  /// The book's Story Map, or null if there is none or it can't be read: a
  /// recap still works from the book's text alone.
  Future<StoryModel?> _loadModel(Book book) async {
    try {
      return await storyMap.loadModel(book);
    } on Object {
      return null;
    }
  }

  @override
  Future<RecapResult> recap(RecapSource source, AiCredentials credentials) =>
      requestRecap(source, credentials: credentials, post: post);
}
