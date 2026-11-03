import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

/// The provider and API key the reader entered.
class AiCredentials {
  const AiCredentials({required this.provider, required this.apiKey});

  final AiProvider provider;
  final String apiKey;

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

/// The reader's AI provider settings, and whether they have seen the
/// first-run API key screen.
///
/// Ask and Story Map stay locked until [credentials] is set.
class AiSettings extends ChangeNotifier {
  AiSettings(this._store, {this.verify = verifyApiKey});

  static const _providerKey = 'ai_provider';
  static const _apiKeyKey = 'ai_api_key';
  static const _onboardedKey = 'ai_onboarding_seen';

  /// Settings kept in the system keychain.
  static Future<AiSettings> open() async {
    final settings = AiSettings(const SecureSecretStore());
    await settings.load();
    return settings;
  }

  final SecretStore _store;

  /// Checks a key before [save]; tests replace the network call.
  final KeyVerifier verify;

  AiCredentials? _credentials;
  bool _onboardingSeen = false;

  AiCredentials? get credentials => _credentials;
  bool get hasKey => _credentials != null;

  /// Whether the first-run API key screen was answered, by a key or a skip.
  bool get onboardingSeen => _onboardingSeen;

  Future<void> load() async {
    _onboardingSeen = await _store.read(_onboardedKey) == 'true';
    final providerName = await _store.read(_providerKey);
    final apiKey = await _store.read(_apiKeyKey);
    final provider = AiProvider.values
        .where((provider) => provider.name == providerName)
        .firstOrNull;
    _credentials = provider == null || apiKey == null
        ? null
        : AiCredentials(provider: provider, apiKey: apiKey);
  }

  Future<void> save(AiCredentials credentials) async {
    await _store.write(_providerKey, credentials.provider.name);
    await _store.write(_apiKeyKey, credentials.apiKey);
    await _store.write(_onboardedKey, 'true');
    _credentials = credentials;
    _onboardingSeen = true;
    notifyListeners();
  }

  Future<void> remove() async {
    await _store.delete(_providerKey);
    await _store.delete(_apiKeyKey);
    _credentials = null;
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
