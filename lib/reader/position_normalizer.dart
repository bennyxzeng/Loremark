import 'epub_sections.dart';
import 'reader_position.dart';

/// Turns the renderer's raw positions into the ones the app reports.
///
/// Readium reports where the current page starts, so the last page of a
/// section is below 1.0. Reading code needs a finished section at exactly 1.0,
/// so this reports it when the reader turns into the next section.
class PositionNormalizer {
  PositionNormalizer(this.spine);

  /// How close to the end counts as the end. A page start never gets there
  /// unless it is the end, so this only absorbs rounding.
  static const _snap = 1e-3;

  /// The book's spine, to know which sections page turns skip.
  final List<SpineItem> spine;

  ReaderPosition? _last;

  /// The positions to report for [raw], in order. Empty if nothing changed.
  List<ReaderPosition> normalize(ReaderPosition raw) {
    final position = ReaderPosition(
      raw.sectionIndex,
      _clean(raw.progression),
      totalProgression: raw.totalProgression == null
          ? null
          : _clean(raw.totalProgression!),
    );
    final last = _last;
    if (position == last) return const [];
    _last = position;
    if (last != null && _isPageTurn(last, position.sectionIndex)) {
      return [_finished(last, position.totalProgression), position];
    }
    return [position];
  }

  /// The positions to report when the reader reaches the end of the book.
  List<ReaderPosition> finish() {
    final lastLinear = spine.lastIndexWhere((item) => item.linear);
    if (lastLinear < 0) return const [];
    final end = ReaderPosition(lastLinear, 1.0, totalProgression: 1.0);
    final last = _last;
    if (last == end) return const [];
    _last = end;
    if (last != null && _isPageTurn(last, lastLinear)) {
      return [_finished(last, end.totalProgression), end];
    }
    return [end];
  }

  /// Clamps [value] into [0, 1] and snaps a rounded-up end to exactly 1.0.
  /// Near-0 values stay as they are.
  static double _clean(double value) {
    if (value.isNaN) return 0;
    if (value >= 1 - _snap) return 1;
    return value < 0 ? 0 : value;
  }

  /// Whether moving from [last] to section [next] is a normal page turn out of
  /// an unfinished section, which renderers do across non-linear items.
  bool _isPageTurn(ReaderPosition last, int next) {
    if (last.progression >= 1 || next <= last.sectionIndex) return false;
    for (var i = last.sectionIndex + 1; i < next; i++) {
      if (i >= spine.length || spine[i].linear) return false;
    }
    return true;
  }

  static ReaderPosition _finished(
    ReaderPosition last,
    double? totalProgression,
  ) => ReaderPosition(
    last.sectionIndex,
    1.0,
    totalProgression: totalProgression,
  );
}
