import 'dart:async';

import 'package:flutter/material.dart';

import '../home/empty_state.dart';
import '../theme/decor.dart';
import 'add_note_sheet.dart';
import 'annotation_service.dart';
import 'highlight_colors.dart';
import 'note.dart';
import 'theory.dart';

/// This asks the Notes tab to scroll to one note and briefly emphasise it.
/// The screen that owns the tabs switches to the Notes tab and calls [focus].
/// It is also how the theory banner opens a theory in the Notes tab.
class NoteFocusController extends ChangeNotifier {
  String? _pending;

  /// This asks the Notes tab to show the note with the given id. If the tab is
  /// not built yet, it shows the note as soon as it is.
  void focus(String noteId) {
    _pending = noteId;
    notifyListeners();
  }

  /// This hands out the note id the tab still has to show, once.
  String? takePending() {
    final id = _pending;
    _pending = null;
    return id;
  }
}

/// This is the list shown in the Notes tab. It lists every note and highlight of
/// the book by chapter and lets the reader search, filter, edit, and delete them.
/// (See Use Case #3, steps 6, 6a, 6b, and 6c)
class NoteList extends StatefulWidget {
  /// This is the service that holds and saves the notes of the book.
  final AnnotationService service;

  /// This is called when the reader taps a note, so the app can open the Read tab
  /// at that passage. (Optional)
  final ValueChanged<Note>? onOpenNote;

  /// This lets other code scroll the list to one note. (Optional)
  final NoteFocusController? focusController;

  const NoteList({
    super.key,
    required this.service,
    this.onOpenNote,
    this.focusController,
  });

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
  // This is the note that was just asked for, drawn with an outline for a moment.
  String? _emphasisedId;
  Timer? _emphasisTimer;
  // These find each note card on screen so the list can scroll to one.
  final _cardKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    widget.focusController?.addListener(_onFocusRequested);
    // A request made before this tab was built is still waiting.
    if (widget.focusController?.takePending() case final id?) _focusNote(id);
  }

  @override
  void didUpdateWidget(NoteList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusController != widget.focusController) {
      oldWidget.focusController?.removeListener(_onFocusRequested);
      widget.focusController?.addListener(_onFocusRequested);
    }
  }

  @override
  void dispose() {
    widget.focusController?.removeListener(_onFocusRequested);
    _emphasisTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onFocusRequested() {
    final id = widget.focusController?.takePending();
    if (id != null) _focusNote(id);
  }

  // This clears the filters so the note is not hidden, scrolls to it, and
  // outlines it for two seconds.
  void _focusNote(String id) {
    if (!widget.service.notes.any((note) => note.id == id)) return;
    _emphasisTimer?.cancel();
    setState(() {
      _searchController.clear();
      _chapter = null;
      _color = null;
      _type = NoteTypeFilter.all;
      _emphasisedId = id;
    });
    _emphasisTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _emphasisedId = null);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _cardKeys[id]?.currentContext;
      if (context != null && context.mounted) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.2,
          duration: const Duration(milliseconds: 250),
        );
      }
    });
  }

  NoteFilter get _filter => NoteFilter(
    query: _searchController.text,
    chapterLabel: _chapter,
    color: _color,
    type: _type,
  );

  // This asks the reader to confirm and only then deletes the note.
  Future<void> _deleteNote(Note note) async {
    final confirmed = await confirmDeleteNote(context);
    if (!confirmed || !mounted) return;
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
                  // A plain scroll view builds every card, which the scroll to a
                  // focused note needs, and a book has few enough notes for that.
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                key: _cardKeys.putIfAbsent(
                                  note.id,
                                  GlobalKey.new,
                                ),
                                note: note,
                                emphasised: note.id == _emphasisedId,
                                status: note.kind == NoteKind.theory
                                    ? service.statusOf(note.id)
                                    : null,
                                buildsOn: _buildsOnText(service, note),
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
            ),
          ],
        );
      },
    );
  }

  // This is the text of the older theory a theory builds on, or null if it
  // builds on nothing (or on a theory that is gone).
  String? _buildsOnText(AnnotationService service, Note note) {
    final id = note.theory?.dependsOnId;
    if (id == null) return null;
    final parent = service.notes.where((each) => each.id == id).firstOrNull;
    return parent == null ? null : shortenTheoryText(parent.body, 60);
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

/// This opens the note sheet with the note's current text, color, and kind, and saves
/// what the reader changes. The sheet also has a button to remove the note.
/// Used by the Notes tab and by tapping a highlight in the Read tab.
/// Parameters:
/// - service: The service that holds the note.
/// - note: The note to edit. A highlight with no text gets "Add note" as its
///   title and a "Remove highlight" button that removes it right away, since
///   nothing written is lost. A note with text gets a "Delete note" button
///   that asks the reader to confirm first.
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
    initialKind: note.kind,
    initialDependsOnId: note.theory?.dependsOnId,
    olderTheories: service.theoriesBefore(note.id),
    title: note.isHighlightOnly ? 'Add note' : 'Edit note',
    removeLabel: note.isHighlightOnly ? 'Remove highlight' : 'Delete note',
  );
  if (result == null || !context.mounted) return;
  switch (result) {
    case AddNoteResult(
      :final body,
      :final color,
      :final kind,
      :final dependsOnId,
    ):
      await saveOrReport(
        context,
        () => service.editNote(
          note.id,
          body: body,
          color: color,
          kind: kind,
          dependsOnId: dependsOnId,
          // A theory saved with "None" builds on nothing.
          clearDependsOn: kind == NoteKind.theory && dependsOnId == null,
        ),
      );
    case RemoveNoteResult():
      if (!note.isHighlightOnly) {
        final confirmed = await confirmDeleteNote(context);
        if (!confirmed || !context.mounted) return;
      }
      await saveOrReport(context, () => service.deleteNote(note.id));
  }
}

/// This asks the reader to confirm before a note is deleted.
/// Returns: True if the reader tapped Delete, or false if they tapped Cancel
/// or closed the dialog.
Future<bool> confirmDeleteNote(BuildContext context) async {
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
  return confirmed ?? false;
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
/// A theory also shows a "Theory" tag, how it is doing, the older theory it
/// builds on, and each of its sub-theories with what settled it.
class _NoteCard extends StatelessWidget {
  final Note note;

  /// This is how the theory is doing, or null for a personal note.
  final TheoryStatus? status;

  /// This is the older theory it builds on, or null.
  final String? buildsOn;

  /// This is true for a moment after the card was asked for.
  final bool emphasised;
  final VoidCallback? onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _NoteCard({
    super.key,
    required this.note,
    required this.status,
    required this.buildsOn,
    required this.emphasised,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theory = note.theory;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: emphasised
            ? BorderSide(color: scheme.primary, width: 2)
            : BorderSide.none,
      ),
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
                      if (status != null) ...[
                        _TheoryTags(status: status!),
                        const SizedBox(height: 8),
                      ],
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
                      if (buildsOn != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Builds on: $buildsOn',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (theory != null && theory.subTheories.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        for (final sub in theory.subTheories)
                          _SubTheoryRow(sub: sub),
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

/// This is the "Theory" tag and the status chip at the top of a theory.
class _TheoryTags extends StatelessWidget {
  final TheoryStatus status;

  const _TheoryTags({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (status) {
      TheoryStatus.confirmed => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      TheoryStatus.partiallyCorrect => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      TheoryStatus.differentOutcome || TheoryStatus.invalidated => (
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      TheoryStatus.unconfirmed => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        _Tag(
          label: 'Theory',
          background: scheme.secondaryContainer,
          foreground: scheme.onSecondaryContainer,
        ),
        _Tag(
          label: status.label,
          background: background,
          foreground: foreground,
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _Tag({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: foreground),
      ),
    );
  }
}

/// This is one sub-theory of a theory: its verdict, and if the book settled it,
/// the quote that did and the chapter it is from.
class _SubTheoryRow extends StatelessWidget {
  final SubTheory sub;

  const _SubTheoryRow({required this.sub});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final evidence = sub.evidence;
    final (icon, verdict) = switch (sub.verdict) {
      SubTheoryVerdict.open => (Icons.radio_button_unchecked, 'Open'),
      SubTheoryVerdict.confirmed => (Icons.check_circle_outline, 'Confirmed'),
      SubTheoryVerdict.refuted => (Icons.cancel_outlined, 'Refuted'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${sub.text} ($verdict)', style: textTheme.bodyMedium),
                if (evidence != null)
                  Text(
                    '“${evidence.quote}” (${evidence.chapterLabel})',
                    style: textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
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
