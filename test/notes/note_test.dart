import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/notes/note.dart';

void main() {
  final created = DateTime.utc(2026, 10, 29, 12);

  Note sampleNote({String body = 'Elian knew all along.'}) => Note(
    id: 'note-1',
    bookId: 'glass-harbor',
    anchor: const NoteAnchor(7, 0.25),
    chapterLabel: 'Chapter 8',
    selectedText: 'You’re my sister, Mara.',
    body: body,
    color: HighlightColor.yellow,
    createdAt: created,
    updatedAt: created,
  );

  group('NoteAnchor', () {
    test('orders by section first, then by progression', () {
      expect(const NoteAnchor(1, 0.9) < const NoteAnchor(2, 0.1), isTrue);
      expect(const NoteAnchor(2, 0.1) < const NoteAnchor(2, 0.5), isTrue);
      expect(const NoteAnchor(2, 0.5) < const NoteAnchor(2, 0.5), isFalse);
    });

    test('uses the same JSON keys as TextPosition', () {
      expect(const NoteAnchor(3, 0.5).toJson(), {
        'sectionIndex': 3,
        'progression': 0.5,
      });
    });

    test('rejects a progression outside 0 to 1', () {
      expect(
        () => NoteAnchor.fromJson({'sectionIndex': 0, 'progression': 1.5}),
        throwsFormatException,
      );
    });
  });

  group('Note', () {
    test('survives a JSON round trip', () {
      final restored = Note.fromJson(sampleNote().toJson());

      expect(restored, sampleNote());
    });

    test('defaults to a personal note', () {
      expect(sampleNote().kind, NoteKind.personalNote);
    });

    test('is a highlight only when the body is blank', () {
      expect(sampleNote(body: '   ').isHighlightOnly, isTrue);
      expect(sampleNote().isHighlightOnly, isFalse);
    });

    test('rejects JSON with a missing field', () {
      final json = sampleNote().toJson()..remove('selectedText');

      expect(() => Note.fromJson(json), throwsFormatException);
    });

    test('rejects JSON with an unknown color', () {
      final json = sampleNote().toJson()..['color'] = 'plaid';

      expect(() => Note.fromJson(json), throwsFormatException);
    });

    test('copyWith changes only the given fields', () {
      final later = created.add(const Duration(hours: 1));
      final edited = sampleNote().copyWith(body: 'New text', updatedAt: later);

      expect(edited.body, 'New text');
      expect(edited.updatedAt, later);
      expect(edited.id, 'note-1');
      expect(edited.createdAt, created);
    });
  });
}
