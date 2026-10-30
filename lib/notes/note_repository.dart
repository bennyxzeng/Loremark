import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'note.dart';

/// This exception is thrown when the notes file exists but cannot be read.
/// We throw instead of returning an empty list so the app never saves over
/// (and loses) notes that are only unreadable.
class NotesFileCorruptedException implements Exception {
  /// This is the path of the notes file that could not be read.
  final String path;

  /// This is the reason the file could not be read.
  final Object cause;

  const NotesFileCorruptedException(this.path, this.cause);

  @override
  String toString() => 'Could not read notes file at $path: $cause';
}

/// This class loads and saves all the notes of one book in a `notes.json` file.
/// Every book has its own directory, so each book has its own notes file.
/// (See "Data Stored" in our design document)
class NoteRepository {
  /// This is the version of the notes file format, saved inside the file.
  static const fileVersion = 1;

  /// This is the directory of the book that the notes file is stored in.
  final Directory bookDirectory;

  NoteRepository(this.bookDirectory);

  /// This creates a repository for a book inside the app's documents folder.
  /// Ex. For the book id 'glass-harbor' the notes are saved in
  /// `<app documents>/books/glass-harbor/notes.json`.
  static Future<NoteRepository> forBook(String bookId) async {
    final documents = await getApplicationDocumentsDirectory();
    return NoteRepository(Directory('${documents.path}/books/$bookId'));
  }

  File get _notesFile => File('${bookDirectory.path}/notes.json');
  File get _tempFile => File('${bookDirectory.path}/notes.json.tmp');

  /// This loads all the notes saved for the book.
  /// Returns: The saved notes, or an empty list if nothing has been saved yet.
  /// Throws a [NotesFileCorruptedException] if the file cannot be read.
  Future<List<Note>> load() async {
    final file = _notesFile;
    if (!await file.exists()) return [];
    try {
      final json = jsonDecode(await file.readAsString());
      final notes = (json as Map<String, dynamic>)['notes'] as List;
      return [for (final note in notes) Note.fromJson(note)];
    } catch (error) {
      throw NotesFileCorruptedException(file.path, error);
    }
  }

  /// This saves the given notes and replaces the notes that were saved before.
  /// The notes are first written to a temp file, which is then renamed over the
  /// real file. If the app is closed in the middle of a save, only the temp
  /// file is half-written and the last saved notes are still safe.
  /// Parameters:
  /// - notes: Every note of the book, not just the ones that changed.
  Future<void> save(List<Note> notes) async {
    await bookDirectory.create(recursive: true);
    final contents = jsonEncode({
      'version': fileVersion,
      'notes': [for (final note in notes) note.toJson()],
    });
    final temp = _tempFile;
    await temp.writeAsString(contents, flush: true);
    await temp.rename(_notesFile.path);
  }
}
