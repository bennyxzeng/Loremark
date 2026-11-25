import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/settings/ai_activity.dart';
import 'package:loremark/settings/ai_settings.dart';

void main() {
  late MemorySecretStore store;
  late AiActivity activity;

  setUp(() {
    store = MemorySecretStore();
    activity = AiActivity();
  });

  Future<AiSettings> open() async {
    final settings = AiSettings(store, activity: activity);
    await settings.load();
    return settings;
  }

  group('AiActivity', () {
    test('is busy until every task has ended', () {
      var changes = 0;
      activity.addListener(() => changes++);

      final endFirst = activity.begin();
      final endSecond = activity.begin();
      expect(activity.busy, isTrue);

      endFirst();
      expect(activity.busy, isTrue);
      endSecond();
      expect(activity.busy, isFalse);
      // Only going busy and going idle are news.
      expect(changes, 2);
    });

    test('ending twice counts once', () {
      final endFirst = activity.begin();
      final endSecond = activity.begin();
      endFirst();
      endFirst();
      expect(activity.busy, isTrue);
      endSecond();
      expect(activity.busy, isFalse);
    });
  });

  group('moving the one key kept before', () {
    test('makes it the first key, in use, and forgets the old place', () async {
      store.values.addAll({
        'ai_onboarding_seen': 'true',
        'ai_provider': 'deepseek',
        'ai_api_key': 'sk-old',
      });

      final settings = await open();

      expect(settings.keys, hasLength(1));
      expect(settings.credentials?.provider, AiProvider.deepseek);
      expect(settings.credentials?.apiKey, 'sk-old');
      expect(store.values.containsKey('ai_provider'), isFalse);
      expect(store.values.containsKey('ai_api_key'), isFalse);
      final id = settings.credentials!.id;
      expect(store.values['ai_key_$id'], 'sk-old');
      expect(store.values['ai_active_key'], id);

      final reopened = await open();
      expect(reopened.credentials?.id, id);
      expect(reopened.credentials?.apiKey, 'sk-old');
    });

    test('does nothing without a key', () async {
      final settings = await open();
      expect(settings.hasKey, isFalse);
      expect(store.values, isEmpty);
    });
  });

  group('adding', () {
    test('puts the new key in use and keeps the others', () async {
      final settings = await open();
      final first = await settings.add(AiProvider.openai, 'sk-one');
      final second = await settings.add(
        AiProvider.deepseek,
        'sk-two',
        name: '  Work  ',
      );

      expect(settings.keys.map((key) => key.id), [first.id, second.id]);
      expect(settings.credentials?.id, second.id);
      expect(second.label, 'Work');
      expect(first.label, 'OpenAI');
      expect(settings.onboardingSeen, isTrue);

      final reopened = await open();
      expect(reopened.keys.map((key) => key.label), ['OpenAI', 'Work']);
      expect(reopened.credentials?.apiKey, 'sk-two');
      // No secret is kept in the list of keys.
      expect(store.values['ai_keys'], isNot(contains('sk-')));
    });

    test('turns down a key already saved', () async {
      final settings = await open();
      await settings.add(AiProvider.openai, 'sk-one');
      expect(
        () => settings.add(AiProvider.deepseek, 'sk-one'),
        throwsA(isA<AiKeyError>()),
      );
      expect(settings.keys, hasLength(1));
    });

    test('stops at the limit', () async {
      final settings = await open();
      for (var i = 0; i < AiSettings.maxKeys; i++) {
        await settings.add(AiProvider.openai, 'sk-$i');
      }
      expect(settings.canAddKey, isFalse);
      expect(
        () => settings.add(AiProvider.openai, 'sk-more'),
        throwsA(isA<AiKeyError>()),
      );
      expect(settings.keys, hasLength(AiSettings.maxKeys));
    });

    test(
      'while a task runs, saves the key without putting it in use',
      () async {
        final settings = await open();
        final first = await settings.add(AiProvider.openai, 'sk-one');
        final end = activity.begin();

        final second = await settings.add(AiProvider.deepseek, 'sk-two');

        expect(settings.keys, hasLength(2));
        expect(settings.credentials?.id, first.id);
        end();
        await settings.activate(second.id);
        expect(settings.credentials?.id, second.id);
      },
    );
  });

  group('switching', () {
    test('puts another key in use, and remembers it', () async {
      final settings = await open();
      final first = await settings.add(AiProvider.openai, 'sk-one');
      await settings.add(AiProvider.deepseek, 'sk-two');

      await settings.activate(first.id);

      expect(settings.credentials?.id, first.id);
      expect((await open()).credentials?.id, first.id);
    });

    test('is turned down while a task runs', () async {
      final settings = await open();
      final first = await settings.add(AiProvider.openai, 'sk-one');
      final second = await settings.add(AiProvider.deepseek, 'sk-two');
      activity.begin();

      expect(settings.canSwitch, isFalse);
      expect(() => settings.activate(first.id), throwsA(isA<AiKeyError>()));
      expect(settings.credentials?.id, second.id);
    });

    test('changes the key in use before the keychain is written', () async {
      final slow = _SlowStore();
      final settings = AiSettings(slow, activity: activity);
      final first = await settings.add(AiProvider.openai, 'sk-one');
      await settings.add(AiProvider.deepseek, 'sk-two');

      slow.hold();
      final switching = settings.activate(first.id);
      // A task starting now must already see the new key.
      expect(settings.credentials?.id, first.id);
      slow.release();
      await switching;
    });
  });

  group('removing', () {
    test('a key not in use leaves the one in use', () async {
      final settings = await open();
      final first = await settings.add(AiProvider.openai, 'sk-one');
      final second = await settings.add(AiProvider.deepseek, 'sk-two');

      await settings.remove(first.id);

      expect(settings.keys.map((key) => key.id), [second.id]);
      expect(settings.credentials?.id, second.id);
      expect(store.values.containsKey('ai_key_${first.id}'), isFalse);
    });

    test('the key in use puts the first one left in use', () async {
      final settings = await open();
      final first = await settings.add(AiProvider.openai, 'sk-one');
      await settings.add(AiProvider.openai, 'sk-two');
      final third = await settings.add(AiProvider.deepseek, 'sk-three');

      expect(settings.replacementFor(third.id)?.id, first.id);
      await settings.remove(third.id);

      expect(settings.credentials?.id, first.id);
      expect((await open()).credentials?.id, first.id);
    });

    test('the last key locks AI again', () async {
      final settings = await open();
      final only = await settings.add(AiProvider.openai, 'sk-one');

      expect(settings.replacementFor(only.id), isNull);
      await settings.remove(only.id);

      expect(settings.hasKey, isFalse);
      expect(store.values.containsKey('ai_active_key'), isFalse);
      expect(jsonDecode(store.values['ai_keys']!), isEmpty);
    });

    test('while a task runs, only keys not in use go', () async {
      final settings = await open();
      final first = await settings.add(AiProvider.openai, 'sk-one');
      final second = await settings.add(AiProvider.deepseek, 'sk-two');
      activity.begin();

      expect(settings.canRemove(second.id), isFalse);
      expect(() => settings.remove(second.id), throwsA(isA<AiKeyError>()));
      expect(settings.credentials?.id, second.id);

      expect(settings.canRemove(first.id), isTrue);
      await settings.remove(first.id);
      expect(settings.keys.map((key) => key.id), [second.id]);
    });
  });

  test('renaming works while a task runs, and empty goes back', () async {
    final settings = await open();
    final key = await settings.add(AiProvider.openai, 'sk-one');
    activity.begin();

    await settings.rename(key.id, 'Personal');
    expect(settings.credentials?.label, 'Personal');
    expect((await open()).credentials?.label, 'Personal');

    await settings.rename(key.id, '   ');
    expect(settings.credentials?.label, 'OpenAI');
  });

  test('an entry whose key is gone is not offered', () async {
    final settings = await open();
    final first = await settings.add(AiProvider.openai, 'sk-one');
    final second = await settings.add(AiProvider.deepseek, 'sk-two');
    store.values.remove('ai_key_${second.id}');

    final reopened = await open();

    expect(reopened.keys.map((key) => key.id), [first.id]);
    expect(reopened.credentials?.id, first.id);
  });
}

/// Holds writes until released, to see what changes before they land.
class _SlowStore extends MemorySecretStore {
  _SlowStore();

  Future<void>? _gate;
  void Function()? _open;

  void hold() {
    final gate = Completer<void>();
    _gate = gate.future;
    _open = gate.complete;
  }

  void release() {
    _open?.call();
    _gate = null;
  }

  @override
  Future<void> write(String key, String value) async {
    if (_gate case final gate?) await gate;
    await super.write(key, value);
  }
}
