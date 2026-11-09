import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/notes_screen.dart';
import 'package:loremark/notes/add_note_sheet.dart';
import 'package:loremark/notes/annotation_service.dart';
import 'package:loremark/notes/note.dart';
import 'package:loremark/notes/note_list.dart';
import 'package:loremark/notes/theory.dart';

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

  Future<Note> addTheory(
    String body, {
    String? dependsOnId,
    NoteAnchor anchor = const NoteAnchor(3, 0.5),
    String chapter = 'Chapter 4',
  }) => service.addNote(
    anchor: anchor,
    chapterLabel: chapter,
    selectedText: 'Passage for $body',
    body: body,
    kind: NoteKind.theory,
    dependsOnId: dependsOnId,
  );

  group('Note sheet', () {
    // Opens the sheet and returns a getter for what it returned once closed.
    Future<NoteSheetResult? Function()> openSheet(
      WidgetTester tester, {
      List<Note> olderTheories = const [],
      NoteKind initialKind = NoteKind.personalNote,
      String? initialDependsOnId,
    }) async {
      NoteSheetResult? result;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showAddNoteSheet(
                  context,
                  selectedText: 'The lights went out.',
                  olderTheories: olderTheories,
                  initialKind: initialKind,
                  initialDependsOnId: initialDependsOnId,
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

    testWidgets('defaults to a personal note', (tester) async {
      final result = await openSheet(tester);

      await tester.enterText(find.byType(TextField), 'Just a thought');
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();

      final saved = result() as AddNoteResult;
      expect(saved.kind, NoteKind.personalNote);
      expect(saved.dependsOnId, isNull);
    });

    testWidgets('lets the reader choose Theory', (tester) async {
      final result = await openSheet(tester);

      expect(find.text('Personal note'), findsOneWidget);
      await tester.tap(find.text('Theory'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Mara cut the power.');
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();

      final saved = result() as AddNoteResult;
      expect(saved.kind, NoteKind.theory);
      expect(saved.body, 'Mara cut the power.');
      expect(saved.dependsOnId, isNull);
    });

    testWidgets('has no Builds on picker without older theories', (
      tester,
    ) async {
      await openSheet(tester);

      await tester.tap(find.text('Theory'));
      await tester.pumpAndSettle();

      expect(find.text('Builds on'), findsNothing);
    });

    testWidgets('offers older theories under Theory only', (tester) async {
      final older = await addTheory('Mara cut the power.');
      await openSheet(tester, olderTheories: [older]);

      expect(find.text('Builds on'), findsNothing);
      await tester.tap(find.text('Theory'));
      await tester.pumpAndSettle();

      expect(find.text('Builds on'), findsOneWidget);
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      expect(find.text('Mara cut the power.'), findsWidgets);
    });

    testWidgets('returns the older theory that was picked', (tester) async {
      final older = await addTheory('Mara cut the power.');
      final result = await openSheet(tester, olderTheories: [older]);

      await tester.tap(find.text('Theory'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mara cut the power.').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Elian helped her.');
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();

      final saved = result() as AddNoteResult;
      expect(saved.kind, NoteKind.theory);
      expect(saved.dependsOnId, older.id);
    });

    testWidgets('a personal note never returns a dependency', (tester) async {
      final older = await addTheory('Mara cut the power.');
      final result = await openSheet(
        tester,
        olderTheories: [older],
        initialKind: NoteKind.theory,
        initialDependsOnId: older.id,
      );

      await tester.tap(find.text('Personal note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Never mind.');
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();

      final saved = result() as AddNoteResult;
      expect(saved.kind, NoteKind.personalNote);
      expect(saved.dependsOnId, isNull);
    });

    testWidgets('shows the current kind and link when editing', (tester) async {
      final older = await addTheory('Mara cut the power.');
      await openSheet(
        tester,
        olderTheories: [older],
        initialKind: NoteKind.theory,
        initialDependsOnId: older.id,
      );

      final selected = tester
          .widget<SegmentedButton<NoteKind>>(
            find.byType(SegmentedButton<NoteKind>),
          )
          .selected;
      expect(selected, {NoteKind.theory});
      expect(find.text('Builds on'), findsOneWidget);
      expect(find.text('Mara cut the power.'), findsWidgets);
    });

    testWidgets('an empty theory stays open with the empty message', (
      tester,
    ) async {
      final result = await openSheet(tester);

      await tester.tap(find.text('Theory'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();

      expect(
        find.text('Your note is empty. Type something to save it.'),
        findsOneWidget,
      );
      expect(result(), isNull);
      expect(find.text('Save note'), findsOneWidget);
    });
  });

  group('Editing from the Notes tab', () {
    Future<void> openList(WidgetTester tester) async {
      await tester.pumpWidget(app(NoteList(service: service)));
      await tester.pumpAndSettle();
    }

    Future<void> editFirst(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Note options').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
    }

    testWidgets('a personal note can be turned into a theory', (tester) async {
      await service.addNote(
        anchor: const NoteAnchor(3, 0.5),
        chapterLabel: 'Chapter 4',
        selectedText: 'The lights went out.',
        body: 'Mara cut the power.',
      );
      await openList(tester);
      expect(find.text('Theory'), findsNothing);

      await editFirst(tester);
      await tester.tap(find.text('Theory'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();

      expect(service.notes.single.kind, NoteKind.theory);
      expect(find.text('Unconfirmed'), findsOneWidget);
    });

    testWidgets('a theory can change what it builds on and drop it', (
      tester,
    ) async {
      final first = await addTheory(
        'First theory',
        anchor: const NoteAnchor(1, 0.1),
        chapter: 'Chapter 2',
      );
      await addTheory('Second theory', dependsOnId: first.id);
      await openList(tester);
      expect(find.text('Builds on: First theory'), findsOneWidget);

      await tester.tap(find.byTooltip('Note options').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('First theory').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('None').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();

      expect(service.theories.last.theory!.dependsOnId, isNull);
      expect(find.textContaining('Builds on:'), findsNothing);
    });
  });

  group('Notes tab tile', () {
    Future<void> openList(
      WidgetTester tester, {
      NoteFocusController? focus,
    }) async {
      await tester.pumpWidget(
        app(NoteList(service: service, focusController: focus)),
      );
      await tester.pumpAndSettle();
    }

    SubTheory sub(
      String id,
      String text, [
      SubTheoryVerdict verdict = SubTheoryVerdict.open,
    ]) => SubTheory(
      id: id,
      text: text,
      verdict: verdict,
      evidence: verdict == SubTheoryVerdict.open
          ? null
          : const TheoryEvidence(
              sectionIndex: 8,
              chapterLabel: 'Chapter 9',
              quote: 'The key was in Mara’s coat.',
            ),
      resolvedAt: verdict == SubTheoryVerdict.open
          ? null
          : DateTime.utc(2026, 11, 3),
    );

    testWidgets('a theory shows the Theory tag and its status', (tester) async {
      await addTheory('Mara cut the power.');
      await openList(tester);

      expect(find.text('Theory'), findsOneWidget);
      expect(find.text('Unconfirmed'), findsOneWidget);
      expect(find.text('Mara cut the power.'), findsOneWidget);
    });

    testWidgets('a personal note shows no tag or status', (tester) async {
      await service.addNote(
        anchor: const NoteAnchor(3, 0.5),
        chapterLabel: 'Chapter 4',
        selectedText: 'The lights went out.',
        body: 'Just a thought',
      );
      await openList(tester);

      expect(find.text('Theory'), findsNothing);
      expect(find.text('Unconfirmed'), findsNothing);
    });

    testWidgets('shows the label of every status', (tester) async {
      final one = await addTheory('One', anchor: const NoteAnchor(1, 0));
      final two = await addTheory('Two', anchor: const NoteAnchor(2, 0));
      final three = await addTheory('Three', anchor: const NoteAnchor(3, 0));
      final four = await addTheory('Four', anchor: const NoteAnchor(4, 0));
      Future<void> set(Note note, List<SubTheory> subs) => service
          .updateTheory(note.id, (state) => state.copyWith(subTheories: subs))
          .then((_) {});
      await set(one, [sub('a', 'A', SubTheoryVerdict.confirmed)]);
      await set(two, [
        sub('b', 'B', SubTheoryVerdict.confirmed),
        sub('c', 'C'),
      ]);
      await set(three, [sub('d', 'D', SubTheoryVerdict.refuted)]);
      await service.editNote(four.id, dependsOnId: three.id);
      await openList(tester);

      expect(find.text(TheoryStatus.confirmed.label), findsOneWidget);
      expect(find.text(TheoryStatus.partiallyCorrect.label), findsOneWidget);
      expect(find.text(TheoryStatus.differentOutcome.label), findsOneWidget);
      expect(find.text(TheoryStatus.invalidated.label), findsOneWidget);
    });

    testWidgets('shows what a theory builds on', (tester) async {
      final older = await addTheory(
        'Mara cut the power.',
        anchor: const NoteAnchor(1, 0.1),
        chapter: 'Chapter 2',
      );
      await addTheory('Elian helped her.', dependsOnId: older.id);
      await openList(tester);

      expect(find.text('Builds on: Mara cut the power.'), findsOneWidget);
    });

    testWidgets('shows sub-theories with their verdicts and evidence', (
      tester,
    ) async {
      final theory = await addTheory('Mara has the key and cut the power.');
      await service.updateTheory(
        theory.id,
        (state) => state.copyWith(
          subTheories: [
            sub('a', 'Mara has the key', SubTheoryVerdict.confirmed),
            sub('b', 'Mara cut the power'),
          ],
        ),
      );
      await openList(tester);

      expect(find.text('Mara has the key (Confirmed)'), findsOneWidget);
      expect(find.text('Mara cut the power (Open)'), findsOneWidget);
      expect(
        find.text('“The key was in Mara’s coat.” (Chapter 9)'),
        findsOneWidget,
      );
      expect(find.text('Partially correct'), findsOneWidget);
    });

    testWidgets('tapping a theory still opens its passage', (tester) async {
      final theory = await addTheory('Mara cut the power.');
      Note? opened;
      await tester.pumpWidget(
        app(NoteList(service: service, onOpenNote: (note) => opened = note)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mara cut the power.'));

      expect(opened?.id, theory.id);
    });

    testWidgets('keeps the All, Notes and Highlights filter', (tester) async {
      await addTheory('Mara cut the power.');
      await service.addHighlight(
        anchor: const NoteAnchor(3, 0.9),
        chapterLabel: 'Chapter 4',
        selectedText: 'A quiet harbor',
      );
      await openList(tester);

      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      expect(find.text('Mara cut the power.'), findsOneWidget);
      expect(find.text('“A quiet harbor”'), findsNothing);

      await tester.tap(find.text('Highlights'));
      await tester.pumpAndSettle();
      expect(find.text('Mara cut the power.'), findsNothing);
    });

    testWidgets('scrolls to and outlines the focused note', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final focus = NoteFocusController();
      addTearDown(focus.dispose);
      for (var i = 0; i < 12; i++) {
        await addTheory(
          'Filler theory $i',
          anchor: NoteAnchor(i, 0),
          chapter: 'Chapter ${i + 1}',
        );
      }
      final target = await addTheory(
        'The target theory',
        anchor: const NoteAnchor(20, 0),
        chapter: 'Chapter 21',
      );
      await openList(tester, focus: focus);
      expect(
        tester.getTopLeft(find.text('The target theory')).dy,
        greaterThan(600),
      );

      focus.focus(target.id);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(
        tester.getTopLeft(find.text('The target theory')).dy,
        lessThan(600),
      );
      final card = tester.widget<Card>(
        find.ancestor(
          of: find.text('The target theory'),
          matching: find.byType(Card),
        ),
      );
      expect((card.shape as RoundedRectangleBorder).side.width, 2);

      await tester.pump(const Duration(seconds: 3));
      final after = tester.widget<Card>(
        find.ancestor(
          of: find.text('The target theory'),
          matching: find.byType(Card),
        ),
      );
      expect((after.shape as RoundedRectangleBorder).side, BorderSide.none);
    });

    testWidgets('focusing a note clears filters that would hide it', (
      tester,
    ) async {
      final focus = NoteFocusController();
      addTearDown(focus.dispose);
      final theory = await addTheory('Mara cut the power.');
      await service.addHighlight(
        anchor: const NoteAnchor(3, 0.9),
        chapterLabel: 'Chapter 4',
        selectedText: 'A quiet harbor',
      );
      await openList(tester, focus: focus);
      await tester.tap(find.text('Highlights'));
      await tester.pumpAndSettle();
      expect(find.text('Mara cut the power.'), findsNothing);

      focus.focus(theory.id);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.text('Mara cut the power.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a request made before the tab was built is not lost', (
      tester,
    ) async {
      final focus = NoteFocusController();
      addTearDown(focus.dispose);
      final theory = await addTheory('Mara cut the power.');
      focus.focus(theory.id);

      await tester.pumpWidget(
        app(NotesScreen(notes: Future.value(service), focusController: focus)),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(focus.takePending(), isNull);
      expect(find.text('Mara cut the power.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
