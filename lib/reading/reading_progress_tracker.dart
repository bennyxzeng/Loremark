import 'dart:math';

import 'text_position.dart';

/// Result of [ReadingProgressTracker.updatePosition].
enum PositionUpdateResult { updated, needsConfirmation }

/// Tracks how far the reader has read and the knowledge boundary for AI features.
///
/// The boundary is the furthest position the reader has confirmed reading.
/// Small steps forward move it automatically, but a jump waits for
/// [confirmJump]: more than [maxJumpSections] sections past it, or, in its own
/// section, more than [maxJumpPages] pages past it. When the section's page
/// count is unknown, more than [maxJumpProgression] of the section is a jump.
class ReadingProgressTracker {
  final int maxJumpSections;
  final int maxJumpPages;
  final double maxJumpProgression;

  TextPosition _current;
  TextPosition _furthest;
  TextPosition _boundary;
  TextPosition? _pendingJump;

  /// The furthest section asked about while [_pendingJump] waits.
  int _askedSection = 0;
  TextPosition _jumpedFrom = const TextPosition(0, 0);

  /// Creates a tracker for a book that has not been opened yet.
  ReadingProgressTracker({
    this.maxJumpSections = 2,
    this.maxJumpPages = 10,
    this.maxJumpProgression = 0.3,
  }) : _current = const TextPosition(0, 0),
       _furthest = const TextPosition(0, 0),
       _boundary = const TextPosition(0, 0);

  /// Picks up a book where it was left, with no jump waiting.
  ReadingProgressTracker.resume({
    required this._current,
    required this._furthest,
    required this._boundary,
    this.maxJumpSections = 2,
    this.maxJumpPages = 10,
    this.maxJumpProgression = 0.3,
  });

  /// Reads a tracker saved by [toJson].
  ///
  /// Throws a [FormatException] if any position is missing or invalid.
  ReadingProgressTracker.fromJson(
    Map<String, dynamic> json, {
    this.maxJumpSections = 2,
    this.maxJumpPages = 10,
    this.maxJumpProgression = 0.3,
  }) : _current = _positionFromJson(json['current']),
       _furthest = _positionFromJson(json['furthest']),
       _boundary = _positionFromJson(json['boundary']);

  TextPosition get current => _current;
  TextPosition get furthest => _furthest;
  TextPosition get boundary => _boundary;

  /// The position of an unconfirmed jump, or null if there is none.
  TextPosition? get pendingJump => _pendingJump;

  /// Where the reader was just before the pending jump, to go back to. If
  /// that was past the boundary, as after reopening a book left there, it is
  /// the boundary. Only meaningful while [pendingJump] is set.
  TextPosition get jumpedFrom => _jumpedFrom;

  /// Records a new reader position and moves the boundary if it is safe.
  ///
  /// [sectionPages] is how many pages [position]'s section has, if known.
  PositionUpdateResult updatePosition(
    TextPosition position, {
    int? sectionPages,
  }) {
    final previous = _current;
    _current = position;
    if (position > _furthest) {
      _furthest = position;
    }
    if (position <= _boundary) {
      _pendingJump = null;
      return PositionUpdateResult.updated;
    }
    final pending = _pendingJump;
    // Reading on from an unconfirmed jump doesn't count as read either, but
    // each new section is asked about once, so a reader who said "not yet"
    // can still move the boundary by reading on.
    if (pending != null && position >= pending) {
      _pendingJump = position;
      if (position.sectionIndex <= _askedSection) {
        return PositionUpdateResult.updated;
      }
      _askedSection = position.sectionIndex;
      return PositionUpdateResult.needsConfirmation;
    }
    if (!_isJump(position, sectionPages)) {
      _boundary = position;
      _pendingJump = null;
      return PositionUpdateResult.updated;
    }
    _pendingJump = position;
    // Ask only once per jump: going back a little from an unconfirmed jump
    // just moves it.
    if (pending != null &&
        (position.sectionIndex - pending.sectionIndex).abs() <=
            maxJumpSections) {
      return PositionUpdateResult.updated;
    }
    // Asked again while a jump still waits, going back still goes to before
    // the first one.
    if (pending == null) {
      _jumpedFrom = previous <= _boundary ? previous : _boundary;
    }
    _askedSection = position.sectionIndex;
    return PositionUpdateResult.needsConfirmation;
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
