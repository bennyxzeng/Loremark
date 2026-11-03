import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/decor.dart';
import '../theme/loremark_theme.dart';
import 'ai_settings.dart';
import 'api_key_screen.dart';

/// Shows [child] blurred behind a lock until the reader adds an API key.
class AiLock extends StatelessWidget {
  const AiLock({super.key, required this.feature, required this.child});

  /// What the reader is missing, e.g. "Ask".
  final String feature;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AiSettingsScope.of(context).hasKey) return child;

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
                            child: const Icon(
                              Icons.lock_outline,
                              size: 18,
                              color: LoremarkColors.onOlive,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '$feature needs an API key',
                      textAlign: TextAlign.center,
                      style: serif(21, height: 1.25),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Ask and Story Map use an AI model through your own '
                      'OpenAI or DeepSeek API key. Reading works without one.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: LoremarkColors.muted,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () => ApiKeyScreen.push(context),
                      icon: const Icon(Icons.key_outlined, size: 18),
                      label: const Text('Add API key'),
                    ),
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
