import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/insights/book_units.dart';
import 'package:loremark/insights/insights_config.dart';
import 'package:loremark/reader/reader_position.dart';

import '../library/test_epub.dart';

void main() {
  const config = InsightsConfig();

  group('countUnits', () {
    test('counts words', () {
      expect(countUnits('The quick brown fox').units, 4);
      expect(countUnits('').units, 0);
      expect(countUnits('   \n\n  ').units, 0);
    });

    test('keeps apostrophes and hyphens inside a word', () {
      expect(countUnits("Don't stop, well-known ’tis o’clock").units, 5);
    });

    test('counts numbers and accented words', () {
      expect(countUnits('In 1984 café naïve').units, 4);
    });

    test('counts every CJK character as a unit', () {
      final counted = countUnits('我喜欢读书。');

      expect(counted.units, 5);
      expect(counted.cjk, 5);
    });

    test('counts kana and hangul per character', () {
      expect(countUnits('こんにちは').units, 5);
      expect(countUnits('한국어').units, 3);
    });

    test('counts mixed text by word and by character', () {
      final counted = countUnits('Ryn 说 hello 你好');

      expect(counted.units, 5);
      expect(counted.cjk, 3);
    });
  });

  group('BookUnits', () {
    BookUnits book({List<bool>? linear}) => BookUnits(
      counts: [100, 200, 300, 400],
      linear: linear ?? [true, true, true, true],
    );

    test('offsets are continuous across a section turn', () {
      final units = book();

      expect(units.offsetAt(0, 1), units.offsetAt(1, 0));
      expect(units.offsetAt(1, 0.5), 200);
      expect(units.total, 1000);
    });

    test('positionAt inverts offsetOf', () {
      final units = book();

      for (final position in const [
        ReaderPosition(0, 0),
        ReaderPosition(1, 0.25),
        ReaderPosition(2, 0.5),
        ReaderPosition(3, 0.9),
      ]) {
        final back = units.positionAt(units.offsetOf(position));
        expect(back.sectionIndex, position.sectionIndex);
        expect(back.progression, closeTo(position.progression, 1e-9));
      }
    });

    test('a border offset is the start of the later section', () {
      final position = book().positionAt(100);

      expect(position.sectionIndex, 1);
      expect(position.progression, 0);
    });

    test('positionAt clamps to the book', () {
      final units = book();

      expect(units.positionAt(5000), const ReaderPosition(3, 1));
      expect(units.positionAt(-5), const ReaderPosition(0, 0));
    });

    test('empty sections do not break positionAt', () {
      final units = BookUnits(
        counts: [100, 0, 100],
        linear: [true, true, true],
      );

      expect(units.positionAt(100).sectionIndex, 2);
      expect(units.positionAt(50).sectionIndex, 0);
    });

    test('remaining counts to the chapter end, linear items only', () {
      final units = book(linear: [true, true, false, true]);

      // 150 left in section 1, section 2 is a footnote page.
      expect(units.remaining(const ReaderPosition(1, 0.25), 3), 150);
      // To the end of the book: also section 3.
      expect(units.remaining(const ReaderPosition(1, 0.25), 4), 550);
      expect(units.remaining(const ReaderPosition(0, 0), 99), 700);
    });

    test('remaining is zero at the end and for an unknown section', () {
      final units = book();

      expect(units.remaining(const ReaderPosition(3, 1), 4), 0);
      expect(units.remaining(const ReaderPosition(9, 0), 10), 0);
    });

    test('decides characters or words by majority', () {
      final chinese = BookUnits.fromTexts(['我喜欢读书。' * 20, 'A few words here']);
      final english = BookUnits.fromTexts(['Many words in here ' * 20, '你好']);

      expect(chinese.countsCharacters(config), isTrue);
      expect(chinese.defaultUnitsPerMinute(config), 400);
      expect(english.countsCharacters(config), isFalse);
      expect(english.defaultUnitsPerMinute(config), 230);
      expect(BookUnits.empty().countsCharacters(config), isFalse);
    });

    test('the default page is longer for characters', () {
      final chinese = BookUnits.fromTexts(['我喜欢读书。' * 20]);

      expect(chinese.defaultPageUnits(config), greaterThan(200));
      expect(book().defaultPageUnits(config), 200);
    });
  });

  group('load', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('loremark_units_');
    });

    tearDown(() => temp.delete(recursive: true));

    test('counts the sections of an EPUB and keeps the linear flags', () async {
      final epub = File('${temp.path}/book.epub');
      await epub.writeAsBytes(
        buildEpub(
          chapters: [
            const EpubChapter(
              id: 'a',
              fileName: 'a.xhtml',
              body: '<p>One two three.</p><p>Four five.</p>',
            ),
            const EpubChapter(
              id: 'b',
              fileName: 'b.xhtml',
              body: '<p>我喜欢读书。</p>',
              linear: false,
            ),
            const EpubChapter(id: 'c', fileName: 'c.xhtml'),
          ],
        ),
      );

      final units = await BookUnits.load(epub.path);

      expect(units.counts, [5, 5, 0]);
      expect(units.linear, [true, false, true]);
      expect(units.cjkUnits, 5);
    });

    test('a file that is not an EPUB throws', () async {
      final bad = File('${temp.path}/bad.epub');
      await bad.writeAsString('not a zip');

      await expectLater(BookUnits.load(bad.path), throwsA(anything));
    });

    group('loadCached', () {
      late File epub;
      late File cache;

      setUp(() async {
        epub = File('${temp.path}/book.epub');
        await epub.writeAsBytes(
          buildEpub(
            chapters: [
              const EpubChapter(
                id: 'a',
                fileName: 'a.xhtml',
                body: '<p>One two three.</p><p>Four five.</p>',
              ),
              const EpubChapter(
                id: 'b',
                fileName: 'b.xhtml',
                body: '<p>我喜欢读书。</p>',
                linear: false,
              ),
            ],
          ),
        );
        cache = File('${temp.path}/reading_log/book1.units.json');
      });

      Future<BookUnits> load() =>
          BookUnits.loadCached(epub.path, cache: cache, bookId: 'book1');

      test('counts the book once and remembers it', () async {
        expect(cache.existsSync(), isFalse);

        final first = await load();

        expect(first.counts, [5, 5]);
        expect(cache.existsSync(), isTrue);
        expect(File('${cache.path}.tmp').existsSync(), isFalse);
        // The EPUB is not read again: it can be gone.
        await epub.delete();
        final second = await load();
        expect(second.counts, [5, 5]);
        expect(second.linear, [true, false]);
        expect(second.cjkUnits, 5);
      });

      test('counts again when the cache is for another book', () async {
        await load();
        final other = BookUnits.loadCached(
          epub.path,
          cache: cache,
          bookId: 'book2',
        );

        expect((await other).counts, [5, 5]);
        expect(
          jsonDecode(cache.readAsStringSync()),
          containsPair('id', 'book2'),
        );
      });

      test('counts again after a change of format version', () async {
        await load();
        final json = jsonDecode(cache.readAsStringSync()) as Map;
        json['version'] = unitsCacheVersion + 1;
        json['counts'] = [1, 1];
        cache.writeAsStringSync(jsonEncode(json));

        expect((await load()).counts, [5, 5]);
        expect(
          jsonDecode(cache.readAsStringSync()),
          containsPair('version', unitsCacheVersion),
        );
      });

      for (final damaged in [
        '',
        '{"version":1,',
        'null',
        '{"version":1,"id":"book1","counts":[1,2],"linear":[true],"cjk":0}',
        '{"version":1,"id":"book1","counts":[1,-2],"linear":[true,true],"cjk":0}',
        '{"version":1,"id":"book1","counts":["a"],"linear":[true],"cjk":0}',
        '{"version":1,"id":"book1","counts":[],"linear":[],"cjk":0}',
        '{"version":1,"id":"book1","counts":[1,2],"linear":[true,true],"cjk":9}',
      ]) {
        test('counts again when the cache says $damaged', () async {
          await cache.parent.create(recursive: true);
          await cache.writeAsString(damaged);

          final units = await load();

          expect(units.counts, [5, 5]);
          // And the cache is whole again.
          epub.deleteSync();
          expect((await load()).counts, [5, 5]);
        });
      }

      test('a book that cannot be counted is not cached', () async {
        await epub.writeAsString('not a zip');

        await expectLater(load(), throwsA(anything));

        expect(cache.existsSync(), isFalse);
      });

      test('an unwritable cache only costs the next count', () async {
        final blocker = File('${temp.path}/blocker')..writeAsStringSync('x');
        final stuck = File('${blocker.path}/book1.units.json');

        final units = await BookUnits.loadCached(
          epub.path,
          cache: stuck,
          bookId: 'book1',
        );

        expect(units.counts, [5, 5]);
      });
    });
  });
}
