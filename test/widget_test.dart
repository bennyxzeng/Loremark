import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/main.dart';

void main() {
  testWidgets('shows a tab for each main feature', (tester) async {
    await tester.pumpWidget(const LoremarkApp());

    for (final label in ['Read', 'Ask', 'Notes', 'Story Map']) {
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: label,
      );
    }
  });

  testWidgets('opens on the Read tab', (tester) async {
    await tester.pumpWidget(const LoremarkApp());

    final navigationBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navigationBar.selectedIndex, 0);
  });

  testWidgets('tapping a tab shows its screen', (tester) async {
    const notesText = 'Your notes and theories will appear here.';
    await tester.pumpWidget(const LoremarkApp());
    expect(find.text(notesText), findsNothing);

    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();

    expect(find.text(notesText), findsOneWidget);
  });

  testWidgets('the recap button opens the Ask tab', (tester) async {
    await tester.pumpWidget(const LoremarkApp());

    await tester.tap(find.text('Recap where I left off'));
    await tester.pumpAndSettle();

    final navigationBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navigationBar.selectedIndex, 1);
  });
}
