import 'package:flutter/foundation.dart';

import '../library/book.dart';
import '../reader/epub_sections.dart';
import '../reader/reader_position.dart';
import '../story_model/story_model.dart';
import 'story_map_backend.dart';

/// What the rest of an open book shows of its Story Map: the update under way,
/// if there is one, and whether the reader's page is in the map.
///
/// Kept by the book, above its tabs, so the header sees it from every tab. The
/// Story Map tab says how its updates and its map change, and the Read tab says
/// where the reader is.
class StoryMapStatusController extends ChangeNotifier {
  /// Starts with the update already running for [book], if there is one, so
  /// coming back to the book shows it from the first frame.
  StoryMapStatusController({required this.book, required this.backend})
    : _updateStartedAt = backend.running(book)?.startedAt;

  final Book book;
  final StoryMapBackend backend;

  DateTime? _updateStartedAt;
  bool _cancelling = false;
  bool _mapKnown = false;
  List<StorySection>? _sections;
  int? _readerAt;
  List<SpineItem>? _spine;
  Future<void>? _readingSpine;
  StoryCoverage? _coverage;
  bool _disposed = false;

  /// When the update under way began, or null if none is.
  DateTime? get updateStartedAt => _updateStartedAt;

  /// Whether the reader has cancelled the update under way, which hasn't
  /// stopped yet.
  bool get cancelling => _cancelling;

  /// Where the reader's page is next to the map. [StoryCoverage.none] as soon
  /// as there is known to be no map; otherwise null until both the map and the
  /// page are known.
  StoryCoverage? get coverage => _coverage;

  void updateStarted(DateTime at) {
    _updateStartedAt = at;
    _cancelling = false;
    _notify();
  }

  void cancelRequested() {
    if (_updateStartedAt == null || _cancelling) return;
    _cancelling = true;
    _notify();
  }

  void updateEnded() {
    if (_updateStartedAt == null && !_cancelling) return;
    _updateStartedAt = null;
    _cancelling = false;
    _notify();
  }

  /// The map's [sections], or null for no map, each time the map is read.
  void mapLoaded(List<StorySection>? sections) {
    _mapKnown = true;
    _sections = sections;
    _recompute();
  }

  /// The map couldn't be read, so where the page is next to it isn't known.
  void mapUnreadable() {
    _mapKnown = false;
    _sections = null;
    _recompute();
  }

  /// Where the Read tab is now. Only the spine item matters, so turning pages
  /// within one changes nothing.
  void readerMoved(ReaderPosition position) {
    if (position.sectionIndex == _readerAt) return;
    _readerAt = position.sectionIndex;
    _recompute();
  }

  void _recompute() {
    final sections = _sections;
    final readerAt = _readerAt;
    final spine = _spine;
    StoryCoverage? coverage;
    if (!_mapKnown) {
      coverage = null;
    } else if (sections == null || sections.isEmpty) {
      coverage = StoryCoverage.none;
    } else if (spine == null) {
      _readingSpine ??= _readSpine();
    } else if (readerAt != null) {
      coverage = storyCoverage(sections, spine, readerAt);
    }
    if (coverage == _coverage) return;
    _coverage = coverage;
    _notify();
  }

  Future<void> _readSpine() async {
    try {
      final spine = await backend.spine(book);
      if (_disposed) return;
      _spine = spine;
      _recompute();
    } on Object catch (error) {
      // Without it the page can't be placed, so the header leaves it out.
      debugPrint('Could not read the spine for the Story Map status: $error');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
