import 'dart:io';

import 'package:loremark/notes/note.dart';
import 'package:loremark/notes/note_repository.dart';

/// A [NoteRepository] that keeps notes in memory for widget tests, where real
/// file reads and writes never complete inside the fake async zone.
class InMemoryNoteRepository extends NoteRepository {
  InMemoryNoteRepository() : super(Directory('unused'));

  List<Note> saved = [];

  @override
  Future<List<Note>> load() async => [...saved];

  @override
  Future<void> save(List<Note> notes) async => saved = [...notes];
}
