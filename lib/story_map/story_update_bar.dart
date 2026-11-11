import 'dart:async';

import 'package:flutter/material.dart';

import '../story_update/story_import.dart';
import '../story_update/story_section_kind.dart';
import '../story_update/story_updater.dart';
import '../theme/loremark_theme.dart';

/// [elapsed] as minutes and seconds, such as `2:51`.
String formatStoryElapsed(Duration elapsed) {
  final seconds = elapsed.isNegative ? 0 : elapsed.inSeconds;
  return '${seconds ~/ 60}:${'${seconds % 60}'.padLeft(2, '0')}';
}

/// What the reader is told when an update fails. Failing never changes the
/// Story Map, and most failures have been charged for, so it says both.
String describeStoryUpdateFailure(StoryUpdateOutcome outcome) {
  const nothingSaved = 'Nothing was saved.';
  const mayCharge =
      'Nothing was saved, but your provider may still charge for it.';
  // The model answers differently each time, so a bad answer can be asked for
  // again. Each try is charged, so it is the reader's call.
  const updateAgain = 'Update again for a new answer.';
  final message = outcome.message;
  switch (outcome.status) {
    case 'api_error':
      return switch (outcome.category) {
        'authentication' || 'permission_denied' =>
          'Your API key was rejected. Check it in Settings. $nothingSaved',
        'rate_limit' =>
          'Your provider is limiting requests, or your credit has run out. '
              'Try again later. $nothingSaved',
        'network' || 'timeout' => 'The request didn’t finish. $mayCharge',
        'server_error' =>
          'Your provider had a problem. Try again later. $nothingSaved',
        _ => 'Your provider refused the request: $message. $nothingSaved',
      };
    case 'refusal':
      return 'The model declined this section. $mayCharge';
    case 'incomplete':
      return 'The model’s answer was cut off. $mayCharge';
    case 'failed' || 'empty_output':
      return 'The model gave no usable answer. $mayCharge';
    case 'schema_invalid':
      return 'The model’s answer wasn’t in the expected form. $mayCharge '
          '$updateAgain';
    case 'validation_failed':
      final errors = outcome.issues.where((issue) => issue.isError).toList();
      final quotesOnly = errors.every(
        (issue) => issue.code == 'quote_not_found',
      );
      if (quotesOnly) {
        return 'The model’s answer had ${errors.length} quote(s) that aren’t '
            'in the book, and Strict quote check is on. $mayCharge '
            '$updateAgain';
      }
      final first = errors.first.message;
      final what = errors.length == 1
          ? 'failed 1 check: $first'
          : 'failed ${errors.length} checks. The first: $first';
      return 'The model’s answer $what. $mayCharge $updateAgain';
    case 'stale_base':
      return 'The Story Map changed during the update. Try again. $mayCharge';
    default:
      return '${message ?? 'The update failed.'} $nothingSaved';
  }
}

/// The Update button above the Story Map, and what it would do. While an
/// update runs, the button cancels it.
class StoryUpdateBar extends StatelessWidget {
  const StoryUpdateBar({
    super.key,
    required this.status,
    required this.online,
    required this.hasKey,
    required this.onUpdate,
    required this.onCancel,
    required this.onChoose,
    required this.onLoad,
    required this.onExport,
    this.onKeepReading,
    this.filesBusy = false,
    this.updateStartedAt,
    this.updateTitle,
    this.updateStep = 0,
    this.updateTotal = 1,
    this.runStartedAt,
    this.cancelling = false,
    this.stopping = false,
    this.notice,
    this.failure,
    this.now = DateTime.now,
  });

  /// What pressing Update would do; null while that is being worked out.
  final StoryUpdateStatus? status;
  final bool online;

  /// Whether the reader has an API key. Looking at a map doesn't need one, but
  /// adding to it does.
  final bool hasKey;
  final VoidCallback onUpdate;
  final VoidCallback onCancel;
  final VoidCallback onChoose;
  final VoidCallback onLoad;
  final VoidCallback onExport;

  /// Goes back to the book while an update runs; null to leave it out.
  final VoidCallback? onKeepReading;

  /// Whether files are being exported or loaded, which an update mustn't overlap.
  final bool filesBusy;

  /// When the section being added began, if one is.
  final DateTime? updateStartedAt;

  /// The title of the section being added, if known.
  final String? updateTitle;

  /// Which of the [updateTotal] sections asked for is being added, counted
  /// from 0.
  final int updateStep;
  final int updateTotal;

  /// When the first of several sections began.
  final DateTime? runStartedAt;

  /// Whether the reader has cancelled the update under way, which hasn't
  /// stopped yet.
  final bool cancelling;

  /// Whether the reader has asked to stop once the section being added is
  /// done.
  final bool stopping;

  /// How the last update went, if it worked.
  final String? notice;

  /// Why the last update failed, if it did.
  final String? failure;

  /// The time now; tests replace it.
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = this.status;
    final startedAt = updateStartedAt;
    final updating = startedAt != null;
    final canAct = online && hasKey && !updating && !filesBusy;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final String title;
    String? detail;
    var canUpdate = false;
    var showButton = true;
    if (updating && cancelling) {
      title = 'Cancelling…';
    } else if (updating && stopping) {
      title = updateTitle == null
          ? 'Stopping after this section…'
          : 'Finishing $updateTitle, then stopping…';
    } else if (updating) {
      final adding = updateTitle;
      // The count comes first, so a long title can't push it out of sight.
      final of = updateTotal > 1 ? '${updateStep + 1} of $updateTotal: ' : '';
      title = adding == null
          ? 'Building your Story Map…'
          : 'Adding $of$adding…';
    } else if (status == null) {
      title = 'Checking this book…';
    } else if (status.isFinished) {
      title = 'Every section is in the map.';
      showButton = false;
    } else if (status.blocked != null) {
      title = 'Can’t add the next section';
      detail = status.blocked;
    } else {
      title = status.isNewStore
          ? 'No Story Map yet'
          : 'Next: ${status.nextTitle}';
      canUpdate = canAct;
      // A missing key comes first: reconnecting wouldn't unlock anything.
      if (!hasKey) {
        detail = 'Add an API key in Settings to update.';
      } else if (!online) {
        detail = 'You’re offline. Updating needs the internet.';
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (status?.canChoose ?? false) ...[
                const SizedBox(width: 4),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: canAct ? onChoose : null,
                  child: const Text('Choose'),
                ),
              ],
              if (showButton) ...[
                const SizedBox(width: 4),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: updating
                      ? (cancelling ? null : onCancel)
                      : (canUpdate ? onUpdate : null),
                  child: Text(updating ? 'Cancel' : 'Update'),
                ),
              ],
              PopupMenuButton<VoidCallback>(
                enabled: !updating && !filesBusy,
                tooltip: 'Story Map files',
                icon: const Icon(Icons.more_horiz),
                // Narrower than usual, to leave the title room on a small phone.
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(minimumSize: const Size(36, 40)),
                onSelected: (action) => action(),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: onLoad,
                    child: const Text('Load from file…'),
                  ),
                  PopupMenuItem(
                    value: onExport,
                    child: const Text('Export files…'),
                  ),
                ],
              ),
            ],
          ),
          if (startedAt != null)
            _UpdatingCard(
              startedAt: startedAt,
              step: updateStep,
              total: updateTotal,
              runStartedAt: runStartedAt,
              now: now,
              cancelling: cancelling,
              stopping: stopping,
              onKeepReading: onKeepReading,
            ),
          if (detail != null) Text(detail, style: muted),
          if (notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(notice!, style: muted),
            ),
          if (failure != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                failure!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What an update under way looks like: how long it has been running, large,
/// so it is plain that something is happening, and that the reader can go back
/// to the book meanwhile.
class _UpdatingCard extends StatelessWidget {
  const _UpdatingCard({
    required this.startedAt,
    required this.step,
    required this.total,
    required this.runStartedAt,
    required this.now,
    required this.cancelling,
    required this.stopping,
    required this.onKeepReading,
  });

  /// When the section being added began.
  final DateTime startedAt;

  /// Which of the [total] sections is being added, counted from 0.
  final int step;
  final int total;

  /// When the first of them began.
  final DateTime? runStartedAt;
  final DateTime Function() now;
  final bool cancelling;
  final bool stopping;
  final VoidCallback? onKeepReading;

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(
      fontSize: 12,
      height: 1.4,
      color: LoremarkColors.muted,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: LoremarkColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: LoremarkColors.line),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 10, 14, cancelling ? 12 : 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  StoryElapsedTime(
                    startedAt: startedAt,
                    now: now,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                      color: LoremarkColors.ink,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('elapsed', style: muted),
                ],
              ),
              if (total > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Text('Section ${step + 1} of $total', style: muted),
                      if (runStartedAt case final runStartedAt?) ...[
                        const Text(' · ', style: muted),
                        StoryElapsedTime(
                          startedAt: runStartedAt,
                          now: now,
                          style: muted,
                        ),
                        const Text(' in all', style: muted),
                      ],
                    ],
                  ),
                ),
              if (!cancelling) ...[
                const SizedBox(height: 4),
                Text(
                  stopping
                      ? 'This section will still be added, since it’s been '
                            'sent. No more will be started.'
                      : total > 1
                      ? 'Each section can take a few minutes. You can keep '
                            'reading, and you’ll be told when they’re done. '
                            'Keep Loremark open.'
                      : 'This can take a few minutes. You can keep reading, '
                            'and you’ll be told when it’s done. Keep Loremark '
                            'open.',
                  style: muted,
                ),
                if (onKeepReading != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onKeepReading,
                      child: const Text('Keep reading'),
                    ),
                  )
                else
                  const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// How long an update has been running, as `m:ss`, ticking once a second. It
/// is its own widget so that a tick rebuilds this text and nothing around it.
///
/// Plain text rather than a spinner: an endless animation would keep widget
/// tests from settling.
class StoryElapsedTime extends StatefulWidget {
  const StoryElapsedTime({
    super.key,
    required this.startedAt,
    this.now = DateTime.now,
    this.style,
  });

  final DateTime startedAt;

  /// The time now; tests replace it.
  final DateTime Function() now;
  final TextStyle? style;

  @override
  State<StoryElapsedTime> createState() => _StoryElapsedTimeState();
}

class _StoryElapsedTimeState extends State<StoryElapsedTime> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    // Each tick reads the clock rather than counting, so the time stays right
    // if the system holds the app back for a moment.
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      formatStoryElapsed(widget.now().difference(widget.startedAt)),
      // Digits of one width, so what is beside them doesn't shift each second.
      style: (widget.style ?? const TextStyle()).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Asks which sections to add, and says what adding them involves and what it
/// leaves out. For a new map, the first one picked is where it starts. Returns
/// those picked, in reading order, or null if the reader backs out.
///
/// Only the next section is picked to begin with, so adding several is always
/// the reader's choice.
Future<List<StorySectionChoice>?> showStorySectionsSheet(
  BuildContext context, {
  required StoryUpdateStatus status,
  required String providerLabel,
}) {
  final first = status.suggestedStart ?? status.nextSectionId;
  return showModalBottomSheet<List<StorySectionChoice>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _StorySectionsSheet(
      status: status,
      providerLabel: providerLabel,
      picked: {?first},
    ),
  );
}

class _StorySectionsSheet extends StatefulWidget {
  const _StorySectionsSheet({
    required this.status,
    required this.providerLabel,
    required this.picked,
  });

  final StoryUpdateStatus status;
  final String providerLabel;

  /// The sections picked to begin with.
  final Set<String> picked;

  @override
  State<_StorySectionsSheet> createState() => _StorySectionsSheetState();
}

class _StorySectionsSheetState extends State<_StorySectionsSheet> {
  late final Set<String> _picked = {...widget.picked};

  List<StorySectionChoice> get _choices => widget.status.choices;

  void _pickMainText() => setState(() {
    _picked
      ..clear()
      ..addAll([
        for (final choice in widget.status.pickable)
          if (choice.kind == StorySectionKind.story) choice.sectionId,
      ]);
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final isNew = widget.status.isNewStore;
    final picked = [
      for (final choice in _choices)
        if (_picked.contains(choice.sectionId)) choice,
    ];
    final lastPicked = picked.isEmpty ? -1 : _choices.indexOf(picked.last);
    final leftOut = [
      for (var i = 0; i < lastPicked; i++)
        if (!_picked.contains(_choices[i].sectionId)) _choices[i].title,
    ];
    final provider = widget.providerLabel;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              isNew ? 'Build a Story Map' : 'Add sections',
              style: theme.textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              children: [
                TextButton(
                  onPressed: _pickMainText,
                  child: const Text('Select all main text'),
                ),
                TextButton(
                  onPressed: _picked.isEmpty
                      ? null
                      : () => setState(_picked.clear),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          // The list gets most of the room, but what picking costs and leaves
          // out keeps some, scrolling if it must.
          Flexible(
            flex: 3,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final choice in _choices)
                  CheckboxListTile(
                    value: _picked.contains(choice.sectionId),
                    onChanged: choice.canPick
                        ? (value) => setState(() {
                            if (value ?? false) {
                              _picked.add(choice.sectionId);
                            } else {
                              _picked.remove(choice.sectionId);
                            }
                          })
                        : null,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    title: Text(
                      choice.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: _subtitle(choice),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Each section is sent to $provider with the map so far, '
                    'as its own request, which $provider charges for. They run '
                    'one at a time, in reading order, and stop at the first '
                    'that doesn’t go through.',
                    style: muted,
                  ),
                  if (leftOut.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      _leftOutWarning(leftOut),
                      style: muted?.copyWith(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: picked.isEmpty
                      ? null
                      : () => Navigator.pop(context, picked),
                  child: Text(
                    picked.length == 1
                        ? 'Add 1 section'
                        : 'Add ${picked.length} sections',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// What [choice] is, beside its title: the next section, what part of the
  /// book it looks like, or why it can't be added.
  Widget? _subtitle(StorySectionChoice choice) {
    final notes = [
      if (choice.sectionId == widget.status.nextSectionId) 'Next',
      ?choice.kind.label,
      // Why exactly is for the bar, once Update gets there.
      if (!choice.canPick) 'Can’t be read reliably',
    ];
    if (notes.isEmpty) return null;
    return Text(
      notes.join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// How the reader wants to stop the sections being added.
enum StoryStopChoice {
  /// Let the section being added finish and go in, and start no more.
  afterThisOne,

  /// Drop the section being added, and start no more.
  now,
}

/// Asks before the update under way is cancelled, since Cancel is where Update
/// was, and pressing Update twice mustn't throw away a paid request. With
/// [remaining] sections still to start after [current], it can also stop once
/// [current] is done. Returns how to stop, or null to keep going.
Future<StoryStopChoice?> showStoryCancelDialog(
  BuildContext context, {
  String? current,
  int remaining = 0,
}) {
  final section = current ?? 'this section';
  final later = remaining == 1
      ? 'the 1 section after it isn’t started'
      : 'the $remaining sections after it aren’t started';
  return showDialog<StoryStopChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        remaining == 0 ? 'Cancel this update?' : 'Stop adding sections?',
      ),
      content: SingleChildScrollView(
        child: Text(
          remaining == 0
              ? 'Nothing will be saved, but your provider may still charge for '
                    'the request.'
              : 'Stop after this one: $section is still added, and $later.\n\n'
                    'Cancel now: $section isn’t saved, but your provider may '
                    'still charge for it, and $later.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Keep going'),
        ),
        if (remaining > 0)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, StoryStopChoice.afterThisOne),
            child: const Text('Stop after this one'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context, StoryStopChoice.now),
          child: Text(remaining == 0 ? 'Cancel update' : 'Cancel now'),
        ),
      ],
    ),
  );
}

/// Asks before [staged] takes the place of the map here, which has
/// [currentSections] sections, if it could be read. Returns whether to go ahead.
Future<bool> showStoryReplaceDialog(
  BuildContext context, {
  required int? currentSections,
  required StagedStoryImport staged,
}) async {
  String count(int sections) =>
      sections == 1 ? '1 section' : '$sections sections';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Replace this Story Map?'),
      content: SingleChildScrollView(
        child: Text(
          [
            if (currentSections != null)
              'The map here has ${count(currentSections)}.',
            'The file has ${count(staged.sectionCount)}.',
            if (staged.viewOnly)
              'It can only be viewed, not updated, since it’s a single file.',
            'Replacing deletes the map here. Export first if you want to keep '
                'it.',
          ].join(' '),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Replace'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Says that the sections called [titles] can't be added once those after
/// them are. A long list is cut short, so the warning stays readable.
String _leftOutWarning(List<String> titles) {
  const shown = 5;
  final listed = titles.length <= shown + 1
      ? titles.join(', ')
      : '${titles.take(shown).join(', ')} and ${titles.length - shown} more';
  return titles.length == 1
      ? 'This skips 1 section: $listed. It can’t be added later.'
      : 'This skips ${titles.length} sections: $listed. They '
            'can’t be added later.';
}
