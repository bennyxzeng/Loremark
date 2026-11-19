import 'package:flutter/foundation.dart';

import 'note.dart';
import 'note_repository.dart';
import 'theory.dart';

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

/// This enum lists which kinds of entries the Notes tab shows.
/// A note has text the reader wrote, and a highlight has none.
/// (See [Note.isHighlightOnly])
enum NoteTypeFilter {
  /// This shows notes and highlights.
  all,

  /// This shows only notes with text the reader wrote.
  notes,

  /// This shows only highlights with no text.
  highlights,
}

/// This class holds the filters the reader picked in the Notes tab.
/// Every filter is optional, and a null filter means "show everything".
/// Ex. NoteFilter(color: HighlightColor.blue, query: 'Elian') shows only blue
/// notes that mention Elian.
/// Ex. NoteFilter(type: NoteTypeFilter.highlights) shows only highlights.
class NoteFilter {
  /// This is the text to search for in the note and in the selected passage.
  final String query;

  /// This is the only chapter to show. (Optional)
  final String? chapterLabel;

  /// This is the only highlight color to show. (Optional)
  final HighlightColor? color;

  /// This is whether to show notes, highlights, or both. (Optional, shows both by default)
  final NoteTypeFilter type;

  const NoteFilter({
    this.query = '',
    this.chapterLabel,
    this.color,
    this.type = NoteTypeFilter.all,
  });

  /// This checks if a note passes every filter.
  bool matches(Note note) {
    if (chapterLabel != null && note.chapterLabel != chapterLabel) {
      return false;
    }
    if (color != null && note.color != color) return false;
    if (type == NoteTypeFilter.notes && note.isHighlightOnly) return false;
    if (type == NoteTypeFilter.highlights && !note.isHighlightOnly) {
      return false;
    }
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

  /// This creates the service for a book's notes saved on the device and loads them.
  /// The Read and Notes tabs share the one it returns.
  /// Parameters:
  /// - bookId: The id of the book. (Ex. 'abc123')
  /// Returns: The loaded service. A corrupted notes file shows up in [loadError] instead.
  static Future<AnnotationService> openForBook(String bookId) async {
    final service = AnnotationService(
      bookId: bookId,
      repository: await NoteRepository.forBook(bookId),
    );
    await service.load();
    return service;
  }

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
  /// - textBefore, textAfter: The text just around the passage. (Optional)
  /// - body: What the reader wrote. (Required, cannot be blank)
  /// - color: The highlight color of the passage.
  /// - kind: Whether it is a personal note or a theory. (Optional, personal note by default)
  /// - dependsOnId: The older theory of this book that a new theory builds on.
  ///   (Optional, only for a theory)
  /// Returns: The saved note. Throws an [EmptyNoteException] if the body is
  /// blank, and an [ArgumentError] if [dependsOnId] is given for a personal
  /// note or does not name a theory of this book.
  Future<Note> addNote({
    required NoteAnchor anchor,
    required String chapterLabel,
    required String selectedText,
    String textBefore = '',
    String textAfter = '',
    required String body,
    HighlightColor color = HighlightColor.yellow,
    NoteKind kind = NoteKind.personalNote,
    String? dependsOnId,
  }) async {
    if (body.trim().isEmpty) throw const EmptyNoteException();
    if (kind == NoteKind.personalNote && dependsOnId != null) {
      throw ArgumentError.value(
        dependsOnId,
        'dependsOnId',
        'only a theory can build on another theory',
      );
    }
    // Every theory saved so far was made before this one, so any may be built on.
    if (dependsOnId != null) _requireTheory(dependsOnId);
    return _add(
      anchor: anchor,
      chapterLabel: chapterLabel,
      selectedText: selectedText,
      textBefore: textBefore,
      textAfter: textAfter,
      body: body.trim(),
      color: color,
      kind: kind,
      theory: kind == NoteKind.theory
          ? TheoryState(dependsOnId: dependsOnId)
          : null,
    );
  }

  /// This saves a colored highlight on a passage without any written text.
  /// (See Use Case #3, extension 3a)
  Future<Note> addHighlight({
    required NoteAnchor anchor,
    required String chapterLabel,
    required String selectedText,
    String textBefore = '',
    String textAfter = '',
    HighlightColor color = HighlightColor.yellow,
  }) => _add(
    anchor: anchor,
    chapterLabel: chapterLabel,
    selectedText: selectedText,
    textBefore: textBefore,
    textAfter: textAfter,
    body: '',
    color: color,
  );

  /// This changes a saved note. Editing a theory's text starts it over: its
  /// sub-theories and check progress are cleared, because it is a new prediction.
  /// A note can be switched between personal note and theory, and one that
  /// becomes a personal note loses its theory data.
  /// Parameters:
  /// - id: The id of the note to edit.
  /// - body: The new text. (Optional, cannot be blank if given)
  /// - color: The new highlight color. (Optional)
  /// - kind: The new kind. (Optional)
  /// - dependsOnId: The older theory this one builds on. (Optional, only for a
  ///   theory, and only a theory made before this one)
  /// - clearDependsOn: True to remove the link instead. (Optional)
  /// Returns: The edited note. Throws an [ArgumentError] if the dependency is
  /// not allowed.
  Future<Note> editNote(
    String id, {
    String? body,
    HighlightColor? color,
    NoteKind? kind,
    String? dependsOnId,
    bool clearDependsOn = false,
  }) async {
    if (body != null && body.trim().isEmpty) throw const EmptyNoteException();
    final index = _indexOf(id);
    final old = _notes[index];
    final newKind = kind ?? old.kind;
    if (newKind == NoteKind.personalNote && dependsOnId != null) {
      throw ArgumentError.value(
        dependsOnId,
        'dependsOnId',
        'only a theory can build on another theory',
      );
    }
    TheoryState? theory;
    if (newKind == NoteKind.theory) {
      theory = old.theory ?? const TheoryState();
      if (clearDependsOn) theory = theory.copyWith(clearDependsOn: true);
      if (dependsOnId != null) {
        _requireOlderTheory(dependsOnId, than: old);
        theory = theory.copyWith(dependsOnId: dependsOnId);
      }
      final textChanged = body != null && body.trim() != old.body;
      if (old.kind == NoteKind.theory && textChanged) {
        theory = TheoryState(dependsOnId: theory.dependsOnId);
      }
    }
    final edited = old.copyWith(
      body: body?.trim(),
      color: color,
      kind: newKind,
      theory: theory,
      updatedAt: _clock(),
    );
    await _save([..._notes]..[index] = edited);
    return edited;
  }

  /// This deletes a note. The app asks the reader to confirm first, except for a
  /// highlight with no text, since nothing written is lost.
  /// A theory that built on the deleted one stops building on anything, and
  /// everything is saved in one go.
  Future<void> deleteNote(String id) async {
    _indexOf(id);
    await _save([
      for (final note in _notes)
        if (note.id != id)
          if (note.theory?.dependsOnId == id)
            note.copyWith(theory: note.theory!.copyWith(clearDependsOn: true))
          else
            note,
    ]);
  }

  /// These are the theories of the book in reading order.
  List<Note> get theories => List.unmodifiable([
    for (final note in _notes)
      if (note.kind == NoteKind.theory) note,
  ]);

  /// These are the theories of the book that a note could build on: the ones
  /// made before the note with the given id, in reading order.
  /// Used for the "Builds on" picker.
  List<Note> theoriesBefore(String id) {
    final note = _notes[_indexOf(id)];
    return [
      for (final each in _notes)
        if (each.kind == NoteKind.theory && _isOlder(each, note)) each,
    ];
  }

  /// This tells how the theory with the given id is doing right now.
  /// It is worked out from the sub-theories and the theories it builds on each time.
  /// Throws a [NoteNotFoundException] if there is no such note, and an
  /// [ArgumentError] if the note is not a theory.
  TheoryStatus statusOf(String id) {
    final note = _notes[_indexOf(id)];
    return theoryStatus(note, {for (final each in _notes) each.id: each});
  }

  /// This changes what is tracked about a theory and saves it. It is the one
  /// way the theory checker writes verdicts, evidence, and progress.
  /// The note's text and its edit time are left alone.
  /// Parameters:
  /// - id: The id of the theory.
  /// - change: Gets the current [TheoryState] and returns the new one.
  /// Returns: The updated note. Throws a [NoteNotFoundException] if there is no
  /// such note, and an [ArgumentError] if it is not a theory.
  Future<Note> updateTheory(
    String id,
    TheoryState Function(TheoryState current) change,
  ) async {
    final index = _indexOf(id);
    final old = _notes[index];
    final current = old.theory;
    if (old.kind != NoteKind.theory || current == null) {
      throw ArgumentError.value(id, 'id', 'is not a theory');
    }
    final updated = old.copyWith(theory: change(current));
    await _save([..._notes]..[index] = updated);
    return updated;
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

  Future<Note> _add({
    required NoteAnchor anchor,
    required String chapterLabel,
    required String selectedText,
    required String textBefore,
    required String textAfter,
    required String body,
    required HighlightColor color,
    NoteKind kind = NoteKind.personalNote,
    TheoryState? theory,
  }) async {
    final now = _clock();
    final note = Note(
      id: '${now.microsecondsSinceEpoch}-${_idCounter++}',
      bookId: bookId,
      anchor: anchor,
      chapterLabel: chapterLabel,
      selectedText: selectedText,
      textBefore: textBefore,
      textAfter: textAfter,
      body: body,
      color: color,
      kind: kind,
      theory: theory,
      createdAt: now,
      updatedAt: now,
    );
    await _save([..._notes, note]);
    return note;
  }

  // This makes sure the id names a theory of this book, or throws an ArgumentError.
  Note _requireTheory(String id) {
    final note = _notes.where((note) => note.id == id).firstOrNull;
    if (note == null || note.kind != NoteKind.theory) {
      throw ArgumentError.value(
        id,
        'dependsOnId',
        'is not a theory of this book',
      );
    }
    return note;
  }

  // This is the same check, and also makes sure the theory is older than [than],
  // which is what keeps the links from ever forming a loop.
  void _requireOlderTheory(String id, {required Note than}) {
    final parent = _requireTheory(id);
    if (!_isOlder(parent, than)) {
      throw ArgumentError.value(
        id,
        'dependsOnId',
        'must be a theory made before the one that builds on it',
      );
    }
  }

  // This is true when [a] was made before [b]. Notes made at the same moment
  // are told apart by the counter at the end of the id.
  static bool _isOlder(Note a, Note b) {
    if (a.id == b.id) return false;
    final byTime = a.createdAt.compareTo(b.createdAt);
    if (byTime != 0) return byTime < 0;
    int counter(Note note) => int.tryParse(note.id.split('-').last) ?? 0;
    return counter(a) < counter(b);
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
