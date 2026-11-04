import 'package:flutter/material.dart';

import 'highlight_colors.dart';
import 'note.dart';

/// This class is what the reader chose in the note sheet: save the note
/// ([AddNoteResult]) or remove it ([RemoveNoteResult]).
sealed class NoteSheetResult {
  const NoteSheetResult();
}

/// This class holds what the reader typed and picked in the note sheet.
final class AddNoteResult extends NoteSheetResult {
  /// This is the text of the note, with spaces trimmed from both ends.
  final String body;

  /// This is the highlight color the reader picked.
  final HighlightColor color;

  const AddNoteResult(this.body, this.color);
}

/// This class means the reader tapped the remove button to remove the note
/// they were editing.
final class RemoveNoteResult extends NoteSheetResult {
  const RemoveNoteResult();
}

/// This shows the sheet where a reader writes a note about the passage they selected.
/// The same sheet is used to edit a note by passing in its current text and color.
/// Parameters:
/// - selectedText: The passage the note is about, shown at the top of the sheet.
/// - initialBody: The text already in the note when editing. (Optional)
/// - initialColor: The color already picked when editing. (Optional)
/// - title: The title of the sheet. (Ex. 'Add note' or 'Edit note')
/// - removeLabel: The label of a button next to "Save note" that removes the
///   note being edited. No button is shown when it is null, as when adding a
///   new note. (Optional) (Ex. 'Remove highlight' or 'Delete note')
/// Returns: The typed note and color, a [RemoveNoteResult] if the reader tapped
/// the remove button, or null if the reader closed the sheet.
Future<NoteSheetResult?> showAddNoteSheet(
  BuildContext context, {
  required String selectedText,
  String initialBody = '',
  HighlightColor initialColor = HighlightColor.yellow,
  String title = 'Add note',
  String? removeLabel,
}) {
  return showModalBottomSheet<NoteSheetResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _AddNoteSheet(
      selectedText: selectedText,
      initialBody: initialBody,
      initialColor: initialColor,
      title: title,
      removeLabel: removeLabel,
    ),
  );
}

class _AddNoteSheet extends StatefulWidget {
  final String selectedText;
  final String initialBody;
  final HighlightColor initialColor;
  final String title;
  final String? removeLabel;

  const _AddNoteSheet({
    required this.selectedText,
    required this.initialBody,
    required this.initialColor,
    required this.title,
    required this.removeLabel,
  });

  @override
  State<_AddNoteSheet> createState() => _AddNoteSheetState();
}

class _AddNoteSheetState extends State<_AddNoteSheet> {
  // This controls the note text input.
  late final _bodyController = TextEditingController(text: widget.initialBody);
  // This is the highlight color the reader currently has picked.
  late HighlightColor _color = widget.initialColor;
  // This is the message shown under the text box when the reader tries to save an empty note.
  String? _errorText;

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  // This is called when the reader taps "Save note".
  // If the note is empty, the sheet stays open and tells the reader to type something.
  // (See Use Case #3, exception 4a)
  void _save() {
    final body = _bodyController.text.trim();
    if (body.isEmpty) {
      setState(() {
        _errorText = 'Your note is empty. Type something to save it.';
      });
      return;
    }
    Navigator.of(context).pop(AddNoteResult(body, _color));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final removeLabel = widget.removeLabel;
    final saveButton = FilledButton(
      onPressed: _save,
      child: const Text('Save note'),
    );

    return Padding(
      // This moves the sheet up above the keyboard when it is open.
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: textTheme.titleLarge),
          const SizedBox(height: 12),
          // This shows the passage the note is about.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _color.swatch.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.selectedText,
              style: const TextStyle(fontStyle: FontStyle.italic),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bodyController,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'What are you thinking?',
              border: const OutlineInputBorder(),
              errorText: _errorText,
            ),
            // This clears the empty note message once the reader starts typing.
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
          ),
          const SizedBox(height: 16),
          // This is the row of colors the reader can pick for the highlight.
          Row(
            children: [
              for (final color in HighlightColor.values)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _ColorDot(
                    color: color,
                    selected: color == _color,
                    onTap: () => setState(() => _color = color),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (removeLabel == null)
            saveButton
          else
            // When editing, the remove button sits next to "Save note" in red.
            Row(
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: () =>
                      Navigator.of(context).pop(const RemoveNoteResult()),
                  child: Text(removeLabel),
                ),
                const SizedBox(width: 12),
                Expanded(child: saveButton),
              ],
            ),
        ],
      ),
    );
  }
}

/// This is one round color button in the note sheet. The picked color has a check mark.
class _ColorDot extends StatelessWidget {
  final HighlightColor color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: color.label,
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: CircleAvatar(
            radius: 16,
            backgroundColor: color.swatch,
            child: selected
                ? const Icon(Icons.check, size: 18, color: Colors.black87)
                : null,
          ),
        ),
      ),
    );
  }
}
