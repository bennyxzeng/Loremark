import 'dart:math';

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
  /// - color: The highlight color of the passage. Green, blue, or pink, since
  ///   yellow is kept for plain highlights. (Optional, green by default)
  ///   (See [noteColors] and issue #124)
  /// Returns: The saved note, or throws an [EmptyNoteException] if the body is blank.
  /// Throws an [ArgumentError] if the color is yellow.
  Future<Note> addNote({
    required NoteAnchor anchor,
    required String chapterLabel,
    required String selectedText,
    String textBefore = '',
    String textAfter = '',
    required String body,
    HighlightColor color = defaultNoteColor,
  }) async {
    if (body.trim().isEmpty) throw const EmptyNoteException();
    _checkNoteColor(color);
    return _add(
      anchor: anchor,
      chapterLabel: chapterLabel,
      selectedText: selectedText,
      textBefore: textBefore,
      textAfter: textAfter,
      body: body.trim(),
      color: color,
    );
  }

  /// This saves a highlight on a passage without any written text.
  /// A highlight is always yellow, so the reader can tell it from a note at a
  /// glance. (See Use Case #3, extension 3a, and issue #124)
  Future<Note> addHighlight({
    required NoteAnchor anchor,
    required String chapterLabel,
    required String selectedText,
    String textBefore = '',
    String textAfter = '',
  }) => _add(
    anchor: anchor,
    chapterLabel: chapterLabel,
    selectedText: selectedText,
    textBefore: textBefore,
    textAfter: textAfter,
    body: '',
    color: highlightColor,
  );

  /// This changes the text and/or color of a saved note.
  /// Adding text to a highlight turns it into a note, which takes the given
  /// color, or green if none is given, since a note is never yellow.
  /// A highlight's own color cannot change: it is always yellow. (See issue #124)
  /// Parameters:
  /// - id: The id of the note to edit.
  /// - body: The new text. (Optional, cannot be blank if given)
  /// - color: The new color, green, blue, or pink. (Optional)
  /// Returns: The edited note.
  /// Throws an [ArgumentError] if the color is yellow, or if a color is given
  /// for a highlight that stays without text.
  Future<Note> editNote(
    String id, {
    String? body,
    HighlightColor? color,
  }) async {
    if (body != null && body.trim().isEmpty) throw const EmptyNoteException();
    final index = _indexOf(id);
    final note = _notes[index];
    final becomesNote = body != null && note.isHighlightOnly;
    final staysHighlight = body == null && note.isHighlightOnly;
    if (color != null) {
      if (staysHighlight) {
        throw ArgumentError.value(
          color,
          'color',
          'A highlight is always ${highlightColor.name}',
        );
      }
      _checkNoteColor(color);
    }
    final edited = note.copyWith(
      body: body?.trim(),
      color: color ?? (becomesNote ? defaultNoteColor : null),
      updatedAt: _clock(),
    );
    await _save([..._notes]..[index] = edited);
    return edited;
  }

  /// This rejects a color that a note cannot have. (See [noteColors])
  static void _checkNoteColor(HighlightColor color) {
    if (!noteColors.contains(color)) {
      throw ArgumentError.value(
        color,
        'color',
        'A note is ${noteColors.map((c) => c.name).join(', ')}',
      );
    }
  }

  /// This deletes a note. The app asks the reader to confirm first, except for a
  /// highlight with no text, since nothing written is lost.
  Future<void> deleteNote(String id) async {
    final index = _indexOf(id);
    await _save([..._notes]..removeAt(index));
  }

  /// This finds every note drawn over the same words as the given note,
  /// including the note itself, in reading order.
  /// The reader view only reports the top highlight when two of them are drawn
  /// on the same words, so the Read tab uses this to let the reader pick one.
  /// (See issue #112)
  /// Two notes overlap only when they share words on the page: they are in
  /// the same section, and the other note's words sit on some of this note's
  /// words. Ex. 'the lamp' and 'She lit the' overlap when both were selected
  /// in "She lit the lamp", but 'the lamp' and 'the door' a sentence later do
  /// not, even though each is in the other's surrounding text.
  /// Parameters:
  /// - note: The note the reader tapped.
  /// Returns: The overlapping notes, or just [note] if nothing overlaps it.
  List<Note> notesOverlapping(Note note) => [
    for (final other in _notes)
      if (other.id == note.id ||
          (other.anchor.sectionIndex == note.anchor.sectionIndex &&
              _sharesWords(note, other)))
        other,
  ];

  /// This checks if [other]'s words sit on some of [note]'s words.
  /// Each note keeps its words with the text around them, so [other] is
  /// placed inside [note]'s passage where its own surrounding text agrees
  /// with what is there, and the two spans are compared.
  /// Only the surrounding text both notes have is compared, so a note saved
  /// without any (from before it was kept) matches its words anywhere.
  static bool _sharesWords(Note note, Note other) {
    final passage = '${note.textBefore}${note.selectedText}${note.textAfter}';
    final start = note.textBefore.length;
    final end = start + note.selectedText.length;
    final words = other.selectedText;
    if (words.isEmpty) return false;
    for (
      var at = passage.indexOf(words);
      at != -1;
      at = passage.indexOf(words, at + 1)
    ) {
      final after = at + words.length;
      // The other note's span must cover part of this note's span.
      if (at >= end || after <= start) continue;
      // And the text around it must match what the other note saved there.
      final before = min(at, other.textBefore.length);
      final behind = min(passage.length - after, other.textAfter.length);
      final beforeMatches = passage
          .substring(at - before, at)
          .endsWith(
            other.textBefore.substring(other.textBefore.length - before),
          );
      final afterMatches = passage
          .substring(after, after + behind)
          .startsWith(other.textAfter.substring(0, behind));
      if (beforeMatches && afterMatches) return true;
    }
    return false;
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

  // Notes at the same spot are ordered by when they were made, then by id.
  // Dart's sort does not promise to keep equal items in order, so without this
  // two notes on the same words could swap places in the Notes tab and in the
  // order they are drawn on the page. (See issue #112)
  static List<Note> _sorted(List<Note> notes) => [...notes]
    ..sort((a, b) {
      final byPlace = a.anchor.compareTo(b.anchor);
      if (byPlace != 0) return byPlace;
      final byTime = a.createdAt.compareTo(b.createdAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
}
