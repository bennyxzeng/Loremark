import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/book_screen.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/recap/recap_backend.dart';
import 'package:loremark/recap/recap_client.dart';
import 'package:loremark/recap/recap_source.dart';
import 'package:loremark/settings/ai_settings.dart';
import 'package:loremark/settings/connection_status.dart';
import 'package:loremark/theme/loremark_theme.dart';

const _source = RecapSource(
  cutoffLabel: 'Chapter 1: Arrival',
  events: [],
  characters: [],
  openQuestions: [],
  sectionText: 'Mara walks along the quay.',
);

/// Says the reader finished [source], and writes a one-moment recap of it.
class _FakeRecapBackend implements RecapBackend {
  _FakeRecapBackend({this.source = _source});

  final RecapSource? source;
  final requests = <RecapSource>[];

  @override
  Future<RecapSource?> prepare(Book book) async => source;

  @override
  Future<RecapResult> recap(
    RecapSource source,
    AiCredentials credentials,
  ) async {
    requests.add(source);
    return RecapReady(
      Recap(
        items: const [
          RecapItem(
            title: 'Mara reaches the harbor.',
            summary: 'She comes looking for work.',
            chapter: 'Chapter 1',
          ),
        ],
        cutoffLabel: source.cutoffLabel,
        usedStoryMap: false,
      ),
    );
  }
}

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
    RecapBackend? recapBackend,
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
            home: BookScreen(book: book, recapBackend: recapBackend),
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

  group('welcome back', () {
    testWidgets('pops up over the book with where the reader stopped', (
      tester,
    ) async {
      final backend = _FakeRecapBackend();
      await pumpBook(tester, recapBackend: backend);
      await tester.pumpAndSettle();

      expect(selectedTab(tester), 0);
      expect(find.text('Welcome back.'), findsOne);
      expect(find.textContaining('you finished Chapter 1: Arrival'), findsOne);
      expect(backend.requests, isEmpty);
    });

    testWidgets('Catch me up opens Ask with the recap', (tester) async {
      final backend = _FakeRecapBackend();
      await pumpBook(tester, recapBackend: backend);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Catch me up'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back.'), findsNothing);
      expect(selectedTab(tester), 1);
      expect(backend.requests, [_source]);
      expect(find.text('Mara reaches the harbor.'), findsOne);

      await tester.tap(find.text('Back to the book →'));
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 0);
      expect(find.text('Welcome back.'), findsNothing);
    });

    testWidgets('Keep reading puts it away without a request', (tester) async {
      final backend = _FakeRecapBackend();
      await pumpBook(tester, recapBackend: backend);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Keep reading'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back.'), findsNothing);
      expect(selectedTab(tester), 0);
      expect(backend.requests, isEmpty);
    });

    testWidgets('tapping beside it is the same as Keep reading', (
      tester,
    ) async {
      final backend = _FakeRecapBackend();
      await pumpBook(tester, recapBackend: backend);
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back.'), findsNothing);
      expect(backend.requests, isEmpty);
    });

    testWidgets('comes once each time the book opens', (tester) async {
      await pumpBook(tester, recapBackend: _FakeRecapBackend());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep reading'));
      await tester.pumpAndSettle();

      // Opening Ask looks for the reader's place again.
      await openTab(tester, 'Ask');
      await openTab(tester, 'Read');

      expect(find.text('Welcome back.'), findsNothing);
    });

    testWidgets('waits until a section is finished', (tester) async {
      await pumpBook(tester, recapBackend: _FakeRecapBackend(source: null));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back.'), findsNothing);
    });

    testWidgets('isn’t offered without an API key', (tester) async {
      final backend = _FakeRecapBackend();
      await pumpBook(tester, hasKey: false, recapBackend: backend);
      await tester.pumpAndSettle();

      expect(find.text('Welcome back.'), findsNothing);
    });

    testWidgets('isn’t offered offline', (tester) async {
      await pumpBook(
        tester,
        connection: ConnectionStatus(online: false),
        recapBackend: _FakeRecapBackend(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Welcome back.'), findsNothing);
    });
  });
}
