import 'package:flutter/foundation.dart';

import 'note.dart';
import 'note_repository.dart';

/// This exception is thrown when a reader tries to save a note with no text.
/// (See Use Case #3, exception 4a)
class EmptyNoteException implements Exception {
  const EmptyNoteException();

  @override
  String toString() => 'A note cannot be empty.';
}

/// This exception is thrown when a note id does not match any saved note.
class NoteNotFoundException implements Exception {
  /// This is the id that could not be found.
  final String id;

  const NoteNotFoundException(this.id);

  @override
  String toString() => 'No note with id $id.';
}

/// This class holds the filters the reader picked in the Notes tab.
/// Every filter is optional, and a null filter means "show everything".
/// Ex. NoteFilter(color: HighlightColor.blue, query: 'Elian') shows only blue
/// notes that mention Elian.
class NoteFilter {
  /// This is the text to search for in the note and in the selected passage.
  final String query;

  /// This is the only chapter to show. (Optional)
  final String? chapterLabel;

  /// This is the only highlight color to show. (Optional)
  final HighlightColor? color;

  const NoteFilter({this.query = '', this.chapterLabel, this.color});

  /// This checks if a note passes every filter.
  bool matches(Note note) {
    if (chapterLabel != null && note.chapterLabel != chapterLabel) {
      return false;
    }
    if (color != null && note.color != color) return false;
    final search = query.trim().toLowerCase();
    if (search.isEmpty) return true;
    return note.body.toLowerCase().contains(search) ||
        note.selectedText.toLowerCase().contains(search);
  }
}

/// This class is one chapter section of the Notes tab with the notes made in it.
class ChapterNotes {
  /// This is the chapter name shown above the notes. (Ex. 'Chapter 8')
  final String chapterLabel;

  /// These are the notes of that chapter in reading order.
  final List<Note> notes;

  const ChapterNotes(this.chapterLabel, this.notes);
}

/// This service creates, edits, deletes, and searches the notes of one book.
/// It keeps the notes in memory for the UI and saves every change right away
/// through the [NoteRepository], so notes are not lost if the app is closed.
/// Notes are kept separate from the story model and are never used as story facts.
class AnnotationService extends ChangeNotifier {
  /// This is the id of the book whose notes this service manages.
  final String bookId;

  /// This is where the notes are loaded from and saved to.
  final NoteRepository repository;

  /// This returns the current time. Tests pass in a fixed clock.
  final DateTime Function() _clock;

  /// These are all the notes of the book, always kept in reading order.
  List<Note> _notes = [];

  /// This counter makes ids unique even when two notes are made in the same microsecond.
  int _idCounter = 0;

  /// This is set when the notes file could not be read.
  /// While it is set, saving is blocked so the unreadable file is not overwritten.
  Object? _loadError;

  AnnotationService({
    required this.bookId,
    required this.repository,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// These are all the notes of the book in reading order.
  List<Note> get notes => List.unmodifiable(_notes);

  /// This is the error from the last [load], or null if the notes loaded fine.
  Object? get loadError => _loadError;

  /// This is every chapter that has at least one note, in reading order.
  /// Used for the chapter filter in the Notes tab.
  List<String> get chapterLabels => [
    for (final group in notesByChapter()) group.chapterLabel,
  ];

  /// This loads the saved notes of the book from the device.
  /// If the file is corrupted, the error is kept in [loadError] instead of being thrown.
  Future<void> load() async {
    try {
      _notes = _sorted(await repository.load());
      _loadError = null;
    } on NotesFileCorruptedException catch (error) {
      _notes = [];
      _loadError = error;
    }
    notifyListeners();
  }

  /// This creates a new note on a passage the reader selected.
  /// Parameters:
  /// - anchor: Where the selected passage is in the book.
  /// - chapterLabel: The chapter name to show in the Notes tab.
  /// - selectedText: The passage the reader selected.
  /// - body: What the reader wrote. (Required, cannot be blank)
  /// - color: The highlight color of the passage.
  /// Returns: The saved note, or throws an [EmptyNoteException] if the body is blank.
  Future<Note> addNote({
    required NoteAnchor anchor,
    required String chapterLabel,
    required String selectedText,
    required String body,
    HighlightColor color = HighlightColor.yellow,
  }) async {
    if (body.trim().isEmpty) throw const EmptyNoteException();
    return _add(anchor, chapterLabel, selectedText, body.trim(), color);
  }

  /// This saves a colored highlight on a passage without any written text.
  /// (See Use Case #3, extension 3a)
  Future<Note> addHighlight({
    required NoteAnchor anchor,
    required String chapterLabel,
    required String selectedText,
    HighlightColor color = HighlightColor.yellow,
  }) => _add(anchor, chapterLabel, selectedText, '', color);

  /// This changes the text and/or color of a saved note.
  /// Parameters:
  /// - id: The id of the note to edit.
  /// - body: The new text. (Optional, cannot be blank if given)
  /// - color: The new highlight color. (Optional)
  /// Returns: The edited note.
  Future<Note> editNote(
    String id, {
    String? body,
    HighlightColor? color,
  }) async {
    if (body != null && body.trim().isEmpty) throw const EmptyNoteException();
    final index = _indexOf(id);
    final edited = _notes[index].copyWith(
      body: body?.trim(),
      color: color,
      updatedAt: _clock(),
    );
    await _save([..._notes]..[index] = edited);
    return edited;
  }

  /// This deletes a note. The Notes tab asks the reader to confirm before calling this.
  Future<void> deleteNote(String id) async {
    final index = _indexOf(id);
    await _save([..._notes]..removeAt(index));
  }

  /// This groups the notes by chapter for the Notes tab, after applying the filter.
  /// Chapters are in reading order, and so are the notes inside each chapter.
  /// Parameters:
  /// - filter: What the reader searched for or picked. (Optional)
  /// Returns: One [ChapterNotes] for every chapter that still has notes after filtering.
  List<ChapterNotes> notesByChapter([NoteFilter filter = const NoteFilter()]) {
    final groups = <String, List<Note>>{};
    // The notes are already in reading order, so each chapter is added to the
    // map the first time one of its notes shows up, which keeps chapters in order too.
    for (final note in _notes.where(filter.matches)) {
      groups.putIfAbsent(note.chapterLabel, () => []).add(note);
    }
    return [
      for (final entry in groups.entries) ChapterNotes(entry.key, entry.value),
    ];
  }

  Future<Note> _add(
    NoteAnchor anchor,
    String chapterLabel,
    String selectedText,
    String body,
    HighlightColor color,
  ) async {
    final now = _clock();
    final note = Note(
      id: '${now.microsecondsSinceEpoch}-${_idCounter++}',
      bookId: bookId,
      anchor: anchor,
      chapterLabel: chapterLabel,
      selectedText: selectedText,
      body: body,
      color: color,
      createdAt: now,
      updatedAt: now,
    );
    await _save([..._notes, note]);
    return note;
  }

  int _indexOf(String id) {
    final index = _notes.indexWhere((note) => note.id == id);
    if (index == -1) throw NoteNotFoundException(id);
    return index;
  }

  /// This saves the new list of notes to the device first, and only then
  /// updates the notes in memory, so the screen never shows a change that was not saved.
  Future<void> _save(List<Note> notes) async {
    if (_loadError != null) {
      throw StateError('Notes could not be loaded, so they cannot be saved.');
    }
    final sorted = _sorted(notes);
    await repository.save(sorted);
    _notes = sorted;
    notifyListeners();
  }

  // Sorting is stable, so notes at the same spot stay in the order they were made.
  static List<Note> _sorted(List<Note> notes) =>
      [...notes]..sort((a, b) => a.anchor.compareTo(b.anchor));
}
