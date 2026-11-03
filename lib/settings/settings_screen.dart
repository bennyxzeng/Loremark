import 'package:flutter/material.dart';

import '../theme/decor.dart';
import '../theme/loremark_theme.dart';
import 'ai_settings.dart';
import 'api_key_screen.dart';

/// App-wide settings, opened from the library.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static Future<void> push(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));

  Future<void> _remove(BuildContext context, AiSettings settings) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove API key?'),
        content: const Text(
          'Ask and Story Map will be locked until you add a key again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) await settings.remove();
  }

  @override
  Widget build(BuildContext context) {
    final settings = AiSettingsScope.of(context);
    final credentials = settings.credentials;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: PaperBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
            children: [
              Text('LOREMARK', style: kicker()),
              const SizedBox(height: 9),
              Text('Settings', style: serif(29, height: 1.18)),
              const SizedBox(height: 26),
              Text('AI PROVIDER', style: kicker(color: LoremarkColors.muted)),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (credentials == null) ...[
                        Text('Not connected', style: serif(18)),
                        const SizedBox(height: 6),
                        const Text(
                          'Ask and Story Map are locked until you add an '
                          'OpenAI or DeepSeek API key.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: LoremarkColors.muted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => ApiKeyScreen.push(context),
                          icon: const Icon(Icons.key_outlined, size: 18),
                          label: const Text('Add API key'),
                        ),
                      ] else ...[
                        Text(credentials.provider.label, style: serif(18)),
                        const SizedBox(height: 4),
                        Text(
                          credentials.maskedKey,
                          style: const TextStyle(
                            fontSize: 14,
                            letterSpacing: 1,
                            color: LoremarkColors.muted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Stored only on this device.',
                          style: TextStyle(
                            fontSize: 12,
                            color: LoremarkColors.muted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => ApiKeyScreen.push(context),
                              child: const Text('Change key'),
                            ),
                            TextButton(
                              onPressed: () => _remove(context, settings),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Text('ABOUT', style: kicker(color: LoremarkColors.muted)),
              const SizedBox(height: 8),
              const _AboutCard(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Who Loremark is, with the companion's portrait.
class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: LoremarkColors.welcomeBorder),
        gradient: const LinearGradient(
          colors: [LoremarkColors.welcomeStart, LoremarkColors.welcomeEnd],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: LoremarkColors.gold, width: 2),
              image: const DecorationImage(
                image: AssetImage(LoremarkArt.avatar),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Loremark',
                  style: serif(18, color: LoremarkColors.welcomeTitle),
                ),
                const SizedBox(height: 4),
                const Text(
                  'A reading companion that only knows the chapters you '
                  'have reached. Your books stay on this device.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: LoremarkColors.welcomeText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
