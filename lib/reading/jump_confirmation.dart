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

/// Asks whether the chapters the reader skipped count as read. False if they
/// don't, or if the dialog is closed without an answer.
Future<bool> confirmSkippedChapters(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('You skipped ahead'),
      content: const Text(
        'Count the chapters you skipped as read? Story Map and Ask only use '
        'what you’ve read.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not yet'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Count as read'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
