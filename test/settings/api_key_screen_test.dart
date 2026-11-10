import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/library/book_repository.dart';
import 'package:loremark/main.dart';
import 'package:loremark/settings/ai_settings.dart';
import 'package:loremark/settings/connection_status.dart';
import 'package:loremark/settings/settings_screen.dart';
import 'package:loremark/story_update/story_model_choice.dart';

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

  group('Story Map settings', () {
    Future<AiSettings> pumpSettings(
      WidgetTester tester, {
      String provider = 'openai',
    }) async {
      tester.view.physicalSize = const Size(1200, 5400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      store = MemorySecretStore({
        'ai_onboarding_seen': 'true',
        'ai_provider': provider,
        'ai_api_key': 'sk-test',
      });
      final settings = AiSettings(store);
      await settings.load();
      await tester.pumpWidget(
        AiSettingsScope(
          settings: settings,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      return settings;
    }

    // Story Map and Ask each have a model and an effort to pick.
    const storyModel = ValueKey('story-model');
    const storyEffort = ValueKey('story-effort');
    const askModel = ValueKey('ask-model');
    const askEffort = ValueKey('ask-effort');

    Finder shown(Key choice, String text) =>
        find.descendant(of: find.byKey(choice), matching: find.text(text));

    Finder dropdown(Key choice) => find.descendant(
      of: find.byKey(choice),
      matching: find.byWidgetPredicate((widget) => widget is DropdownButton),
    );

    Future<void> pick(WidgetTester tester, Key choice, String to) async {
      await tester.tap(dropdown(choice));
      await tester.pumpAndSettle();
      await tester.tap(find.text(to).last);
      await tester.pumpAndSettle();
    }

    testWidgets('OpenAI offers Terra, by default, and Sol', (tester) async {
      final settings = await pumpSettings(tester);
      expect(shown(storyModel, 'GPT-6.1 Terra'), findsOne);
      await pick(tester, storyModel, 'GPT-6.1 Sol');
      expect(settings.storyModel, StoryModelChoice.gpt61Sol);
      expect(store.values['story_model'], 'gpt-6.1-sol');
    });

    testWidgets('DeepSeek offers its own model', (tester) async {
      await pumpSettings(tester, provider: 'deepseek');
      expect(shown(storyModel, 'DeepSeek Flash'), findsOne);
      expect(find.text('GPT-6.1 Terra'), findsNothing);
    });

    testWidgets('the reader picks the reasoning effort, high by default', (
      tester,
    ) async {
      final settings = await pumpSettings(tester);
      expect(settings.storyEffort, StoryEffort.high);
      await pick(tester, storyEffort, 'Max');
      expect(settings.storyEffort, StoryEffort.max);
      expect(store.values['story_effort'], 'max');
    });

    testWidgets('efforts follow the model', (tester) async {
      await pumpSettings(tester, provider: 'deepseek');
      await tester.tap(dropdown(storyEffort));
      await tester.pumpAndSettle();
      expect(find.text('Medium'), findsNothing);
      expect(find.text('Extra high'), findsNothing);
      expect(find.text('None'), findsWidgets);
    });

    testWidgets('an effort the new model doesn\'t take falls back', (
      tester,
    ) async {
      final settings = await pumpSettings(tester);
      await pick(tester, storyEffort, 'None');
      expect(settings.storyEffort, StoryEffort.none);
      await pick(tester, storyModel, 'GPT-6.1 Sol');
      expect(settings.storyEffort, StoryEffort.high);
    });

    testWidgets('Ask picks its own model and effort, apart from updates', (
      tester,
    ) async {
      final settings = await pumpSettings(tester);
      expect(settings.chatModel, StoryModelChoice.gpt61Terra);
      expect(settings.chatEffort, StoryEffort.high);
      expect(shown(askModel, 'GPT-6.1 Terra'), findsOne);

      await pick(tester, askModel, 'GPT-6.1 Sol');
      await pick(tester, askEffort, 'Low');
      expect(settings.chatModel, StoryModelChoice.gpt61Sol);
      expect(settings.chatEffort, StoryEffort.low);
      expect(store.values['chat_model'], 'gpt-6.1-sol');
      expect(store.values['chat_effort'], 'low');
      // Story Map updates keep theirs.
      expect(settings.storyModel, StoryModelChoice.gpt61Terra);
      expect(settings.storyEffort, StoryEffort.high);

      await pick(tester, storyModel, 'GPT-6.1 Sol');
      await pick(tester, storyEffort, 'Max');
      expect(settings.chatEffort, StoryEffort.low);

      final reloaded = AiSettings(store);
      await reloaded.load();
      expect(reloaded.chatModel, StoryModelChoice.gpt61Sol);
      expect(reloaded.chatEffort, StoryEffort.low);
    });

    testWidgets('Ask falls back the way updates do', (tester) async {
      final settings = await pumpSettings(tester);
      await settings.setChatModel(StoryModelChoice.gpt61Sol);
      await settings.save(
        const AiCredentials(provider: AiProvider.deepseek, apiKey: 'sk-new'),
      );
      expect(settings.chatModel, StoryModelChoice.deepseekFlash);
      await settings.setChatEffort(StoryEffort.xhigh);
      // DeepSeek treats Extra high as High, so it isn't offered.
      expect(settings.chatEffort, StoryEffort.high);
    });

    testWidgets('changing provider falls back to its default model', (
      tester,
    ) async {
      final settings = await pumpSettings(tester);
      await settings.setStoryModel(StoryModelChoice.gpt61Sol);
      await settings.save(
        const AiCredentials(provider: AiProvider.deepseek, apiKey: 'sk-new'),
      );
      expect(settings.storyModel, StoryModelChoice.deepseekFlash);
    });

    testWidgets('the quote check is off until turned on', (tester) async {
      final settings = await pumpSettings(tester);
      expect(settings.checkStoryQuotes, isFalse);
      await tester.tap(find.text('Strict quote check'));
      await tester.pumpAndSettle();
      expect(settings.checkStoryQuotes, isTrue);
      expect(store.values['story_check_quotes'], 'true');

      final reloaded = AiSettings(store);
      await reloaded.load();
      expect(reloaded.checkStoryQuotes, isTrue);
    });

    testWidgets('without a key, only the quote check shows', (tester) async {
      tester.view.physicalSize = const Size(1200, 5400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final settings = AiSettings(store);
      await settings.load();
      await tester.pumpWidget(
        AiSettingsScope(
          settings: settings,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      expect(find.text('Strict quote check'), findsOne);
      expect(find.text('Reasoning effort'), findsNothing);
      expect(find.text('ASK'), findsNothing);
    });

    testWidgets('fits a small phone', (tester) async {
      await pumpSettings(tester);
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Strict quote check'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Reasoning effort'), findsOne);
    });

    testWidgets('removing the key keeps the choices', (tester) async {
      final settings = await pumpSettings(tester);
      await settings.setStoryEffort(StoryEffort.low);
      await settings.remove();
      await settings.save(
        const AiCredentials(provider: AiProvider.openai, apiKey: 'sk-new'),
      );
      expect(settings.storyEffort, StoryEffort.low);
    });
  });
}
