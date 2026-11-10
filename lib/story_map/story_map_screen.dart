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
/// sections they haven't read. It starts at where they are, down to the paragraph
/// in a section they are partway through, and asks before showing anything past
/// that. It follows them back when they turn back. The slider moves freely, but
/// past that point what's shown stays put until the reader lets go and confirms.
class StoryMapScreen extends StatefulWidget {
  const StoryMapScreen({
    super.key,
    required this.model,
    this.finishedSections,
    this.hiddenInNext,
  });

  final StoryModel model;

  /// How many of the model's sections, counted from the first, the reader has
  /// finished. Null shows every section without asking.
  final int? finishedSections;

  /// If the reader is partway through the section after those, what of it they
  /// haven't reached: see [StoryReadingProgress.hiddenInNext].
  final Set<String>? hiddenInNext;

  @override
  State<StoryMapScreen> createState() => _StoryMapScreenState();
}

class _StoryMapScreenState extends State<StoryMapScreen> {
  /// Sections the reader agreed to see past where they are. They aren't asked
  /// again while this screen lasts.
  int _confirmedSections = 0;

  /// The section being read, if the reader has switched to seeing all of it.
  /// Kept by ID, so that it doesn't carry over to the next section they start.
  String? _wholeSectionId;

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
    final reached = screen.finishedSections == null
        ? total
        : screen.finishedSections! + (screen.hiddenInNext == null ? 0 : 1);
    return max(_confirmedSections, reached).clamp(0, total);
  }

  /// Whether the section at [index] is the one the reader is partway through.
  bool _isBeingRead(int index) =>
      widget.hiddenInNext != null && index == widget.finishedSections;

  /// Whether only the part of the section at [index] that has been read shows.
  bool _isPartial(int index) =>
      _isBeingRead(index) && widget.model.sections[index].id != _wholeSectionId;

  StorySnapshot? _snapshotAt(int index) => index < 0
      ? null
      : StorySnapshot(
          widget.model,
          widget.model.sections[index],
          hidden: _isPartial(index) ? widget.hiddenInNext! : const {},
        );

  @override
  void didUpdateWidget(StoryMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldShown = _shownSections(oldWidget);
    final shown = _shownSections(widget);
    // Someone at the newest section they may see stays at the newest, and
    // nothing stays showing that they have turned back from.
    if (_sectionIndex == oldShown - 1 || _sectionIndex >= shown) {
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
    final partial = _isPartial(index);
    final what = partial ? 'The rest of ${section.title}' : section.title;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Past where you’ve read'),
        content: Text(
          '$what is past your reading position, so showing it may spoil the '
          'story.',
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
      setState(() {
        if (partial) {
          _wholeSectionId = section.id;
        } else {
          _confirmedSections = index + 1;
        }
        _sectionIndex = index;
        _snapshot = _snapshotAt(index);
      });
    } else {
      _selectSection(_dragStartIndex ?? _sectionIndex);
    }
  }

  /// Turning the whole chapter on asks first; going back to what has been read
  /// can't spoil anything, so it doesn't.
  void _setWholeChapter(bool whole) {
    if (whole) {
      _dragStartIndex = _sectionIndex;
      _confirmShowing(_sectionIndex);
    } else {
      setState(() {
        _wholeSectionId = null;
        _snapshot = _snapshotAt(_sectionIndex);
      });
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      snapshot == null
                          ? 'You haven’t finished any of these sections yet.'
                          : _isPartial(_sectionIndex)
                          ? 'Known so far in ${snapshot.section.title}'
                          : 'Known by the end of ${snapshot.section.title}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (_isBeingRead(_sectionIndex)) ...[
                    const SizedBox(width: 8),
                    Text('Whole chapter', style: theme.textTheme.labelSmall),
                    Switch(
                      value: !_isPartial(_sectionIndex),
                      onChanged: _setWholeChapter,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ],
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
