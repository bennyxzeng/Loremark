import 'package:flutter/material.dart';

import '../reader/reading_position_store.dart';
import 'reading_progress_tracker.dart';
import 'text_position.dart';

/// [bookId]'s tracker as [store] last saved it.
///
/// A book read before the tracker existed has only its position saved, so
/// everything up to it counts as read, and that is saved at once. Otherwise
/// the next open would ask about a jump to where the reader already was, or,
/// after they went back, forget how far they had read. Throws if that save
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
    await store.saveProgress(bookId, furthest: current, boundary: current);
  }
  return ReadingProgressTracker.resume(
    current: current,
    furthest: progress?.furthest ?? current,
    boundary: progress?.boundary ?? current,
  );
}

/// What the reader chose when asked about a jump ahead.
enum JumpAnswer {
  /// Count what was skipped as read.
  countAsRead,

  /// Return to where they were before the jump.
  goBack,

  /// Stay without counting it, such as to look something up.
  notYet,
}

/// Asks whether what the reader skipped counts as read. [JumpAnswer.notYet]
/// if the dialog is closed without an answer.
Future<JumpAnswer> confirmSkippedChapters(BuildContext context) async {
  final answer = await showDialog<JumpAnswer>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('You skipped ahead'),
      content: const Text(
        'Count what you skipped as read? Story Map and Ask only use what '
        'you’ve read.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, JumpAnswer.notYet),
          child: const Text('Not yet'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, JumpAnswer.goBack),
          child: const Text('Go back'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, JumpAnswer.countAsRead),
          child: const Text('Count as read'),
        ),
      ],
    ),
  );
  return answer ?? JumpAnswer.notYet;
}
