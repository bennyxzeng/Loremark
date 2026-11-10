import 'dart:async';

import 'package:flutter/material.dart';

import '../ask/ask_boundary.dart';
import '../ask/ask_citations.dart';
import '../ask/ask_controller.dart';
import '../reader/epub_reader_service.dart';
import '../settings/ai_settings.dart';
import '../story_map/story_facts.dart';
import '../story_model/story_model.dart';
import '../story_update/story_paragraphs.dart';
import '../theme/decor.dart';
import '../theme/loremark_theme.dart';
import 'empty_state.dart';

/// The Ask tab: questions about the book, answered from the page the reader is
/// on and what they read before it, and nothing after.
class AskScreen extends StatefulWidget {
  const AskScreen({
    super.key,
    required this.controller,
    required this.active,
    required this.onOpenStoryMap,
    required this.onOpenPassage,
  });

  final AskController controller;

  /// Whether this is the tab showing. The reader may have read on since it last
  /// was, so coming back looks at their place again.
  final bool active;

  final VoidCallback onOpenStoryMap;

  /// Shows a passage an answer cites in the Read tab.
  final Future<void> Function(PassageTarget target) onOpenPassage;

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  final _scroll = ScrollController();

  AskController get _ask => widget.controller;

  @override
  void initState() {
    super.initState();
    _ask.addListener(_changed);
    _ask.draft.addListener(_draftChanged);
    if (widget.active) unawaited(_ask.refresh());
  }

  @override
  void didUpdateWidget(AskScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller
        ..removeListener(_changed)
        ..draft.removeListener(_draftChanged);
      _ask
        ..addListener(_changed)
        ..draft.addListener(_draftChanged);
    }
    if (widget.active && !oldWidget.active) unawaited(_ask.refresh());
  }

  @override
  void dispose() {
    _ask
      ..removeListener(_changed)
      ..draft.removeListener(_draftChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _draftChanged() => setState(() {});

  Future<void> _send() async {
    final settings = AiSettingsScope.of(context);
    final credentials = settings.credentials;
    final question = _ask.draft.text;
    if (credentials == null || question.trim().isEmpty || _ask.busy) return;
    _ask.draft.clear();
    await _ask.ask(
      question,
      credentials: credentials,
      model: settings.chatModel,
      effort: settings.chatEffort,
    );
  }

  Future<void> _retry() async {
    final settings = AiSettingsScope.of(context);
    final credentials = settings.credentials;
    if (credentials == null) return;
    await _ask.retry(
      credentials: credentials,
      model: settings.chatModel,
      effort: settings.chatEffort,
    );
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear this conversation?'),
        content: const Text(
          'The questions and answers about this book are removed from this '
          'device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _ask.clear();
  }

  /// Shows the paragraph [ref] names, with one on either side.
  Future<void> _openCitation(AskRef ref) async {
    final boundary = _ask.boundary;
    final section = boundary?.model?.sectionById(ref.sectionId!);
    final cited = boundary?.paragraphs.paragraph(
      ref.sectionId!,
      ref.paragraphId!,
    );
    if (boundary == null || section == null || cited == null) return;
    final shown = boundary.paragraphs.forEvidence([
      Evidence(sectionId: cited.sectionId, paragraphId: cited.id, quote: ''),
    ], context: 1);
    await showFactSheet(
      context,
      builder: (sheetContext, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        children: [
          Text(section.name, style: kicker()),
          const SizedBox(height: 12),
          for (final paragraph in shown)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: paragraph.id == cited.id
                  ? const BoxDecoration(
                      color: LoremarkColors.noteQuote,
                      border: Border(
                        left: BorderSide(
                          color: LoremarkColors.noteBorder,
                          width: 3,
                        ),
                      ),
                    )
                  : null,
              child: Text(
                paragraph.text,
                style: serif(
                  15,
                  height: 1.6,
                  color: paragraph.id == cited.id
                      ? LoremarkColors.readerText
                      : LoremarkColors.muted,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => _openInBook(sheetContext, section, cited),
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: const Text('Open in book'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openInBook(
    BuildContext sheetContext,
    StorySection section,
    StoryParagraph paragraph,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    PassageTarget? target;
    try {
      target = await _ask.backend.passageTarget(_ask.book, section, paragraph);
    } on Object catch (error) {
      debugPrint('Could not place the passage: $error');
    }
    if (!mounted) return;
    if (target == null) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Couldn’t find that passage in the book.'),
        ),
      );
      return;
    }
    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
    await widget.onOpenPassage(target);
  }

  @override
  Widget build(BuildContext context) {
    final boundary = _ask.boundary;
    final exchanges = _ask.exchanges;
    final pending = _ask.pending;
    final canAsk = boundary != null && !boundary.isEmpty;

    bool visible(AskRef ref) =>
        !ref.isPage &&
        boundary?.paragraphs.paragraph(ref.sectionId!, ref.paragraphId!) !=
            null;

    final Widget conversation;
    if (exchanges.isEmpty && pending == null) {
      conversation = EmptyState(
        image: LoremarkArt.chibiHush,
        label: 'A THREAD BACK INTO THE STORY',
        title: 'Ask about what you’ve read.',
        icon: Icons.chat_bubble_outline,
        message: boundary != null && boundary.isEmpty
            ? 'Read a page first. Answers only use what you’ve read.'
            : 'Ask about a person, a place, or what just happened. Answers '
                  'use only what you’ve read, up to the end of this page, and '
                  'show where in the book they come from.',
      );
    } else {
      conversation = ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
        children: [
          for (final exchange in exchanges) ...[
            _Question(exchange.question),
            _Answer(
              text: exchange.answer,
              cutOff: exchange.cutOff,
              visible: visible,
              onCite: _openCitation,
            ),
          ],
          if (pending != null) ...[
            _Question(pending.question),
            if (pending.running)
              _Working(
                pending: pending,
                visible: visible,
                onCite: _openCitation,
              )
            else
              _Failed(
                message: pending.failure ?? '',
                onRetry: _retry,
                onDismiss: _ask.dismiss,
              ),
          ],
        ],
      );
    }

    return ColoredBox(
      color: LoremarkColors.paper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Coverage(
            controller: _ask,
            onOpenStoryMap: widget.onOpenStoryMap,
            onClear: exchanges.isEmpty || _ask.busy ? null : _clear,
          ),
          Expanded(child: conversation),
          _Composer(
            draft: _ask.draft,
            enabled: canAsk,
            busy: _ask.busy,
            onSend: _send,
            onStop: _ask.stop,
          ),
        ],
      ),
    );
  }
}

/// What answers can draw on, in one line, and what to do when it isn't enough.
class _Coverage extends StatelessWidget {
  const _Coverage({
    required this.controller,
    required this.onOpenStoryMap,
    required this.onClear,
  });

  final AskController controller;
  final VoidCallback onOpenStoryMap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final boundary = controller.boundary;
    final String summary;
    String? advice;
    if (boundary == null) {
      summary = controller.boundaryError == null
          ? 'Finding your place…'
          : 'Couldn’t work out where you are in the book.';
    } else {
      summary = '${_pageSummary(boundary)} · ${_mapSummary(boundary)}';
      if (boundary.model == null) {
        advice = 'Build a Story Map to ask about more than this page.';
      } else if (boundary.reach.pastMap) {
        advice =
            'You’re past what the Story Map covers. Update it to ask about '
            'this part.';
      }
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: LoremarkColors.boundary,
        border: Border(bottom: BorderSide(color: LoremarkColors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 14,
                  color: LoremarkColors.safeDot,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: LoremarkColors.boundaryText,
                    ),
                  ),
                ),
                if (onClear != null)
                  IconButton(
                    tooltip: 'Clear conversation',
                    visualDensity: VisualDensity.compact,
                    onPressed: onClear,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                  )
                else
                  const SizedBox(height: 40),
              ],
            ),
            if (advice != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      advice,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: LoremarkColors.muted,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onOpenStoryMap,
                    child: const Text('Story Map'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  static String _pageSummary(AskBoundary boundary) =>
      boundary.page == null ? 'Can’t see this page' : 'Sees this page';

  static String _mapSummary(AskBoundary boundary) {
    if (boundary.model == null) return 'No Story Map yet';
    final sections = boundary.sections;
    if (sections.isEmpty) return 'Story Map: nothing you’ve read yet';
    return 'Story Map to ${sections.last.name}'
        '${boundary.partway ? ', partway' : ''}';
  }
}

class _Question extends StatelessWidget {
  const _Question(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10, left: 40),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: const BoxDecoration(
            color: LoremarkColors.panel,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: SelectableText(
            text,
            style: const TextStyle(fontSize: 14, height: 1.45),
          ),
        ),
      ),
    );
  }
}

/// The frame an answer sits in.
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18, right: 24),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: LoremarkColors.card,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(14),
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
        border: Border.all(color: LoremarkColors.line),
      ),
      child: child,
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer({
    required this.text,
    required this.visible,
    required this.onCite,
    this.cutOff = false,
  });

  final String text;
  final bool cutOff;
  final bool Function(AskRef ref) visible;
  final void Function(AskRef ref) onCite;

  @override
  Widget build(BuildContext context) {
    final parts = splitAnswer(text);
    final notes = [
      if (cutOff) 'Cut off before it finished.',
      if (!citesAnything(parts)) 'No passage cited.',
    ];
    return _AnswerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AnswerText(parts: parts, visible: visible, onCite: onCite),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              notes.join(' '),
              style: const TextStyle(fontSize: 11, color: LoremarkColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// An answer's words, with its citations as small numbered chips.
class _AnswerText extends StatelessWidget {
  const _AnswerText({
    required this.parts,
    required this.visible,
    required this.onCite,
  });

  final List<AnswerPart> parts;
  final bool Function(AskRef ref) visible;
  final void Function(AskRef ref) onCite;

  @override
  Widget build(BuildContext context) {
    final numbers = <AskRef, int>{};
    final spans = <InlineSpan>[];
    for (final part in parts) {
      switch (part) {
        case AnswerText(:final text):
          spans.add(TextSpan(text: text));
        case AnswerCitation(:final refs):
          for (final ref in refs) {
            final label = ref.isPage
                ? 'this page'
                : '${numbers.putIfAbsent(ref, () => numbers.length + 1)}';
            final enabled = visible(ref);
            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _CitationChip(
                  label: label,
                  tooltip: ref.isPage
                      ? 'From the page you’re on'
                      : enabled
                      ? 'Show the passage'
                      : 'Past where you are now',
                  onTap: enabled ? () => onCite(ref) : null,
                ),
              ),
            );
          }
      }
    }
    return Text.rich(
      TextSpan(children: spans),
      style: serif(15.5, height: 1.6, color: LoremarkColors.readerText),
    );
  }
}

class _CitationChip extends StatelessWidget {
  const _CitationChip({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: enabled ? LoremarkColors.chip : LoremarkColors.boundary,
          shape: const StadiumBorder(
            side: BorderSide(color: LoremarkColors.chipBorder),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: enabled
                      ? LoremarkColors.chipText
                      : LoremarkColors.muted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A question under way: what it is doing, then its answer as it arrives.
class _Working extends StatelessWidget {
  const _Working({
    required this.pending,
    required this.visible,
    required this.onCite,
  });

  final AskPending pending;
  final bool Function(AskRef ref) visible;
  final void Function(AskRef ref) onCite;

  @override
  Widget build(BuildContext context) {
    if (pending.text.isNotEmpty) {
      return _AnswerCard(
        child: _AnswerText(
          parts: splitAnswer(pending.text, streaming: true),
          visible: visible,
          onCite: onCite,
        ),
      );
    }
    // Words, not a spinner: an endless animation would keep widget tests
    // from settling.
    final status = switch (pending.stage) {
      AskStage.reading => 'Finding your place…',
      AskStage.lookingUp => 'Checking the Story Map…',
      _ => 'Thinking…',
    };
    return _AnswerCard(
      child: Text(
        status,
        style: const TextStyle(
          fontSize: 13,
          fontStyle: FontStyle.italic,
          color: LoremarkColors.muted,
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return _AnswerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: LoremarkColors.muted,
            ),
          ),
          Row(
            children: [
              TextButton(onPressed: onRetry, child: const Text('Try again')),
              TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.draft,
    required this.enabled,
    required this.busy,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController draft;
  final bool enabled;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final canSend = enabled && !busy && draft.text.trim().isNotEmpty;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: LoremarkColors.header,
        border: Border(top: BorderSide(color: LoremarkColors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('ask-input'),
                controller: draft,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) {
                  if (canSend) onSend();
                },
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                  hintText: enabled
                      ? 'Ask about the story so far'
                      : 'Read a page to start asking',
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (busy)
              IconButton.filled(
                tooltip: 'Stop',
                onPressed: onStop,
                icon: const Icon(Icons.stop_rounded),
              )
            else
              IconButton.filled(
                tooltip: 'Ask',
                onPressed: canSend ? onSend : null,
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
          ],
        ),
      ),
    );
  }
}
