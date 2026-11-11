import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../ask/ask_backend.dart' show RecentPages;
import '../ask/ask_boundary.dart';
import '../ask/ask_citations.dart';
import '../ask/ask_controller.dart';
import '../ask/ask_history.dart' show AskConversation;
import '../reader/epub_reader_service.dart';
import '../reading/text_position.dart';
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
    this.recap,
  });

  final AskController controller;

  /// Whether this is the tab showing. The reader may have read on since it last
  /// was, so coming back looks at their place again.
  final bool active;

  final VoidCallback onOpenStoryMap;

  /// Shows a passage an answer cites in the Read tab.
  final Future<void> Function(PassageTarget target) onOpenPassage;

  /// The welcome-back recap (use case 1), shown above the conversation, so a
  /// follow-up question goes right below it. It hides itself when there is
  /// nothing to recap.
  final Widget? recap;

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  final _scroll = ScrollController();

  /// Leaving the app counts as leaving Ask, for how long the reader is away.
  /// Null only in a state kept by a hot reload from before it existed.
  AppLifecycleListener? _lifecycle;

  AskController get _ask => widget.controller;

  @override
  void initState() {
    super.initState();
    _ask.addListener(_changed);
    _ask.draft.addListener(_draftChanged);
    _lifecycle = AppLifecycleListener(
      onHide: () {
        if (widget.active) _ask.leave();
      },
      onShow: () {
        if (widget.active) unawaited(_ask.refresh());
      },
    );
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
    if (!widget.active && oldWidget.active) _ask.leave();
  }

  @override
  void dispose() {
    _ask
      ..removeListener(_changed)
      ..draft.removeListener(_draftChanged);
    _lifecycle?.dispose();
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

  /// The book's saved conversations, to open one, start a new one, or delete
  /// one.
  Future<void> _openConversations() => showFactSheet(
    context,
    builder: (sheetContext, scrollController) => ListenableBuilder(
      listenable: _ask,
      builder: (context, _) {
        final conversations = _ask.conversations;
        final now = DateTime.now();
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('CONVERSATIONS', style: kicker()),
            ),
            ListTile(
              enabled: !_ask.busy,
              leading: const Icon(Icons.add_comment_outlined),
              title: const Text('New conversation'),
              onTap: () {
                Navigator.pop(sheetContext);
                _ask.startNew();
              },
            ),
            if (conversations.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'Conversations you have about this book are kept here.',
                  style: TextStyle(fontSize: 13, color: LoremarkColors.muted),
                ),
              ),
            for (final conversation in conversations)
              ListTile(
                key: ValueKey('conversation-${conversation.id}'),
                enabled: !_ask.busy,
                selected: conversation.id == _ask.conversationId,
                selectedColor: LoremarkColors.ink,
                selectedTileColor: LoremarkColors.panel,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                title: Text(
                  conversation.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${conversationTime(conversation.updatedAt, now)} · '
                  '${conversation.length} '
                  '${conversation.length == 1 ? 'question' : 'questions'}',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _ask.open(conversation.id);
                },
                trailing: IconButton(
                  tooltip: 'Delete conversation',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: _ask.busy && conversation.id == _ask.conversationId
                      ? null
                      : () => _deleteConversation(conversation),
                ),
              ),
          ],
        );
      },
    ),
  );

  Future<void> _deleteConversation(AskConversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this conversation?'),
        content: const Text(
          'Its questions and answers are removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _ask.deleteConversation(conversation.id);
  }

  /// Shows the passage a citation chip stands for: one or more lines of the
  /// recent pages, or paragraphs of one section, that follow each other (see
  /// `citedPassages`). [limit] is where the reader's page ended when the
  /// answer was given.
  Future<void> _openCitation(List<AskRef> passage, TextPosition? limit) async {
    if (passage.first.isPage) {
      final lines = [for (final ref in passage) ?ref.line];
      if (limit != null) await _openRecentPages(lines, limit);
      return;
    }
    final boundary = _ask.boundary;
    final section = boundary?.model?.sectionById(passage.first.sectionId!);
    final cited = [
      for (final ref in passage)
        ?boundary?.paragraphs.paragraph(ref.sectionId!, ref.paragraphId!),
    ];
    if (boundary == null || section == null || cited.isEmpty) return;
    final citedIds = {for (final paragraph in cited) paragraph.id};
    final shown = boundary.paragraphs.forEvidence([
      for (final paragraph in cited)
        Evidence(
          sectionId: paragraph.sectionId,
          paragraphId: paragraph.id,
          quote: '',
        ),
    ], context: 1);
    await showFactSheet(
      context,
      builder: (sheetContext, scrollController) => _PassageSheet(
        scrollController: scrollController,
        heading: section.name,
        passages: [
          for (final paragraph in shown)
            (paragraph.text, citedIds.contains(paragraph.id)),
        ],
        onOpen: () => _openInBook(sheetContext, section, cited),
      ),
    );
  }

  /// Shows [lines] of the recent pages an answer was given when the reader's
  /// page ended at [limit], with one on either side; or all of them if [lines]
  /// is empty or isn't among them.
  Future<void> _openRecentPages(List<int> lines, TextPosition limit) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    RecentPages? pages;
    try {
      pages = await _ask.backend.recentPages(_ask.book, limit);
    } on Object catch (error) {
      debugPrint('Could not read the recent pages: $error');
    }
    if (!mounted) return;
    if (pages == null) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Couldn’t find those pages in the book.')),
      );
      return;
    }
    final all = pages.lines;
    final cited = {
      for (final line in lines)
        if (line >= 1 && line <= all.length) line,
    };
    // Lines that follow each other, as `citedPassages` makes them.
    final ordered = cited.toList()..sort();
    final first = ordered.firstOrNull;
    final last = ordered.lastOrNull;
    // The jump goes to the first, and all of them are highlighted.
    final target = first == null
        ? pages.target(all.length)
        : pages.target(first).alsoHighlighting([
            for (final line in ordered.skip(1)) pages.target(line),
          ]);
    await showFactSheet(
      context,
      builder: (sheetContext, scrollController) => _PassageSheet(
        scrollController: scrollController,
        heading: 'RECENT PAGES',
        intro:
            'What Ask saw: the page you were on when you asked, and a few '
            'pages before it.',
        passages: first == null || last == null
            ? [for (final at in all) (at.text, false)]
            : [
                for (
                  var n = max(1, first - 1);
                  n <= min(all.length, last + 1);
                  n++
                )
                  (all[n - 1].text, cited.contains(n)),
              ],
        onOpen: () async {
          Navigator.of(sheetContext).pop();
          await widget.onOpenPassage(target);
        },
      ),
    );
  }

  /// Goes to the first of [paragraphs], highlighting all of them.
  Future<void> _openInBook(
    BuildContext sheetContext,
    StorySection section,
    List<StoryParagraph> paragraphs,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    PassageTarget? target;
    try {
      final placed = [
        for (final paragraph in paragraphs)
          ?await _ask.backend.passageTarget(_ask.book, section, paragraph),
      ];
      if (placed.isNotEmpty) {
        target = placed.first.alsoHighlighting(placed.sublist(1));
      }
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

    int? paragraphNumber(AskRef ref) => boundary?.paragraphs
        .paragraph(ref.sectionId!, ref.paragraphId!)
        ?.number;

    // Recent pages can be shown when the answer's page end was measured;
    // paragraphs while the reader is still past them.
    bool Function(List<AskRef>) visibleAt(TextPosition? limit) =>
        (passage) => passage.every(
          (ref) => ref.isPage
              ? limit != null && limit.progression > 0
              : paragraphNumber(ref) != null,
        );

    final Widget conversation;
    if (exchanges.isEmpty && pending == null) {
      conversation = EmptyState(
        top: widget.recap,
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
          ?widget.recap,
          for (final exchange in exchanges) ...[
            _Question(exchange.question),
            _Answer(
              text: exchange.answer,
              cutOff: exchange.cutOff,
              paragraphNumber: paragraphNumber,
              visible: visibleAt(exchange.limit),
              onCite: (passage) => _openCitation(passage, exchange.limit),
            ),
          ],
          if (pending != null) ...[
            _Question(pending.question),
            if (pending.running)
              _Working(
                pending: pending,
                paragraphNumber: paragraphNumber,
                visible: visibleAt(boundary?.reach.limit),
                onCite: (passage) =>
                    _openCitation(passage, boundary?.reach.limit),
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
            onConversations: _openConversations,
            onNew: exchanges.isEmpty || _ask.busy ? null : _ask.startNew,
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
    required this.onConversations,
    required this.onNew,
  });

  final AskController controller;
  final VoidCallback onOpenStoryMap;
  final VoidCallback onConversations;

  /// Null when there's nothing to start afresh from.
  final VoidCallback? onNew;

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
        advice = 'Build a Story Map to ask about more than your recent pages.';
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
                IconButton(
                  tooltip: 'Conversations',
                  visualDensity: VisualDensity.compact,
                  onPressed: onConversations,
                  icon: const Icon(Icons.history, size: 20),
                ),
                IconButton(
                  tooltip: 'New conversation',
                  visualDensity: VisualDensity.compact,
                  onPressed: onNew,
                  icon: const Icon(Icons.add_comment_outlined, size: 20),
                ),
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

  static String _pageSummary(AskBoundary boundary) => boundary.page == null
      ? 'Can’t see your recent pages'
      : 'Sees your recent pages';

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
    required this.paragraphNumber,
    required this.visible,
    required this.onCite,
    this.cutOff = false,
  });

  final String text;
  final bool cutOff;
  final int? Function(AskRef ref) paragraphNumber;
  final bool Function(List<AskRef> passage) visible;
  final void Function(List<AskRef> passage) onCite;

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
          _AnswerText(
            parts: parts,
            paragraphNumber: paragraphNumber,
            visible: visible,
            onCite: onCite,
          ),
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
    required this.paragraphNumber,
    required this.visible,
    required this.onCite,
  });

  final List<AnswerPart> parts;
  final int? Function(AskRef ref) paragraphNumber;
  final bool Function(List<AskRef> passage) visible;
  final void Function(List<AskRef> passage) onCite;

  @override
  Widget build(BuildContext context) {
    // A passage cited again keeps its number.
    final numbers = <String, int>{};
    final spans = <InlineSpan>[];
    for (final part in parts) {
      switch (part) {
        case AnswerText(:final text):
          spans.add(TextSpan(text: text));
        case AnswerCitation(:final refs):
          for (final passage in citedPassages(refs, paragraphNumber)) {
            final first = passage.first;
            // Lines of the recent pages are numbered with the paragraphs;
            // the recent pages as a whole, from older answers, aren't.
            final label = first.isPage && first.line == null
                ? 'recent pages'
                : '${numbers.putIfAbsent(passage.join(', '), () => numbers.length + 1)}';
            final enabled = visible(passage);
            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _CitationChip(
                  label: label,
                  tooltip: first.isPage
                      ? 'From your recent pages'
                      : enabled
                      ? 'Show the passage'
                      : 'Past where you are now',
                  onTap: enabled ? () => onCite(passage) : null,
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

/// What a citation points to: the cited passage marked, the ones around it
/// faded, and a way into the book. With none marked, all are shown plainly.
class _PassageSheet extends StatelessWidget {
  const _PassageSheet({
    required this.scrollController,
    required this.heading,
    required this.passages,
    required this.onOpen,
    this.intro,
  });

  final ScrollController scrollController;
  final String heading;
  final String? intro;

  /// Each passage's text, and whether it is the one cited.
  final List<(String, bool)> passages;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final anyCited = passages.any((passage) => passage.$2);
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      children: [
        Text(heading, style: kicker()),
        if (intro case final intro?) ...[
          const SizedBox(height: 6),
          Text(
            intro,
            style: const TextStyle(fontSize: 12.5, color: LoremarkColors.muted),
          ),
        ],
        const SizedBox(height: 12),
        for (final (text, cited) in passages)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: cited
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
              text,
              style: serif(
                15,
                height: 1.6,
                color: cited || !anyCited
                    ? LoremarkColors.readerText
                    : LoremarkColors.muted,
              ),
            ),
          ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('Open in book'),
          ),
        ),
      ],
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
    required this.paragraphNumber,
    required this.visible,
    required this.onCite,
  });

  final AskPending pending;
  final int? Function(AskRef ref) paragraphNumber;
  final bool Function(List<AskRef> passage) visible;
  final void Function(List<AskRef> passage) onCite;

  @override
  Widget build(BuildContext context) {
    if (pending.text.isNotEmpty) {
      return _AnswerCard(
        child: _AnswerText(
          parts: splitAnswer(pending.text, streaming: true),
          paragraphNumber: paragraphNumber,
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

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// When a conversation was last added to, as its list shows it: the time if
/// it was [now]'s day, the date if [now]'s year, and the year too if earlier.
@visibleForTesting
String conversationTime(DateTime time, DateTime now) {
  final at = time.toLocal();
  final today = now.toLocal();
  final sameYear = at.year == today.year;
  if (sameYear && at.month == today.month && at.day == today.day) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Today ${two(at.hour)}:${two(at.minute)}';
  }
  final date = '${_months[at.month - 1]} ${at.day}';
  return sameYear ? date : '$date, ${at.year}';
}
