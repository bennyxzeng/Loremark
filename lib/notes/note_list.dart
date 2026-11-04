import 'package:flutter/material.dart';

import '../home/empty_state.dart';
import '../theme/decor.dart';
import 'add_note_sheet.dart';
import 'annotation_service.dart';
import 'highlight_colors.dart';
import 'note.dart';

/// This is the list shown in the Notes tab. It lists every note and highlight of
/// the book by chapter and lets the reader search, filter, edit, and delete them.
/// (See Use Case #3, steps 6, 6a, 6b, and 6c)
class NoteList extends StatefulWidget {
  /// This is the service that holds and saves the notes of the book.
  final AnnotationService service;

  /// This is called when the reader taps a note, so the app can open the Read tab
  /// at that passage. (Optional)
  final ValueChanged<Note>? onOpenNote;

  const NoteList({super.key, required this.service, this.onOpenNote});

  @override
  State<NoteList> createState() => _NoteListState();
}

class _NoteListState extends State<NoteList> {
  // This controls the search box at the top of the tab.
  final _searchController = TextEditingController();
  // This is the chapter the reader filtered by, or null for every chapter.
  String? _chapter;
  // This is the color the reader filtered by, or null for every color.
  HighlightColor? _color;
  // This is whether the reader is looking at notes, highlights, or both.
  NoteTypeFilter _type = NoteTypeFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  NoteFilter get _filter => NoteFilter(
    query: _searchController.text,
    chapterLabel: _chapter,
    color: _color,
    type: _type,
  );

  // This asks the reader to confirm and only then deletes the note.
  Future<void> _deleteNote(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this note?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await saveOrReport(context, () => widget.service.deleteNote(note.id));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.service,
      builder: (context, _) {
        final service = widget.service;
        if (service.loadError != null) {
          return const _Message(
            'Your notes could not be loaded. They have not been changed.',
          );
        }
        if (service.notes.isEmpty) {
          // This uses the same empty state as the other tabs so the app looks the same everywhere.
          return const EmptyState(
            image: LoremarkArt.chibiPondering,
            label: 'IN THE MARGINS',
            title: 'Notes & theories',
            icon: Icons.edit_note,
            message:
                'No notes yet.\n'
                'Your notes and highlights for this book will appear here.',
          );
        }

        // If the chapter that was filtered by no longer has notes, show every chapter again.
        final chapters = service.chapterLabels;
        if (_chapter != null && !chapters.contains(_chapter)) _chapter = null;
        final groups = service.notesByChapter(_filter);

        return Column(
          children: [
            _buildFilters(chapters),
            Expanded(
              child: groups.isEmpty
                  ? const _Message('No notes match your search.')
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        for (final group in groups) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                            child: Text(
                              group.chapterLabel,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          for (final note in group.notes)
                            _NoteCard(
                              note: note,
                              onTap: widget.onOpenNote == null
                                  ? null
                                  : () => widget.onOpenNote!(note),
                              onEdit: () => editNoteWithSheet(
                                context,
                                widget.service,
                                note,
                              ),
                              onDelete: () => _deleteNote(note),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  // This builds the search box, the All / Notes / Highlights toggle, the chapter
  // picker, and the color filter chips.
  Widget _buildFilters(List<String> chapters) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search notes',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          // This toggle has its own row and fills its width, so it fits on a narrow phone.
          SegmentedButton<NoteTypeFilter>(
            segments: const [
              ButtonSegment(value: NoteTypeFilter.all, label: Text('All')),
              ButtonSegment(value: NoteTypeFilter.notes, label: Text('Notes')),
              ButtonSegment(
                value: NoteTypeFilter.highlights,
                label: Text('Highlights'),
              ),
            ],
            selected: {_type},
            showSelectedIcon: false,
            expandedInsets: EdgeInsets.zero,
            onSelectionChanged: (selection) =>
                setState(() => _type = selection.single),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                DropdownButton<String?>(
                  value: _chapter,
                  underline: const SizedBox.shrink(),
                  items: [
                    const DropdownMenuItem(child: Text('All chapters')),
                    for (final chapter in chapters)
                      DropdownMenuItem(value: chapter, child: Text(chapter)),
                  ],
                  onChanged: (chapter) => setState(() => _chapter = chapter),
                ),
                const SizedBox(width: 8),
                // Tapping a color chip again turns that color filter off.
                for (final color in HighlightColor.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(color.label),
                      avatar: CircleAvatar(backgroundColor: color.swatch),
                      selected: _color == color,
                      onSelected: (selected) =>
                          setState(() => _color = selected ? color : null),
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

/// This opens the note sheet with the note's current text and color, and saves
/// what the reader changes. Used by the Notes tab and by tapping a highlight in
/// the Read tab.
/// Parameters:
/// - service: The service that holds the note.
/// - note: The note to edit. A highlight with no text gets "Add note" as its title.
Future<void> editNoteWithSheet(
  BuildContext context,
  AnnotationService service,
  Note note,
) async {
  final result = await showAddNoteSheet(
    context,
    selectedText: note.selectedText,
    initialBody: note.body,
    initialColor: note.color,
    title: note.isHighlightOnly ? 'Add note' : 'Edit note',
  );
  if (result == null || !context.mounted) return;
  await saveOrReport(
    context,
    () => service.editNote(note.id, body: result.body, color: result.color),
  );
}

/// This runs a save and shows a small message at the bottom if it fails,
/// so a failed save never closes the app or loses the reader's other notes.
/// Parameters:
/// - save: The change to save. (Ex. adding, editing, or deleting a note)
/// - failureMessage: What to show if it fails. (Optional)
Future<void> saveOrReport(
  BuildContext context,
  Future<void> Function() save, {
  String failureMessage = 'Could not save your change. Try again.',
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await save();
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
  }
}

/// This is one note in the Notes tab. It shows the selected passage with its
/// highlight color, the reader's note under it, and a menu to edit or delete.
class _NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback? onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _NoteCard({
    required this.note,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // This colored bar on the left shows the highlight color.
              Container(width: 6, color: note.color.swatch),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '“${note.selectedText}”',
                        style: const TextStyle(fontStyle: FontStyle.italic),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (!note.isHighlightOnly) ...[
                        const SizedBox(height: 8),
                        Text(note.body),
                      ],
                    ],
                  ),
                ),
              ),
              PopupMenuButton<VoidCallback>(
                tooltip: 'Note options',
                onSelected: (action) => action(),
                itemBuilder: (context) => [
                  PopupMenuItem(value: onEdit, child: const Text('Edit')),
                  PopupMenuItem(value: onDelete, child: const Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// This shows a short centered message, like when there are no notes yet.
class _Message extends StatelessWidget {
  final String text;

  const _Message(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
