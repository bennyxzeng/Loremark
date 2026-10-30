import 'package:flutter/material.dart';

import 'add_note_sheet.dart';
import 'annotation_service.dart';
import 'note.dart';

/// This shows a passage of the book that the reader can select to add a note or highlight.
/// When the reader selects text, the menu shows "Highlight" and "Add note"
/// next to the usual copy options. (See Use Case #3, steps 1 to 5)
/// This is a stand-in until the Readium reader is added, which will report the
/// selected text and its position in the book in the same way.
class NotePassage extends StatelessWidget {
  /// This is the service that saves the notes of the book.
  final AnnotationService service;

  /// This is the text of the passage.
  final String text;

  /// This is the index of the book section (EPUB spine item) the passage is in.
  final int sectionIndex;

  /// This is the chapter name saved with each note. (Ex. 'Chapter 8')
  final String chapterLabel;

  /// This is the text style of the passage. (Optional)
  final TextStyle? style;

  const NotePassage({
    super.key,
    required this.service,
    required this.text,
    required this.sectionIndex,
    required this.chapterLabel,
    this.style,
  });

  // This turns the selected range into a spot in the book.
  // Ex. A selection that starts halfway through the passage gets a progression of 0.5.
  NoteAnchor _anchorFor(TextSelection selection) =>
      NoteAnchor(sectionIndex, selection.start / text.length);

  // This saves a highlight on the selected words and tells the reader it was saved.
  Future<void> _highlight(BuildContext context, TextSelection selection) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await service.addHighlight(
        anchor: _anchorFor(selection),
        chapterLabel: chapterLabel,
        selectedText: selection.textInside(text),
      );
      messenger.showSnackBar(const SnackBar(content: Text('Highlight saved')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save the highlight.')),
      );
    }
  }

  // This opens the note sheet for the selected words and saves the note when the reader taps "Save note".
  Future<void> _addNote(BuildContext context, TextSelection selection) async {
    final messenger = ScaffoldMessenger.of(context);
    final selectedText = selection.textInside(text);
    final result = await showAddNoteSheet(context, selectedText: selectedText);
    if (result == null) return;
    try {
      await service.addNote(
        anchor: _anchorFor(selection),
        chapterLabel: chapterLabel,
        selectedText: selectedText,
        body: result.body,
        color: result.color,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save your note.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          text,
          style: style,
          contextMenuBuilder: (menuContext, editableTextState) {
            final selection = editableTextState.textEditingValue.selection;
            // These are our two buttons. They only show up when some text is selected.
            final noteButtons = selection.isCollapsed
                ? <ContextMenuButtonItem>[]
                : [
                    ContextMenuButtonItem(
                      label: 'Highlight',
                      onPressed: () {
                        editableTextState.hideToolbar();
                        _highlight(context, selection);
                      },
                    ),
                    ContextMenuButtonItem(
                      label: 'Add note',
                      onPressed: () {
                        editableTextState.hideToolbar();
                        _addNote(context, selection);
                      },
                    ),
                  ];
            return AdaptiveTextSelectionToolbar.buttonItems(
              anchors: editableTextState.contextMenuAnchors,
              buttonItems: [
                ...noteButtons,
                ...editableTextState.contextMenuButtonItems,
              ],
            );
          },
        ),
        // This marks the passage with a note icon when the reader has notes on it.
        ListenableBuilder(
          listenable: service,
          builder: (context, _) {
            final count = service.notes
                .where(
                  (note) =>
                      note.anchor.sectionIndex == sectionIndex &&
                      !note.isHighlightOnly,
                )
                .length;
            if (count == 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.sticky_note_2_outlined, size: 18),
                  const SizedBox(width: 6),
                  Text(count == 1 ? '1 note here' : '$count notes here'),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
