import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/library/book_repository.dart';
import 'package:loremark/main.dart';
import 'package:loremark/settings/ai_settings.dart';
import 'package:loremark/settings/connection_status.dart';
import 'package:loremark/settings/settings_screen.dart';

void main() {
  late MemorySecretStore store;
  late List<(AiProvider, String)> checked;
  late KeyCheck nextCheck;

  setUp(() {
    store = MemorySecretStore();
    checked = [];
    nextCheck = KeyCheck.valid;
  });

  Future<AiSettings> pumpApp(WidgetTester tester) async {
    // Tall enough that the whole key screen is built.
    tester.view.physicalSize = const Size(1200, 5400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final settings = AiSettings(
      store,
      verify: (provider, key) async {
        checked.add((provider, key));
        return nextCheck;
      },
    );
    await settings.load();
    // The library folder is never created: an empty library is enough.
    final repository = BookRepository(
      Directory('${Directory.systemTemp.path}/loremark_missing_library'),
    );
    await tester.pumpWidget(
      LoremarkApp(
        repository: Future.value(repository),
        settings: Future.value(settings),
        connection: ConnectionStatus(),
        pickEpub: () async => null,
      ),
    );
    await tester.pumpAndSettle();
    return settings;
  }

  Finder keyField() => find.byType(TextField);

  testWidgets('first launch asks for an API key before the library', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('Connect an AI provider'), findsOne);
    expect(find.text('Books'), findsNothing);
    expect(find.text('OpenAI'), findsOne);
    expect(find.text('DeepSeek'), findsOne);
  });

  testWidgets('the key is shown as dots', (tester) async {
    await pumpApp(tester);

    await tester.enterText(keyField(), 'sk-secret');
    await tester.pump();

    final field = tester.widget<TextField>(keyField());
    expect(field.obscureText, isTrue);
    expect(field.obscuringCharacter, '•');
  });

  testWidgets('saving a valid key opens the library and stores it', (
    tester,
  ) async {
    final settings = await pumpApp(tester);

    await tester.tap(find.text('DeepSeek'));
    await tester.pump();
    await tester.enterText(keyField(), '  sk-deep123  ');
    await tester.tap(find.text('Save key'));
    await tester.pumpAndSettle();

    expect(checked, [(AiProvider.deepseek, 'sk-deep123')]);
    expect(find.text('Books'), findsOne);
    expect(settings.credentials?.provider, AiProvider.deepseek);
    expect(store.values['ai_api_key'], 'sk-deep123');
  });

  testWidgets('a rejected key is not saved', (tester) async {
    final settings = await pumpApp(tester);
    nextCheck = KeyCheck.rejected;

    await tester.enterText(keyField(), 'sk-wrong');
    await tester.tap(find.text('Save key'));
    await tester.pumpAndSettle();

    expect(find.textContaining('didn’t accept this key'), findsOne);
    expect(settings.hasKey, isFalse);
    expect(find.text('Connect an AI provider'), findsOne);
  });

  testWidgets('a key without the sk- prefix is caught before checking', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.enterText(keyField(), 'hello');
    await tester.tap(find.text('Save key'));
    await tester.pumpAndSettle();

    expect(checked, isEmpty);
    expect(find.textContaining('start with “sk-”'), findsOne);
  });

  testWidgets('when the provider is unreachable the key can be saved '
      'unchecked', (tester) async {
    final settings = await pumpApp(tester);
    nextCheck = KeyCheck.unreachable;

    await tester.enterText(keyField(), 'sk-offline');
    await tester.tap(find.text('Save key'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save without checking'));
    await tester.tap(find.text('Save without checking'));
    await tester.pumpAndSettle();

    expect(settings.credentials?.apiKey, 'sk-offline');
    expect(find.text('Books'), findsOne);
  });

  testWidgets('skipping warns first, then opens the library without a key', (
    tester,
  ) async {
    final settings = await pumpApp(tester);

    await tester.ensureVisible(find.text('Skip for now'));
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    expect(find.text('Continue without AI?'), findsOne);

    await tester.tap(find.text('Skip for now').last);
    await tester.pumpAndSettle();

    expect(find.text('Books'), findsOne);
    expect(settings.onboardingSeen, isTrue);
    expect(settings.hasKey, isFalse);
  });

  testWidgets('settings can add, then remove, a key', (tester) async {
    store.values['ai_onboarding_seen'] = 'true';
    final settings = await pumpApp(tester);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Not connected'), findsOne);

    await tester.tap(find.text('Add API key'));
    await tester.pumpAndSettle();
    expect(find.text('Skip for now'), findsNothing);

    await tester.enterText(keyField(), 'sk-abcdWXYZ');
    await tester.tap(find.text('Save key'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOne);
    expect(find.text('••••••••WXYZ'), findsOne);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(settings.hasKey, isFalse);
    expect(store.values.containsKey('ai_api_key'), isFalse);
    expect(find.text('Not connected'), findsOne);
  });

  test('settings load what was saved', () async {
    final first = AiSettings(store);
    await first.save(
      const AiCredentials(provider: AiProvider.openai, apiKey: 'sk-kept'),
    );

    final reopened = AiSettings(store);
    await reopened.load();

    expect(reopened.onboardingSeen, isTrue);
    expect(reopened.credentials?.provider, AiProvider.openai);
    expect(reopened.credentials?.apiKey, 'sk-kept');
  });
}
