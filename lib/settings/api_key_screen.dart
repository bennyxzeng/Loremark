import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/decor.dart';
import '../theme/loremark_theme.dart';
import 'ai_settings.dart';

/// Asks for the reader's OpenAI or DeepSeek API key.
///
/// On first run ([onboarding]) it is the whole app until the reader saves a
/// key or skips; otherwise it is pushed from Settings or a locked tab to add
/// another key, which can be named, and pops once the key is saved.
class ApiKeyScreen extends StatefulWidget {
  const ApiKeyScreen({super.key, this.onboarding = false});

  final bool onboarding;

  static const keyFieldKey = ValueKey('api-key-field');
  static const nameFieldKey = ValueKey('api-key-name');

  static Future<void> push(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const ApiKeyScreen()));

  @override
  State<ApiKeyScreen> createState() => _ApiKeyScreenState();
}

class _ApiKeyScreenState extends State<ApiKeyScreen> {
  final _keyField = TextEditingController();
  final _nameField = TextEditingController();
  AiProvider _provider = AiProvider.openai;
  bool _checking = false;
  String? _error;

  /// Set when the provider could not be reached, so the key can be saved
  /// unchecked.
  bool _offerUnchecked = false;

  @override
  void initState() {
    super.initState();
    _keyField.addListener(() {
      if (_error != null || _offerUnchecked) {
        setState(() {
          _error = null;
          _offerUnchecked = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _keyField.dispose();
    _nameField.dispose();
    super.dispose();
  }

  String get _key => _keyField.text.trim();

  Future<void> _submit({bool check = true}) async {
    final settings = AiSettingsScope.of(context);
    final key = _key;
    if (key.isEmpty) {
      setState(() => _error = 'Paste your API key first.');
      return;
    }
    if (!key.startsWith('sk-')) {
      setState(
        () => _error =
            '${_provider.label} API keys start with “sk-”. '
            'Check that you copied the whole key.',
      );
      return;
    }
    // Before checking, so a saved key isn't sent to the provider again.
    if (settings.keys.any((saved) => saved.apiKey == key)) {
      setState(() => _error = 'This key is already saved.');
      return;
    }

    if (check) {
      setState(() {
        _checking = true;
        _error = null;
        _offerUnchecked = false;
      });
      final result = await settings.verify(_provider, key);
      if (!mounted) return;
      setState(() => _checking = false);
      switch (result) {
        case KeyCheck.valid:
          break;
        case KeyCheck.rejected:
          setState(
            () => _error =
                '${_provider.label} didn’t accept this key. Check that it’s '
                'a ${_provider.label} key and that it hasn’t been revoked.',
          );
          return;
        case KeyCheck.unreachable:
          setState(() {
            _error =
                'Couldn’t reach ${_provider.label} to check the key. '
                'Check your connection and try again.';
            _offerUnchecked = true;
          });
          return;
      }
    }

    final AiCredentials added;
    try {
      added = await settings.add(_provider, key, name: _nameField.text);
    } on AiKeyError catch (error) {
      if (mounted) setState(() => _error = error.message);
      return;
    }
    if (!mounted) return;
    // On first run, saving swaps this screen for the library.
    if (widget.onboarding) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    if (settings.credentials?.id != added.id) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '“${added.label}” is saved. You can switch to it once the AI '
            'task running now finishes.',
          ),
        ),
      );
    }
  }

  Future<void> _skip() async {
    final settings = AiSettingsScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Continue without AI?'),
        content: const Text(
          'Without an API key, Ask stays locked and Story Map can’t update: '
          'no recaps, no questions about the story, no new character maps.\n\n'
          'Importing and reading books still work. You can add a key '
          'any time in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Add a key'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Skip for now'),
          ),
        ],
      ),
    );
    if (confirmed == true) await settings.skipOnboarding();
  }

  Future<void> _openKeysPage() async {
    final opened = await launchUrl(
      Uri.parse(_provider.keysUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Open ${_provider.keysUrlLabel} in a browser.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Light status bar icons over the illustration.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: widget.onboarding
            ? null
            : AppBar(
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                systemOverlayStyle: SystemUiOverlayStyle.light,
                leading: const _FloatingBack(),
              ),
        body: PaperBackground(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const FadedIllustration(
                asset: LoremarkArt.companionHeader,
                height: 280,
                alignment: Alignment(0.1, -0.4),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('AI COMPANION', style: kicker()),
                    const SizedBox(height: 9),
                    Text(
                      widget.onboarding
                          ? 'Connect an AI provider'
                          : 'Add an API key',
                      style: serif(29, height: 1.18),
                    ),
                    const SizedBox(height: 14),
                    const _Body(
                      'Ask and Story Map use an AI model that you pay for with your '
                      'own API key. Loremark supports OpenAI and DeepSeek keys only.',
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'PROVIDER',
                      style: kicker(color: LoremarkColors.muted),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<AiProvider>(
                      segments: [
                        for (final provider in AiProvider.values)
                          ButtonSegment(
                            value: provider,
                            label: Text(provider.label),
                          ),
                      ],
                      selected: {_provider},
                      showSelectedIcon: false,
                      onSelectionChanged: _checking
                          ? null
                          : (selection) => setState(() {
                              _provider = selection.single;
                              _error = null;
                              _offerUnchecked = false;
                            }),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'HOW TO GET A KEY',
                      style: kicker(color: LoremarkColors.muted),
                    ),
                    const SizedBox(height: 10),
                    _Step(
                      number: 1,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'Sign in at '),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.baseline,
                              baseline: TextBaseline.alphabetic,
                              child: GestureDetector(
                                onTap: _openKeysPage,
                                child: Text(
                                  _provider.keysUrlLabel,
                                  style: _Body.style.copyWith(
                                    color: LoremarkColors.olive,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
                        style: _Body.style,
                      ),
                    ),
                    const _Step(
                      number: 2,
                      child: _Body('Create a new secret key and copy it.'),
                    ),
                    _Step(
                      number: 3,
                      child: _Body(
                        'Add credit to your ${_provider.label} account. Keys don’t '
                        'work without a balance.',
                      ),
                    ),
                    const _Step(
                      number: 4,
                      child: _Body('Paste the key below.'),
                    ),
                    if (_provider == AiProvider.openai) ...[
                      const SizedBox(height: 6),
                      const _Note(
                        icon: Icons.info_outline,
                        text:
                            'A ChatGPT Plus or Pro subscription doesn’t include API '
                            'access. API usage is billed separately by OpenAI.',
                      ),
                    ],
                    const SizedBox(height: 22),
                    TextField(
                      key: ApiKeyScreen.keyFieldKey,
                      controller: _keyField,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      enabled: !_checking,
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: '${_provider.label} API key',
                        hintText: 'sk-…',
                        errorText: _error,
                        errorMaxLines: 4,
                      ),
                    ),
                    // A first key needs no name: there is nothing to tell it
                    // apart from.
                    if (!widget.onboarding) ...[
                      const SizedBox(height: 12),
                      TextField(
                        key: ApiKeyScreen.nameFieldKey,
                        controller: _nameField,
                        enabled: !_checking,
                        maxLength: 30,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Name (optional)',
                          hintText: 'e.g. Personal, Work',
                          helperText:
                              'Shown in Settings instead of '
                              '“${_provider.label}”.',
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    const _Note(
                      icon: Icons.lock_outline,
                      text:
                          'Your key is stored only on this device, in the system '
                          'keychain, and is sent only to the provider you chose.',
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _checking ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                      child: Text(_checking ? 'Checking key…' : 'Save key'),
                    ),
                    if (_offerUnchecked) ...[
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: () => _submit(check: false),
                        child: const Text('Save without checking'),
                      ),
                    ],
                    if (widget.onboarding) ...[
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: _checking ? null : _skip,
                        child: const Text('Skip for now'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A back button on a paper disc, readable over the illustration.
class _FloatingBack extends StatelessWidget {
  const _FloatingBack();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: LoremarkColors.paper.withValues(alpha: 0.9),
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: 'Back',
          iconSize: 20,
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.arrow_back, color: LoremarkColors.ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  static const style = TextStyle(
    fontSize: 14,
    height: 1.55,
    color: LoremarkColors.readerText,
  );

  @override
  Widget build(BuildContext context) => Text(text, style: style);
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.child});

  final int number;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(right: 10, top: 1),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: LoremarkColors.panel,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: LoremarkColors.chipText,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LoremarkColors.noteQuote,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: LoremarkColors.chipText),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: LoremarkColors.welcomeText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
