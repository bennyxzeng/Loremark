import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/notes/add_note_sheet.dart';
import 'package:loremark/notes/annotation_service.dart';
import 'package:loremark/notes/note.dart';
import 'package:loremark/notes/note_passage.dart';
import 'package:loremark/notes/notes_screen.dart';

import 'in_memory_note_repository.dart';

void main() {
  late AnnotationService service;

  setUp(() async {
    service = AnnotationService(
      bookId: 'glass-harbor',
      repository: InMemoryNoteRepository(),
    );
    await service.load();
  });

  Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

  Future<void> addNote(
    String body, {
    NoteAnchor anchor = const NoteAnchor(7, 0.2),
    String chapter = 'Chapter 8',
    HighlightColor color = HighlightColor.yellow,
  }) => service.addNote(
    anchor: anchor,
    chapterLabel: chapter,
    selectedText: 'Passage for $body',
    body: body,
    color: color,
  );

  group('Add note sheet', () {
    // Opens the sheet and returns a getter for what it returned once closed.
    Future<AddNoteResult? Function()> openSheet(WidgetTester tester) async {
      AddNoteResult? result;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showAddNoteSheet(
                  context,
                  selectedText: 'You’re my sister, Mara.',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return () => result;
    }

    testWidgets('does not save an empty note and stays open', (tester) async {
      await openSheet(tester);

      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();

      expect(
        find.text('Your note is empty. Type something to save it.'),
        findsOneWidget,
      );
      expect(find.text('Save note'), findsOneWidget);
    });

    testWidgets('returns the typed note and the picked color', (tester) async {
      final result = await openSheet(tester);

      expect(find.text('You’re my sister, Mara.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'She knew.');
      await tester.tap(find.byTooltip('Blue'));
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();

      final saved = result();
      expect(saved?.body, 'She knew.');
      expect(saved?.color, HighlightColor.blue);
    });
  });

  group('Notes tab', () {
    testWidgets('shows an empty state when there are no notes', (tester) async {
      await tester.pumpWidget(app(NotesScreen(service: service)));

      expect(find.textContaining('No notes yet'), findsOneWidget);
    });

    testWidgets('lists notes under their chapter in reading order', (
      tester,
    ) async {
      await addNote('Later note', anchor: const NoteAnchor(7, 0.9));
      await addNote(
        'Early note',
        anchor: const NoteAnchor(2, 0.1),
        chapter: 'Chapter 3',
      );

      await tester.pumpWidget(app(NotesScreen(service: service)));

      final chapter3 = tester.getTopLeft(find.text('Chapter 3')).dy;
      final early = tester.getTopLeft(find.text('Early note')).dy;
      final chapter8 = tester.getTopLeft(find.text('Chapter 8')).dy;
      final later = tester.getTopLeft(find.text('Later note')).dy;
      expect(chapter3 < early && early < chapter8 && chapter8 < later, isTrue);
    });

    testWidgets('search hides notes that do not match', (tester) async {
      await addNote('Mara hides the letter');
      await addNote('Elian is nervous');
      await tester.pumpWidget(app(NotesScreen(service: service)));

      await tester.enterText(find.byType(TextField), 'elian');
      await tester.pump();

      expect(find.text('Elian is nervous'), findsOneWidget);
      expect(find.text('Mara hides the letter'), findsNothing);
    });

    testWidgets('color filter shows only notes of that color', (tester) async {
      await addNote('Yellow note');
      await addNote('Pink note', color: HighlightColor.pink);
      await tester.pumpWidget(app(NotesScreen(service: service)));

      await tester.tap(find.widgetWithText(FilterChip, 'Pink'));
      await tester.pump();

      expect(find.text('Pink note'), findsOneWidget);
      expect(find.text('Yellow note'), findsNothing);
    });

    testWidgets('delete asks for confirmation before deleting', (tester) async {
      await addNote('Delete me');
      await tester.pumpWidget(app(NotesScreen(service: service)));

      await tester.tap(find.byTooltip('Note options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete this note?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.notes, hasLength(1));

      await tester.tap(find.byTooltip('Note options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(service.notes, isEmpty);
      expect(find.text('Delete me'), findsNothing);
    });

    testWidgets('edit changes the note text', (tester) async {
      await addNote('Old text');
      await tester.pumpWidget(app(NotesScreen(service: service)));

      await tester.tap(find.byTooltip('Note options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'New text');
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();

      expect(service.notes.single.body, 'New text');
      expect(find.text('New text'), findsOneWidget);
    });

    testWidgets('tapping a note opens it in the reader', (tester) async {
      await addNote('Open me');
      Note? opened;
      await tester.pumpWidget(
        app(NotesScreen(service: service, onOpenNote: (note) => opened = note)),
      );

      await tester.tap(find.text('Open me'));

      expect(opened?.body, 'Open me');
    });
  });

  group('Read passage', () {
    const passage = 'He pushed the letter across the table.';

    Widget passageApp() => app(
      NotePassage(
        service: service,
        text: passage,
        sectionIndex: 7,
        chapterLabel: 'Chapter 8',
      ),
    );

    Future<void> selectWord(WidgetTester tester) async {
      await tester.pumpWidget(passageApp());
      await tester.longPress(find.byType(SelectableText));
      await tester.pumpAndSettle();
    }

    testWidgets('selecting text offers Highlight and Add note', (tester) async {
      await selectWord(tester);

      expect(find.text('Highlight'), findsOneWidget);
      expect(find.text('Add note'), findsOneWidget);
    });

    testWidgets('Highlight saves a highlight on the selected words', (
      tester,
    ) async {
      await selectWord(tester);

      await tester.tap(find.text('Highlight'));
      await tester.pumpAndSettle();

      final highlight = service.notes.single;
      expect(highlight.isHighlightOnly, isTrue);
      expect(passage, contains(highlight.selectedText));
      expect(highlight.anchor.sectionIndex, 7);
      expect(highlight.chapterLabel, 'Chapter 8');
    });

    testWidgets('Add note saves a note and marks the passage', (tester) async {
      await selectWord(tester);

      await tester.tap(find.text('Add note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Suspicious.');
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();

      expect(service.notes.single.body, 'Suspicious.');
      expect(find.byIcon(Icons.sticky_note_2_outlined), findsOneWidget);
    });
  });
}
