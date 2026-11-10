import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/ask/ask_history.dart';
import 'package:loremark/library/book_repository.dart';
import 'package:loremark/story_update/story_import.dart';
import 'package:loremark/story_update/story_updater.dart';

import 'test_epub.dart';

void main() {
  late Directory temp;
  late BookRepository repository;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('loremark_library_');
    repository = BookRepository(Directory('${temp.path}/library'));
  });

  tearDown(() => temp.delete(recursive: true));

  Future<String> writeFile(String name, List<int> bytes) async {
    final file = File('${temp.path}/$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  test('imports a copy of the EPUB and its cover', () async {
    final source = await writeFile('harbor.epub', buildEpub());

    final (:book, :isNew) = await repository.importEpub(source);
    await File(source).delete();

    expect(isNew, isTrue);
    expect(book.title, 'The Glass Harbor');
    expect(book.id, hasLength(64));
    expect(await File(book.epubPath).exists(), isTrue);
    expect(await File(book.coverPath!).readAsBytes(), coverBytes);
    expect(repository.books, [book]);
  });

  test('keeps the library across restarts', () async {
    final source = await writeFile('harbor.epub', buildEpub());
    final (:book, isNew: _) = await repository.importEpub(source);
    await repository.markOpened(book);

    final reopened = BookRepository(repository.root);
    await reopened.load();

    expect(reopened.books.single.title, 'The Glass Harbor');
    expect(reopened.lastOpened?.id, book.id);
  });

  test('finds its files after the app’s folder moves', () async {
    final source = await writeFile('harbor.epub', buildEpub());
    final (:book, isNew: _) = await repository.importEpub(source);
    await repository.saved;

    // As iOS does when the app is reinstalled or updated.
    final moved = Directory('${temp.path}/moved/library');
    await moved.parent.create();
    await repository.root.rename(moved.path);
    final reopened = BookRepository(moved);
    await reopened.load();

    final found = reopened.books.single;
    expect(found.epubPath, isNot(book.epubPath));
    expect(await File(found.epubPath).exists(), isTrue);
    expect(await File(found.coverPath!).readAsBytes(), coverBytes);
  });

  test('imports the same file only once', () async {
    final first = await writeFile('a.epub', buildEpub());
    final copy = await writeFile('b.epub', buildEpub());

    await repository.importEpub(first);
    final (:book, :isNew) = await repository.importEpub(copy);

    expect(isNew, isFalse);
    expect(repository.books, [book]);
  });

  test('lists the newest import first', () async {
    await repository.importEpub(
      await writeFile('a.epub', buildEpub(title: 'First')),
    );
    await repository.importEpub(
      await writeFile('b.epub', buildEpub(title: 'Second')),
    );

    expect(
      [for (final book in repository.books) book.title],
      ['Second', 'First'],
    );
  });

  test('removes a book and its files', () async {
    final source = await writeFile('harbor.epub', buildEpub());
    final (:book, isNew: _) = await repository.importEpub(source);
    await repository.markOpened(book);
    final storyModel = File(
      '${storyStorePath(repository.root.path, book.id)}/story_model.json',
    );
    await storyModel.create(recursive: true);
    final sideFolders = [
      for (final path in storySidePaths(storyModel.parent.path))
        Directory(path),
    ];
    expect(sideFolders, isNotEmpty);
    for (final folder in sideFolders) {
      await File('${folder.path}/kept.json').create(recursive: true);
    }
    final chats = AskHistoryStore(repository.root);
    final chat = chats.file(book.id, 'c1');
    await chat.create(recursive: true);
    // The one conversation a book had before there could be several.
    final single = File('${chats.folder(book.id).path}.json');
    await single.create();

    await repository.remove(book);

    expect(repository.books, isEmpty);
    expect(repository.lastOpened, isNull);
    expect(await File(book.epubPath).exists(), isFalse);
    expect(await File(book.coverPath!).exists(), isFalse);
    expect(await storyModel.parent.exists(), isFalse);
    for (final folder in sideFolders) {
      expect(await folder.exists(), isFalse, reason: folder.path);
    }
    expect(await chat.parent.exists(), isFalse);
    expect(await single.exists(), isFalse);
  });

  test('rejects a file that is not an EPUB', () async {
    final source = await writeFile('notes.epub', 'plain text'.codeUnits);

    await expectLater(repository.importEpub(source), throwsFormatException);
    expect(repository.books, isEmpty);
  });
}
