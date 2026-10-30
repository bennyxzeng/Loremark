import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/notes/note.dart';
import 'package:loremark/notes/note_repository.dart';

void main() {
  late Directory bookDirectory;
  late NoteRepository repository;

  final created = DateTime.utc(2026, 10, 29);

  Note note(String id, {String body = 'A thought'}) => Note(
    id: id,
    bookId: 'glass-harbor',
    anchor: const NoteAnchor(7, 0.25),
    chapterLabel: 'Chapter 8',
    selectedText: 'You’re my sister, Mara.',
    body: body,
    color: HighlightColor.green,
    createdAt: created,
    updatedAt: created,
  );

  setUp(() {
    bookDirectory = Directory.systemTemp.createTempSync('loremark_notes_');
    repository = NoteRepository(bookDirectory);
  });

  tearDown(() => bookDirectory.deleteSync(recursive: true));

  test('loads no notes when the notes file does not exist yet', () async {
    expect(await repository.load(), isEmpty);
  });

  test('loads the same notes that were saved', () async {
    await repository.save([note('a'), note('b', body: '')]);

    expect(await repository.load(), [note('a'), note('b', body: '')]);
  });

  test('saving replaces the notes that were saved before', () async {
    await repository.save([note('a'), note('b')]);
    await repository.save([note('b')]);

    expect(await repository.load(), [note('b')]);
  });

  test('creates the book directory if it is missing', () async {
    final nested = NoteRepository(
      Directory('${bookDirectory.path}/books/new-book'),
    );

    await nested.save([note('a')]);

    expect(await nested.load(), [note('a')]);
  });

  test('throws instead of returning nothing when the file is corrupted', () {
    File('${bookDirectory.path}/notes.json').writeAsStringSync('{not json');

    expect(repository.load(), throwsA(isA<NotesFileCorruptedException>()));
  });

  test('throws when a note in the file is invalid', () {
    File('${bookDirectory.path}/notes.json')
        .writeAsStringSync('{"version": 1, "notes": [{"id": "a"}]}');

    expect(repository.load(), throwsA(isA<NotesFileCorruptedException>()));
  });

  test('keeps the last saved notes when a save was interrupted', () async {
    await repository.save([note('a')]);
    // A crash in the middle of a save leaves only a half-written temp file.
    File('${bookDirectory.path}/notes.json.tmp').writeAsStringSync('{"vers');

    expect(await repository.load(), [note('a')]);
  });

  test('does not leave a temp file behind after a save', () async {
    await repository.save([note('a')]);

    expect(File('${bookDirectory.path}/notes.json.tmp').existsSync(), isFalse);
  });
}
