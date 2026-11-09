import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/book_screen.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/notes/annotation_service.dart';
import 'package:loremark/notes/note.dart';
import 'package:loremark/notes/theory.dart';
import 'package:loremark/settings/ai_settings.dart';
import 'package:loremark/settings/connection_status.dart';
import 'package:loremark/theme/loremark_theme.dart';
import 'package:loremark/theories/theory_checker.dart';

import '../notes/in_memory_note_repository.dart';

/// A checker that never calls anything and reports the changes a test sends.
class _ScriptedChecker extends TheoryChecker {
  _ScriptedChecker(AnnotationService notes)
    : super(
        annotations: notes,
        loadSectionTexts: () async => const [],
        credentials: () => null,
        isOnline: () => false,
      );

  final controller = StreamController<TheoryStatusChange>.broadcast();

  @override
  Stream<TheoryStatusChange> get changes => controller.stream;
}

void main() {
  final book = Book(
    id: 'abc',
    title: 'The Glass Harbor',
    author: null,
    epubPath: 'unused.epub',
    coverPath: null,
    importedAt: DateTime(2026),
  );

  testWidgets('the banner opens the Notes tab on the theory', (tester) async {
    final settings = AiSettings(
      MemorySecretStore({'ai_onboarding_seen': 'true'}),
    );
    await settings.load();
    final theory = Note(
      id: 'theory-1',
      bookId: 'abc',
      anchor: const NoteAnchor(3, 0.5),
      chapterLabel: 'Chapter 4',
      selectedText: 'The lights went out.',
      body: 'Mara is the thief',
      color: HighlightColor.yellow,
      kind: NoteKind.theory,
      theory: const TheoryState(),
      createdAt: DateTime.utc(2026, 11),
      updatedAt: DateTime.utc(2026, 11),
    );
    final notes = AnnotationService(
      bookId: 'abc',
      repository: InMemoryNoteRepository()..saved = [theory],
    );
    await notes.load();
    late _ScriptedChecker checker;
    await tester.pumpWidget(
      AiSettingsScope(
        settings: settings,
        child: ConnectionScope(
          status: ConnectionStatus(),
          child: MaterialApp(
            theme: buildLoremarkTheme(),
            home: BookScreen(
              book: book,
              openNotes: (_) async => notes,
              checkerFactory: (notes) => checker = _ScriptedChecker(notes),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // The checker is only made once the notes have opened.
    expect(() => checker, returnsNormally);
    checker.controller.add(
      const TheoryStatusChange(
        noteId: 'theory-1',
        body: 'Mara is the thief',
        from: TheoryStatus.unconfirmed,
        to: TheoryStatus.confirmed,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Theory confirmed: "Mara is the thief"'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);

    // Pressed directly: a tap on the button did not hit it in the test
    // (cause not found), but what the button does is what is checked here.
    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
    await tester.pumpAndSettle();

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 2, reason: 'the Notes tab');
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Notes'),
      ),
      findsOneWidget,
    );
    expect(find.text('Mara is the thief'), findsOneWidget);
    expect(find.text('Unconfirmed'), findsOneWidget);
  });
}
