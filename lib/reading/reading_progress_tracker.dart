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
///
/// Pages flipped through don't count as read either. Once [fastFlipPages]
/// pages past the boundary each go by in less than [fastPageTime], the
/// boundary goes back to where the flipping began and the reader is past it
/// on a jump, [flippedAhead]. Fewer than that before a page stays longer
/// count as read.
class ReadingProgressTracker {
  final int maxJumpPages;
  final double maxJumpProgression;
  final Duration fastPageTime;
  final int fastFlipPages;

  TextPosition _current;
  TextPosition _furthest;
  TextPosition _boundary;
  TextPosition? _pendingJump;
  TextPosition _jumpedFrom = const TextPosition(0, 0);
  bool _flippedAhead = false;
  double? _currentTotal;
  double? _boundaryTotal;

  /// How many pages the sections of [current] and [boundary] have, if known.
  int? _currentPages;
  int? _boundaryPages;

  /// When [current] was reported, if known.
  DateTime? _currentAt;

  /// Pages past the boundary flipped through since a page last stayed on
  /// screen for [fastPageTime], and where the boundary was before the first.
  int _flipped = 0;
  late ({TextPosition position, double? total, int? pages}) _flipStart;

  /// Creates a tracker for a book that has not been opened yet.
  ReadingProgressTracker({
    this.maxJumpPages = 10,
    this.maxJumpProgression = 0.3,
    this.fastPageTime = const Duration(seconds: 2),
    this.fastFlipPages = 5,
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
    this.fastPageTime = const Duration(seconds: 2),
    this.fastFlipPages = 5,
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

  /// Whether the pending jump comes from flipping through pages, not from
  /// one jump. [jumpedFrom] is then where the flipping began.
  bool get flippedAhead => _flippedAhead;

  /// How far into the whole book [current] is, or null if unknown.
  double? get currentTotal => _currentTotal;

  /// How far into the whole book [boundary] is, or null if unknown.
  double? get boundaryTotal => _boundaryTotal;

  /// Records a new reader position and moves the boundary if it is safe.
  ///
  /// [sectionPages] is how many pages [position]'s section has, and
  /// [totalProgression] how far into the whole book it is, if known. [at] is
  /// when the reader got there; without it, nothing counts as flipping.
  void updatePosition(
    TextPosition position, {
    int? sectionPages,
    double? totalProgression,
    DateTime? at,
  }) {
    final previous = _current;
    final previousAt = _currentAt;
    // The page before this one was flipped through.
    final fast =
        at != null &&
        previousAt != null &&
        at.difference(previousAt) < fastPageTime;
    _current = position;
    _currentTotal = totalProgression;
    _currentPages = sectionPages;
    _currentAt = at;
    if (!fast) _flipped = 0;
    if (position > _furthest) {
      _furthest = position;
    }
    if (position <= _boundary) {
      _pendingJump = null;
      _flippedAhead = false;
      return;
    }
    final pending = _pendingJump;
    // Reading on from an unconfirmed jump doesn't count as read either, and
    // after flipping, nothing up to where it began does.
    if ((pending != null && (position >= pending || _flippedAhead)) ||
        _isJump(position, sectionPages)) {
      // With no jump waiting, the reader was at or behind the boundary.
      if (pending == null) _jumpedFrom = previous;
      _pendingJump = position;
      _flipped = 0;
      return;
    }
    if (fast) {
      if (_flipped == 0) {
        _flipStart = (
          position: _boundary,
          total: _boundaryTotal,
          pages: _boundaryPages,
        );
      }
      // Only pages past the boundary count; flipping back and forth over
      // read ones is re-reading them.
      _flipped += _turnsFromBoundary(position, sectionPages) ?? 1;
      if (_flipped >= fastFlipPages) {
        _boundary = _flipStart.position;
        _boundaryTotal = _flipStart.total;
        _boundaryPages = _flipStart.pages;
        _jumpedFrom = _flipStart.position;
        _pendingJump = position;
        _flippedAhead = true;
        _flipped = 0;
        return;
      }
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
    final turns = _turnsFromBoundary(position, sectionPages);
    if (turns != null) return turns > maxJumpPages;
    final read = sections == 0
        ? position.progression - _boundary.progression
        : 1 - _boundary.progression + position.progression;
    return read > maxJumpProgression;
  }

  /// How many page turns [position] is past the boundary, in its section or
  /// the next one, or null if a page count it needs is unknown.
  int? _turnsFromBoundary(TextPosition position, int? sectionPages) {
    final sections = position.sectionIndex - _boundary.sectionIndex;
    final boundaryPages = sections == 0 ? sectionPages : _boundaryPages;
    if (sectionPages == null || boundaryPages == null) return null;
    final from = _pageIndex(_boundary.progression, boundaryPages);
    final to = _pageIndex(position.progression, sectionPages);
    // Into the next section: the boundary's pages left, then one turn onto
    // its first page, then its pages up to [position].
    return sections == 0 ? to - from : boundaryPages - from + to;
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
    _flippedAhead = false;
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
