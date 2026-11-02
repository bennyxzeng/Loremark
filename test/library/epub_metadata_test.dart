import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/library/epub_metadata.dart';

import 'test_epub.dart';

void main() {
  EpubMetadata read(Uint8List bytes) =>
      readEpubMetadata(bytes, fallbackTitle: 'file-name');

  test('reads the title and author', () {
    final metadata = read(buildEpub(title: '86—EIGHTY-SIX', author: 'Asato'));

    expect(metadata.title, '86—EIGHTY-SIX');
    expect(metadata.author, 'Asato');
  });

  test('finds an EPUB 3 cover', () {
    final metadata = read(buildEpub(cover: CoverStyle.epub3));

    expect(metadata.cover, coverBytes);
    expect(metadata.coverExtension, 'jpg');
  });

  test('finds an EPUB 2 cover', () {
    expect(read(buildEpub(cover: CoverStyle.epub2)).cover, coverBytes);
  });

  test('works without a cover or author', () {
    final metadata = read(buildEpub(author: null, cover: CoverStyle.none));

    expect(metadata.author, isNull);
    expect(metadata.cover, isNull);
  });

  test('falls back to the file name without a title', () {
    expect(read(buildEpub(title: null)).title, 'file-name');
  });

  test('rejects a file that is not an EPUB', () {
    expect(
      () => read(Uint8List.fromList('not a zip'.codeUnits)),
      throwsFormatException,
    );
  });
}
