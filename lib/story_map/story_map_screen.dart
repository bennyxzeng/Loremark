import 'package:flutter/material.dart';

import '../story_model/story_model.dart';
import '../story_model/story_snapshot.dart';
import 'chapter_digest_view.dart';
import 'character_card_view.dart';
import 'character_graph_view.dart';
import 'character_list_view.dart';

enum _StoryMapTab { graph, characters, chapter }

/// The Story Map tab: the story as known at a chapter the reader picks.
///
/// The slider starts at the latest processed chapter and can only move back,
/// so nothing past it is ever shown.
class StoryMapScreen extends StatefulWidget {
  const StoryMapScreen({super.key, required this.model});

  final StoryModel model;

  @override
  State<StoryMapScreen> createState() => _StoryMapScreenState();
}

class _StoryMapScreenState extends State<StoryMapScreen> {
  late int _sectionIndex = widget.model.sections.length - 1;
  late StorySnapshot _snapshot = _snapshotAt(_sectionIndex);
  _StoryMapTab _tab = _StoryMapTab.graph;

  StorySnapshot _snapshotAt(int index) =>
      StorySnapshot(widget.model, widget.model.sections[index]);

  void _selectSection(int index) {
    if (index == _sectionIndex) return;
    setState(() {
      _sectionIndex = index;
      _snapshot = _snapshotAt(index);
    });
  }

  void _openCard(String entityId) =>
      showCharacterCard(context, _snapshot, entityId);

  @override
  Widget build(BuildContext context) {
    final sections = widget.model.sections;
    if (sections.isEmpty) {
      return const Center(child: Text('No chapters processed yet.'));
    }
    final theme = Theme.of(context);
    final section = sections[_sectionIndex];

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
                'Known by the end of ${section.title}',
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
                    value: _sectionIndex.toDouble(),
                    max: (sections.length - 1).toDouble(),
                    divisions: sections.length - 1,
                    label: section.label,
                    onChanged: (value) => _selectSection(value.round()),
                  ),
                ),
                Text(sections.last.label, style: theme.textTheme.labelSmall),
              ],
            ),
          )
        else
          const SizedBox(height: 12),
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
              snapshot: _snapshot,
              onEntityTap: _openCard,
            ),
            _StoryMapTab.characters => CharacterListView(
              snapshot: _snapshot,
              onEntityTap: _openCard,
            ),
            _StoryMapTab.chapter => ChapterDigestView(
              snapshot: _snapshot,
              onEntityTap: _openCard,
            ),
          },
        ),
      ],
    );
  }
}
