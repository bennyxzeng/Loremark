import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/read_screen.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/notes/annotation_service.dart';
import 'package:loremark/notes/note.dart';
import 'package:loremark/reader/epub_reader_service.dart';
import 'package:loremark/theme/loremark_theme.dart';

import '../notes/in_memory_note_repository.dart';
import 'fake_epub_reader_service.dart';

void main() {
  final book = Book(
    id: 'abc',
    title: 'The Glass Harbor',
    author: null,
    epubPath: 'glass.epub',
    coverPath: null,
    importedAt: DateTime(2026),
  );

  late FakeEpubReaderService readerService;
  late AnnotationService notes;
  late NoteJumpController jumps;

  setUp(() async {
    readerService = FakeEpubReaderService();
    notes = AnnotationService(
      bookId: book.id,
      repository: InMemoryNoteRepository(),
    );
    await notes.load();
    jumps = NoteJumpController();
  });

  /// Pumps the Read tab with [notes] until the reader view is showing.
  Future<FakeEpubReaderSession> openBook(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLoremarkTheme(),
        home: Scaffold(
          body: ReadScreen(
            book: book,
            readerService: readerService,
            openPositionStore: () async => FakeReadingPositionStore(),
            notes: Future.value(notes),
            noteJumps: jumps,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return readerService.sessions.single;
  }

  /// Picks [command] from the menu over "a grey cat" in Chapter Two.
  Future<void> select(
    WidgetTester tester,
    FakeEpubReaderSession session,
    SelectionCommand command,
  ) async {
    session.emitChapter(FakeEpubReaderService.defaultToc[2]);
    session.select(
      PassageSelection(
        command: command,
        sectionIndex: 4,
        progression: 0.3,
        text: 'a grey cat',
        before: 'There was ',
        after: ' on the wall',
      ),
    );
    await tester.idle();
    await tester.pumpAndSettle();
  }

  Future<Note> addSavedNote() => notes.addNote(
    anchor: const NoteAnchor(4, 0.3),
    chapterLabel: 'Chapter Two',
    selectedText: 'a grey cat',
    textBefore: 'There was ',
    body: 'Whose cat?',
  );

  testWidgets('draws the saved notes when the book opens', (tester) async {
    final note = await addSavedNote();

    final session = await openBook(tester);

    final drawn = session.shownNoteHighlights.last.single;
    expect(drawn.id, note.id);
    expect(drawn.target.highlight, 'a grey cat');
    expect(drawn.target.before, 'There was ');
    expect(drawn.target.sectionIndex, 4);
  });

  testWidgets('Highlight saves the selection in the current chapter', (
    tester,
  ) async {
    final session = await openBook(tester);

    await select(tester, session, SelectionCommand.highlight);

    final saved = notes.notes.single;
    expect(saved.isHighlightOnly, isTrue);
    expect(saved.selectedText, 'a grey cat');
    expect(saved.textBefore, 'There was ');
    expect(saved.textAfter, ' on the wall');
    expect(saved.chapterLabel, 'Chapter Two');
    expect(saved.anchor, const NoteAnchor(4, 0.3));
    expect(session.shownNoteHighlights.last.single.id, saved.id);
  });

  testWidgets('Add note saves what the reader typed', (tester) async {
    final session = await openBook(tester);

    await select(tester, session, SelectionCommand.addNote);
    expect(find.text('a grey cat'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Whose cat?');
    await tester.tap(find.text('Save note'));
    await tester.pumpAndSettle();

    expect(notes.notes.single.body, 'Whose cat?');
    expect(notes.notes.single.chapterLabel, 'Chapter Two');
  });

  testWidgets('closing the note sheet saves nothing', (tester) async {
    final session = await openBook(tester);

    await select(tester, session, SelectionCommand.addNote);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(notes.notes, isEmpty);
  });

  testWidgets('Copy puts the selection on the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final session = await openBook(tester);

    await select(tester, session, SelectionCommand.copy);

    expect(copied, 'a grey cat');
    expect(notes.notes, isEmpty);
  });

  testWidgets('tapping a highlight opens its note to edit', (tester) async {
    final note = await addSavedNote();
    final session = await openBook(tester);

    session.tapHighlight(note.id);
    await tester.idle();
    await tester.pumpAndSettle();
    expect(find.text('Edit note'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'A stray.');
    await tester.tap(find.text('Save note'));
    await tester.pumpAndSettle();

    expect(notes.notes.single.body, 'A stray.');
  });

  testWidgets('Remove highlight takes a highlight off the page', (
    tester,
  ) async {
    final highlight = await notes.addHighlight(
      anchor: const NoteAnchor(4, 0.3),
      chapterLabel: 'Chapter Two',
      selectedText: 'a grey cat',
      textBefore: 'There was ',
    );
    final session = await openBook(tester);

    session.tapHighlight(highlight.id);
    await tester.idle();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove highlight'));
    await tester.pumpAndSettle();

    expect(find.text('Delete this note?'), findsNothing);
    expect(notes.notes, isEmpty);
    expect(session.shownNoteHighlights.last, isEmpty);
  });

  testWidgets('Delete note asks first, and Cancel keeps the note', (
    tester,
  ) async {
    final note = await addSavedNote();
    final session = await openBook(tester);

    session.tapHighlight(note.id);
    await tester.idle();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete note'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this note?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(notes.notes.single.id, note.id);
    expect(session.shownNoteHighlights.last.single.id, note.id);

    session.tapHighlight(note.id);
    await tester.idle();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete note'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(notes.notes, isEmpty);
    expect(session.shownNoteHighlights.last, isEmpty);
  });

  testWidgets('a deleted note is taken off the page', (tester) async {
    final note = await addSavedNote();
    final session = await openBook(tester);

    await notes.deleteNote(note.id);
    await tester.pump();

    expect(session.shownNoteHighlights.last, isEmpty);
  });

  testWidgets('jumping to a note shows its passage', (tester) async {
    final note = await addSavedNote();
    final session = await openBook(tester);

    await jumps.show(note);
    await tester.pump();

    final shown = session.shownPassages.single;
    expect(shown.highlight, 'a grey cat');
    expect(shown.before, 'There was ');
    expect(shown.sectionIndex, 4);
  });
}
