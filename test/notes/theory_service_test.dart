import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/notes/annotation_service.dart';
import 'package:loremark/notes/note.dart';
import 'package:loremark/notes/note_repository.dart';
import 'package:loremark/notes/theory.dart';

void main() {
  late Directory bookDirectory;
  late NoteRepository repository;
  late AnnotationService service;

  AnnotationService newService() => AnnotationService(
    bookId: 'glass-harbor',
    repository: repository,
    // A fixed clock on purpose: notes made together share one creation time.
    clock: () => DateTime.utc(2026, 11, 2, 9),
  );

  Future<Note> addTheory(
    String body, {
    String? dependsOnId,
    NoteAnchor anchor = const NoteAnchor(3, 0.5),
  }) => service.addNote(
    anchor: anchor,
    chapterLabel: 'Chapter 4',
    selectedText: 'The lights went out.',
    body: body,
    kind: NoteKind.theory,
    dependsOnId: dependsOnId,
  );

  Future<Note> addPersonal(String body) => service.addNote(
    anchor: const NoteAnchor(3, 0.5),
    chapterLabel: 'Chapter 4',
    selectedText: 'The lights went out.',
    body: body,
  );

  SubTheory resolved(String id, SubTheoryVerdict verdict) => SubTheory(
    id: id,
    text: 'Part $id',
    verdict: verdict,
    evidence: const TheoryEvidence(
      sectionIndex: 6,
      chapterLabel: 'Chapter 7',
      quote: 'It was Mara.',
    ),
    resolvedAt: DateTime.utc(2026, 11, 3),
  );

  setUp(() async {
    bookDirectory = Directory.systemTemp.createTempSync('loremark_theory_');
    repository = NoteRepository(bookDirectory);
    service = newService();
    await service.load();
  });

  tearDown(() => bookDirectory.deleteSync(recursive: true));

  group('adding a theory', () {
    test('starts unsplit, unchecked and Unconfirmed', () async {
      final theory = await addTheory('  Mara cut the power.  ');

      expect(theory.kind, NoteKind.theory);
      expect(theory.body, 'Mara cut the power.');
      expect(theory.theory, const TheoryState());
      expect(theory.theory!.checkedThroughSection, -1);
      expect(service.statusOf(theory.id), TheoryStatus.unconfirmed);
    });

    test('a personal note carries no theory data', () async {
      final note = await addPersonal('Just a thought');
      expect(note.theory, isNull);
    });

    test(
      'is saved with its theory data and read back after reopening',
      () async {
        final older = await addTheory('Mara cut the power.');
        final newer = await addTheory(
          'Elian helped her.',
          dependsOnId: older.id,
        );
        await service.updateTheory(
          older.id,
          (state) => state.copyWith(
            subTheories: [resolved('a', SubTheoryVerdict.confirmed)],
            checkedThroughSection: 6,
          ),
        );

        final reopened = newService();
        await reopened.load();

        expect(reopened.notes, service.notes);
        final read = reopened.notes.firstWhere((note) => note.id == newer.id);
        expect(read.theory!.dependsOnId, older.id);
        expect(
          reopened.notes.firstWhere((note) => note.id == older.id).theory,
          service.notes.firstWhere((note) => note.id == older.id).theory,
        );
      },
    );

    test('can build on an older theory of the book', () async {
      final older = await addTheory('Mara cut the power.');
      final newer = await addTheory('Elian helped her.', dependsOnId: older.id);
      expect(newer.theory!.dependsOnId, older.id);
    });

    test('cannot build on a theory that does not exist', () async {
      await expectLater(
        addTheory('Elian helped her.', dependsOnId: 'missing'),
        throwsArgumentError,
      );
      expect(service.notes, isEmpty);
    });

    test('cannot build on a personal note', () async {
      final personal = await addPersonal('Just a thought');
      await expectLater(
        addTheory('Elian helped her.', dependsOnId: personal.id),
        throwsArgumentError,
      );
    });

    test('a personal note cannot pass dependsOnId', () async {
      final older = await addTheory('Mara cut the power.');
      await expectLater(
        service.addNote(
          anchor: const NoteAnchor(3, 0.5),
          chapterLabel: 'Chapter 4',
          selectedText: 'x',
          body: 'y',
          dependsOnId: older.id,
        ),
        throwsArgumentError,
      );
    });

    test('an empty theory is refused like an empty note', () async {
      await expectLater(addTheory('  '), throwsA(isA<EmptyNoteException>()));
    });

    test('theories lists only theories in reading order', () async {
      final later = await addTheory('Later', anchor: const NoteAnchor(9, 0.1));
      await addPersonal('Not a theory');
      final earlier = await addTheory(
        'Earlier',
        anchor: const NoteAnchor(2, 0.1),
      );

      expect(service.theories.map((note) => note.id), [earlier.id, later.id]);
    });
  });

  group('editing a theory', () {
    test('changing its text starts it over but keeps the link', () async {
      final older = await addTheory('Mara cut the power.');
      final theory = await addTheory(
        'Elian helped her.',
        dependsOnId: older.id,
      );
      await service.updateTheory(
        theory.id,
        (state) => state.copyWith(
          subTheories: [resolved('a', SubTheoryVerdict.confirmed)],
          checkedThroughSection: 6,
        ),
      );

      final edited = await service.editNote(theory.id, body: 'Elian hid her.');

      expect(edited.theory!.subTheories, isEmpty);
      expect(edited.theory!.checkedThroughSection, -1);
      expect(edited.theory!.dependsOnId, older.id);
    });

    test('changing only the color keeps the check progress', () async {
      final theory = await addTheory('Mara cut the power.');
      await service.updateTheory(
        theory.id,
        (state) => state.copyWith(
          subTheories: [resolved('a', SubTheoryVerdict.confirmed)],
          checkedThroughSection: 6,
        ),
      );

      final edited = await service.editNote(
        theory.id,
        color: HighlightColor.blue,
      );

      expect(edited.theory!.subTheories, hasLength(1));
      expect(edited.theory!.checkedThroughSection, 6);
    });

    test('saving the same text keeps the check progress', () async {
      final theory = await addTheory('Mara cut the power.');
      await service.updateTheory(
        theory.id,
        (state) => state.copyWith(checkedThroughSection: 6),
      );

      final edited = await service.editNote(
        theory.id,
        body: ' Mara cut the power. ',
      );

      expect(edited.theory!.checkedThroughSection, 6);
    });

    test('a personal note can become a theory', () async {
      final note = await addPersonal('Mara cut the power.');

      final edited = await service.editNote(note.id, kind: NoteKind.theory);

      expect(edited.kind, NoteKind.theory);
      expect(edited.theory, const TheoryState());
      expect(service.statusOf(note.id), TheoryStatus.unconfirmed);
    });

    test('a theory can become a personal note and drops its data', () async {
      final theory = await addTheory('Mara cut the power.');
      await service.updateTheory(
        theory.id,
        (state) => state.copyWith(checkedThroughSection: 6),
      );

      final edited = await service.editNote(
        theory.id,
        kind: NoteKind.personalNote,
      );

      expect(edited.kind, NoteKind.personalNote);
      expect(edited.theory, isNull);
      expect(service.theories, isEmpty);
    });

    test(
      'a personal note can become a theory that builds on an older one',
      () async {
        final older = await addTheory('Mara cut the power.');
        final note = await addPersonal('Elian helped her.');

        final edited = await service.editNote(
          note.id,
          kind: NoteKind.theory,
          dependsOnId: older.id,
        );

        expect(edited.theory!.dependsOnId, older.id);
      },
    );

    test('the dependency can be changed and cleared', () async {
      final first = await addTheory('One');
      final second = await addTheory('Two');
      final third = await addTheory('Three', dependsOnId: first.id);

      final moved = await service.editNote(third.id, dependsOnId: second.id);
      expect(moved.theory!.dependsOnId, second.id);

      final cleared = await service.editNote(third.id, clearDependsOn: true);
      expect(cleared.theory!.dependsOnId, isNull);
    });

    test('an older theory cannot be pointed at a newer one', () async {
      final older = await addTheory('One');
      final newer = await addTheory('Two');

      await expectLater(
        service.editNote(older.id, dependsOnId: newer.id),
        throwsArgumentError,
      );
      expect(
        service.notes
            .firstWhere((note) => note.id == older.id)
            .theory!
            .dependsOnId,
        isNull,
      );
    });

    test('a theory cannot build on itself', () async {
      final theory = await addTheory('One');
      await expectLater(
        service.editNote(theory.id, dependsOnId: theory.id),
        throwsArgumentError,
      );
    });

    test(
      'a note that stays or becomes personal cannot pass dependsOnId',
      () async {
        final older = await addTheory('One');
        final personal = await addPersonal('Two');
        await expectLater(
          service.editNote(personal.id, dependsOnId: older.id),
          throwsArgumentError,
        );
        await expectLater(
          service.editNote(
            older.id,
            kind: NoteKind.personalNote,
            dependsOnId: older.id,
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('deleting a theory', () {
    test('clears the link on theories that built on it, in one save', () async {
      final older = await addTheory('One');
      final child = await addTheory('Two', dependsOnId: older.id);
      final other = await addTheory('Three');

      var notifications = 0;
      service.addListener(() => notifications++);
      await service.deleteNote(older.id);

      expect(notifications, 1);
      final notes = {for (final note in service.notes) note.id: note};
      expect(notes.containsKey(older.id), isFalse);
      expect(notes[child.id]!.theory!.dependsOnId, isNull);
      expect(notes[other.id]!.theory!.dependsOnId, isNull);

      final reopened = newService();
      await reopened.load();
      expect(
        reopened.notes
            .firstWhere((note) => note.id == child.id)
            .theory!
            .dependsOnId,
        isNull,
      );
    });

    test('keeps the progress of the theory that built on it', () async {
      final older = await addTheory('One');
      final child = await addTheory('Two', dependsOnId: older.id);
      await service.updateTheory(
        child.id,
        (state) => state.copyWith(
          subTheories: [resolved('a', SubTheoryVerdict.confirmed)],
          checkedThroughSection: 6,
        ),
      );

      await service.deleteNote(older.id);

      expect(service.statusOf(child.id), TheoryStatus.confirmed);
    });

    test('deleting a missing note throws', () async {
      await expectLater(
        service.deleteNote('missing'),
        throwsA(isA<NoteNotFoundException>()),
      );
    });
  });

  group('statusOf', () {
    test('follows the verdicts and dependencies', () async {
      final older = await addTheory('One');
      final child = await addTheory('Two', dependsOnId: older.id);
      await service.updateTheory(
        child.id,
        (state) => state.copyWith(
          subTheories: [resolved('a', SubTheoryVerdict.confirmed)],
        ),
      );
      expect(service.statusOf(child.id), TheoryStatus.confirmed);

      await service.updateTheory(
        older.id,
        (state) => state.copyWith(
          subTheories: [resolved('b', SubTheoryVerdict.refuted)],
        ),
      );

      expect(service.statusOf(older.id), TheoryStatus.differentOutcome);
      expect(service.statusOf(child.id), TheoryStatus.invalidated);
    });

    test('rejects a missing note and a personal note', () async {
      final personal = await addPersonal('Just a thought');
      expect(
        () => service.statusOf('missing'),
        throwsA(isA<NoteNotFoundException>()),
      );
      expect(() => service.statusOf(personal.id), throwsArgumentError);
    });
  });

  group('updateTheory', () {
    test(
      'saves the new state, notifies, and leaves the text and edit time',
      () async {
        final theory = await addTheory('Mara cut the power.');
        var notifications = 0;
        service.addListener(() => notifications++);

        final updated = await service.updateTheory(
          theory.id,
          (state) => state.copyWith(
            subTheories: [resolved('a', SubTheoryVerdict.confirmed)],
            checkedThroughSection: 6,
          ),
        );

        expect(notifications, 1);
        expect(updated.body, theory.body);
        expect(updated.updatedAt, theory.updatedAt);
        expect(updated.theory!.checkedThroughSection, 6);
        expect(service.notes.single, updated);
        expect(await repository.load(), [updated]);
      },
    );

    test('gives the change the current state', () async {
      final theory = await addTheory('Mara cut the power.');
      await service.updateTheory(
        theory.id,
        (state) => state.copyWith(checkedThroughSection: 2),
      );

      late TheoryState seen;
      await service.updateTheory(theory.id, (state) {
        seen = state;
        return state;
      });

      expect(seen.checkedThroughSection, 2);
    });

    test('throws for a personal note and a missing note', () async {
      final personal = await addPersonal('Just a thought');
      await expectLater(
        service.updateTheory(personal.id, (state) => state),
        throwsArgumentError,
      );
      await expectLater(
        service.updateTheory('missing', (state) => state),
        throwsA(isA<NoteNotFoundException>()),
      );
    });

    test('does not change the notes in memory when the save fails', () async {
      final theory = await addTheory('Mara cut the power.');
      final failing = _FailingRepository(bookDirectory);
      final other = AnnotationService(
        bookId: 'glass-harbor',
        repository: failing,
      );
      await other.load();
      failing.failSaves = true;

      await expectLater(
        other.updateTheory(
          theory.id,
          (state) => state.copyWith(checkedThroughSection: 4),
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(other.notes.single.theory!.checkedThroughSection, -1);
    });
  });

  group('old notes files', () {
    test('a file saved before theories were tracked still loads', () async {
      File('${bookDirectory.path}/notes.json').writeAsStringSync('''
{
  "version": 1,
  "notes": [
    {
      "id": "old-1",
      "bookId": "glass-harbor",
      "anchor": {"sectionIndex": 1, "progression": 0.1},
      "chapterLabel": "Chapter 2",
      "selectedText": "Old passage",
      "body": "Old note",
      "color": "blue",
      "kind": "personalNote",
      "createdAt": "2026-10-29T12:00:00.000Z",
      "updatedAt": "2026-10-29T12:00:00.000Z"
    }
  ]
}
''');
      final reopened = newService();
      await reopened.load();

      expect(reopened.loadError, isNull);
      expect(reopened.notes.single.body, 'Old note');
      expect(reopened.notes.single.theory, isNull);
      expect(NoteRepository.fileVersion, 1);
    });
  });
}

/// A repository whose saves can be made to fail.
class _FailingRepository extends NoteRepository {
  _FailingRepository(super.bookDirectory);

  bool failSaves = false;

  @override
  Future<void> save(List<Note> notes) async {
    if (failSaves) throw const FileSystemException('disk full');
    return super.save(notes);
  }
}
