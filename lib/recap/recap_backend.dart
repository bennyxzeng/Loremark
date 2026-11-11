import '../library/book.dart';
import '../story_map/story_map_backend.dart';
import 'recap_stop.dart';

/// Whether the welcome back can offer a recap of a book now, and if so where
/// the reader stopped.
sealed class RecapStart {
  const RecapStart();
}

/// The book has no Story Map, so there is no recap to offer: it is built from
/// the map.
class RecapNeedsStoryMap extends RecapStart {
  const RecapNeedsStoryMap();
}

/// The reader hasn't read anything the Story Map covers yet.
class RecapNeedsReading extends RecapStart {
  const RecapNeedsReading();
}

/// A recap can be offered: the reader stopped at [stop].
class RecapCanStart extends RecapStart {
  const RecapCanStart(this.stop);

  final RecapStop stop;
}

/// What the welcome back needs from the device, so tests can stand in for it.
abstract interface class RecapBackend {
  /// Whether a recap of [book] can be offered, and where the reader stopped.
  Future<RecapStart> prepare(Book book);
}

/// The real thing: the book's Story Map and the reader's progress through it.
class DeviceRecapBackend implements RecapBackend {
  DeviceRecapBackend({required this.storyMap});

  /// The book's Story Map and how far the reader has got through it, the one
  /// the Story Map tab uses, so the welcome back names the place it shows.
  final StoryMapBackend storyMap;

  @override
  Future<RecapStart> prepare(Book book) async {
    final model = await storyMap.loadModel(book);
    if (model == null) return const RecapNeedsStoryMap();
    // It waits for the reader's last save, so it sees where they left off even
    // while the book is still opening.
    final progress = await storyMap.readingProgress(book, model.sections);
    final stop = recapStopAt(model, progress);
    return stop == null ? const RecapNeedsReading() : RecapCanStart(stop);
  }
}
