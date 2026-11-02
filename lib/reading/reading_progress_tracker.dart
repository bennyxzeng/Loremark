import 'text_position.dart';

/// Result of [ReadingProgressTracker.updatePosition].
enum PositionUpdateResult { updated, needsConfirmation }

/// Tracks how far the reader has read and the knowledge boundary for AI features.
///
/// The boundary is the furthest position the reader has confirmed reading.
/// Small steps forward move it automatically, but a jump of more than
/// [maxJumpSections] sections past it waits for [confirmJump].
class ReadingProgressTracker {
  final int maxJumpSections;

  TextPosition _current;
  TextPosition _furthest;
  TextPosition _boundary;
  TextPosition? _pendingJump;

  /// Creates a tracker for a book that has not been opened yet.
  ReadingProgressTracker({this.maxJumpSections = 2})
    : _current = const TextPosition(0, 0),
      _furthest = const TextPosition(0, 0),
      _boundary = const TextPosition(0, 0);

  /// Reads a tracker saved by [toJson].
  ///
  /// Throws a [FormatException] if any position is missing or invalid.
  ReadingProgressTracker.fromJson(
    Map<String, dynamic> json, {
    this.maxJumpSections = 2,
  }) : _current = _positionFromJson(json['current']),
       _furthest = _positionFromJson(json['furthest']),
       _boundary = _positionFromJson(json['boundary']);

  TextPosition get current => _current;
  TextPosition get furthest => _furthest;
  TextPosition get boundary => _boundary;

  /// The position of an unconfirmed jump, or null if there is none.
  TextPosition? get pendingJump => _pendingJump;

  /// Records a new reader position and moves the boundary if it is safe.
  PositionUpdateResult updatePosition(TextPosition position) {
    _current = position;
    if (position > _furthest) {
      _furthest = position;
    }
    if (position <= _boundary) {
      _pendingJump = null;
      return PositionUpdateResult.updated;
    }
    if (position.sectionIndex - _boundary.sectionIndex > maxJumpSections) {
      final pending = _pendingJump;
      _pendingJump = position;
      // Ask only once per jump: reading on near an unconfirmed jump just moves it.
      if (pending != null &&
          (position.sectionIndex - pending.sectionIndex).abs() <=
              maxJumpSections) {
        return PositionUpdateResult.updated;
      }
      return PositionUpdateResult.needsConfirmation;
    }
    _boundary = position;
    _pendingJump = null;
    return PositionUpdateResult.updated;
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
