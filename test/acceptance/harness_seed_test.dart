import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/epub_sections.dart';
import 'package:loremark/reader/reader_position.dart';

import '../../tool/acceptance/seed.dart';

void main() {
  late Directory temp;
  late HarnessBook book;

  setUpAll(() {
    book = buildHarnessBook(chapters: 5, wordsPerChapter: 600, seed: 9);
    temp = Directory.systemTemp.createTempSync('harness-seed-test-');
  });

  tearDownAll(() => temp.deleteSync(recursive: true));

  group('buildHarnessBook', () {
    test('is deterministic and its id is the SHA-256 of the bytes', () async {
      // Zip entries carry a modification time; it must not leak in.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final again = buildHarnessBook(
        chapters: 5,
        wordsPerChapter: 600,
        seed: 9,
      );

      expect(again.bytes, book.bytes);
      expect(book.id, sha256.convert(book.bytes).toString());
      expect(book.id, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(
        buildHarnessBook(chapters: 5, wordsPerChapter: 600, seed: 10).id,
        isNot(book.id),
      );
    });

    test('stores mimetype first and uncompressed, as Readium needs', () {
      final archive = ZipDecoder().decodeBytes(book.bytes);

      expect(archive.files.first.name, 'mimetype');
      expect(archive.files.first.compression, CompressionType.none);
      expect(
        utf8.decode(archive.files.first.content as List<int>),
        'application/epub+zip',
      );
      // The first local file header says "stored" (method 0) on the wire too.
      expect(book.bytes[8], 0);
      expect(book.bytes[9], 0);
    });

    test('has a navigation document and the metadata Readium wants', () {
      final archive = ZipDecoder().decodeBytes(book.bytes);
      String read(String name) =>
          utf8.decode(archive.findFile(name)!.content as List<int>);

      final opf = read('OEBPS/content.opf');
      expect(opf, contains('properties="nav"'));
      expect(opf, contains('<dc:identifier'));
      expect(opf, contains('<dc:language>en</dc:language>'));
      expect(opf, contains('dcterms:modified'));
      expect(read('OEBPS/nav.xhtml'), contains('epub:type="toc"'));
    });

    test(
      'opens through the app\'s own EPUB reader with one marker per chapter',
      () async {
        final file = File('${temp.path}/book.epub')
          ..writeAsBytesSync(book.bytes);

        final spine = await readSpine(file.path);
        final texts = await readSectionTexts(file.path);

        expect(spine, hasLength(5));
        expect(texts, hasLength(5));
        expect(book.markers, hasLength(5));
        for (var c = 0; c < 5; c++) {
          expect(texts[c], contains(book.markers[c]));
          for (var other = 0; other < 5; other++) {
            if (other == c) continue;
            expect(texts[c], isNot(contains(book.markers[other])));
          }
        }
      },
    );
  });

  group('seed files', () {
    test('library.json is what the app\'s Book model reads', () {
      final json = jsonDecode(libraryJson(book, lastOpened: true));

      expect(json['version'], 1);
      expect(json['last_opened_id'], book.id);
      final parsed = Book.fromJson((json['books'] as List).single);
      expect(parsed.id, book.id);
      expect(parsed.title, harnessTitle);
      expect(
        parsed.epubPath,
        '/data/user/0/com.example.loremark/files/library/books/${book.id}.epub',
      );
      expect(parsed.coverPath, isNull);
    });

    test('library.json can leave nothing to auto-open', () {
      final json = jsonDecode(libraryJson(book, lastOpened: false));

      expect(json['last_opened_id'], isNull);
    });

    test('reading_state is what ReaderPosition reads, and reads back', () {
      final json = jsonDecode(readingStateJson(3, 0.375));

      expect(json['version'], 1);
      expect(
        ReaderPosition.fromJson(json['current']),
        const ReaderPosition(3, 0.375),
      );
      final back = parseReadingState(readingStateJson(3, 0.375))!;
      expect(back.section, 3);
      expect(back.progression, 0.375);
    });

    test('parseReadingState gives null for anything else', () {
      expect(parseReadingState(''), isNull);
      expect(parseReadingState('cat: no such file'), isNull);
      expect(parseReadingState('{"version":1}'), isNull);
      expect(
        parseReadingState('{"version":1,"current":{"sectionIndex":"x"}}'),
        isNull,
      );
    });
  });
}
