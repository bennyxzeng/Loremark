import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/notes/note.dart';
import 'package:loremark/notes/theory.dart';

void main() {
  final created = DateTime.utc(2026, 11, 2, 12);

  SubTheory sub(
    String id, [
    SubTheoryVerdict verdict = SubTheoryVerdict.open,
  ]) => SubTheory(
    id: id,
    text: 'Part $id',
    verdict: verdict,
    evidence: verdict == SubTheoryVerdict.open
        ? null
        : const TheoryEvidence(
            sectionIndex: 9,
            chapterLabel: 'Chapter 10',
            quote: 'It was Mara.',
          ),
    resolvedAt: verdict == SubTheoryVerdict.open ? null : created,
  );

  Note theoryNote(
    String id, {
    List<SubTheory> subs = const [],
    String? dependsOn,
  }) => Note(
    id: id,
    bookId: 'glass-harbor',
    anchor: const NoteAnchor(3, 0.5),
    chapterLabel: 'Chapter 4',
    selectedText: 'The lights went out.',
    body: 'Mara cut the power.',
    color: HighlightColor.yellow,
    kind: NoteKind.theory,
    theory: TheoryState(subTheories: subs, dependsOnId: dependsOn),
    createdAt: created,
    updatedAt: created,
  );

  Map<String, Note> byId(List<Note> notes) => {
    for (final note in notes) note.id: note,
  };

  TheoryStatus statusOf(Note note, List<Note> all) =>
      theoryStatus(note, byId(all));

  group('TheoryStatus', () {
    test('has the reader-facing labels', () {
      expect(
        [for (final status in TheoryStatus.values) status.label],
        [
          'Unconfirmed',
          'Confirmed',
          'Partially correct',
          'Different outcome',
          'Invalidated',
        ],
      );
    });
  });

  group('JSON', () {
    test('evidence round-trips', () {
      const evidence = TheoryEvidence(
        sectionIndex: 4,
        chapterLabel: 'Chapter 5',
        quote: 'She burned the letter.',
      );
      expect(TheoryEvidence.fromJson(evidence.toJson()), evidence);
    });

    test('a resolved sub-theory round-trips', () {
      final resolved = sub('a', SubTheoryVerdict.refuted);
      expect(SubTheory.fromJson(resolved.toJson()), resolved);
    });

    test('an open sub-theory round-trips without evidence', () {
      final open = sub('a');
      final read = SubTheory.fromJson(open.toJson());
      expect(read, open);
      expect(read.evidence, isNull);
      expect(read.resolvedAt, isNull);
    });

    test('a theory state round-trips', () {
      final state = TheoryState(
        subTheories: [sub('a'), sub('b', SubTheoryVerdict.confirmed)],
        dependsOnId: 'older',
        checkedThroughSection: 6,
      );
      expect(TheoryState.fromJson(state.toJson()), state);
    });

    test('a note with theory data round-trips', () {
      final note = theoryNote('t1', subs: [sub('a')], dependsOn: 'older');
      expect(Note.fromJson(note.toJson()), note);
    });

    test('rejects bad evidence', () {
      expect(
        () => TheoryEvidence.fromJson({
          'sectionIndex': -1,
          'chapterLabel': 'x',
          'quote': 'y',
        }),
        throwsFormatException,
      );
      expect(
        () => TheoryEvidence.fromJson({'sectionIndex': 1, 'quote': 'y'}),
        throwsFormatException,
      );
    });

    test('rejects a sub-theory with an unknown verdict or missing text', () {
      expect(
        () => SubTheory.fromJson({'id': 'a', 'text': 't', 'verdict': 'maybe'}),
        throwsFormatException,
      );
      expect(
        () => SubTheory.fromJson({'id': 'a', 'verdict': 'open'}),
        throwsFormatException,
      );
    });

    test('rejects a theory state with bad fields', () {
      expect(
        () => TheoryState.fromJson({'checkedThroughSection': 0}),
        throwsFormatException,
      );
      expect(
        () => TheoryState.fromJson({
          'subTheories': <dynamic>[],
          'checkedThroughSection': -2,
        }),
        throwsFormatException,
      );
      expect(
        () => TheoryState.fromJson({
          'subTheories': [
            {'id': 'a'},
          ],
          'checkedThroughSection': -1,
        }),
        throwsFormatException,
      );
    });

    test('rejects a note whose theory data is invalid', () {
      final json = theoryNote('t1').toJson();
      json['theory'] = {'subTheories': 'nope', 'checkedThroughSection': -1};
      expect(() => Note.fromJson(json), throwsFormatException);
    });

    test('rejects a personal note that carries theory data', () {
      final json = theoryNote('t1').toJson()..['kind'] = 'personalNote';
      expect(() => Note.fromJson(json), throwsFormatException);
    });

    test('a note file from before theories still loads', () {
      // This is the exact shape older versions of the app saved.
      final note = Note.fromJson({
        'id': 'old-1',
        'bookId': 'glass-harbor',
        'anchor': {'sectionIndex': 1, 'progression': 0.1},
        'chapterLabel': 'Chapter 2',
        'selectedText': 'Old passage',
        'body': 'Old note',
        'color': 'blue',
        'kind': 'personalNote',
        'createdAt': '2026-10-29T12:00:00.000Z',
        'updatedAt': '2026-10-29T12:00:00.000Z',
      });
      expect(note.kind, NoteKind.personalNote);
      expect(note.theory, isNull);
    });

    test('an old-format theory without data starts unsplit', () {
      final json = theoryNote('t1').toJson()..remove('theory');
      final note = Note.fromJson(json);
      expect(note.theory, const TheoryState());
    });

    test('a personal note saves no theory key', () {
      final note = Note(
        id: 'p',
        bookId: 'b',
        anchor: const NoteAnchor(0, 0),
        chapterLabel: 'c',
        selectedText: 's',
        body: 'b',
        color: HighlightColor.pink,
        createdAt: created,
        updatedAt: created,
      );
      expect(note.toJson().containsKey('theory'), isFalse);
    });
  });

  group('Note.copyWith', () {
    test('becoming a personal note drops the theory data', () {
      final note = theoryNote('t1', subs: [sub('a')]);
      final copy = note.copyWith(kind: NoteKind.personalNote);
      expect(copy.kind, NoteKind.personalNote);
      expect(copy.theory, isNull);
    });

    test('becoming a theory starts with empty theory data', () {
      final personal = theoryNote('t1').copyWith(kind: NoteKind.personalNote);
      final copy = personal.copyWith(kind: NoteKind.theory);
      expect(copy.theory, const TheoryState());
    });
  });

  group('theoryStatus', () {
    test('no sub-theories yet is Unconfirmed', () {
      final note = theoryNote('t1');
      expect(statusOf(note, [note]), TheoryStatus.unconfirmed);
    });

    test('every sub-theory open is Unconfirmed', () {
      final note = theoryNote('t1', subs: [sub('a'), sub('b')]);
      expect(statusOf(note, [note]), TheoryStatus.unconfirmed);
    });

    test('every sub-theory confirmed is Confirmed', () {
      final note = theoryNote(
        't1',
        subs: [
          sub('a', SubTheoryVerdict.confirmed),
          sub('b', SubTheoryVerdict.confirmed),
        ],
      );
      expect(statusOf(note, [note]), TheoryStatus.confirmed);
    });

    test('every sub-theory refuted is Different outcome', () {
      final note = theoryNote(
        't1',
        subs: [
          sub('a', SubTheoryVerdict.refuted),
          sub('b', SubTheoryVerdict.refuted),
        ],
      );
      expect(statusOf(note, [note]), TheoryStatus.differentOutcome);
    });

    test('a mix of confirmed and refuted is Partially correct', () {
      final note = theoryNote(
        't1',
        subs: [
          sub('a', SubTheoryVerdict.confirmed),
          sub('b', SubTheoryVerdict.refuted),
        ],
      );
      expect(statusOf(note, [note]), TheoryStatus.partiallyCorrect);
    });

    test('some confirmed and some still open is Partially correct', () {
      final note = theoryNote(
        't1',
        subs: [sub('a', SubTheoryVerdict.confirmed), sub('b')],
      );
      expect(statusOf(note, [note]), TheoryStatus.partiallyCorrect);
    });

    test('some refuted and some still open is Partially correct', () {
      final note = theoryNote(
        't1',
        subs: [sub('a', SubTheoryVerdict.refuted), sub('b')],
      );
      expect(statusOf(note, [note]), TheoryStatus.partiallyCorrect);
    });

    test('building on a Different outcome theory is Invalidated', () {
      final parent = theoryNote(
        'parent',
        subs: [sub('a', SubTheoryVerdict.refuted)],
      );
      final child = theoryNote(
        'child',
        subs: [sub('b', SubTheoryVerdict.confirmed)],
        dependsOn: 'parent',
      );
      expect(statusOf(child, [parent, child]), TheoryStatus.invalidated);
    });

    test('invalidation is transitive down the chain', () {
      final root = theoryNote(
        'root',
        subs: [sub('a', SubTheoryVerdict.refuted)],
      );
      final middle = theoryNote('middle', subs: [sub('b')], dependsOn: 'root');
      final leaf = theoryNote(
        'leaf',
        subs: [sub('c', SubTheoryVerdict.confirmed)],
        dependsOn: 'middle',
      );
      final all = [root, middle, leaf];
      expect(statusOf(middle, all), TheoryStatus.invalidated);
      expect(statusOf(leaf, all), TheoryStatus.invalidated);
    });

    test(
      'building on a Confirmed or Partially correct theory is unaffected',
      () {
        final confirmed = theoryNote(
          'confirmed',
          subs: [sub('a', SubTheoryVerdict.confirmed)],
        );
        final partial = theoryNote(
          'partial',
          subs: [sub('b', SubTheoryVerdict.confirmed), sub('c')],
        );
        final onConfirmed = theoryNote(
          'c1',
          subs: [sub('d')],
          dependsOn: 'confirmed',
        );
        final onPartial = theoryNote(
          'c2',
          subs: [sub('e', SubTheoryVerdict.confirmed)],
          dependsOn: 'partial',
        );
        final all = [confirmed, partial, onConfirmed, onPartial];
        expect(statusOf(onConfirmed, all), TheoryStatus.unconfirmed);
        expect(statusOf(onPartial, all), TheoryStatus.confirmed);
      },
    );

    test('a dangling dependsOnId is ignored', () {
      final note = theoryNote(
        't1',
        subs: [sub('a', SubTheoryVerdict.confirmed)],
        dependsOn: 'gone',
      );
      expect(statusOf(note, [note]), TheoryStatus.confirmed);
    });

    test('a dependency on a personal note is ignored', () {
      final personal = theoryNote('p').copyWith(kind: NoteKind.personalNote);
      final note = theoryNote('t1', dependsOn: 'p');
      expect(statusOf(note, [personal, note]), TheoryStatus.unconfirmed);
    });

    test('a loop in the links does not hang', () {
      final a = theoryNote('a', subs: [sub('x')], dependsOn: 'b');
      final b = theoryNote('b', subs: [sub('y')], dependsOn: 'a');
      expect(statusOf(a, [a, b]), TheoryStatus.unconfirmed);
    });

    test('a personal note has no status', () {
      final personal = theoryNote('p').copyWith(kind: NoteKind.personalNote);
      expect(() => statusOf(personal, [personal]), throwsArgumentError);
    });
  });
}
