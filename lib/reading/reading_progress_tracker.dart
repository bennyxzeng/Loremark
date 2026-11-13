import 'dart:math';

import 'text_position.dart';

/// Tracks how far the reader has read and the knowledge boundary for AI features.
///
/// The boundary is the furthest position the reader has confirmed reading.
/// Small steps forward move it automatically, but a jump leaves it where it is
/// until [confirmJump]: more than [maxJumpSections] sections past it, or, in
/// its own section, more than [maxJumpPages] pages past it. When the section's
/// page count is unknown, more than [maxJumpProgression] of the section is a
/// jump. While the reader is past the boundary after a jump, [pendingJump] is
/// where they are.
class ReadingProgressTracker {
  final int maxJumpSections;
  final int maxJumpPages;
  final double maxJumpProgression;

  TextPosition _current;
  TextPosition _furthest;
  TextPosition _boundary;
  TextPosition? _pendingJump;
  TextPosition _jumpedFrom = const TextPosition(0, 0);
  double? _currentTotal;
  double? _boundaryTotal;

  /// Creates a tracker for a book that has not been opened yet.
  ReadingProgressTracker({
    this.maxJumpSections = 2,
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
    this.maxJumpSections = 2,
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
    _pendingJump = null;
  }

  /// Whether [position], past the boundary, is too far to count as read
  /// without asking.
  bool _isJump(TextPosition position, int? sectionPages) {
    if (position.sectionIndex != _boundary.sectionIndex) {
      return position.sectionIndex - _boundary.sectionIndex > maxJumpSections;
    }
    if (sectionPages == null) {
      return position.progression - _boundary.progression > maxJumpProgression;
    }
    // The last page reports 1.0, not where it starts, which would count it as
    // one page more. Rounded, since page starts are not exact fractions.
    final start = min(position.progression, (sectionPages - 1) / sectionPages);
    return ((start - _boundary.progression) * sectionPages).round() >
        maxJumpPages;
  }

  /// Moves the boundary to the pending jump after the user confirms it.
  void confirmJump() {
    final pending = _pendingJump;
    if (pending == null) {
      return;
    }
    _boundary = pending;
    // A pending jump is always where the reader is.
    _boundaryTotal = _currentTotal;
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
