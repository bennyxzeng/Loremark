import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/notes_screen.dart';
import 'package:loremark/notes/annotation_service.dart';
import 'package:loremark/notes/note.dart';

import '../notes/in_memory_note_repository.dart';

void main() {
  /// The loaded notes of book "abc", with [saved] already in them.
  Future<AnnotationService> openNotes([List<Note> saved = const []]) async {
    final service = AnnotationService(
      bookId: 'abc',
      repository: InMemoryNoteRepository()..saved = saved,
    );
    await service.load();
    return service;
  }

  Widget screen(
    Future<AnnotationService> notes, {
    ValueChanged<Note>? onOpen,
  }) => MaterialApp(
    home: Scaffold(
      body: NotesScreen(notes: notes, onOpenNote: onOpen),
    ),
  );

  final saved = Note(
    id: 'n1',
    bookId: 'abc',
    anchor: const NoteAnchor(3, 0.5),
    chapterLabel: 'Chapter 4',
    selectedText: 'The harbor lights went out.',
    body: 'Someone cut the power.',
    color: HighlightColor.yellow,
    createdAt: DateTime.utc(2026, 11),
    updatedAt: DateTime.utc(2026, 11),
  );

  testWidgets('shows the notes of the opened book', (tester) async {
    await tester.pumpWidget(screen(openNotes([saved])));
    await tester.pumpAndSettle();

    expect(find.text('Chapter 4'), findsOneWidget);
    expect(find.text('Someone cut the power.'), findsOneWidget);
  });

  testWidgets('tapping a note asks to open it in the reader', (tester) async {
    Note? opened;
    await tester.pumpWidget(
      screen(openNotes([saved]), onOpen: (note) => opened = note),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Someone cut the power.'));

    expect(opened, saved);
  });

  testWidgets('shows a note added elsewhere, such as in the Read tab', (
    tester,
  ) async {
    final notes = openNotes();
    await tester.pumpWidget(screen(notes));
    await tester.pumpAndSettle();

    await (await notes).addHighlight(
      anchor: const NoteAnchor(1, 0.2),
      chapterLabel: 'Chapter 2',
      selectedText: 'The tide turned.',
    );
    await tester.pump();

    expect(find.text('Chapter 2'), findsOneWidget);
  });

  testWidgets('shows the empty state when the book has no notes', (
    tester,
  ) async {
    await tester.pumpWidget(screen(openNotes()));
    await tester.pumpAndSettle();

    expect(find.text('Notes & theories'), findsOneWidget);
    expect(find.textContaining('No notes yet'), findsOneWidget);
  });

  testWidgets('says so when the notes cannot be opened', (tester) async {
    final opening = Completer<AnnotationService>();
    await tester.pumpWidget(screen(opening.future));
    opening.completeError(StateError('no storage'));
    await tester.pumpAndSettle();

    expect(find.text('Could not open your notes.'), findsOneWidget);
  });
}
