import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/library/book_repository.dart';

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

    await repository.remove(book);

    expect(repository.books, isEmpty);
    expect(repository.lastOpened, isNull);
    expect(await File(book.epubPath).exists(), isFalse);
    expect(await File(book.coverPath!).exists(), isFalse);
  });

  test('rejects a file that is not an EPUB', () async {
    final source = await writeFile('notes.epub', 'plain text'.codeUnits);

    await expectLater(repository.importEpub(source), throwsFormatException);
    expect(repository.books, isEmpty);
  });
}
