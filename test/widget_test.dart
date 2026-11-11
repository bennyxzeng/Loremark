import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/book_screen.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/settings/ai_settings.dart';
import 'package:loremark/settings/connection_status.dart';
import 'package:loremark/story_map/story_map_backend.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/story_update/story_model_choice.dart';
import 'package:loremark/story_update/story_updater.dart';
import 'package:loremark/theme/loremark_theme.dart';

/// A book with no Story Map yet, whose updates wait for [finish], section by
/// section.
class _StoryMapBackend implements StoryMapBackend {
  Completer<StoryUpdateOutcome>? finish;

  @override
  Future<StoryModel?> loadModel(Book book) async => null;

  @override
  Future<StoryUpdateStatus> inspect(Book book) async =>
      const StoryUpdateStatus.ready(
        's3',
        'Chapter 3',
        choices: [
          StorySectionChoice('s3', 'Chapter 3', 40),
          StorySectionChoice('s4', 'Chapter 4', 40),
          StorySectionChoice('s5', 'Chapter 5', 40),
        ],
      );

  @override
  RunningStoryBatch? running(Book book) => null;

  @override
  Future<RunningStoryBatch> update(
    Book book, {
    required AiCredentials credentials,
    required StoryModelChoice model,
    required StoryEffort effort,
    required bool checkQuotes,
    required List<StorySectionChoice> sections,
  }) async =>
      RunningStoryBatch(sections, (section) => (finish = Completer()).future);

  @override
  void cancelUpdate(Book book) {}

  @override
  Future<bool> introSeen() async => true;

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
    StoryMapBackend? storyMapBackend,
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
            home: BookScreen(book: book, storyMapBackend: storyMapBackend),
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

  group('a Story Map update', () {
    late _StoryMapBackend backend;

    setUp(() => backend = _StoryMapBackend());

    /// Starts an update from the Story Map tab, then goes to [tab].
    Future<void> startUpdate(WidgetTester tester, {String tab = 'Read'}) async {
      await openTab(tester, 'Story Map');
      await tester.tap(find.widgetWithText(FilledButton, 'Update'));
      await tester.pumpAndSettle();
      await openTab(tester, tab);
    }

    Future<void> finish(WidgetTester tester, StoryUpdateOutcome outcome) async {
      backend.finish!.complete(outcome);
      await tester.pumpAndSettle();
    }

    const added = StoryUpdateOutcome('committed', sectionTitle: 'Chapter 3');

    /// The update banner's card, by its title.
    Finder banner(String title) => find
        .ancestor(of: find.text(title), matching: find.byType(Material))
        .first;

    bool shown(WidgetTester tester, String title) =>
        find.text(title).evaluate().isNotEmpty &&
        tester
                .widget<AnimatedOpacity>(
                  find
                      .ancestor(
                        of: find.text(title),
                        matching: find.byType(AnimatedOpacity),
                      )
                      .first,
                )
                .opacity ==
            1;

    testWidgets('shows in the header from every tab', (tester) async {
      await pumpBook(tester, storyMapBackend: backend);
      await startUpdate(tester, tab: 'Notes');
      expect(find.text('UPDATING'), findsOne);

      await finish(tester, added);
      expect(find.text('UPDATING'), findsNothing);
    });

    testWidgets('that ends on another tab says so at the top', (tester) async {
      await pumpBook(tester, storyMapBackend: backend);
      await startUpdate(tester);
      await finish(tester, added);
      expect(shown(tester, 'Story Map updated'), isTrue);
      expect(find.text('Added Chapter 3.'), findsOne);

      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 3);
      expect(shown(tester, 'Story Map updated'), isFalse);
    });

    testWidgets('says so for a while, or until closed', (tester) async {
      await pumpBook(tester, storyMapBackend: backend);
      await startUpdate(tester);
      await finish(tester, added);
      await tester.pump(const Duration(seconds: 5));
      expect(shown(tester, 'Story Map updated'), isTrue);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(shown(tester, 'Story Map updated'), isFalse);

      await startUpdate(tester);
      await finish(tester, added);
      expect(shown(tester, 'Story Map updated'), isTrue);
      await tester.tap(
        find.descendant(
          of: banner('Story Map updated'),
          matching: find.byTooltip('Dismiss'),
        ),
      );
      await tester.pumpAndSettle();
      expect(shown(tester, 'Story Map updated'), isFalse);
      expect(selectedTab(tester), 0);
    });

    testWidgets('that fails says so too', (tester) async {
      await pumpBook(tester, storyMapBackend: backend);
      await startUpdate(tester);
      await finish(
        tester,
        const StoryUpdateOutcome('api_error', category: 'timeout'),
      );
      expect(shown(tester, 'The Story Map update didn’t go through'), isTrue);
      expect(find.text('See the Story Map for why.'), findsOne);
    });

    testWidgets('of several sections says so once, at the end', (tester) async {
      await pumpBook(tester, storyMapBackend: backend);
      await openTab(tester, 'Story Map');
      await tester.tap(find.widgetWithText(TextButton, 'Choose'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select all main text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add 3 sections'));
      await tester.pumpAndSettle();
      await openTab(tester, 'Read');
      expect(find.text('1/3'), findsOne);

      await finish(tester, added);
      expect(find.text('2/3'), findsOne);
      expect(find.text('Story Map updated'), findsNothing);

      await finish(tester, const StoryUpdateOutcome('schema_invalid'));
      expect(find.text('UPDATING'), findsNothing);
      expect(shown(tester, 'Story Map update stopped'), isTrue);
      expect(
        find.text(
          'Added 1 of 3 sections. Chapter 4 didn’t go through. See the Story '
          'Map for why.',
        ),
        findsOne,
      );
    });

    testWidgets('that ends on the Story Map tab needs no banner', (
      tester,
    ) async {
      await pumpBook(tester, storyMapBackend: backend);
      await startUpdate(tester, tab: 'Story Map');
      await finish(tester, added);
      expect(find.text('Story Map updated'), findsNothing);
      expect(find.textContaining('Added Chapter 3 in '), findsOne);
    });

    testWidgets('that was cancelled needs no banner', (tester) async {
      await pumpBook(tester, storyMapBackend: backend);
      await startUpdate(tester, tab: 'Story Map');
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel update'));
      await tester.pumpAndSettle();
      await openTab(tester, 'Read');
      await finish(
        tester,
        const StoryUpdateOutcome('cancelled', category: 'cancelled'),
      );
      expect(find.text('Story Map updated'), findsNothing);
      expect(find.text('The Story Map update didn’t go through'), findsNothing);
    });

    testWidgets('goes under the offline banner, and up when it goes', (
      tester,
    ) async {
      final connection = ConnectionStatus();
      await pumpBook(tester, storyMapBackend: backend, connection: connection);
      await startUpdate(tester);
      connection.isOnline = false;
      await tester.pumpAndSettle();
      await finish(
        tester,
        const StoryUpdateOutcome('api_error', category: 'network'),
      );
      const failed = 'The Story Map update didn’t go through';
      final offline = banner('You’re offline');
      expect(
        tester.getRect(banner(failed)).top,
        greaterThanOrEqualTo(tester.getRect(offline).bottom),
      );
      final under = tester.getRect(banner(failed)).top;

      await tester.tap(
        find.descendant(of: offline, matching: find.byTooltip('Dismiss')),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(banner(failed)).top, lessThan(under));
      expect(shown(tester, failed), isTrue);
    });
  });
}
