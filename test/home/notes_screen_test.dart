import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/notes_screen.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/notes/annotation_service.dart';
import 'package:loremark/notes/note.dart';

import '../notes/in_memory_note_repository.dart';

void main() {
  Book book(String id) => Book(
    id: id,
    title: 'Glass Harbor',
    author: null,
    epubPath: '$id.epub',
    coverPath: null,
    importedAt: DateTime.utc(2026, 11),
  );

  testWidgets('shows the notes of the opened book', (tester) async {
    final opened = <String>[];
    final repository = InMemoryNoteRepository()
      ..saved = [
        Note(
          id: 'n1',
          bookId: 'abc',
          anchor: const NoteAnchor(3, 0.5),
          chapterLabel: 'Chapter 4',
          selectedText: 'The harbor lights went out.',
          body: 'Someone cut the power.',
          color: HighlightColor.yellow,
          createdAt: DateTime.utc(2026, 11),
          updatedAt: DateTime.utc(2026, 11),
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotesScreen(
            book: book('abc'),
            openNotes: (bookId) async {
              opened.add(bookId);
              return AnnotationService(bookId: bookId, repository: repository);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(opened, ['abc']);
    expect(find.text('Chapter 4'), findsOneWidget);
    expect(find.text('Someone cut the power.'), findsOneWidget);
  });

  testWidgets('shows the empty state when the book has no notes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotesScreen(
            book: book('abc'),
            openNotes: (bookId) async => AnnotationService(
              bookId: bookId,
              repository: InMemoryNoteRepository(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Notes & theories'), findsOneWidget);
    expect(find.textContaining('No notes yet'), findsOneWidget);
  });

  testWidgets('says so when the notes cannot be opened', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotesScreen(
            book: book('abc'),
            openNotes: (_) async => throw StateError('no storage'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not open your notes.'), findsOneWidget);
  });
}
