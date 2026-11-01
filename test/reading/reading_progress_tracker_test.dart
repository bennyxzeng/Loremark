import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reading/reading_progress_tracker.dart';
import 'package:loremark/reading/text_position.dart';

void main() {
  late ReadingProgressTracker tracker;

  setUp(() {
    tracker = ReadingProgressTracker();
    tracker.updatePosition(const TextPosition(5, 0.5));
    tracker.confirmJump();
  });

  test('new tracker starts at the beginning of the book', () {
    final fresh = ReadingProgressTracker();
    expect(fresh.current, const TextPosition(0, 0));
    expect(fresh.furthest, const TextPosition(0, 0));
    expect(fresh.boundary, const TextPosition(0, 0));
    expect(fresh.pendingJump, isNull);
  });

  test('small step forward moves the boundary', () {
    final result = tracker.updatePosition(const TextPosition(7, 0.9));
    expect(result, PositionUpdateResult.updated);
    expect(tracker.current, const TextPosition(7, 0.9));
    expect(tracker.furthest, const TextPosition(7, 0.9));
    expect(tracker.boundary, const TextPosition(7, 0.9));
  });

  test('going back keeps furthest and boundary', () {
    final result = tracker.updatePosition(const TextPosition(2, 0.1));
    expect(result, PositionUpdateResult.updated);
    expect(tracker.current, const TextPosition(2, 0.1));
    expect(tracker.furthest, const TextPosition(5, 0.5));
    expect(tracker.boundary, const TextPosition(5, 0.5));
  });

  test('big jump needs confirmation and keeps the boundary', () {
    final result = tracker.updatePosition(const TextPosition(8, 0.0));
    expect(result, PositionUpdateResult.needsConfirmation);
    expect(tracker.current, const TextPosition(8, 0.0));
    expect(tracker.furthest, const TextPosition(8, 0.0));
    expect(tracker.boundary, const TextPosition(5, 0.5));
    expect(tracker.pendingJump, const TextPosition(8, 0.0));
  });

  test('confirmJump moves the boundary to the pending jump', () {
    tracker.updatePosition(const TextPosition(8, 0.0));
    tracker.confirmJump();
    expect(tracker.boundary, const TextPosition(8, 0.0));
    expect(tracker.pendingJump, isNull);
  });

  test('reading on after an unconfirmed jump does not ask again', () {
    tracker.updatePosition(const TextPosition(8, 0.0));
    for (final position in const [
      TextPosition(8, 0.4),
      TextPosition(9, 0.1),
      TextPosition(10, 0.5),
    ]) {
      expect(tracker.updatePosition(position), PositionUpdateResult.updated);
      expect(tracker.pendingJump, position);
    }
    expect(tracker.boundary, const TextPosition(5, 0.5));
  });

  test('confirmJump after reading on uses the latest pending position', () {
    tracker.updatePosition(const TextPosition(8, 0.0));
    tracker.updatePosition(const TextPosition(9, 0.3));
    tracker.confirmJump();
    expect(tracker.boundary, const TextPosition(9, 0.3));
  });

  test('another big jump from the pending jump asks again', () {
    tracker.updatePosition(const TextPosition(8, 0.0));
    final result = tracker.updatePosition(const TextPosition(11, 0.0));
    expect(result, PositionUpdateResult.needsConfirmation);
    expect(tracker.pendingJump, const TextPosition(11, 0.0));
  });

  test('big jump back from the pending jump asks again', () {
    tracker.updatePosition(const TextPosition(20, 0.0));
    final result = tracker.updatePosition(const TextPosition(9, 0.0));
    expect(result, PositionUpdateResult.needsConfirmation);
    expect(tracker.pendingJump, const TextPosition(9, 0.0));
  });

  test('going back after an unconfirmed jump drops it', () {
    tracker.updatePosition(const TextPosition(8, 0.0));
    tracker.updatePosition(const TextPosition(6, 0.0));
    expect(tracker.pendingJump, isNull);
    expect(tracker.boundary, const TextPosition(6, 0.0));
    tracker.confirmJump();
    expect(tracker.boundary, const TextPosition(6, 0.0));
  });

  test('confirmJump without a pending jump does nothing', () {
    tracker.confirmJump();
    expect(tracker.boundary, const TextPosition(5, 0.5));
  });

  test('maxJumpSections changes the threshold', () {
    final strict = ReadingProgressTracker(maxJumpSections: 0);
    expect(
      strict.updatePosition(const TextPosition(0, 0.9)),
      PositionUpdateResult.updated,
    );
    expect(
      strict.updatePosition(const TextPosition(1, 0.0)),
      PositionUpdateResult.needsConfirmation,
    );
  });

  group('json', () {
    test('round trip keeps current, furthest and boundary', () {
      tracker.updatePosition(const TextPosition(9, 0.25));
      tracker.updatePosition(const TextPosition(4, 0.75));
      final decoded = jsonDecode(jsonEncode(tracker.toJson()));
      final loaded = ReadingProgressTracker.fromJson(decoded);
      expect(loaded.current, const TextPosition(4, 0.75));
      expect(loaded.furthest, const TextPosition(9, 0.25));
      expect(loaded.boundary, const TextPosition(5, 0.5));
      expect(loaded.pendingJump, isNull);
    });

    test('throws FormatException when a position is missing or invalid', () {
      final valid = tracker.toJson();
      expect(
        () => ReadingProgressTracker.fromJson({...valid}..remove('boundary')),
        throwsFormatException,
      );
      expect(
        () => ReadingProgressTracker.fromJson({
          ...valid,
          'current': {'sectionIndex': -1, 'progression': 0},
        }),
        throwsFormatException,
      );
    });
  });
}
