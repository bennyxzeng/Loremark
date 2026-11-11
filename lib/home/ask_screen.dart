import 'dart:async';

import 'package:flutter/material.dart';

import '../reader/epub_reader_service.dart';
import '../recap/recap_backend.dart';
import '../recap/recap_client.dart';
import '../recap/recap_controller.dart';
import '../recap/recap_source.dart';
import '../settings/ai_settings.dart';
import '../theme/decor.dart';
import '../theme/loremark_theme.dart';
import 'empty_state.dart';

/// The Ask tab: the "welcome back" recap of the story up to where the reader
/// stopped, the same place the Story Map stops (use case 1).
///
/// The welcome-back pop-up over the Read tab can start a recap and bring the
/// reader here. Questions about the story (use case 6) will go here too.
class AskScreen extends StatefulWidget {
  const AskScreen({
    super.key,
    required this.controller,
    this.active = true,
    this.onBackToBook,
    this.onOpenPassage,
    this.onOpenStoryMap,
  });

  /// The book's recap, shared with the Read tab's welcome-back card.
  final RecapController controller;

  /// Whether the tab is showing. Where the recap stops is found again each time
  /// the tab opens, since the reader may have read on or updated the map.
  final bool active;

  /// Goes back to the Read tab.
  final VoidCallback? onBackToBook;

  /// Opens the book at a passage behind a recap moment.
  final ValueChanged<PassageTarget>? onOpenPassage;

  /// Opens the Story Map tab, where the map can be updated.
  final VoidCallback? onOpenStoryMap;

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  RecapController get _recap => widget.controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.active && !_recap.prepared) _prepare();
  }

  @override
  void didUpdateWidget(AskScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _prepare();
  }

  /// Looks again for where the recap would stop. Behind the API key lock there
  /// is nothing to get ready for.
  void _prepare() {
    if (_recap.preparing || _recap.writing) return;
    if (!AiSettingsScope.of(context).hasKey) return;
    unawaited(_recap.prepare());
  }

  void _write(AiCredentials credentials) {
    unawaited(_recap.write(credentials));
  }

  @override
  Widget build(BuildContext context) {
    final credentials = AiSettingsScope.of(context).credentials;
    return ListenableBuilder(
      listenable: _recap,
      builder: (context, _) => _build(context, credentials),
    );
  }

  Widget _build(BuildContext context, AiCredentials? credentials) {
    final source = _recap.source;
    final recap = _recap.recap;
    if (recap == null && !_recap.writing) {
      switch (_recap.start) {
        case RecapNeedsStoryMap():
          return const EmptyState(
            image: LoremarkArt.chibiHush,
            label: 'A THREAD BACK INTO THE STORY',
            title: 'Where we left off.',
            icon: Icons.chat_bubble_outline,
            message:
                'Recaps are built from your Story Map.\n'
                'Build it in the Story Map tab, and a recap will be waiting '
                'here.',
          );
        case RecapNeedsReading():
          return const EmptyState(
            image: LoremarkArt.chibiHush,
            label: 'A THREAD BACK INTO THE STORY',
            title: 'Where we left off.',
            icon: Icons.chat_bubble_outline,
            message:
                'Read a few pages, and a recap will be waiting here.\n'
                'Recaps only use what you’ve read.',
          );
        case RecapCanStart() || null:
          break;
      }
    }
    final stopsAt = recap?.stopsAt ?? source?.stopsAt;
    final error = _recap.error;
    return PaperBackground(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
        children: [
          Text('A THREAD BACK INTO THE STORY', style: kicker()),
          const SizedBox(height: 9),
          Text('Where we left off.', style: serif(29, height: 1.18)),
          if (stopsAt != null) ...[
            const SizedBox(height: 8),
            Text(
              '${_recap.book.title} · Up to $stopsAt',
              style: const TextStyle(fontSize: 13, color: LoremarkColors.muted),
            ),
          ],
          const SizedBox(height: 22),
          if (recap == null)
            _WelcomeCard(child: _startOrWait(source, credentials)),
          if (_recap.writing) ...[
            const SizedBox(height: 18),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text(
              'Writing your recap…',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: LoremarkColors.muted),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 16),
            Text(
              error,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          if (recap != null) ...[
            const _CompanionRow(),
            for (final (index, item) in recap.items.indexed)
              _RecapItemTile(
                number: index + 1,
                item: item,
                onOpenPassage: widget.onOpenPassage,
              ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.onBackToBook != null)
                  OutlinedButton(
                    onPressed: widget.onBackToBook,
                    child: const Text('Back to the book →'),
                  ),
                TextButton(
                  onPressed: _recap.writing || credentials == null
                      ? null
                      : () => _write(credentials),
                  child: Text(error != null ? 'Try again' : 'New recap'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Before the first recap: where it would stop and the button that asks for
  /// it, so the reader can check the stopping point before paying for one.
  Widget _startOrWait(RecapSource? source, AiCredentials? credentials) {
    final prepareError = _recap.prepareError;
    if (source == null && prepareError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prepareError,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: LoremarkColors.welcomeText,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _prepare, child: const Text('Look again')),
        ],
      );
    }
    if (source == null) {
      return const Text(
        'Finding your place…',
        style: TextStyle(color: LoremarkColors.welcomeText),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('RECAP UP TO', style: kicker(color: LoremarkColors.welcomeText)),
        const SizedBox(height: 6),
        Text(
          _capitalized(source.stopsAt),
          style: serif(20, color: LoremarkColors.welcomeTitle, height: 1.25),
        ),
        // The map is only updated when the reader asks, so once they have
        // read all it holds, a newer recap needs a newer map.
        if (source.mapEndsHere) ...[
          const SizedBox(height: 8),
          _UpdateMapHint(onOpenStoryMap: widget.onOpenStoryMap),
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _recap.writing || credentials == null
              ? null
              : () => _write(credentials),
          child: Text(_recap.error != null ? 'Try again' : 'Catch me up'),
        ),
        const SizedBox(height: 8),
        const Text(
          'A 30-second read.',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: LoremarkColors.muted,
          ),
        ),
      ],
    );
  }
}

/// Points a reader who has read all the Story Map holds to updating it.
class _UpdateMapHint extends StatelessWidget {
  const _UpdateMapHint({required this.onOpenStoryMap});

  final VoidCallback? onOpenStoryMap;

  static const _style = TextStyle(
    fontSize: 13,
    height: 1.5,
    color: LoremarkColors.welcomeText,
  );

  @override
  Widget build(BuildContext context) {
    final open = onOpenStoryMap;
    if (open == null) {
      return const Text(
        'Want a newer recap? Update your Story Map.',
        style: _style,
      );
    }
    return InkWell(
      onTap: open,
      borderRadius: BorderRadius.circular(6),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text.rich(
          TextSpan(
            style: _style,
            children: [
              TextSpan(text: 'Read further? '),
              TextSpan(
                text: 'Update your Story Map →',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: LoremarkColors.welcomeText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _capitalized(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// The card behind where the recap stops, in the library's welcome-back look.
class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LoremarkColors.welcomeBorder),
        gradient: const LinearGradient(
          colors: [LoremarkColors.welcomeStart, LoremarkColors.welcomeEnd],
        ),
      ),
      child: child,
    );
  }
}

/// "Your story companion", above the recap's moments.
class _CompanionRow extends StatelessWidget {
  const _CompanionRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: LoremarkColors.line),
        ),
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: LoremarkColors.welcomeBorder, width: 2),
            ),
            child: const CircleAvatar(
              radius: 22,
              backgroundImage: AssetImage(LoremarkArt.avatar),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your story companion',
                  style: serif(18, color: LoremarkColors.welcomeTitle),
                ),
                const SizedBox(height: 2),
                const Text(
                  'A little context, just for you.',
                  style: TextStyle(fontSize: 12, color: LoremarkColors.muted),
                ),
              ],
            ),
          ),
          const Icon(Icons.auto_awesome_outlined, color: LoremarkColors.gold),
        ],
      ),
    );
  }
}

/// One numbered moment: its title, summary, chapter, and, when the Story Map
/// cites the book for it, a link to that passage.
class _RecapItemTile extends StatelessWidget {
  const _RecapItemTile({
    required this.number,
    required this.item,
    required this.onOpenPassage,
  });

  final int number;
  final RecapItem item;
  final ValueChanged<PassageTarget>? onOpenPassage;

  @override
  Widget build(BuildContext context) {
    const footer = TextStyle(
      fontSize: 11.5,
      color: LoremarkColors.welcomeText,
      decoration: TextDecoration.underline,
      decorationColor: LoremarkColors.welcomeText,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(
              number.toString().padLeft(2, '0'),
              style: serif(16, color: LoremarkColors.gold),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: LoremarkColors.readerText,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.summary,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: LoremarkColors.muted,
                  ),
                ),
                const SizedBox(height: 6),
                if (item.passages.isEmpty)
                  Text(item.chapter, style: footer)
                else
                  InkWell(
                    onTap: () => _showPassage(context, item, onOpenPassage),
                    child: Text(
                      '${item.chapter} · View passage',
                      style: footer,
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

/// The paragraphs of the book behind a recap moment, as the Story Map cites
/// them, each with a way to read it in the book.
void _showPassage(
  BuildContext context,
  RecapItem item,
  ValueChanged<PassageTarget>? onOpenPassage,
) {
  unawaited(
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('FROM ${item.chapter.toUpperCase()}', style: kicker()),
              const SizedBox(height: 12),
              for (final passage in item.passages) ...[
                Container(
                  padding: const EdgeInsets.only(left: 14),
                  decoration: const BoxDecoration(
                    border: Border(
                      left: BorderSide(color: LoremarkColors.gold, width: 2),
                    ),
                  ),
                  child: Text(
                    passage.text,
                    style: serif(
                      16,
                      color: LoremarkColors.readerText,
                      height: 1.55,
                    ),
                  ),
                ),
                if ((passage.target, onOpenPassage) case (
                  final target?,
                  final open?,
                )) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      open(target);
                    },
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: const Text('Read it in the book'),
                  ),
                ],
                const SizedBox(height: 18),
              ],
              const Text(
                'The book’s words, as your Story Map cites them.',
                style: TextStyle(fontSize: 12, color: LoremarkColors.muted),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
