import 'package:flutter/material.dart';

import '../story_update/story_model_choice.dart';
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
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
                sliver: SliverList.list(
                  children: [
                    Text('LOREMARK', style: kicker()),
                    const SizedBox(height: 9),
                    Text('Settings', style: serif(29, height: 1.18)),
                    const SizedBox(height: 26),
                    Text(
                      'AI PROVIDER',
                      style: kicker(color: LoremarkColors.muted),
                    ),
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
                                'OpenAI, DeepSeek or OpenRouter API key.',
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
                              Text(
                                credentials.provider.label,
                                style: serif(18),
                              ),
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
                    const SizedBox(height: 26),
                    Text(
                      'STORY MAP',
                      style: kicker(color: LoremarkColors.muted),
                    ),
                    const SizedBox(height: 8),
                    _StoryMapSettings(settings: settings),
                  ],
                ),
              ),
              // Fills whatever height is left, so the flourish sits at the
              // bottom of the screen and scrolls along on short screens.
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: _Flourish(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A quiet sign-off for the bottom of the screen: the companion reading,
/// faded into the paper above a thin gold rule.
class _Flourish extends StatelessWidget {
  const _Flourish();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 36, 40, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: 0.55,
              child: Image.asset(LoremarkArt.chibiPondering, height: 104),
            ),
            const SizedBox(height: 14),
            const Row(
              children: [
                Expanded(child: _Rule(fadeTowardsStart: true)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(
                    Icons.auto_awesome,
                    size: 12,
                    color: LoremarkColors.gold,
                  ),
                ),
                Expanded(child: _Rule(fadeTowardsStart: false)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'HAPPY READING',
              style: kicker(
                color: LoremarkColors.muted.withValues(alpha: 0.8),
                size: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A hairline that fades out at one end.
class _Rule extends StatelessWidget {
  const _Rule({required this.fadeTowardsStart});

  final bool fadeTowardsStart;

  @override
  Widget build(BuildContext context) {
    final faded = LoremarkColors.gold.withValues(alpha: 0);
    final solid = LoremarkColors.gold.withValues(alpha: 0.55);
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: fadeTowardsStart ? [faded, solid] : [solid, faded],
        ),
      ),
    );
  }
}

/// What Story Map updates use: the model, how hard it thinks, and how strictly
/// its answers are checked.
class _StoryMapSettings extends StatelessWidget {
  const _StoryMapSettings({required this.settings});

  final AiSettings settings;

  @override
  Widget build(BuildContext context) {
    final provider = settings.credentials?.provider;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The choices depend on the provider, so they wait for a key.
            if (provider != null) ...[
              _Choice<StoryModelChoice>(
                label: 'Model',
                value: settings.storyModel,
                options: StoryModelChoice.forProvider(provider.name),
                optionLabel: (model) => model.label,
                onChanged: settings.setStoryModel,
              ),
              _Choice<StoryEffort>(
                label: 'Reasoning effort',
                value: settings.storyEffort,
                options: settings.storyModel.efforts,
                optionLabel: (effort) => effort.label,
                onChanged: settings.setStoryEffort,
              ),
              const Padding(
                padding: EdgeInsets.only(top: 2, bottom: 6),
                child: Text(
                  'Higher effort can give better results, but takes longer '
                  'and costs more.',
                  style: TextStyle(fontSize: 12, color: LoremarkColors.muted),
                ),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Strict quote check'),
              subtitle: const Text(
                'Reject an update if a quote can’t be found in the book. '
                'A rejected update still costs you. When off, those quotes '
                'are only flagged.',
              ),
              value: settings.checkStoryQuotes,
              onChanged: settings.setCheckStoryQuotes,
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.options,
    required this.optionLabel,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> options;
  final String Function(T) optionLabel;
  final Future<void> Function(T) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 8),
        Flexible(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: [
              for (final option in options)
                DropdownMenuItem(
                  value: option,
                  child: Text(
                    optionLabel(option),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (picked) {
              if (picked != null) onChanged(picked);
            },
          ),
        ),
      ],
    );
  }
}
