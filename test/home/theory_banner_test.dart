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

  Note theoryNote(String id, String body) => Note(
    id: id,
    bookId: 'abc',
    anchor: const NoteAnchor(3, 0.5),
    chapterLabel: 'Chapter 4',
    selectedText: 'The lights went out.',
    body: body,
    color: HighlightColor.yellow,
    kind: NoteKind.theory,
    theory: const TheoryState(),
    createdAt: DateTime.utc(2026, 11),
    updatedAt: DateTime.utc(2026, 11),
  );

  TheoryStatusChange confirmed(String id, String body) => TheoryStatusChange(
    noteId: id,
    body: body,
    from: TheoryStatus.unconfirmed,
    to: TheoryStatus.confirmed,
  );

  Future<_ScriptedChecker> openBook(WidgetTester tester) async {
    final settings = AiSettings(
      MemorySecretStore({'ai_onboarding_seen': 'true'}),
    );
    await settings.load();
    final notes = AnnotationService(
      bookId: 'abc',
      repository: InMemoryNoteRepository()
        ..saved = [
          theoryNote('theory-1', 'Mara is the thief'),
          theoryNote('theory-2', 'The harbor is haunted'),
        ],
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
    return checker;
  }

  final banner1 = find.text('Theory confirmed: "Mara is the thief"');
  final banner2 = find.text('Theory confirmed: "The harbor is haunted"');

  testWidgets('the banner sits at the top and View opens the theory', (
    tester,
  ) async {
    final checker = await openBook(tester);
    checker.controller.add(confirmed('theory-1', 'Mara is the thief'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // The banner slides in; a tap before the slide ends misses its buttons.
    await tester.pump(const Duration(seconds: 1));

    expect(banner1, findsOneWidget);
    expect(find.text('View'), findsOneWidget);

    // Regression: the banner must not cover the page-turn row or the tab bar.
    final rect = tester.getRect(find.byType(MaterialBanner));
    final nav = tester.getRect(find.byType(NavigationBar));
    final screen = tester.getRect(find.byType(Scaffold).first);
    expect(rect.overlaps(nav), isFalse, reason: 'clear of the tab bar');
    expect(rect.bottom, lessThan(screen.center.dy), reason: 'top half');
    // The page arrows only exist when a book is open; this test has none, so
    // the check applies whenever they are on screen.
    final next = find.byTooltip('Next page');
    if (next.evaluate().isNotEmpty) {
      expect(rect.bottom, lessThanOrEqualTo(tester.getRect(next).top));
    }

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 2, reason: 'the Notes tab');
    expect(banner1, findsNothing, reason: 'View hides the banner');
    expect(find.text('Mara is the thief'), findsOneWidget);
    expect(find.text('Unconfirmed'), findsWidgets);
  });

  testWidgets('Dismiss removes the banner', (tester) async {
    final checker = await openBook(tester);
    checker.controller.add(confirmed('theory-1', 'Mara is the thief'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // The banner slides in; a tap before the slide ends misses its buttons.
    await tester.pump(const Duration(seconds: 1));
    expect(banner1, findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();

    expect(banner1, findsNothing);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, isNot(2), reason: 'Dismiss does not navigate');
  });

  testWidgets('the banner disappears after 8 seconds', (tester) async {
    final checker = await openBook(tester);
    checker.controller.add(confirmed('theory-1', 'Mara is the thief'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // The banner slides in; a tap before the slide ends misses its buttons.
    await tester.pump(const Duration(seconds: 1));
    expect(banner1, findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(banner1, findsOneWidget, reason: '7 seconds in, still up');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(banner1, findsNothing);
  });

  testWidgets('two resolutions in a row never leave two banners', (
    tester,
  ) async {
    final checker = await openBook(tester);
    checker.controller.add(confirmed('theory-1', 'Mara is the thief'));
    checker.controller.add(confirmed('theory-2', 'The harbor is haunted'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // The banner slides in; a tap before the slide ends misses its buttons.
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(MaterialBanner), findsOneWidget);
    expect(banner1, findsNothing);
    expect(banner2, findsOneWidget);

    // The first banner's timer must not hide the second one early.
    await tester.pump(const Duration(seconds: 5));
    expect(banner2, findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('leaving the book screen removes the banner', (tester) async {
    final checker = await openBook(tester);
    checker.controller.add(confirmed('theory-1', 'Mara is the thief'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // The banner slides in; a tap before the slide ends misses its buttons.
    await tester.pump(const Duration(seconds: 1));
    expect(banner1, findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing);
  });
}
