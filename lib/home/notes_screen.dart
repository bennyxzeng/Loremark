import 'package:flutter/material.dart';

import '../library/book.dart';
import '../notes/annotation_service.dart';
import '../notes/note.dart';
import '../notes/note_list.dart';
import '../notes/note_repository.dart';

/// This opens the notes of a book. Tests pass in their own so nothing is read from the device.
typedef NotesOpener = Future<AnnotationService> Function(String bookId);

/// This creates the notes service for a book, saved in the app's library folder.
/// The notes are loaded afterwards by [NotesScreen].
Future<AnnotationService> _openSavedNotes(String bookId) async =>
    AnnotationService(
      bookId: bookId,
      repository: await NoteRepository.forBook(bookId),
    );

/// This is the Notes tab. It loads the notes of the opened [book] and lists them.
/// (See Use Case #3, step 6)
class NotesScreen extends StatefulWidget {
  const NotesScreen({
    super.key,
    required this.book,
    this.onOpenNote,
    this.openNotes = _openSavedNotes,
  });

  /// This is the book whose notes are shown.
  final Book book;

  /// This is called when the reader taps a note. (Optional)
  final ValueChanged<Note>? onOpenNote;

  /// This loads the notes of the book. (Optional, reads from the device by default)
  final NotesOpener openNotes;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  // The notes are only loaded once, when the tab is first built.
  late final Future<AnnotationService> _notes = _open();

  // This opens the service and loads the saved notes into it.
  Future<AnnotationService> _open() async {
    final service = await widget.openNotes(widget.book.id);
    await service.load();
    return service;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AnnotationService>(
      future: _notes,
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
        return NoteList(service: service, onOpenNote: widget.onOpenNote);
      },
    );
  }
}
