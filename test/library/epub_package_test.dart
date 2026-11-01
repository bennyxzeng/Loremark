import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/library/epub_package.dart';

import 'test_epub.dart';

void main() {
  test('reads the manifest and the spine', () {
    final package = EpubPackage.fromBytes(
      buildEpub(
        chapters: const [
          EpubChapter(id: 'a', fileName: 'Chapter 1.xhtml'),
          EpubChapter(id: 'b', fileName: 'b.xhtml', linear: false),
        ],
      ),
    );

    expect(package.opfPath, 'OEBPS/content.opf');
    expect(package.manifest['a']?.href, 'Chapter%201.xhtml');
    expect(package.manifest['a']?.path, 'OEBPS/Chapter 1.xhtml');
    expect(package.manifest['a']?.mediaType, 'application/xhtml+xml');
    expect(package.manifest['cover-img']?.properties, {'cover-image'});
    expect(package.spine.map((ref) => (ref.idref, ref.linear)), [
      ('a', true),
      ('b', false),
    ]);
  });

  test('resolves hrefs relative to the package document', () {
    final package = EpubPackage.fromBytes(buildEpub());

    expect(package.resolve('ch1.xhtml'), 'OEBPS/ch1.xhtml');
    expect(package.resolve('../ch%201.xhtml'), 'ch 1.xhtml');
    expect(package.resolve('./images/a.png'), 'OEBPS/images/a.png');
  });

  test('keeps an href that is not valid percent-encoding', () {
    expect(
      EpubPackage.fromBytes(buildEpub()).resolve('100%.xhtml'),
      isNotEmpty,
    );
    expect(decodeEpubPath('100%'), '100%');
  });

  test('throws a FormatException for bytes that are not an EPUB', () {
    expect(
      () => EpubPackage.fromBytes(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}
