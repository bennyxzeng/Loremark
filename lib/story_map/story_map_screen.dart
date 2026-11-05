import 'dart:math';

import 'package:flutter/material.dart';

import '../story_model/story_model.dart';
import '../story_model/story_snapshot.dart';
import 'chapter_digest_view.dart';
import 'character_card_view.dart';
import 'character_graph_view.dart';
import 'character_list_view.dart';
import 'graph_guide_sheet.dart';
import 'label_guide_sheet.dart';

enum _StoryMapTab { graph, characters, chapter }

/// The story as known at a chapter the reader picks.
///
/// Updating isn't tied to how far the reader has got, so the map can hold
/// sections they haven't read. It starts at the last section they have finished,
/// and asks before showing anything past that. The slider moves freely, but past
/// that point what's shown stays put until the reader lets go and confirms.
class StoryMapScreen extends StatefulWidget {
  const StoryMapScreen({super.key, required this.model, this.finishedSections});

  final StoryModel model;

  /// How many of the model's sections, counted from the first, the reader has
  /// finished. Null shows every section without asking.
  final int? finishedSections;

  @override
  State<StoryMapScreen> createState() => _StoryMapScreenState();
}

class _StoryMapScreenState extends State<StoryMapScreen> {
  /// Sections the reader agreed to see, or could already see. They aren't asked
  /// again while this screen lasts, even if they turn back to an earlier page.
  int _confirmedSections = 0;

  /// The section shown, or -1 if the reader hasn't finished any.
  late int _sectionIndex = _shownSections(widget) - 1;
  late StorySnapshot? _snapshot = _snapshotAt(_sectionIndex);
  _StoryMapTab _tab = _StoryMapTab.graph;

  /// Where the slider is while it is past what may be shown.
  int? _pendingIndex;

  /// Where the current drag began, to go back to if the reader says no.
  int? _dragStartIndex;

  int _shownSections(StoryMapScreen screen) {
    final total = screen.model.sections.length;
    return max(
      _confirmedSections,
      screen.finishedSections ?? total,
    ).clamp(0, total);
  }

  StorySnapshot? _snapshotAt(int index) => index < 0
      ? null
      : StorySnapshot(widget.model, widget.model.sections[index]);

  @override
  void didUpdateWidget(StoryMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldShown = _shownSections(oldWidget);
    _confirmedSections = oldShown;
    final shown = _shownSections(widget);
    // Someone at the newest section they may see stays at the newest.
    if (_sectionIndex == oldShown - 1 && shown > oldShown) {
      _sectionIndex = shown - 1;
    }
    _snapshot = _snapshotAt(_sectionIndex);
  }

  void _selectSection(int index) {
    if (index == _sectionIndex) return;
    setState(() {
      _sectionIndex = index;
      _snapshot = _snapshotAt(index);
    });
  }

  void _slideTo(int index) {
    if (index < _shownSections(widget)) {
      setState(() => _pendingIndex = null);
      _selectSection(index);
    } else {
      setState(() => _pendingIndex = index);
    }
  }

  void _slideEnded(int index) {
    if (index >= _shownSections(widget)) _confirmShowing(index);
  }

  Future<void> _confirmShowing(int index) async {
    final section = widget.model.sections[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Past where you’ve read'),
        content: Text(
          '${section.title} is past your reading position, so showing it may '
          'spoil the story.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Show anyway'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _pendingIndex = null);
    if (confirmed == true) {
      _confirmedSections = index + 1;
      _selectSection(index);
    } else {
      _selectSection(_dragStartIndex ?? _sectionIndex);
    }
  }

  void _openCard(String entityId) =>
      showCharacterCard(context, _snapshot!, entityId);

  @override
  Widget build(BuildContext context) {
    final sections = widget.model.sections;
    if (sections.isEmpty) {
      return const Center(child: Text('No chapters processed yet.'));
    }
    final theme = Theme.of(context);
    final snapshot = _snapshot;
    final sliderIndex = _pendingIndex ?? max(_sectionIndex, 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.model.bookTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(
                snapshot == null
                    ? 'You haven’t finished any of these sections yet.'
                    : 'Known by the end of ${snapshot.section.title}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (sections.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(sections.first.label, style: theme.textTheme.labelSmall),
                Expanded(
                  child: Slider(
                    value: sliderIndex.toDouble(),
                    max: (sections.length - 1).toDouble(),
                    divisions: sections.length - 1,
                    label: sections[sliderIndex].label,
                    onChangeStart: (_) => _dragStartIndex = _sectionIndex,
                    onChanged: (value) => _slideTo(value.round()),
                    onChangeEnd: (value) => _slideEnded(value.round()),
                  ),
                ),
                Text(sections.last.label, style: theme.textTheme.labelSmall),
              ],
            ),
          )
        else
          const SizedBox(height: 12),
        if (snapshot == null)
          Expanded(
            child: Center(
              child: FilledButton.tonal(
                onPressed: () {
                  _dragStartIndex = _sectionIndex;
                  _confirmShowing(0);
                },
                child: Text('Show ${sections.first.label} anyway'),
              ),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SegmentedButton<_StoryMapTab>(
              segments: const [
                ButtonSegment(value: _StoryMapTab.graph, label: Text('Graph')),
                ButtonSegment(
                  value: _StoryMapTab.characters,
                  label: Text('Characters'),
                ),
                ButtonSegment(
                  value: _StoryMapTab.chapter,
                  label: Text('Chapter'),
                ),
              ],
              showSelectedIcon: false,
              selected: {_tab},
              onSelectionChanged: (selection) =>
                  setState(() => _tab = selection.single),
            ),
          ),
          Expanded(
            child: switch (_tab) {
              _StoryMapTab.graph => CharacterGraphView(
                snapshot: snapshot,
                onEntityTap: _openCard,
                onGuideTap: () => showGraphGuide(
                  context,
                  sectionLabel: snapshot.section.label,
                ),
              ),
              _StoryMapTab.characters => CharacterListView(
                snapshot: snapshot,
                onEntityTap: _openCard,
              ),
              _StoryMapTab.chapter => ChapterDigestView(
                snapshot: snapshot,
                onEntityTap: _openCard,
                onGuideTap: () => showLabelGuide(context),
              ),
            },
          ),
        ],
      ],
    );
  }
}
