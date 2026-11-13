import '../reader/reading_position_store.dart';
import 'reading_progress_tracker.dart';
import 'text_position.dart';

/// [bookId]'s tracker as [store] last saved it.
///
/// A book read before the tracker existed has only its position saved, so
/// everything up to it counts as read, and that is saved at once. Otherwise
/// the next open would take the reader for ahead of where they already were,
/// or, after they went back, forget how far they had read. Throws if that save
/// fails.
Future<ReadingProgressTracker> loadTracker(
  ReadingPositionStore store,
  String bookId,
) async {
  final saved = await store.load(bookId);
  final current = saved == null
      ? const TextPosition(0, 0)
      : TextPosition(saved.sectionIndex, saved.progression);
  final progress = await store.loadProgress(bookId);
  if (progress == null) {
    await store.saveProgress(
      bookId,
      furthest: current,
      boundary: current,
      boundaryTotal: saved?.totalProgression,
    );
  }
  return ReadingProgressTracker.resume(
    current: current,
    furthest: progress?.furthest ?? current,
    boundary: progress?.boundary ?? current,
    currentTotal: saved?.totalProgression,
    boundaryTotal: progress == null
        ? saved?.totalProgression
        : progress.boundaryTotal,
  );
}
