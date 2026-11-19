import 'dart:math';

import 'text_position.dart';

/// Tracks how far the reader has read and the knowledge boundary for AI features.
///
/// The boundary is the furthest position the reader has confirmed reading.
/// Small steps forward move it automatically, but a jump leaves it where it is
/// until [confirmJump]: more than [maxJumpPages] page turns past it, in its
/// own section or on into the next, or any section after that. When a page
/// count is unknown, more than [maxJumpProgression] of a section is a jump.
/// While the reader is past the boundary after a jump, [pendingJump] is where
/// they are.
class ReadingProgressTracker {
  final int maxJumpPages;
  final double maxJumpProgression;

  TextPosition _current;
  TextPosition _furthest;
  TextPosition _boundary;
  TextPosition? _pendingJump;
  TextPosition _jumpedFrom = const TextPosition(0, 0);
  double? _currentTotal;
  double? _boundaryTotal;

  /// How many pages the sections of [current] and [boundary] have, if known.
  int? _currentPages;
  int? _boundaryPages;

  /// Creates a tracker for a book that has not been opened yet.
  ReadingProgressTracker({
    this.maxJumpPages = 10,
    this.maxJumpProgression = 0.3,
  }) : _current = const TextPosition(0, 0),
       _furthest = const TextPosition(0, 0),
       _boundary = const TextPosition(0, 0);

  /// Picks up a book where it was left. A book left past the boundary was
  /// left on a jump that still waits, to go back from to the boundary.
  ReadingProgressTracker.resume({
    required this._current,
    required this._furthest,
    required this._boundary,
    this._currentTotal,
    this._boundaryTotal,
    this.maxJumpPages = 10,
    this.maxJumpProgression = 0.3,
  }) {
    if (_current > _boundary) {
      _pendingJump = _current;
      _jumpedFrom = _boundary;
    }
  }

  /// Reads a tracker saved by [toJson], the way [ReadingProgressTracker.resume]
  /// picks one up.
  ///
  /// Throws a [FormatException] if any position is missing or invalid.
  ReadingProgressTracker.fromJson(Map<String, dynamic> json)
    : this.resume(
        current: _positionFromJson(json['current']),
        furthest: _positionFromJson(json['furthest']),
        boundary: _positionFromJson(json['boundary']),
      );

  TextPosition get current => _current;
  TextPosition get furthest => _furthest;
  TextPosition get boundary => _boundary;

  /// Where the reader is past the boundary after a jump, or null if they
  /// aren't.
  TextPosition? get pendingJump => _pendingJump;

  /// Where the reader was just before the pending jump, to go back to. Only
  /// meaningful while [pendingJump] is set.
  TextPosition get jumpedFrom => _jumpedFrom;

  /// How far into the whole book [current] is, or null if unknown.
  double? get currentTotal => _currentTotal;

  /// How far into the whole book [boundary] is, or null if unknown.
  double? get boundaryTotal => _boundaryTotal;

  /// Records a new reader position and moves the boundary if it is safe.
  ///
  /// [sectionPages] is how many pages [position]'s section has, and
  /// [totalProgression] how far into the whole book it is, if known.
  void updatePosition(
    TextPosition position, {
    int? sectionPages,
    double? totalProgression,
  }) {
    final previous = _current;
    _current = position;
    _currentTotal = totalProgression;
    _currentPages = sectionPages;
    if (position > _furthest) {
      _furthest = position;
    }
    if (position <= _boundary) {
      _pendingJump = null;
      return;
    }
    final pending = _pendingJump;
    // Reading on from an unconfirmed jump doesn't count as read either.
    if ((pending != null && position >= pending) ||
        _isJump(position, sectionPages)) {
      // With no jump waiting, the reader was at or behind the boundary.
      if (pending == null) _jumpedFrom = previous;
      _pendingJump = position;
      return;
    }
    _boundary = position;
    _boundaryTotal = totalProgression;
    _boundaryPages = sectionPages;
    _pendingJump = null;
  }

  /// Whether [position], past the boundary, is too far to count as read
  /// without asking. The next section counts as read on only from the end of
  /// the boundary's, so skipping to it from the middle of a chapter is a jump.
  /// A section past the next is always a jump, since nothing says how long
  /// the one between is.
  bool _isJump(TextPosition position, int? sectionPages) {
    final sections = position.sectionIndex - _boundary.sectionIndex;
    if (sections > 1) return true;
    final boundaryPages = sections == 0 ? sectionPages : _boundaryPages;
    if (sectionPages == null || boundaryPages == null) {
      final read = sections == 0
          ? position.progression - _boundary.progression
          : 1 - _boundary.progression + position.progression;
      return read > maxJumpProgression;
    }
    final from = _pageIndex(_boundary.progression, boundaryPages);
    final to = _pageIndex(position.progression, sectionPages);
    // Into the next section: the boundary's pages left, then one turn onto
    // its first page, then its pages up to [position].
    final turns = sections == 0 ? to - from : boundaryPages - from + to;
    return turns > maxJumpPages;
  }

  /// The page of a section of [pages] that [progression] is on. The last page
  /// reports 1.0, not where it starts. Rounded, since page starts are not
  /// exact fractions.
  static int _pageIndex(double progression, int pages) =>
      (min(progression, (pages - 1) / pages) * pages).round();

  /// Moves the boundary to the pending jump after the user confirms it.
  void confirmJump() {
    final pending = _pendingJump;
    if (pending == null) {
      return;
    }
    _boundary = pending;
    // A pending jump is always where the reader is.
    _boundaryTotal = _currentTotal;
    _boundaryPages = _currentPages;
    _pendingJump = null;
  }

  Map<String, dynamic> toJson() => {
    'current': _current.toJson(),
    'furthest': _furthest.toJson(),
    'boundary': _boundary.toJson(),
  };

  static TextPosition _positionFromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw FormatException('Invalid position in reading state: $json');
    }
    return TextPosition.fromJson(json);
  }
}
