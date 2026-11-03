import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/book_screen.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/settings/ai_settings.dart';
import 'package:loremark/theme/loremark_theme.dart';

// Smoke tests for an open book's tabs. They only check navigation, not the
// placeholder screen content, so they keep passing as each screen is built.
void main() {
  const tabs = ['Read', 'Ask', 'Notes', 'Story Map'];
  final book = Book(
    id: 'abc',
    title: 'The Glass Harbor',
    author: null,
    epubPath: 'unused.epub',
    coverPath: null,
    importedAt: DateTime(2026),
  );

  Future<void> pumpBook(WidgetTester tester, {bool hasKey = true}) async {
    final settings = AiSettings(
      MemorySecretStore({
        'ai_onboarding_seen': 'true',
        if (hasKey) ...{'ai_provider': 'openai', 'ai_api_key': 'sk-test'},
      }),
    );
    await settings.load();
    await tester.pumpWidget(
      AiSettingsScope(
        settings: settings,
        child: MaterialApp(
          theme: buildLoremarkTheme(),
          home: BookScreen(book: book),
        ),
      ),
    );
  }

  int selectedTab(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  testWidgets('shows a tab for each main feature', (tester) async {
    await pumpBook(tester);

    for (final label in tabs) {
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
    await pumpBook(tester);

    expect(selectedTab(tester), 0);
  });

  testWidgets('tapping a tab selects it', (tester) async {
    await pumpBook(tester);

    for (final (index, label) in tabs.indexed.toList().reversed) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();

      expect(selectedTab(tester), index, reason: label);
    }
  });

  testWidgets('without an API key, Ask and Story Map are locked', (
    tester,
  ) async {
    await pumpBook(tester, hasKey: false);

    for (final label in ['Ask', 'Story Map']) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('$label needs an API key'), findsOne, reason: label);
    }
  });

  testWidgets('with an API key, nothing is locked', (tester) async {
    await pumpBook(tester);

    expect(find.textContaining('needs an API key'), findsNothing);
  });
}
