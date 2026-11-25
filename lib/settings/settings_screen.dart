import 'package:flutter/material.dart';

import '../story_update/story_model_choice.dart';
import '../theme/decor.dart';
import '../theme/loremark_theme.dart';
import 'ai_activity.dart';
import 'ai_settings.dart';
import 'api_key_screen.dart';

/// App-wide settings, opened from the library.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static Future<void> push(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));

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
                    _KeysCard(settings: settings),
                    const SizedBox(height: 26),
                    Text(
                      'STORY MAP',
                      style: kicker(color: LoremarkColors.muted),
                    ),
                    const SizedBox(height: 8),
                    _StoryMapSettings(settings: settings),
                    // Only once there is a provider: the models depend on it.
                    if (credentials != null) ...[
                      const SizedBox(height: 26),
                      Text('ASK', style: kicker(color: LoremarkColors.muted)),
                      const SizedBox(height: 8),
                      _AskSettings(settings: settings),
                    ],
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

/// The saved API keys: which is in use, switching between them, naming,
/// adding and removing them.
///
/// The key in use can't be switched or removed while an AI task runs on it,
/// since the task would carry on with it: see [AiActivity].
class _KeysCard extends StatelessWidget {
  const _KeysCard({required this.settings});

  final AiSettings settings;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        // Tasks start and end without the settings changing.
        child: ListenableBuilder(
          listenable: settings.activity,
          builder: (context, _) =>
              settings.hasKey ? _keys(context) : _notConnected(context),
        ),
      ),
    );
  }

  Widget _notConnected(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Not connected', style: serif(18)),
      const SizedBox(height: 6),
      const Text(
        'Ask and Story Map are locked until you add an OpenAI or DeepSeek API '
        'key.',
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
    ],
  );

  Widget _keys(BuildContext context) {
    final active = settings.credentials!;
    final keys = settings.keys;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (settings.isBusy) ...[
          _BusyNote(label: active.label),
          const SizedBox(height: 8),
        ],
        for (final key in keys)
          _KeyRow(
            credentials: key,
            active: key.id == active.id,
            canSwitch: settings.canSwitch,
            canRemove: settings.canRemove(key.id),
            onUse: () => _guard(context, () => settings.activate(key.id)),
            onRename: () => _rename(context, key),
            onRemove: () => _remove(context, key),
          ),
        const SizedBox(height: 4),
        const Text(
          'Stored only on this device.',
          style: TextStyle(fontSize: 12, color: LoremarkColors.muted),
        ),
        const SizedBox(height: 2),
        TextButton.icon(
          onPressed: settings.canAddKey
              ? () => ApiKeyScreen.push(context)
              : null,
          icon: const Icon(Icons.add, size: 18),
          label: Text(
            settings.canAddKey
                ? 'Add another key (${keys.length} of ${AiSettings.maxKeys})'
                : 'Up to ${AiSettings.maxKeys} keys',
          ),
        ),
      ],
    );
  }

  /// Runs [change], telling the reader if it was turned down because a task
  /// started first.
  Future<void> _guard(
    BuildContext context,
    Future<void> Function() change,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await change();
    } on AiKeyError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _rename(BuildContext context, AiCredentials key) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(credentials: key),
    );
    if (name != null) await settings.rename(key.id, name);
  }

  Future<void> _remove(BuildContext context, AiCredentials key) async {
    final inUse = key.id == settings.credentials?.id;
    final replacement = settings.replacementFor(key.id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          settings.keys.length == 1
              ? 'Remove API key?'
              : 'Remove “${key.label}”?',
        ),
        content: Text(switch ((inUse, replacement)) {
          (_, null) =>
            'Ask and Story Map will be locked until you add a key again.',
          (true, final next?) =>
            'It’s deleted from this device. Loremark will switch to '
                '“${next.label}”.',
          (false, _) => 'It’s deleted from this device.',
        }),
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
    if (confirmed == true && context.mounted) {
      await _guard(context, () => settings.remove(key.id));
    }
  }
}

/// Why the key in use can't be switched or removed just now.
class _BusyNote extends StatelessWidget {
  const _BusyNote({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: LoremarkColors.noteQuote,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.hourglass_top,
            size: 16,
            color: LoremarkColors.chipText,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'An AI task is running on “$label”. You can switch keys, or '
              'remove this one, once it finishes.',
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: LoremarkColors.welcomeText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One saved key: its name, provider and last characters, and what can be done
/// with it.
class _KeyRow extends StatelessWidget {
  const _KeyRow({
    required this.credentials,
    required this.active,
    required this.canSwitch,
    required this.canRemove,
    required this.onUse,
    required this.onRename,
    required this.onRemove,
  });

  final AiCredentials credentials;
  final bool active;
  final bool canSwitch;
  final bool canRemove;
  final VoidCallback onUse;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey('ai-key-${credentials.id}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            active ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 20,
            color: active ? LoremarkColors.olive : LoremarkColors.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  credentials.label,
                  style: serif(17),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  credentials.name == null
                      ? credentials.maskedKey
                      : '${credentials.provider.label} · '
                            '${credentials.maskedKey}',
                  style: const TextStyle(
                    fontSize: 13,
                    letterSpacing: 0.5,
                    color: LoremarkColors.muted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (active)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'In use',
                style: TextStyle(fontSize: 12, color: LoremarkColors.olive),
              ),
            )
          else
            TextButton(
              onPressed: canSwitch ? onUse : null,
              child: const Text('Use'),
            ),
          PopupMenuButton<VoidCallback>(
            tooltip: 'More for ${credentials.label}',
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              PopupMenuItem(value: onRename, child: const Text('Rename')),
              PopupMenuItem(
                value: onRemove,
                enabled: canRemove,
                child: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.credentials});

  final AiCredentials credentials;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _name = TextEditingController(text: widget.credentials.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename key'),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 30,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (name) => Navigator.pop(context, name),
        decoration: InputDecoration(
          labelText: 'Name',
          hintText: widget.credentials.provider.label,
          helperText: 'Leave empty to show the provider’s name.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _name.text),
          child: const Text('Save'),
        ),
      ],
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
                key: const ValueKey('story-model'),
                label: 'Model',
                value: settings.storyModel,
                options: StoryModelChoice.forProvider(provider.name),
                optionLabel: (model) => model.label,
                onChanged: settings.setStoryModel,
              ),
              _Choice<StoryEffort>(
                key: const ValueKey('story-effort'),
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

/// What Ask answers with, chosen apart from what Story Map updates use.
class _AskSettings extends StatelessWidget {
  const _AskSettings({required this.settings});

  final AiSettings settings;

  @override
  Widget build(BuildContext context) {
    final provider = settings.credentials!.provider;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Choice<StoryModelChoice>(
              key: const ValueKey('ask-model'),
              label: 'Model',
              value: settings.chatModel,
              options: StoryModelChoice.forProvider(provider.name),
              optionLabel: (model) => model.label,
              onChanged: settings.setChatModel,
            ),
            _Choice<StoryEffort>(
              key: const ValueKey('ask-effort'),
              label: 'Reasoning effort',
              value: settings.chatEffort,
              options: settings.chatModel.efforts,
              optionLabel: (effort) => effort.label,
              onChanged: settings.setChatEffort,
            ),
            const Padding(
              padding: EdgeInsets.only(top: 2, bottom: 6),
              child: Text(
                'Used for answers in Ask, apart from Story Map updates. A '
                'question can take a few requests while it looks things up.',
                style: TextStyle(fontSize: 12, color: LoremarkColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    super.key,
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
