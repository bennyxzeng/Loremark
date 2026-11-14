import 'package:flutter/material.dart';

import '../notes/annotation_service.dart';
import '../notes/note.dart';
import '../notes/note_list.dart';

/// This is the Notes tab. It lists the notes of the opened book once they are loaded.
/// The same notes are shared with the Read tab, so a note made there shows up here right away.
/// (See Use Case #3, step 6)
class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key, required this.notes, this.onOpenNote});

  /// These are the loaded notes of the book. (See [AnnotationService.openForBook])
  final Future<AnnotationService> notes;

  /// This is called when the reader taps a note. (Optional)
  final ValueChanged<Note>? onOpenNote;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AnnotationService>(
      future: notes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not open your notes.'));
        }
        final service = snapshot.data;
        // Plain text rather than a spinner: an endless animation would keep
        // widget tests from settling.
        if (service == null) {
          return const Center(child: Text('Loading notes…'));
        }
        return NoteList(service: service, onOpenNote: onOpenNote);
      },
    );
  }
}
