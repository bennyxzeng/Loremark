import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/decor.dart';
import '../theme/loremark_theme.dart';
import 'ai_settings.dart';
import 'api_key_screen.dart';
import 'connection_status.dart';

/// Shows [child] blurred behind a lock until the reader adds an API key and,
/// if [needsConnection], while the device is offline.
class AiLock extends StatelessWidget {
  const AiLock({
    super.key,
    required this.feature,
    this.needsConnection = false,
    required this.child,
  });

  /// What the reader is missing, e.g. "Ask".
  final String feature;

  /// Whether [feature] calls the provider each time it's used, so it can't
  /// work offline.
  final bool needsConnection;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final settings = AiSettingsScope.of(context);
    // A missing key comes first: reconnecting wouldn't unlock anything.
    if (!settings.hasKey) {
      return _Locked(
        badge: Icons.lock_outline,
        title: '$feature needs an API key',
        message:
            '$feature uses an AI model through your own OpenAI or DeepSeek '
            'API key. Reading works without one.',
        action: FilledButton.icon(
          onPressed: () => ApiKeyScreen.push(context),
          icon: const Icon(Icons.key_outlined, size: 18),
          label: const Text('Add API key'),
        ),
        child: child,
      );
    }
    if (needsConnection && !ConnectionScope.of(context).isOnline) {
      return _Locked(
        badge: Icons.wifi_off,
        title: '$feature needs a connection',
        message:
            '$feature sends your question to '
            '${settings.credentials!.provider.label}, so it needs the '
            'internet. It unlocks on its own once you’re back online.',
        child: child,
      );
    }
    return child;
  }
}

class _Locked extends StatelessWidget {
  const _Locked({
    required this.badge,
    required this.title,
    required this.message,
    this.action,
    required this.child,
  });

  final IconData badge;
  final String title;
  final String message;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          child: IgnorePointer(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
              child: child,
            ),
          ),
        ),
        ColoredBox(color: LoremarkColors.paper.withValues(alpha: 0.6)),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Image.asset(
                          LoremarkArt.chibiReading,
                          height: 120,
                          excludeFromSemantics: true,
                        ),
                        Positioned(
                          right: 4,
                          bottom: 2,
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: LoremarkColors.olive,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: LoremarkColors.card,
                                width: 3,
                              ),
                            ),
                            child: Icon(
                              badge,
                              size: 18,
                              color: LoremarkColors.onOlive,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: serif(21, height: 1.25),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: LoremarkColors.muted,
                      ),
                    ),
                    if (action != null) ...[const SizedBox(height: 18), action],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
