import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/search/search_index.dart';
import 'package:loremark/search/search_index_store.dart';

import '../library/test_epub.dart';
import 'search_fixtures.dart';

Uint8List storyEpub() => buildEpub(
  chapters: [
    for (var i = 0; i < storySections.length; i++)
      EpubChapter(
        id: 'ch$i',
        fileName: 'ch$i.xhtml',
        linear: storyLinear[i],
        body: [
          for (final paragraph in storySections[i].split('\n\n'))
            '<p>${paragraph.replaceAll('&', '&amp;')}</p>',
        ].join(),
      ),
  ],
);

void main() {
  late Directory root;
  late File epub;
  late SearchIndexStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('loremark_search_');
    epub = File('${root.path}/book.epub')..writeAsBytesSync(storyEpub());
    store = SearchIndexStore(Directory('${root.path}/library'));
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<SearchIndex> open({String id = 'book1', String? path}) =>
      store.load(bookId: id, epubPath: path ?? epub.path);

  test('builds the index from the EPUB and saves it', () async {
    final index = await open();
    expect(index.bookId, 'book1');
    expect(index.paragraphCount, 7);
    final saved = store.file('book1');
    expect(saved.path, endsWith('library/search_index/book1.bin'));
    expect(saved.existsSync(), isTrue);
    final hit = index
        .search('lamp', cutoff: const ReaderPosition(3, 0))
        .hits
        .single;
    expect(hit.passage.sectionIndex, 0);
  });

  test('leaves no temporary file behind', () async {
    await open();
    final names = store
        .file('book1')
        .parent
        .listSync()
        .map((e) => e.uri.pathSegments.last);
    expect(names, ['book1.bin']);
  });

  test('skips non-linear sections like footnotes', () async {
    final index = await open();
    expect(
      index.search('founded', cutoff: const ReaderPosition(5, 0)).hits,
      isEmpty,
    );
    // Section 1 is a footnote page; the second chapter is spine index 2.
    final dalia = index.search('dalia', cutoff: const ReaderPosition(5, 0));
    expect(dalia.hits.first.passage.sectionIndex, 2);
  });

  test('loads the saved index without opening the EPUB again', () async {
    final built = await open();
    epub.deleteSync();
    final loaded = await open();
    expect(loaded.paragraphCount, built.paragraphCount);
    expect(
      loaded.search('harbor', cutoff: const ReaderPosition(3, 0)).hits.length,
      built.search('harbor', cutoff: const ReaderPosition(3, 0)).hits.length,
    );
  });

  test('a damaged file is replaced by a fresh index', () async {
    await open();
    final file = store.file('book1');
    final good = file.readAsBytesSync();
    file.writeAsBytesSync(good.sublist(0, good.length ~/ 3));
    final index = await open();
    expect(index.paragraphCount, 7);
    expect(file.readAsBytesSync(), good);
  });

  test('garbage in the file is replaced too', () async {
    final file = store.file('book1')..createSync(recursive: true);
    file.writeAsStringSync('not an index');
    final index = await open();
    expect(index.paragraphCount, 7);
    expect(file.lengthSync(), greaterThan(100));
  });

  test("another book's index at the path is rebuilt, never used", () async {
    await open(id: 'book1');
    final other = File('${root.path}/other.epub')
      ..writeAsBytesSync(
        buildEpub(
          chapters: [
            const EpubChapter(
              id: 'ch1',
              fileName: 'ch1.xhtml',
              body: '<p>Entirely different words about a cathedral.</p>',
            ),
          ],
        ),
      );
    // Put book1's index where book2's belongs.
    store.file('book2').parent.createSync(recursive: true);
    store.file('book1').copySync(store.file('book2').path);
    final index = await open(id: 'book2', path: other.path);
    expect(index.bookId, 'book2');
    expect(index.paragraphCount, 1);
    expect(
      index.search('cathedral', cutoff: const ReaderPosition(1, 0)).hits,
      hasLength(1),
    );
    expect(
      index.search('harbor', cutoff: const ReaderPosition(1, 0)).hits,
      isEmpty,
    );
  });

  test('an index from another format version is rebuilt', () async {
    await open();
    final file = store.file('book1');
    // Version 0 in the first byte after the magic, inside the gzip stream.
    final plain = gzip.decode(file.readAsBytesSync());
    plain[4] = 99;
    file.writeAsBytesSync(gzip.encode(plain));
    final index = await open();
    expect(index.paragraphCount, 7);
    expect(gzip.decode(file.readAsBytesSync())[4], isNot(99));
  });

  test('concurrent requests for a book share one load', () async {
    final first = open();
    final second = open();
    expect(identical(first, second), isTrue);
    expect((await first).paragraphCount, 7);
  });

  test('a book id can not reach outside the folder', () {
    expect(() => store.file('../escape'), throwsArgumentError);
    expect(() => store.file('a/b'), throwsArgumentError);
    expect(() => store.file(''), throwsArgumentError);
  });

  test('a missing EPUB with no saved index is an error', () async {
    await expectLater(
      open(path: '${root.path}/missing.epub'),
      throwsA(isA<FileSystemException>()),
    );
    // A later call can still succeed.
    expect((await open()).paragraphCount, 7);
  });

  test('a file that is not an EPUB is an error', () async {
    final bad = File('${root.path}/bad.epub')..writeAsStringSync('nope');
    await expectLater(
      open(id: 'bad', path: bad.path),
      throwsA(isA<FormatException>()),
    );
  });

  test('search still works when the index can not be saved', () async {
    // A file where the folder should be.
    final blocked = File('${root.path}/blocked')..writeAsStringSync('x');
    final index = await SearchIndexStore(Directory(blocked.path))
        .load(bookId: 'book1', epubPath: epub.path);
    expect(index.paragraphCount, 7);
  });

  test('openPassageSearch uses the folder it is given', () async {
    final search = await openPassageSearch(
      bookId: 'abc123',
      epubPath: epub.path,
      root: Directory('${root.path}/elsewhere'),
    );
    expect(
      File('${root.path}/elsewhere/search_index/abc123.bin').existsSync(),
      isTrue,
    );
    final hits = search
        .search('keeper', cutoff: const ReaderPosition(3, 0))
        .hits;
    expect(hits, isNotEmpty);
  });
}
