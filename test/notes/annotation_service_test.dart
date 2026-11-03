import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/notes/annotation_service.dart';
import 'package:loremark/notes/note.dart';
import 'package:loremark/notes/note_repository.dart';

void main() {
  late Directory bookDirectory;
  late NoteRepository repository;
  late DateTime now;
  late AnnotationService service;

  AnnotationService newService() => AnnotationService(
    bookId: 'glass-harbor',
    repository: repository,
    clock: () => now,
  );

  Future<Note> addNote(
    String body, {
    NoteAnchor anchor = const NoteAnchor(7, 0.25),
    String chapter = 'Chapter 8',
    HighlightColor color = HighlightColor.yellow,
    String selectedText = 'You’re my sister, Mara.',
  }) => service.addNote(
    anchor: anchor,
    chapterLabel: chapter,
    selectedText: selectedText,
    body: body,
    color: color,
  );

  setUp(() async {
    bookDirectory = Directory.systemTemp.createTempSync('loremark_service_');
    repository = NoteRepository(bookDirectory);
    now = DateTime.utc(2026, 10, 29, 9);
    service = newService();
    await service.load();
  });

  tearDown(() => bookDirectory.deleteSync(recursive: true));

  group('adding', () {
    test('saves a note so it is still there after reopening the app', () async {
      final note = await addNote('Elian knew all along.');

      final reopened = newService();
      await reopened.load();

      expect(reopened.notes, [note]);
    });

    test('rejects a note with an empty body', () async {
      await expectLater(addNote(''), throwsA(isA<EmptyNoteException>()));
      await expectLater(addNote('   \n'), throwsA(isA<EmptyNoteException>()));
      expect(service.notes, isEmpty);
    });

    test('a highlight is saved without any text', () async {
      final highlight = await service.addHighlight(
        anchor: const NoteAnchor(2, 0.5),
        chapterLabel: 'Chapter 3',
        selectedText: 'The harbor lights went out.',
        color: HighlightColor.pink,
      );

      expect(highlight.isHighlightOnly, isTrue);
      expect(service.notes, [highlight]);
    });

    test('trims the body and gives every note its own id', () async {
      final first = await addNote('  First  ');
      final second = await addNote('Second');

      expect(first.body, 'First');
      expect(first.id, isNot(second.id));
      expect(first.kind, NoteKind.personalNote);
    });

    test(
      'lists notes in reading order, not in the order they were added',
      () async {
        final later = await addNote('later', anchor: const NoteAnchor(9, 0.1));
        final earlier = await addNote(
          'earlier',
          anchor: const NoteAnchor(1, 0.9),
        );

        expect(service.notes, [earlier, later]);
      },
    );
  });

  group('editing and deleting', () {
    test('editing changes the body and the edited time', () async {
      final note = await addNote('Old');
      now = now.add(const Duration(minutes: 5));

      final edited = await service.editNote(note.id, body: 'New');

      expect(edited.body, 'New');
      expect(edited.updatedAt, now);
      expect(edited.createdAt, note.createdAt);
      expect(service.notes, [edited]);
    });

    test('editing a note to be empty is rejected', () async {
      final note = await addNote('Old');

      await expectLater(
        service.editNote(note.id, body: ' '),
        throwsA(isA<EmptyNoteException>()),
      );
      expect(service.notes, [note]);
    });

    test('editing only the color keeps the body', () async {
      final note = await addNote('Keep me');

      final edited = await service.editNote(
        note.id,
        color: HighlightColor.blue,
      );

      expect(edited.body, 'Keep me');
      expect(edited.color, HighlightColor.blue);
    });

    test('deleting removes the note from the saved file too', () async {
      final note = await addNote('Delete me');
      final kept = await addNote('Keep me');

      await service.deleteNote(note.id);

      final reopened = newService();
      await reopened.load();
      expect(reopened.notes, [kept]);
    });

    test('editing a note that does not exist throws', () {
      expect(
        service.editNote('missing', body: 'x'),
        throwsA(isA<NoteNotFoundException>()),
      );
    });
  });

  group('grouping and filtering', () {
    setUp(() async {
      await addNote(
        'Mara hides the letter',
        anchor: const NoteAnchor(7, 0.2),
        chapter: 'Chapter 8',
        color: HighlightColor.yellow,
      );
      await addNote(
        'The lighthouse keeper lies',
        anchor: const NoteAnchor(2, 0.4),
        chapter: 'Chapter 3',
        color: HighlightColor.blue,
        selectedText: 'He said the light was never lit.',
      );
      await addNote(
        'Elian is nervous',
        anchor: const NoteAnchor(7, 0.6),
        chapter: 'Chapter 8',
        color: HighlightColor.blue,
      );
    });

    test('groups notes by chapter in reading order', () {
      final groups = service.notesByChapter();

      expect(groups.map((group) => group.chapterLabel), [
        'Chapter 3',
        'Chapter 8',
      ]);
      expect(groups.last.notes.map((note) => note.body), [
        'Mara hides the letter',
        'Elian is nervous',
      ]);
    });

    test('filters by chapter', () {
      final groups = service.notesByChapter(
        const NoteFilter(chapterLabel: 'Chapter 3'),
      );

      expect(groups.single.chapterLabel, 'Chapter 3');
    });

    test('filters by color', () {
      final groups = service.notesByChapter(
        const NoteFilter(color: HighlightColor.blue),
      );

      expect(groups.expand((group) => group.notes).map((note) => note.body), [
        'The lighthouse keeper lies',
        'Elian is nervous',
      ]);
    });

    test('searches the note text and the selected passage, ignoring case', () {
      final byBody = service.notesByChapter(const NoteFilter(query: 'ELIAN'));
      final byPassage = service.notesByChapter(
        const NoteFilter(query: 'never lit'),
      );

      expect(byBody.single.notes.single.body, 'Elian is nervous');
      expect(byPassage.single.notes.single.body, 'The lighthouse keeper lies');
    });

    test('lists every chapter that has notes, in reading order', () {
      expect(service.chapterLabels, ['Chapter 3', 'Chapter 8']);
    });
  });

  group('a corrupted notes file', () {
    setUp(() {
      File('${bookDirectory.path}/notes.json').writeAsStringSync('{broken');
      service = newService();
    });

    test('is reported instead of showing an empty list', () async {
      await service.load();

      expect(service.loadError, isA<NotesFileCorruptedException>());
    });

    test('is never overwritten by a new note', () async {
      await service.load();

      await expectLater(addNote('New'), throwsA(isA<StateError>()));
      expect(
        File('${bookDirectory.path}/notes.json').readAsStringSync(),
        '{broken',
      );
    });
  });
}
