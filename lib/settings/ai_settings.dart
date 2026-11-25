import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../story_update/story_model_choice.dart';
import 'ai_activity.dart';

/// The AI providers Loremark can call with the reader's own API key.
enum AiProvider {
  openai(
    label: 'OpenAI',
    keysUrl: 'https://platform.openai.com/api-keys',
    keysUrlLabel: 'platform.openai.com/api-keys',
    modelsUrl: 'https://api.openai.com/v1/models',
  ),
  deepseek(
    label: 'DeepSeek',
    keysUrl: 'https://platform.deepseek.com/api_keys',
    keysUrlLabel: 'platform.deepseek.com/api_keys',
    modelsUrl: 'https://api.deepseek.com/models',
  );

  const AiProvider({
    required this.label,
    required this.keysUrl,
    required this.keysUrlLabel,
    required this.modelsUrl,
  });

  final String label;

  /// The provider's page for creating API keys.
  final String keysUrl;
  final String keysUrlLabel;

  /// A cheap endpoint that only answers with a valid key.
  final String modelsUrl;
}

/// One API key the reader saved, and its provider.
class AiCredentials {
  const AiCredentials({
    this.id = '',
    required this.provider,
    required this.apiKey,
    this.name,
  });

  /// What the key is saved under. Empty for one that was never saved.
  final String id;
  final AiProvider provider;
  final String apiKey;

  /// What the reader called the key, if they named it.
  final String? name;

  /// The key's name, or else its provider's.
  String get label => name ?? provider.label;

  AiCredentials _named(String? name) =>
      AiCredentials(id: id, provider: provider, apiKey: apiKey, name: name);

  /// The key with all but its last four characters hidden.
  String get maskedKey {
    final tail = apiKey.length > 4 ? apiKey.substring(apiKey.length - 4) : '';
    return '••••••••$tail';
  }
}

/// Where secrets are kept. The app uses the system keychain; tests use memory.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// The iOS Keychain or Android Keystore.
class SecureSecretStore implements SecretStore {
  const SecureSecretStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemorySecretStore implements SecretStore {
  MemorySecretStore([Map<String, String>? values]) : values = values ?? {};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Why a key couldn't be added, switched to or removed.
class AiKeyError implements Exception {
  const AiKeyError(this.message);

  /// What to tell the reader.
  final String message;

  @override
  String toString() => message;
}

/// The reader's API keys and which one is in use, their model choices, and
/// whether they have seen the first-run API key screen.
///
/// Ask stays locked, and Story Map can't be updated, until [credentials] is set.
/// The key in use can't change while [isBusy]: see [AiActivity].
class AiSettings extends ChangeNotifier {
  AiSettings(this._store, {this.verify = verifyApiKey, AiActivity? activity})
    : activity = activity ?? AiActivity.instance;

  /// How many keys can be saved at once.
  static const maxKeys = 5;

  /// The saved keys' ids, providers and names, as JSON. The keys themselves
  /// are kept apart, one entry each, under [_secretKey].
  static const _keysKey = 'ai_keys';
  static const _activeKeyKey = 'ai_active_key';
  static String _secretKey(String id) => 'ai_key_$id';

  /// Where the one key was kept before there could be several.
  static const _legacyProviderKey = 'ai_provider';
  static const _legacyApiKeyKey = 'ai_api_key';

  static const _onboardedKey = 'ai_onboarding_seen';
  static const _storyModelKey = 'story_model';
  static const _storyEffortKey = 'story_effort';
  static const _storyQuotesKey = 'story_check_quotes';
  static const _chatModelKey = 'chat_model';
  static const _chatEffortKey = 'chat_effort';

  /// Settings kept in the system keychain.
  static Future<AiSettings> open() async {
    final settings = AiSettings(const SecureSecretStore());
    await settings.load();
    return settings;
  }

  final SecretStore _store;

  /// Checks a key before [save]; tests replace the network call.
  final KeyVerifier verify;

  /// The AI tasks running, which hold on to the key in use.
  final AiActivity activity;

  var _keys = <AiCredentials>[];
  String? _activeId;
  bool _onboardingSeen = false;
  String? _storyModelId;
  String? _storyEffortName;
  bool _checkStoryQuotes = false;
  String? _chatModelId;
  String? _chatEffortName;

  /// The saved keys, in the order they were added.
  List<AiCredentials> get keys => List.unmodifiable(_keys);

  /// The key in use. Set whenever any key is saved.
  AiCredentials? get credentials => _find(_activeId);
  bool get hasKey => credentials != null;

  /// Whether an AI task is running on the key in use.
  bool get isBusy => activity.busy;

  bool get canAddKey => _keys.length < maxKeys;

  /// Whether another key can be put in use now.
  bool get canSwitch => !isBusy;

  /// Whether the key [id] can be removed now: any but the one in use, and that
  /// one too while nothing runs on it.
  bool canRemove(String id) => id != _activeId || !isBusy;

  /// The key that would be put in use if the key [id] were removed, if any.
  AiCredentials? replacementFor(String id) => id != _activeId
      ? credentials
      : _keys.where((key) => key.id != id).firstOrNull;

  AiCredentials? _find(String? id) =>
      _keys.where((key) => key.id == id).firstOrNull;

  /// Whether the first-run API key screen was answered, by a key or a skip.
  bool get onboardingSeen => _onboardingSeen;

  /// The model Story Map updates use: the reader's choice if the current
  /// provider has it, or else the provider's default.
  StoryModelChoice get storyModel => StoryModelChoice.resolve(
    (credentials?.provider ?? AiProvider.openai).name,
    _storyModelId,
  );

  /// The reasoning effort for [storyModel]: the reader's choice if the model
  /// accepts it, or else the default.
  StoryEffort get storyEffort => storyModel.resolveEffort(_storyEffortName);

  /// Whether a quote missing from its paragraph fails a Story Map update. Off,
  /// it is only flagged, since a rejected update has already been paid for.
  bool get checkStoryQuotes => _checkStoryQuotes;

  /// The model Ask answers with, chosen apart from [storyModel]: the reader's
  /// choice if the current provider has it, or else the provider's default.
  StoryModelChoice get chatModel => StoryModelChoice.resolve(
    (credentials?.provider ?? AiProvider.openai).name,
    _chatModelId,
  );

  /// The reasoning effort for [chatModel], resolved as [storyEffort] is.
  StoryEffort get chatEffort => chatModel.resolveEffort(_chatEffortName);

  Future<void> load() async {
    _onboardingSeen = await _store.read(_onboardedKey) == 'true';
    _storyModelId = await _store.read(_storyModelKey);
    _storyEffortName = await _store.read(_storyEffortKey);
    _checkStoryQuotes = await _store.read(_storyQuotesKey) == 'true';
    _chatModelId = await _store.read(_chatModelKey);
    _chatEffortName = await _store.read(_chatEffortKey);
    _keys = await _loadKeys();
    final active = await _store.read(_activeKeyKey);
    // A key is always in use while any is saved.
    _activeId = (_find(active) ?? _keys.firstOrNull)?.id;
  }

  Future<List<AiCredentials>> _loadKeys() async {
    final index = await _store.read(_keysKey);
    if (index == null) return _moveLegacyKey();
    final keys = <AiCredentials>[];
    for (final entry in _decodeIndex(index)) {
      final apiKey = await _store.read(_secretKey(entry.id));
      // An entry whose key is gone can't be used, so it isn't offered.
      if (apiKey != null) {
        keys.add(
          AiCredentials(
            id: entry.id,
            provider: entry.provider,
            apiKey: apiKey,
            name: entry.name,
          ),
        );
      }
    }
    return keys;
  }

  /// Saves the one key kept before there could be several as the first of
  /// them, in use, and forgets where it was.
  Future<List<AiCredentials>> _moveLegacyKey() async {
    final providerName = await _store.read(_legacyProviderKey);
    final apiKey = await _store.read(_legacyApiKeyKey);
    final provider = AiProvider.values
        .where((provider) => provider.name == providerName)
        .firstOrNull;
    if (provider == null || apiKey == null) return [];
    final key = AiCredentials(id: _newId(), provider: provider, apiKey: apiKey);
    await _store.write(_secretKey(key.id), apiKey);
    await _writeIndex([key]);
    await _store.write(_activeKeyKey, key.id);
    await _store.delete(_legacyProviderKey);
    await _store.delete(_legacyApiKeyKey);
    return [key];
  }

  /// Saves another key, and puts it in use unless an AI task is running.
  ///
  /// Throws [AiKeyError] if [maxKeys] are already saved, or this key is.
  Future<AiCredentials> add(
    AiProvider provider,
    String apiKey, {
    String? name,
  }) async {
    if (_keys.any((key) => key.apiKey == apiKey)) {
      throw const AiKeyError('This key is already saved.');
    }
    if (!canAddKey) {
      throw const AiKeyError(
        'You can save up to $maxKeys keys. Remove one to add another.',
      );
    }
    final key = AiCredentials(
      id: _newId(),
      provider: provider,
      apiKey: apiKey,
      name: _cleanName(name),
    );
    final keys = [..._keys, key];
    // The key before the entry naming it, so an entry never lacks its key.
    await _store.write(_secretKey(key.id), apiKey);
    await _writeIndex(keys);
    _keys = keys;
    // Decided with no await before the change, so no task can start between
    // the check and the switch.
    final activate = !isBusy || _activeId == null;
    if (activate) _activeId = key.id;
    _onboardingSeen = true;
    notifyListeners();
    if (activate) await _store.write(_activeKeyKey, key.id);
    await _store.write(_onboardedKey, 'true');
    return key;
  }

  /// Puts the key [id] in use.
  ///
  /// Throws [AiKeyError] while an AI task is running.
  Future<void> activate(String id) async {
    if (id == _activeId || _find(id) == null) return;
    if (!canSwitch) throw const AiKeyError(_busyMessage);
    // In memory first, so a task starting while the keychain is written
    // already takes the new key.
    _activeId = id;
    notifyListeners();
    await _store.write(_activeKeyKey, id);
  }

  /// Names the key [id]; an empty [name] goes back to the provider's.
  Future<void> rename(String id, String? name) async {
    final index = _keys.indexWhere((key) => key.id == id);
    if (index < 0) return;
    final keys = [..._keys];
    keys[index] = keys[index]._named(_cleanName(name));
    await _writeIndex(keys);
    _keys = keys;
    notifyListeners();
  }

  /// Forgets the key [id]. If it was in use, [replacementFor] it is put in use.
  ///
  /// Throws [AiKeyError] if it is in use and an AI task is running.
  Future<void> remove(String id) async {
    if (_find(id) == null) return;
    if (!canRemove(id)) throw const AiKeyError(_busyMessage);
    final wasActive = id == _activeId;
    final keys = [
      for (final key in _keys)
        if (key.id != id) key,
    ];
    _keys = keys;
    if (wasActive) _activeId = keys.firstOrNull?.id;
    notifyListeners();
    // The entry before the key, so an entry never lacks its key.
    await _writeIndex(keys);
    if (wasActive) {
      final active = _activeId;
      active == null
          ? await _store.delete(_activeKeyKey)
          : await _store.write(_activeKeyKey, active);
    }
    await _store.delete(_secretKey(id));
  }

  static const _busyMessage =
      'An AI task is running on the key in use. Switch after it finishes.';

  Future<void> _writeIndex(List<AiCredentials> keys) => _store.write(
    _keysKey,
    jsonEncode([
      for (final key in keys)
        {
          'id': key.id,
          'provider': key.provider.name,
          if (key.name != null) 'name': key.name,
        },
    ]),
  );

  static List<({String id, AiProvider provider, String? name})> _decodeIndex(
    String index,
  ) {
    final Object? entries;
    try {
      entries = jsonDecode(index);
    } on FormatException {
      return [];
    }
    if (entries is! List) return [];
    return [
      for (final entry in entries)
        if (entry case {'id': final String id, 'provider': final String name})
          if (AiProvider.values.where((p) => p.name == name).firstOrNull
              case final provider?)
            (
              id: id,
              provider: provider,
              name: switch (entry['name']) {
                final String name => name,
                _ => null,
              },
            ),
    ];
  }

  /// An id no saved key has.
  String _newId() {
    var time = DateTime.now().microsecondsSinceEpoch;
    String id() => time.toRadixString(36);
    while (_find(id()) != null) {
      time++;
    }
    return id();
  }

  static String? _cleanName(String? name) {
    final trimmed = name?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> setStoryModel(StoryModelChoice model) async {
    await _store.write(_storyModelKey, model.id);
    _storyModelId = model.id;
    notifyListeners();
  }

  Future<void> setStoryEffort(StoryEffort effort) async {
    await _store.write(_storyEffortKey, effort.name);
    _storyEffortName = effort.name;
    notifyListeners();
  }

  Future<void> setChatModel(StoryModelChoice model) async {
    await _store.write(_chatModelKey, model.id);
    _chatModelId = model.id;
    notifyListeners();
  }

  Future<void> setChatEffort(StoryEffort effort) async {
    await _store.write(_chatEffortKey, effort.name);
    _chatEffortName = effort.name;
    notifyListeners();
  }

  Future<void> setCheckStoryQuotes(bool check) async {
    await _store.write(_storyQuotesKey, '$check');
    _checkStoryQuotes = check;
    notifyListeners();
  }

  Future<void> skipOnboarding() async {
    await _store.write(_onboardedKey, 'true');
    _onboardingSeen = true;
    notifyListeners();
  }
}

/// Makes [AiSettings] available to every screen, rebuilding them when it
/// changes.
class AiSettingsScope extends InheritedNotifier<AiSettings> {
  const AiSettingsScope({
    super.key,
    required AiSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static AiSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AiSettingsScope>()!.notifier!;
}

enum KeyCheck { valid, rejected, unreachable }

/// Checks an API key against its provider before it is saved.
typedef KeyVerifier = Future<KeyCheck> Function(AiProvider, String apiKey);

/// Asks the provider for its model list, which needs a valid key but costs
/// nothing. It cannot tell whether the account has credit.
Future<KeyCheck> verifyApiKey(AiProvider provider, String apiKey) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(Uri.parse(provider.modelsUrl));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    final response = await request.close().timeout(const Duration(seconds: 15));
    await response.drain<void>();
    return switch (response.statusCode) {
      200 => KeyCheck.valid,
      401 || 403 => KeyCheck.rejected,
      _ => KeyCheck.unreachable,
    };
  } on Exception {
    return KeyCheck.unreachable;
  } finally {
    client.close(force: true);
  }
}
