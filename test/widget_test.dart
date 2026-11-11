import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/book_screen.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/settings/ai_settings.dart';
import 'package:loremark/settings/connection_status.dart';
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

  Future<void> pumpBook(
    WidgetTester tester, {
    bool hasKey = true,
    ConnectionStatus? connection,
  }) async {
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
        child: ConnectionScope(
          status: connection ?? ConnectionStatus(),
          child: MaterialApp(
            theme: buildLoremarkTheme(),
            home: BookScreen(book: book),
          ),
        ),
      ),
    );
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
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

  group('tabs have no tooltip repeating their label', () {
    testWidgets('when hovered', (tester) async {
      await pumpBook(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);

      for (final label in tabs) {
        final shown = find.text(label).evaluate().length;
        final tab = find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        );
        await mouse.moveTo(tester.getCenter(tab));
        await tester.pump(const Duration(seconds: 1));

        expect(find.text(label), findsNWidgets(shown), reason: label);
      }
    });

    testWidgets('when long pressed', (tester) async {
      await pumpBook(tester);

      for (final label in tabs) {
        final shown = find.text(label).evaluate().length;
        final tab = find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        );
        final press = await tester.startGesture(tester.getCenter(tab));
        await tester.pump(const Duration(seconds: 1));

        expect(find.text(label), findsNWidgets(shown), reason: label);
        await press.cancel();
        await tester.pump(const Duration(seconds: 3));
      }
    });
  });

  testWidgets('the page never drops below where it rests as the keyboard '
      'goes', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    // An iPhone's home indicator, which the keyboard covers when it's up.
    void keyboard(double height) {
      tester.view.viewInsets = FakeViewPadding(bottom: height);
      tester.view.padding = FakeViewPadding(bottom: (34 - height).clamp(0, 34));
    }

    keyboard(0);
    await pumpBook(tester);
    await openTab(tester, 'Ask');
    final input = find.byKey(const ValueKey('ask-input'));
    final rest = tester.getBottomLeft(input).dy;

    for (var height = 300.0; height >= 0; height -= 30) {
      keyboard(height);
      await tester.pump();
      expect(
        tester.getBottomLeft(input).dy,
        lessThanOrEqualTo(rest),
        reason: 'with the keyboard $height high',
      );
    }
    expect(tester.getBottomLeft(input).dy, rest);
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

  testWidgets('without an API key, Ask is locked but Story Map opens', (
    tester,
  ) async {
    await pumpBook(tester, hasKey: false);

    await openTab(tester, 'Ask');
    expect(find.text('Ask needs an API key'), findsOne);
    expect(find.textContaining('Ask uses an AI model'), findsOne);

    await openTab(tester, 'Story Map');
    expect(find.text('Story Map needs an API key'), findsNothing);
    expect(find.byTooltip('Story Map files'), findsOne);
  });

  testWidgets('with an API key, nothing is locked', (tester) async {
    await pumpBook(tester);

    expect(find.textContaining('needs an API key'), findsNothing);
  });

  group('offline', () {
    testWidgets('locks Ask but not Story Map', (tester) async {
      await pumpBook(tester, connection: ConnectionStatus(online: false));

      await openTab(tester, 'Ask');
      expect(find.text('Ask needs a connection'), findsOne);

      await openTab(tester, 'Story Map');
      expect(find.textContaining('needs a connection'), findsNothing);
    });

    testWidgets('a missing key is shown before the connection', (tester) async {
      await pumpBook(
        tester,
        hasKey: false,
        connection: ConnectionStatus(online: false),
      );

      await openTab(tester, 'Ask');
      expect(find.text('Ask needs an API key'), findsOne);
      expect(find.textContaining('needs a connection'), findsNothing);
    });

    testWidgets('Ask unlocks when the connection comes back', (tester) async {
      final connection = ConnectionStatus(online: false);
      await pumpBook(tester, connection: connection);
      await openTab(tester, 'Ask');

      connection.isOnline = true;
      await tester.pumpAndSettle();

      expect(find.textContaining('needs a connection'), findsNothing);
    });

    testWidgets('the banner can be dismissed; the header chip stays', (
      tester,
    ) async {
      final connection = ConnectionStatus(online: false);
      await pumpBook(tester, connection: connection);

      expect(connection.showOfflineBanner, isTrue);
      expect(find.text('OFFLINE'), findsOne);

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();

      expect(connection.showOfflineBanner, isFalse);
      expect(find.text('OFFLINE'), findsOne);
    });

    testWidgets('going offline again brings the banner back', (tester) async {
      final connection = ConnectionStatus(online: false)
        ..dismissOfflineBanner();
      await pumpBook(tester, connection: connection);

      connection
        ..isOnline = true
        ..isOnline = false;
      await tester.pumpAndSettle();

      expect(connection.showOfflineBanner, isTrue);
    });

    testWidgets('online shows no banner or chip', (tester) async {
      final connection = ConnectionStatus();
      await pumpBook(tester, connection: connection);

      expect(connection.showOfflineBanner, isFalse);
      expect(find.text('OFFLINE'), findsNothing);
    });
  });
}
