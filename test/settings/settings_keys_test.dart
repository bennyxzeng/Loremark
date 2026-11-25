import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/settings/ai_activity.dart';
import 'package:loremark/settings/ai_settings.dart';
import 'package:loremark/settings/api_key_screen.dart';
import 'package:loremark/settings/settings_screen.dart';

void main() {
  late AiActivity activity;
  late AiSettings settings;
  late List<String> checked;

  setUp(() async {
    activity = AiActivity();
    checked = [];
    settings = AiSettings(
      MemorySecretStore({'ai_onboarding_seen': 'true'}),
      activity: activity,
      verify: (provider, key) async {
        checked.add(key);
        return KeyCheck.valid;
      },
    );
    await settings.load();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 5400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AiSettingsScope(
        settings: settings,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder rowOf(AiCredentials key) => find.byKey(ValueKey('ai-key-${key.id}'));

  Finder inRow(AiCredentials key, Finder finder) =>
      find.descendant(of: rowOf(key), matching: finder);

  TextButton useButton(WidgetTester tester, AiCredentials key) => tester
      .widget<TextButton>(inRow(key, find.widgetWithText(TextButton, 'Use')));

  Future<void> openMenu(WidgetTester tester, AiCredentials key) async {
    await tester.tap(find.byTooltip('More for ${key.label}'));
    await tester.pumpAndSettle();
  }

  PopupMenuItem<Object?> menuItem(WidgetTester tester, String text) =>
      tester.widget<PopupMenuItem<Object?>>(
        find.ancestor(
          of: find.text(text),
          matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
        ),
      );

  testWidgets('lists the keys and switches between them', (tester) async {
    final personal = await settings.add(
      AiProvider.openai,
      'sk-personal1111',
      name: 'Personal',
    );
    final work = await settings.add(AiProvider.deepseek, 'sk-work2222');
    await pumpSettings(tester);

    expect(find.text('Personal'), findsOne);
    expect(find.text('OpenAI · ••••••••1111'), findsOne);
    expect(inRow(work, find.text('In use')), findsOne);
    expect(find.text('Add another key (2 of 5)'), findsOne);

    await tester.tap(inRow(personal, find.text('Use')));
    await tester.pumpAndSettle();

    expect(settings.credentials?.id, personal.id);
    expect(inRow(personal, find.text('In use')), findsOne);
    expect(inRow(work, find.text('Use')), findsOne);
  });

  testWidgets('while a task runs, the key in use stays put', (tester) async {
    final personal = await settings.add(AiProvider.openai, 'sk-personal1111');
    final work = await settings.add(
      AiProvider.deepseek,
      'sk-work2222',
      name: 'Work',
    );
    await pumpSettings(tester);
    expect(find.textContaining('An AI task is running'), findsNothing);

    final end = activity.begin();
    await tester.pump();

    expect(find.textContaining('An AI task is running on “Work”'), findsOne);
    expect(useButton(tester, personal).onPressed, isNull);

    await openMenu(tester, work);
    expect(menuItem(tester, 'Remove').enabled, isFalse);
    expect(menuItem(tester, 'Rename').enabled, isTrue);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    // A key not in use can still go.
    await openMenu(tester, personal);
    expect(menuItem(tester, 'Remove').enabled, isTrue);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    end();
    await tester.pump();

    expect(find.textContaining('An AI task is running'), findsNothing);
    expect(useButton(tester, personal).onPressed, isNotNull);
  });

  testWidgets('a task starting under an open menu turns the switch down', (
    tester,
  ) async {
    await settings.add(AiProvider.openai, 'sk-personal1111');
    final work = await settings.add(AiProvider.deepseek, 'sk-work2222');
    await pumpSettings(tester);

    await openMenu(tester, work);
    activity.begin();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(settings.keys, hasLength(2));
    expect(settings.credentials?.id, work.id);
    expect(find.textContaining('Switch after it finishes'), findsOne);
  });

  testWidgets('removing the key in use says which takes over', (tester) async {
    final personal = await settings.add(
      AiProvider.openai,
      'sk-personal1111',
      name: 'Personal',
    );
    final work = await settings.add(
      AiProvider.deepseek,
      'sk-work2222',
      name: 'Work',
    );
    await pumpSettings(tester);

    await openMenu(tester, work);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Remove “Work”?'), findsOne);
    expect(find.textContaining('will switch to “Personal”'), findsOne);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(settings.credentials?.id, personal.id);
    expect(rowOf(work), findsNothing);
  });

  testWidgets('renames a key', (tester) async {
    final key = await settings.add(AiProvider.openai, 'sk-personal1111');
    await pumpSettings(tester);

    await openMenu(tester, key);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Personal');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(settings.credentials?.label, 'Personal');
    expect(find.text('Personal'), findsOne);
  });

  testWidgets('no more can be added at the limit', (tester) async {
    for (var i = 0; i < AiSettings.maxKeys; i++) {
      await settings.add(AiProvider.openai, 'sk-key$i');
    }
    await pumpSettings(tester);

    final add = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Up to 5 keys'),
        matching: find.byWidgetPredicate((w) => w is TextButton),
      ),
    );
    expect(add.onPressed, isNull);
  });

  group('adding from Settings', () {
    Future<void> addKey(WidgetTester tester, String key, {String? name}) async {
      await tester.tap(find.textContaining('Add another key'));
      await tester.pumpAndSettle();
      expect(find.text('Add an API key'), findsOne);
      await tester.enterText(find.byKey(ApiKeyScreen.keyFieldKey), key);
      if (name != null) {
        await tester.enterText(find.byKey(ApiKeyScreen.nameFieldKey), name);
      }
      await tester.tap(find.text('Save key'));
      await tester.pumpAndSettle();
    }

    testWidgets('names the key and puts it in use', (tester) async {
      await settings.add(AiProvider.openai, 'sk-personal1111');
      await pumpSettings(tester);

      await addKey(tester, 'sk-work2222', name: 'Work');

      expect(find.byType(SettingsScreen), findsOne);
      expect(settings.credentials?.label, 'Work');
      expect(settings.keys, hasLength(2));
    });

    testWidgets('a key already saved is caught before checking', (
      tester,
    ) async {
      await settings.add(AiProvider.openai, 'sk-personal1111');
      await pumpSettings(tester);

      await addKey(tester, 'sk-personal1111');

      expect(find.text('This key is already saved.'), findsOne);
      expect(checked, isEmpty);
      expect(settings.keys, hasLength(1));
    });

    testWidgets('while a task runs, it is saved but not put in use', (
      tester,
    ) async {
      final personal = await settings.add(AiProvider.openai, 'sk-personal1111');
      await pumpSettings(tester);
      activity.begin();

      await addKey(tester, 'sk-work2222', name: 'Work');

      expect(settings.keys, hasLength(2));
      expect(settings.credentials?.id, personal.id);
      expect(find.textContaining('“Work” is saved'), findsOne);
    });
  });
}
