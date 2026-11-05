import 'package:flutter/material.dart';

import '../story_update/story_updater.dart';

/// What the reader is told when an update fails. Failing never changes the
/// Story Map, and most failures have been charged for, so it says both.
String describeStoryUpdateFailure(StoryUpdateOutcome outcome) {
  const nothingSaved = 'Nothing was saved.';
  const mayCharge =
      'Nothing was saved, but your provider may still charge for it.';
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
      return 'The model’s answer wasn’t in the expected form. $mayCharge';
    case 'validation_failed':
      final errors = outcome.issues.where((issue) => issue.isError).toList();
      final quotesOnly = errors.every(
        (issue) => issue.code == 'quote_not_found',
      );
      if (quotesOnly) {
        return 'The model’s answer had ${errors.length} quote(s) that aren’t '
            'in the book, and Strict quote check is on. $mayCharge';
      }
      return 'The model’s answer failed ${errors.length} check(s). $mayCharge';
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
    required this.updating,
    required this.online,
    required this.onUpdate,
    this.notice,
    this.failure,
  });

  /// What pressing Update would do; null while that is being worked out.
  final StoryUpdateStatus? status;
  final bool updating;
  final bool online;
  final VoidCallback onUpdate;

  /// How the last update went, if it worked.
  final String? notice;

  /// Why the last update failed, if it did.
  final String? failure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = this.status;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final String title;
    String? detail;
    var canUpdate = false;
    var showButton = true;
    if (updating) {
      title = status?.nextTitle == null
          ? 'Building your Story Map…'
          : 'Adding ${status!.nextTitle}…';
      // Plain text rather than a spinner: an endless animation would keep
      // widget tests from settling.
      detail = 'This can take a few minutes. Keep Loremark open.';
    } else if (status == null) {
      title = 'Checking this book…';
    } else if (status.isFinished) {
      title = 'Every section is in the map.';
      showButton = false;
    } else if (status.blocked != null) {
      title = 'Can’t update right now';
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (detail != null) Text(detail, style: muted),
                  ],
                ),
              ),
              if (showButton) ...[
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: canUpdate && !updating ? onUpdate : null,
                  child: const Text('Update'),
                ),
              ],
            ],
          ),
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
                  for (final choice in status.startChoices)
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
