import 'dart:async';

import 'package:flutter/material.dart';

import '../story_update/story_updater.dart';

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

/// The Update button above the Story Map, and what it would do.
class StoryUpdateBar extends StatelessWidget {
  const StoryUpdateBar({
    super.key,
    required this.status,
    required this.online,
    required this.onUpdate,
    required this.onChoose,
    this.updateStartedAt,
    this.updateSectionId,
    this.notice,
    this.failure,
    this.now = DateTime.now,
  });

  /// What pressing Update would do; null while that is being worked out.
  final StoryUpdateStatus? status;
  final bool online;
  final VoidCallback onUpdate;
  final VoidCallback onChoose;

  /// When the update under way began, if one is.
  final DateTime? updateStartedAt;

  /// The section asked of the update under way; null for the next one.
  final String? updateSectionId;

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
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final String title;
    String? detail;
    var canUpdate = false;
    var showButton = true;
    if (updating) {
      final adding = status?.titleOf(updateSectionId);
      title = adding == null ? 'Building your Story Map…' : 'Adding $adding…';
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
      canUpdate = online;
      if (!online) detail = 'You’re offline. Updating needs the internet.';
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
                  onPressed: online && !updating ? onChoose : null,
                  child: const Text('Choose'),
                ),
              ],
              if (showButton) ...[
                const SizedBox(width: 4),
                FilledButton.tonal(
                  onPressed: canUpdate && !updating ? onUpdate : null,
                  child: const Text('Update'),
                ),
              ],
            ],
          ),
          if (startedAt != null)
            _ElapsedTime(startedAt: startedAt, now: now, style: muted),
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

/// How long an update has been running, ticking once a second. It is its own
/// widget so that a tick rebuilds this line and not the map below it.
///
/// Plain text rather than a spinner: an endless animation would keep widget
/// tests from settling.
class _ElapsedTime extends StatefulWidget {
  const _ElapsedTime({
    required this.startedAt,
    required this.now,
    required this.style,
  });

  final DateTime startedAt;
  final DateTime Function() now;
  final TextStyle? style;

  @override
  State<_ElapsedTime> createState() => _ElapsedTimeState();
}

class _ElapsedTimeState extends State<_ElapsedTime> {
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
    final elapsed = formatStoryElapsed(
      widget.now().difference(widget.startedAt),
    );
    return Text(
      '$elapsed elapsed. This can take a few minutes. Keep Loremark open.',
      // Digits of one width, so the words after them don't shift each second.
      style: widget.style?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Asks where a new Story Map starts, and says what updating involves. Returns
/// the section to start from, or null if the reader backs out.
Future<String?> showStoryStartDialog(
  BuildContext context, {
  required StoryUpdateStatus status,
  required String providerLabel,
}) {
  var picked = status.suggestedStart!;
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Build a Story Map'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Each update sends one section of this book, and the map so far, '
                'to $providerLabel using your API key, which $providerLabel '
                'charges for.',
              ),
              const SizedBox(height: 16),
              const Text('Start from'),
              DropdownButton<String>(
                value: picked,
                isExpanded: true,
                items: [
                  for (final choice in status.choices)
                    DropdownMenuItem(
                      value: choice.sectionId,
                      child: Text(
                        choice.title,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => picked = value);
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Sections before this one can’t be added later.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, picked),
            child: const Text('Start'),
          ),
        ],
      ),
    ),
  );
}

/// Asks which later section to add, and says what picking one leaves out.
/// Returns the section, or null if the reader backs out.
Future<String?> showStorySectionDialog(
  BuildContext context, {
  required StoryUpdateStatus status,
}) {
  var picked = status.choices.first;
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Choose a section'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButton<StorySectionChoice>(
                value: picked,
                isExpanded: true,
                items: [
                  for (final choice in status.choices)
                    DropdownMenuItem(
                      value: choice,
                      child: Text(
                        choice.title,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => picked = value);
                },
              ),
              if (picked.skips.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_skipWarning(picked.skips)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, picked.sectionId),
            child: const Text('Add section'),
          ),
        ],
      ),
    ),
  );
}

String _skipWarning(List<String> skips) => skips.length == 1
    ? 'This skips 1 section: ${skips.single}. It can’t be added later.'
    : 'This skips ${skips.length} sections: ${skips.join(', ')}. They can’t be '
          'added later.';
