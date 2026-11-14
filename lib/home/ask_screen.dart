import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../ask/ask_backend.dart' show RecentPages;
import '../ask/ask_boundary.dart';
import '../ask/ask_citations.dart';
import '../ask/ask_controller.dart';
import '../ask/ask_history.dart' show AskConversation;
import '../companion/companion_art.dart';
import '../companion/companion_director.dart';
import '../companion/companion_sprite.dart';
import '../reader/epub_reader_service.dart';
import '../reading/text_position.dart';
import '../settings/ai_settings.dart';
import '../story_map/story_facts.dart';
import '../story_model/story_model.dart';
import '../story_update/story_paragraphs.dart';
import '../theme/decor.dart';
import '../theme/loremark_theme.dart';
import 'eased_keyboard.dart';

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

  /// The question box's focus, to put the keyboard away.
  final _input = FocusNode();

  /// The whole tab, whose bottom the keyboard pushes up.
  final _tab = GlobalKey();

  /// Leaving the app counts as leaving Ask, for how long the reader is away.
  /// Null only in a state kept by a hot reload from before it existed.
  AppLifecycleListener? _lifecycle;

  AskController get _ask => widget.controller;

  @override
  void initState() {
    super.initState();
    _ask.addListener(_changed);
    _ask.draft.addListener(_draftChanged);
    _input.addListener(_focusChanged);
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
    if (!widget.active && oldWidget.active) {
      // The tabs are stacked, so the box would keep the keyboard up over
      // whichever one the reader went to.
      _input.unfocus();
      _ask.leave();
    }
  }

  @override
  void dispose() {
    _ask
      ..removeListener(_changed)
      ..draft.removeListener(_draftChanged);
    _lifecycle?.dispose();
    _scroll.dispose();
    _input
      ..removeListener(_focusChanged)
      ..dispose();
    super.dispose();
  }

  /// The conversation and question the dialogue box last showed, and whether
  /// it was under way, to tell another one being opened from one finishing.
  (String?, int)? _shown;
  bool _wasPending = false;

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final pending = _ask.pending != null;
    final shown = (_ask.conversationId, _ask.exchanges.length);
    final opened = !pending && !_wasPending && shown != _shown;
    _shown = shown;
    _wasPending = pending;
    // The box follows an answer as it arrives, and starts at the question
    // when another conversation is opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      if (pending) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      } else if (opened) {
        _scroll.jumpTo(0);
      }
    });
  }

  void _draftChanged() => setState(() {});

  /// She steps up while a first question is being written, so the keyboard
  /// doesn't shrink her under the heading.
  void _focusChanged() => setState(() {});

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
          _closeLog();
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
    _closeLog();
    await widget.onOpenPassage(target);
  }

  /// Where [ref]'s paragraph is among those read, or null if it is past them.
  int? _paragraphNumber(AskRef ref) => _ask.boundary?.paragraphs
      .paragraph(ref.sectionId!, ref.paragraphId!)
      ?.number;

  /// Whether a passage can be shown, for an answer given when the reader's
  /// page ended at [limit]: recent pages when that end was measured,
  /// paragraphs while the reader is still past them.
  bool Function(List<AskRef>) _visibleAt(TextPosition? limit) =>
      (passage) => passage.every(
        (ref) => ref.isPage
            ? limit != null && limit.progression > 0
            : _paragraphNumber(ref) != null,
      );

  /// The log, while it's open, so going to a passage from it can close it.
  BuildContext? _logSheet;

  /// Every question of the conversation and its answer, as a visual novel's
  /// backlog shows what was said before.
  Future<void> _openLog() async {
    await showFactSheet(
      context,
      builder: (sheetContext, scrollController) {
        _logSheet = sheetContext;
        return ListenableBuilder(
          listenable: _ask,
          builder: (context, _) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
                child: Text('LOG', style: kicker()),
              ),
              for (final exchange in _ask.exchanges) ...[
                _Question(exchange.question),
                _Answer(
                  text: exchange.answer,
                  cutOff: exchange.cutOff,
                  paragraphNumber: _paragraphNumber,
                  visible: _visibleAt(exchange.limit),
                  onCite: (passage) => _openCitation(passage, exchange.limit),
                ),
              ],
            ],
          ),
        );
      },
    );
    _logSheet = null;
  }

  /// Closes the log, if a passage opened from it is being shown in the book.
  void _closeLog() {
    final log = _logSheet;
    if (log != null && log.mounted) Navigator.of(log).pop();
  }

  @override
  Widget build(BuildContext context) {
    final boundary = _ask.boundary;
    final exchanges = _ask.exchanges;
    final pending = _ask.pending;
    final canAsk = boundary != null && !boundary.isEmpty;

    // What she's saying: the question under way, or else the last one asked.
    final last = exchanges.lastOrNull;
    final Widget? said;
    if (pending != null) {
      said = _Said(
        question: pending.question,
        answer: pending.running
            ? _WorkingBody(
                pending: pending,
                paragraphNumber: _paragraphNumber,
                visible: _visibleAt(boundary?.reach.limit),
                onCite: (passage) =>
                    _openCitation(passage, boundary?.reach.limit),
              )
            : _FailedBody(
                message: pending.failure ?? '',
                onRetry: _retry,
                onDismiss: _ask.dismiss,
              ),
      );
    } else if (last != null) {
      said = _Said(
        question: last.question,
        answer: _AnswerBody(
          text: last.answer,
          cutOff: last.cutOff,
          paragraphNumber: _paragraphNumber,
          visible: _visibleAt(last.limit),
          onCite: (passage) => _openCitation(passage, last.limit),
        ),
      );
    } else {
      said = null;
    }

    final conversation = _Stage(
      active: widget.active,
      cue: _companionCue(pending),
      // The question box having focus is the keyboard being up: the Scaffold
      // keeps the keyboard's height out of this tab's MediaQuery.
      close: said != null || _input.hasFocus,
      typing: _input.hasFocus,
      tab: _tab,
      scroll: _scroll,
      said: said,
      onLog: exchanges.isEmpty ? null : _openLog,
    );

    return ColoredBox(
      key: _tab,
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
            focus: _input,
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

/// How the companion looks: her mood, what she's saying so far, and how many
/// citations it has.
typedef _Cue = ({CompanionMood mood, String speech, int citations});

/// How she looks while [pending] is under way: thinking until its answer starts
/// arriving, then saying it. Waiting otherwise.
_Cue _companionCue(AskPending? pending) {
  if (pending == null || !pending.running) {
    return (mood: CompanionMood.idle, speech: '', citations: 0);
  }
  if (pending.stage != AskStage.writing) {
    return (mood: CompanionMood.thinking, speech: '', citations: 0);
  }
  final speech = StringBuffer();
  var citations = 0;
  for (final part in splitAnswer(pending.text, streaming: true)) {
    switch (part) {
      case AnswerText(:final text):
        speech.write(text);
      case AnswerCitation():
        citations++;
    }
  }
  return (
    mood: CompanionMood.talking,
    speech: speech.toString(),
    citations: citations,
  );
}

enum _Slot { heading, companion, floor, dialogue }

/// The Ask tab as a visual novel's scene. Before a first question the heading
/// is shown, with the companion standing under it; once one is being written
/// she steps up [close], and what she [said] is in a dialogue box in front of
/// her.
class _Stage extends StatefulWidget {
  const _Stage({
    required this.active,
    required this.cue,
    required this.close,
    required this.typing,
    required this.tab,
    required this.scroll,
    required this.said,
    required this.onLog,
  });

  final bool active;
  final _Cue cue;

  /// Whether she has stepped up: in a conversation, or while a first question
  /// is being written.
  final bool close;

  /// Whether the question box has focus, the keyboard up.
  final bool typing;

  /// The whole tab, whose bottom the keyboard pushes up.
  final GlobalKey tab;

  /// Scrolls the dialogue box.
  final ScrollController scroll;

  /// The question and its answer, or null before a first question, when there
  /// is no dialogue box.
  final Widget? said;

  /// Opens the log of the conversation; null while nothing has been answered.
  final VoidCallback? onLog;

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> with SingleTickerProviderStateMixin {
  /// From standing under the heading (0) to close up (1).
  late final AnimationController _step = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
    // The keyboard goes quicker than it comes, and she keeps up with it.
    reverseDuration: const Duration(milliseconds: 250),
    value: widget.close ? 1 : 0,
  );
  late final CurvedAnimation _eased = CurvedAnimation(
    parent: _step,
    curve: Curves.easeOutCubic,
    // Stepping back, she sets off at once too, rather than easing away from
    // close up while the keyboard is already gone.
    reverseCurve: Curves.easeOutCubic.flipped,
  );

  /// The stage's height when it was last laid out, and what it would have
  /// been without the keyboard.
  double? _height;
  double? _rest;

  /// Where the tab's bottom was on the screen the last time the keyboard
  /// wasn't pushing it up: over the tab bar, or at the screen's bottom.
  double? _bottom;

  /// The stage's height when she began her latest step.
  double? _from;

  /// How tall the stage is with the keyboard up, when it's [rest] tall without
  /// it: learnt the last time the question box lost focus with the keyboard
  /// up, in any book's Ask, the keyboard being the same. The first time, until
  /// the keyboard has come all the way, there's no telling.
  static ({double rest, double up})? _keyboard;

  @override
  void didUpdateWidget(_Stage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The question box loses focus before the keyboard begins to go, so the
    // stage was last laid out with the keyboard up, if one came.
    if (oldWidget.typing && !widget.typing) {
      if ((_rest, _height) case (final rest?, final up?) when up < rest) {
        _keyboard = (rest: rest, up: up);
      }
    }
    final close = widget.close;
    if (close == oldWidget.close) return;
    _from = _height;
    if (MediaQuery.disableAnimationsOf(context)) {
      _step.value = close ? 1 : 0;
    } else if (close) {
      _step.forward();
    } else {
      _step.reverse();
    }
  }

  /// How high the keyboard reached for the tab when it was last laid out. The
  /// Scaffold keeps it out of this tab's MediaQuery.
  double _inset = 0;

  /// Where the keyboard's top is on the screen, or the screen's bottom with
  /// none up.
  double _keyboardTop() {
    final view = View.of(context);
    return view.physicalSize.height / view.devicePixelRatio - _inset;
  }

  /// How much shorter the keyboard makes the stage. The tab ends at the
  /// keyboard's top or where it ends without it, whichever is higher.
  double _covered() {
    final bottom = _bottom;
    return bottom == null ? 0 : max(0, bottom - _keyboardTop());
  }

  /// Notes where the tab ends without the keyboard, if it isn't pushing it up.
  void _measure() {
    if (!mounted) return;
    final tab = widget.tab.currentContext?.findRenderObject();
    if (tab is! RenderBox || !tab.attached || !tab.hasSize) return;
    final bottom = tab.localToGlobal(Offset(0, tab.size.height)).dy;
    if (_inset == 0 || bottom < _keyboardTop() - 0.5) _bottom = bottom;
  }

  @override
  void dispose() {
    _eased.dispose();
    _step.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PaperBackground(
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = _height = constraints.maxHeight;
            _inset = EasedKeyboard.insetOf(context);
            final rest = _rest = height + _covered();
            WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
            return AnimatedBuilder(
              animation: _eased,
              builder: (context, _) => _scene(height, rest),
            );
          },
        ),
      ),
    );
  }

  /// The stage, [height] tall and [rest] tall without the keyboard, as far as
  /// she has stepped.
  Widget _scene(double height, double rest) {
    final t = _eased.value;
    final said = widget.said;
    // Close up, she's sized for the stage as it will be when she gets there,
    // not as it is on the way, so the keyboard coming or going can't swell
    // her as she steps.
    final closeOn = switch (_step.status) {
      // Stepping back, the keyboard going: the stage she began from.
      AnimationStatus.reverse => _from ?? height,
      // Stepping up as a first question is begun, the keyboard coming.
      AnimationStatus.forward when widget.said == null => _writingOn(
        height,
        rest,
        t,
      ),
      _ => height,
    };
    return CustomMultiChildLayout(
      delegate: _StageLayout(
        t,
        // She stands only with the keyboard down, so she stands on the stage
        // as it is without it, not as the keyboard coming or going shortens
        // it.
        standingOn: rest,
        closeOn: closeOn,
      ),
      children: [
        if (t < 1)
          LayoutId(
            id: _Slot.heading,
            child: Opacity(opacity: 1 - t, child: const _Heading()),
          ),
        LayoutId(
          id: _Slot.companion,
          // Keyed, and always here, so she carries on from the empty
          // thread into a conversation.
          child: KeyedSubtree(
            key: const ValueKey('companion'),
            child: LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: Alignment.bottomCenter,
                child: _Standing(
                  height: constraints.maxHeight,
                  shadow: 1 - t,
                  active: widget.active,
                  cue: widget.cue,
                ),
              ),
            ),
          ),
        ),
        // Paper over her legs at the foot of the stage, so nothing of
        // her shows in the gap under the dialogue box, and with no box
        // she fades out there instead of being cut off.
        if (t > 0)
          LayoutId(
            id: _Slot.floor,
            child: Opacity(
              opacity: t,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      LoremarkColors.paper.withValues(alpha: 0),
                      LoremarkColors.paper,
                    ],
                    stops: const [0, 0.7],
                  ),
                ),
              ),
            ),
          ),
        if (said != null)
          LayoutId(
            id: _Slot.dialogue,
            child: Transform.translate(
              offset: Offset(0, 12 * (1 - t)),
              child: _DialogueBox(
                key: const ValueKey('dialogue'),
                reveal: t,
                scroll: widget.scroll,
                onLog: widget.onLog,
                child: said,
              ),
            ),
          ),
      ],
    );
  }

  /// How tall a stage she's close up on, [t] of the way into stepping up as a
  /// first question is begun, the stage [height] tall so far and [rest] tall
  /// without the keyboard.
  double _writingOn(double height, double rest, double t) {
    final known = _keyboard;
    // Without knowing how tall the stage will be, she can only follow it.
    if (known == null || (known.rest - rest).abs() > 0.5) return height;
    // The stage as it will be with the keyboard up, or as it is if it's
    // shorter already, the keyboard taller than last time.
    final up = min(height, known.up);
    if (height < rest) return up;
    // Before the keyboard has begun to come, or with none coming, as with a
    // hardware keyboard: by the end she's on the stage as it is.
    return up + (height - up) * t;
  }
}

/// Places the stage's heading, companion and dialogue box, [t] of the way
/// from standing under the heading to close up.
class _StageLayout extends MultiChildLayoutDelegate {
  _StageLayout(this.t, {required this.standingOn, required this.closeOn});

  final double t;

  /// How tall a stage she stands on, and is close up on. Outside a step,
  /// both are the stage's own height.
  final double standingOn;
  final double closeOn;

  static const _headingAt = Offset(22, 24);

  // Standing under the heading: room over her head and under her feet, and
  // never so tall she crowds a tablet.
  static const _above = 20.0;
  static const _below = 14.0;
  static const _tallestStanding = 460.0;

  // Close up: her head near the top, a little larger than the stage, her legs
  // behind the dialogue box.
  static const _top = 8.0;
  static const _closeScale = 1.12;
  static const _tallestClose = 620.0;

  static const _boxMargin = 12.0;
  static const _shortestBox = 132.0;

  /// How far over the dialogue box's bottom edge her legs fade into the floor.
  static const _floorFade = 28.0;

  /// How much of the stage the dialogue box may cover, so her face shows.
  static const _boxShare = 0.58;

  @override
  void performLayout(Size size) {
    final close = Rect.fromLTWH(
      0,
      _top,
      size.width,
      ((closeOn - _top) * _closeScale).clamp(0, _tallestClose),
    );
    var at = close;
    if (hasChild(_Slot.heading)) {
      final heading = layoutChild(
        _Slot.heading,
        BoxConstraints(maxWidth: max(0, size.width - 2 * _headingAt.dx)),
      );
      positionChild(_Slot.heading, _headingAt);
      final room = standingOn - _headingAt.dy - heading.height;
      final height = (room - _above - _below).clamp(0.0, _tallestStanding);
      final standing = Rect.fromLTWH(
        0,
        standingOn - _below - height,
        size.width,
        height,
      );
      at = Rect.lerp(standing, close, t)!;
    }
    layoutChild(_Slot.companion, BoxConstraints.tight(at.size));
    positionChild(_Slot.companion, at.topLeft);

    if (hasChild(_Slot.floor)) {
      final floor = Size(size.width, min(size.height, _boxMargin + _floorFade));
      layoutChild(_Slot.floor, BoxConstraints.tight(floor));
      positionChild(_Slot.floor, Offset(0, size.height - floor.height));
    }

    if (hasChild(_Slot.dialogue)) {
      final width = max(0.0, size.width - 2 * _boxMargin);
      final tallest = size.height * _boxShare;
      final box = layoutChild(
        _Slot.dialogue,
        BoxConstraints(
          minWidth: width,
          maxWidth: width,
          minHeight: min(_shortestBox, tallest),
          maxHeight: tallest,
        ),
      );
      positionChild(
        _Slot.dialogue,
        Offset(_boxMargin, size.height - _boxMargin - box.height),
      );
    }
  }

  @override
  bool shouldRelayout(_StageLayout oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.standingOn != standingOn ||
      oldDelegate.closeOn != closeOn;
}

class _Heading extends StatelessWidget {
  const _Heading();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('A THREAD BACK INTO THE STORY', style: kicker()),
        const SizedBox(height: 9),
        Text('Ask about what you’ve read.', style: serif(29, height: 1.18)),
      ],
    );
  }
}

/// The whole companion, [height] tall, on a soft shadow that stays on the
/// ground when she hops. The shadow is [shadow] opaque: it fades as she steps
/// up behind the dialogue box.
class _Standing extends StatelessWidget {
  const _Standing({
    required this.height,
    required this.shadow,
    required this.active,
    required this.cue,
  });

  final double height;
  final double shadow;
  final bool active;
  final _Cue cue;

  @override
  Widget build(BuildContext context) {
    if (height < 1) return const SizedBox.shrink();
    final shadowSize = Size(height * 0.3, height * 0.04);
    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: [
        // Centred on the soles of her boots.
        if (shadow > 0)
          Positioned(
            bottom: -shadowSize.height / 2,
            child: CustomPaint(
              size: shadowSize,
              painter: _ShadowPainter(shadow),
            ),
          ),
        CompanionSprite(
          frame: CompanionFrame.full,
          height: height,
          mood: cue.mood,
          speech: cue.speech,
          citations: cue.citations,
          active: active,
          greet: true,
        ),
      ],
    );
  }
}

class _ShadowPainter extends CustomPainter {
  _ShadowPainter(this.opacity);

  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawOval(
      Offset.zero & size,
      Paint()
        ..color = LoremarkColors.ink.withValues(alpha: 0.14 * opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.height / 3),
    );
  }

  @override
  bool shouldRepaint(_ShadowPainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}

/// A visual novel's dialogue box: see-through, so she shows behind it, with
/// her name on its edge and the log in its corner. [reveal] fades it in.
class _DialogueBox extends StatelessWidget {
  const _DialogueBox({
    super.key,
    required this.reveal,
    required this.scroll,
    required this.onLog,
    required this.child,
  });

  final double reveal;
  final ScrollController scroll;
  final VoidCallback? onLog;
  final Widget child;

  static const _radius = BorderRadius.all(Radius.circular(16));

  @override
  Widget build(BuildContext context) {
    // The backdrop is faded by hand: under an Opacity it would blur nothing.
    final blur = 8 * reveal;
    return Stack(
      // As tall as the stage asks, so the log sits at the bottom.
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: _radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: LoremarkColors.card.withValues(alpha: 0.76 * reveal),
                borderRadius: _radius,
                border: Border.all(
                  color: LoremarkColors.gold.withValues(alpha: 0.5 * reveal),
                ),
              ),
              child: Opacity(
                opacity: reveal,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 22, 8, 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(
                        child: SingleChildScrollView(
                          controller: scroll,
                          padding: const EdgeInsets.only(right: 8),
                          child: child,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: onLog,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'LOG',
                            style: kicker(
                              size: 11,
                              color: onLog == null
                                  ? LoremarkColors.line
                                  : LoremarkColors.gold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: -12,
          left: 14,
          child: Opacity(opacity: reveal, child: const _NameTag()),
        ),
      ],
    );
  }
}

/// Her name, on the dialogue box's edge.
class _NameTag extends StatelessWidget {
  const _NameTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 5),
      decoration: BoxDecoration(
        color: LoremarkColors.olive,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: LoremarkColors.gold.withValues(alpha: 0.7)),
      ),
      child: Text(
        'Loremark',
        style: serif(13.5, height: 1.2, color: LoremarkColors.onOlive),
      ),
    );
  }
}

/// What's in the dialogue box: the reader's question, then her answer.
class _Said extends StatelessWidget {
  const _Said({required this.question, required this.answer});

  final String question;
  final Widget answer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: LoremarkColors.gold.withValues(alpha: 0.6),
                width: 2,
              ),
            ),
          ),
          child: SelectableText(
            question,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: LoremarkColors.muted,
            ),
          ),
        ),
        const SizedBox(height: 10),
        answer,
      ],
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

/// An earlier answer in the log, in a card.
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 18, right: 24),
      child: Container(
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
        child: _AnswerBody(
          text: text,
          cutOff: cutOff,
          paragraphNumber: paragraphNumber,
          visible: visible,
          onCite: onCite,
        ),
      ),
    );
  }
}

/// An answer's words and citations, and a note if it was cut off or cites
/// nothing.
class _AnswerBody extends StatelessWidget {
  const _AnswerBody({
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
    return Column(
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
class _WorkingBody extends StatelessWidget {
  const _WorkingBody({
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
      return _AnswerText(
        parts: splitAnswer(pending.text, streaming: true),
        paragraphNumber: paragraphNumber,
        visible: visible,
        onCite: onCite,
      );
    }
    // Words, not a spinner: an endless animation would keep widget tests
    // from settling.
    final status = switch (pending.stage) {
      AskStage.reading => 'Finding your place…',
      AskStage.lookingUp => 'Checking the Story Map…',
      _ => 'Thinking…',
    };
    return Text(
      status,
      style: const TextStyle(
        fontSize: 13,
        fontStyle: FontStyle.italic,
        color: LoremarkColors.muted,
      ),
    );
  }
}

/// A question that failed: why, and what can be done.
class _FailedBody extends StatelessWidget {
  const _FailedBody({
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Column(
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
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.draft,
    required this.focus,
    required this.enabled,
    required this.busy,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController draft;
  final FocusNode focus;
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
                focusNode: focus,
                // On phones a field keeps the keyboard up until told
                // otherwise: a touch anywhere else puts it away, the way the
                // keyboard's own send key does.
                onTapOutside: (_) => focus.unfocus(),
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
