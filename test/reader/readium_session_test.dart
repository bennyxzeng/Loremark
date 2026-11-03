import 'dart:async';
import 'dart:io';

import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/epub_reader_service.dart';
import 'package:loremark/reader/readium_reader_service.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/reading/text_position.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../library/test_epub.dart';

const _xhtml = 'application/xhtml+xml';

/// The hrefs Readium reports for the books built below.
const _hrefs = [
  'OEBPS/ch0.xhtml',
  'OEBPS/ch1.xhtml',
  'OEBPS/ch2.xhtml',
  'OEBPS/ch3.xhtml',
];

/// Stands in for the native Readium plugin, so sessions run without it.
///
/// Like the real singleton it has one open publication, and closing takes
/// whatever is open at the moment the close finishes.
class _FakeReadiumPlatform extends FlutterReadiumPlatform
    with MockPlatformInterfaceMixin {
  final locators = StreamController<Locator>.broadcast();
  final statuses = StreamController<ReadiumReaderStatus>.broadcast();

  /// Native calls in order, such as `open a.epub` or `close start`.
  final calls = <String>[];

  /// The file name of the book that is open now, or null.
  String? openBook;

  /// If set, a close waits for it before it finishes.
  Completer<void>? closeGate;

  /// If set, a close fails with it.
  Object? closeError;

  int get closeCount => calls.where((call) => call == 'close start').length;

  @override
  Future<Publication> openPublication(String pubUrl) async {
    final name = Uri.parse(pubUrl).pathSegments.last;
    calls.add('open $name');
    injectedAtOpen[name] = List.of(injected);
    openBook = name;
    return Publication.fromJson({
      'metadata': {'title': 'Test book'},
      'readingOrder': [
        for (final href in _hrefs) {'href': href, 'type': _xhtml},
      ],
      'toc': tocLinks,
    })!;
  }

  /// The contents list the plugin reports, as `{href, title}` links.
  List<Map<String, String>> tocLinks = [
    {'href': _hrefs[1], 'title': 'One'},
    {'href': '${_hrefs[2]}#s', 'title': 'Two'},
  ];

  /// Whether showing a file is reported to the app when a jump to it is
  /// asked for, as Readium does.
  bool arrivesOnGoTo = true;

  /// If set, registering the page script fails with it.
  Object? injectionError;

  /// The script assets registered so far.
  final injected = <String>[];

  /// What was registered at the moment each book opened.
  final injectedAtOpen = <String, List<String>>{};

  @override
  Future<void> setJavaScriptInjections(List<InjectionAsset> injections) async {
    if (injectionError case final error?) throw error;
    injected.addAll(injections.map((e) => e.assetPath));
  }

  @override
  Future<void> closePublication() async {
    calls.add('close start');
    await closeGate?.future;
    if (closeError case final error?) throw error;
    openBook = null;
    calls.add('close end');
  }

  @override
  Stream<Locator> get onTextLocatorChanged => locators.stream;

  @override
  Stream<ReadiumReaderStatus> get onReaderStatusChanged => statuses.stream;

  @override
  void setDefaultPreferences(EPUBPreferences preferences) {}

  /// The decorations last applied per group, as `applyDecorations` got them.
  final decorations = <String, List<ReaderDecoration>>{};

  /// Every goToLocator argument, in order.
  final goToLocators = <Locator>[];

  @override
  Future<void> applyDecorations(
    String id,
    List<ReaderDecoration> decorations,
  ) async {
    calls.add('decorate $id ${decorations.length}');
    this.decorations[id] = decorations;
  }

  @override
  Future<bool> goToLocator(Locator locator) async {
    goToLocators.add(locator);
    calls.add('goTo ${locator.href}');
    if (arrivesOnGoTo) {
      locators.add(
        Locator(
          href: locator.href,
          type: _xhtml,
          locations: const Locations(progression: 0),
        ),
      );
    }
    return true;
  }

  @override
  Future<void> goForward() async => calls.add('forward');

  @override
  Future<void> goBackward() async => calls.add('backward');
}

/// A bare locator, as Readium sends first for each page.
Locator _bare(int section, double progression, {double? total}) => Locator(
  href: _hrefs[section],
  type: _xhtml,
  locations: Locations(progression: progression, totalProgression: total),
);

/// The full locator that follows it, with the zero-based page numbers.
Locator _full(
  int section,
  double progression, {
  required int page,
  required int pages,
  double? total,
}) => Locator(
  href: _hrefs[section],
  type: _xhtml,
  locations: Locations(
    progression: progression,
    totalProgression: total,
    additionalProperties: {'currentPage': page, 'totalPages': pages},
  ),
);

void main() {
  late _FakeReadiumPlatform fake;
  late Directory temp;
  late String bookA;
  late String bookB;
  final opened = <EpubReaderSession>[];

  const service = ReadiumReaderService();

  /// A book of [words] words in every chapter, or tiny chapters.
  Future<String> writeBook(
    String name, {
    String? chapterOne,
    int words = 0,
  }) async {
    final path = '${temp.path}/$name';
    String body(int i) {
      if (i == 1 && chapterOne != null) return chapterOne;
      if (words == 0) return '<p>$i</p>';
      return '<p>${List.filled(words, 'word').join(' ')}</p>';
    }

    await File(path).writeAsBytes(
      buildEpub(
        chapters: [
          for (var i = 0; i < _hrefs.length; i++)
            EpubChapter(id: 'c$i', fileName: 'ch$i.xhtml', body: body(i)),
        ],
      ),
    );
    return path;
  }

  Future<EpubReaderSession> open(String path) async {
    final session = await service.open(path);
    opened.add(session);
    return session;
  }

  /// Every position [session] reports from now on.
  List<ReaderPosition> collect(EpubReaderSession session) {
    final positions = <ReaderPosition>[];
    session.positions.listen(positions.add);
    return positions;
  }

  /// Sends [locators] the way the plugin does and lets them be delivered.
  Future<void> send(List<Locator> locators) async {
    locators.forEach(fake.locators.add);
    await pumpEventQueue();
  }

  setUp(() async {
    fake = _FakeReadiumPlatform();
    FlutterReadiumPlatform.instance = fake;
    temp = await Directory.systemTemp.createTemp('loremark_session_');
    bookA = await writeBook('a.epub');
    bookB = await writeBook('b.epub');
  });

  tearDown(() async {
    // The service keeps the open session in a static, so none may outlive
    // its test.
    for (final session in opened) {
      await session.close();
    }
    opened.clear();
    await temp.delete(recursive: true);
  });

  group('page script', () {
    test('is registered before the book opens', () async {
      await open(bookA);

      expect(fake.injectedAtOpen['a.epub'], [pageEndScriptAsset]);
    });

    test('is not needed for the book to open', () async {
      fake.injectionError = StateError('no injections');

      final session = await open(bookA);

      expect(session.sectionCount, _hrefs.length);
      expect(fake.openBook, 'a.epub');
    });
  });

  group('pageTextEnds', () {
    late String book;

    /// The full locator of a page of chapter 1 whose script reported
    /// [marker] as the first block past the page.
    Locator page(Object? marker, {double progression = 0.1}) => Locator(
      href: _hrefs[1],
      type: _xhtml,
      locations: Locations(
        progression: progression,
        additionalProperties: {
          'currentPage': 0,
          'totalPages': 5,
          'physicalPage': ?marker,
        },
      ),
    );

    setUp(() async {
      book = await writeBook(
        'text.epub',
        chapterOne: '<p>Alpha</p><p>Beta</p><p>Gamma</p>',
      );
    });

    /// Everything [session] reports on [EpubReaderSession.pageTextEnds].
    List<TextPosition> collectEnds(EpubReaderSession session) {
      final ends = <TextPosition>[];
      session.pageTextEnds.listen(ends.add);
      return ends;
    }

    /// Waits for [count] reports: the chapter is read in the background.
    Future<void> waitFor(List<TextPosition> ends, int count) async {
      final stop = DateTime.now().add(const Duration(seconds: 5));
      while (ends.length < count && DateTime.now().isBefore(stop)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    /// Gives a report that should not come time to show up.
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 300));

    test('reports how far the text on the page goes', () async {
      final session = await open(book);
      final ends = collectEnds(session);

      // The text is "Alpha\n\nBeta\n\nGamma", and Gamma starts at character 13.
      await send([page('loremark-end:2')]);
      await waitFor(ends, 1);

      expect(ends, hasLength(1));
      expect(ends.single.sectionIndex, 1);
      expect(ends.single.progression, closeTo(13.25 / 18, 1e-9));
    });

    test('reports a page once however often Readium repeats it', () async {
      final session = await open(book);
      final ends = collectEnds(session);

      await send([page('loremark-end:1'), page('loremark-end:1')]);
      await waitFor(ends, 1);
      await settle();

      expect(ends, hasLength(1));
    });

    test('reports each page as the reader turns to it', () async {
      final session = await open(book);
      final ends = collectEnds(session);

      await send([page('loremark-end:1', progression: 0.1)]);
      await waitFor(ends, 1);
      await send([page('loremark-end:2', progression: 0.5)]);
      await waitFor(ends, 2);

      expect(ends, hasLength(2));
      expect(ends[0].progression, lessThan(ends[1].progression));
    });

    test('reports nothing for a page the script could not measure', () async {
      final session = await open(book);
      final ends = collectEnds(session);

      await send([page(null), page('iv'), page('loremark-end:9')]);
      await settle();

      expect(ends, isEmpty);
    });

    test('reports nothing once the book is closed', () async {
      final session = await open(book);
      final ends = collectEnds(session);

      await session.close();
      await send([page('loremark-end:2')]);
      await settle();

      expect(ends, isEmpty);
    });
  });

  group('close', () {
    test('completes for a session nobody listened to', () async {
      final session = await open(bookA);

      await session.close().timeout(const Duration(seconds: 5));

      expect(fake.closeCount, 1);
    });

    test('closes the publication once however often it is called', () async {
      final session = await open(bookA);

      await session.close();
      await session.close();

      expect(fake.closeCount, 1);
    });

    test('ends the positions stream', () async {
      final session = await open(bookA);
      final done = Completer<void>();
      session.positions.listen((_) {}, onDone: done.complete);

      await session.close();

      await done.future.timeout(const Duration(seconds: 5));
    });

    test('stops reporting locators', () async {
      final session = await open(bookA);
      final positions = collect(session);

      await session.close();
      await send([_bare(1, 0.5)]);

      expect(positions, isEmpty);
    });
  });

  group('positions', () {
    test('reports a bare and a full locator as one position', () async {
      final session = await open(bookA);
      final positions = collect(session);

      await send([
        _bare(1, 0.3, total: 0.2),
        _full(1, 0.3, page: 1, pages: 4, total: 0.2),
      ]);

      expect(positions, [const ReaderPosition(1, 0.3, totalProgression: 0.2)]);
    });

    test('reports the last page of a section as exactly 1.0', () async {
      final session = await open(bookA);
      final positions = collect(session);

      await send([_bare(1, 0.75), _full(1, 0.75, page: 3, pages: 4)]);

      expect(positions.last, const ReaderPosition(1, 1.0));
    });

    test('a jump from mid-chapter with page info is not a finish', () async {
      final session = await open(bookA);
      final positions = collect(session);

      await send([
        _bare(1, 0.4),
        _full(1, 0.4, page: 1, pages: 4),
        // Jumps to the next chapter from the table of contents.
        _bare(2, 0),
        _full(2, 0, page: 0, pages: 3),
      ]);

      expect(positions, [
        const ReaderPosition(1, 0.4),
        const ReaderPosition(2, 0),
      ]);
    });

    test(
      'a jump keeps its place even if the jump target is a repeat',
      () async {
        final session = await open(bookA);
        final positions = collect(session);

        await send([
          _full(1, 0.4, page: 1, pages: 4),
          _full(1, 0.4, page: 1, pages: 4),
          _bare(2, 0),
        ]);

        expect(positions, [
          const ReaderPosition(1, 0.4),
          const ReaderPosition(2, 0),
        ]);
      },
    );

    test('finishes the section on a page turn without page info', () async {
      final session = await open(bookA);
      final positions = collect(session);

      await send([_bare(1, 0.4), _bare(2, 0)]);

      expect(positions, [
        const ReaderPosition(1, 0.4),
        const ReaderPosition(1, 1.0),
        const ReaderPosition(2, 0),
      ]);
    });

    test('drops locators for hrefs outside the spine', () async {
      final session = await open(bookA);
      final positions = collect(session);

      await send([
        Locator(
          href: 'OEBPS/elsewhere.xhtml',
          type: _xhtml,
          locations: Locations(progression: 0.5),
        ),
        _bare(1, 0.5),
      ]);

      expect(positions, [const ReaderPosition(1, 0.5)]);
    });
  });

  group('table of contents', () {
    test('maps entries to spine items', () async {
      final session = await open(bookA);

      expect(session.tableOfContents.map((e) => (e.title, e.sectionIndex)), [
        ('One', 1),
        ('Two', 2),
      ]);
      expect(session.sectionCount, 4);
    });

    test('goTo and page turns reach the plugin', () async {
      final session = await open(bookA);

      await session.goTo(session.tableOfContents.last);
      await session.goForward();
      await session.goBackward();

      // The first jump to another file is asked for again once it shows.
      expect(fake.calls.skip(1), [
        'goTo ${_hrefs[2]}',
        'goTo ${_hrefs[2]}',
        'forward',
        'backward',
      ]);
    });

    test('a jump inside the file the reader is in is asked for once', () async {
      final session = await open(bookA);
      await send([_bare(2, 0.1)]);

      await session.goTo(session.tableOfContents.last);

      expect(fake.goToLocators.map((l) => l.href), [_hrefs[2]]);
    });

    test('a jump to another file is asked for again once it shows', () async {
      final session = await open(bookA);
      await send([_bare(1, 0.5)]);

      await session.goTo(session.tableOfContents.last);

      expect(fake.goToLocators.map((l) => l.href), [_hrefs[2], _hrefs[2]]);
    });

    test('waits for the file to show before asking again', () async {
      final session = await open(bookA);
      await send([_bare(1, 0.5)]);
      fake.arrivesOnGoTo = false;

      final done = session.goTo(session.tableOfContents.last);
      await pumpEventQueue();
      expect(fake.goToLocators, hasLength(1));

      await send([_bare(2, 0)]);
      await done;

      expect(fake.goToLocators, hasLength(2));
    });

    test('asks again anyway when the file never shows', () async {
      final session = await open(bookA);
      await send([_bare(1, 0.5)]);
      fake.arrivesOnGoTo = false;
      final saved = ReadiumReaderService.arrivalTimeout;
      ReadiumReaderService.arrivalTimeout = const Duration(milliseconds: 50);
      addTearDown(() => ReadiumReaderService.arrivalTimeout = saved);

      await session.goTo(session.tableOfContents.last);

      expect(fake.goToLocators, hasLength(2));
    });

    test('a search jump to another file is also asked for again', () async {
      final session = await open(bookA);
      await send([_bare(1, 0.5)]);

      await session.showPassage(
        const PassageTarget(
          sectionIndex: 2,
          progression: 0.4,
          highlight: 'a grey cat',
        ),
      );

      expect(fake.goToLocators, hasLength(2));
      expect(fake.goToLocators.last.text?.highlight, 'a grey cat');
    });
  });

  group('a book without a usable table of contents', () {
    List<(String, int?, bool)> summary(EpubReaderSession session) => [
      for (final e in session.tableOfContents)
        (e.title, e.sectionIndex, e.isSynthetic),
    ];

    test('is cut into sections of about 5,000 words', () async {
      fake.tocLinks = const [];
      // Four chapters of 3,000 words: 12,000 words, two sections.
      final session = await open(await writeBook('long.epub', words: 3000));

      expect(summary(session), [
        ('Section 1', 0, true),
        ('Section 2', 2, true),
      ]);
    });

    test('keeps its own entries when it is too short to cut', () async {
      fake.tocLinks = const [];
      final session = await open(bookA);

      expect(session.tableOfContents, isEmpty);
    });

    test('is cut when its contents list is one entry', () async {
      fake.tocLinks = [
        {'href': _hrefs[1], 'title': 'Start'},
      ];
      final session = await open(await writeBook('one.epub', words: 3000));

      expect(session.tableOfContents.every((e) => e.isSynthetic), isTrue);
      expect(session.tableOfContents, hasLength(2));
    });

    test('is cut when its contents list points nowhere', () async {
      fake.tocLinks = [
        {'href': 'OEBPS/gone.xhtml', 'title': 'Gone'},
        {'href': 'OEBPS/missing.xhtml#x', 'title': 'Missing'},
        {'href': 'https://example.com/', 'title': 'Web'},
      ];
      final session = await open(await writeBook('nowhere.epub', words: 3000));

      expect(session.tableOfContents.every((e) => e.isSynthetic), isTrue);
    });

    test('keeps a contents list that has two usable entries', () async {
      final session = await open(await writeBook('toc.epub', words: 3000));

      expect(summary(session), [('One', 1, false), ('Two', 2, false)]);
    });

    test('jumps to a section start', () async {
      fake.tocLinks = const [];
      final session = await open(await writeBook('jump.epub', words: 3000));

      await session.goTo(session.tableOfContents.last);

      expect(fake.goToLocators.first.href, _hrefs[2]);
    });
  });

  group('chapterChanges', () {
    Locator inChapter(String tocHref) => Locator(
      href: _hrefs[1],
      type: _xhtml,
      locations: Locations(
        progression: 0.2,
        additionalProperties: {'tocHref': tocHref},
      ),
    );

    test('reports the entry the plugin names', () async {
      final session = await open(bookA);
      final chapters = <TocEntry>[];
      session.chapterChanges.listen(chapters.add);

      await send([inChapter(_hrefs[1]), inChapter('${_hrefs[2]}#s')]);

      expect(chapters.map((c) => c.title), ['One', 'Two']);
      expect(identical(chapters.first, session.tableOfContents.first), isTrue);
    });

    test('reports a chapter once however often it is repeated', () async {
      final session = await open(bookA);
      final chapters = <TocEntry>[];
      session.chapterChanges.listen(chapters.add);

      await send([inChapter(_hrefs[1]), inChapter(_hrefs[1])]);

      expect(chapters, hasLength(1));
    });

    test('ignores a chapter it does not have', () async {
      final session = await open(bookA);
      final chapters = <TocEntry>[];
      session.chapterChanges.listen(chapters.add);

      await send([inChapter('OEBPS/other.xhtml#x'), inChapter(_hrefs[1])]);

      expect(chapters.map((c) => c.title), ['One']);
    });
  });

  group('chapterForTocHref', () {
    int? indexOf(String href) {
      final path = Uri.decodeFull(
        href.split('#').first.replaceFirst(RegExp('^/+'), ''),
      );
      final index = _hrefs.indexOf(path);
      return index == -1 ? null : index;
    }

    final entries = [
      TocEntry(title: 'A', href: _hrefs[1], sectionIndex: 1),
      TocEntry(title: 'B', href: '${_hrefs[1]}#ch2', sectionIndex: 1),
      TocEntry(title: 'C', href: '${_hrefs[2]}#x%20y', sectionIndex: 2),
      const TocEntry(
        title: 'S',
        href: '',
        sectionIndex: 1,
        position: ReaderPosition(1, 0.5),
      ),
    ];

    test('matches by spine item and fragment', () {
      expect(chapterForTocHref(entries, _hrefs[1], indexOf)?.title, 'A');
      expect(
        chapterForTocHref(entries, '${_hrefs[1]}#ch2', indexOf)?.title,
        'B',
      );
    });

    test('ignores how the path is written', () {
      expect(
        chapterForTocHref(entries, '/${_hrefs[1]}#ch2', indexOf)?.title,
        'B',
      );
      expect(
        chapterForTocHref(entries, '${_hrefs[2]}#x%20y', indexOf)?.title,
        'C',
      );
    });

    test('is null for another file, another fragment or a section', () {
      expect(chapterForTocHref(entries, 'OEBPS/zzz.xhtml', indexOf), isNull);
      expect(chapterForTocHref(entries, '${_hrefs[1]}#nope', indexOf), isNull);
    });
  });

  group('showPassage', () {
    const target = PassageTarget(
      sectionIndex: 2,
      progression: 0.4,
      highlight: 'a grey cat',
      before: 'There was ',
      after: ' on the wall',
    );

    test('jumps with the text quote, href and progression', () async {
      final session = await open(bookA);

      await session.showPassage(target);

      final locator = fake.goToLocators.first;
      expect(locator.href, _hrefs[2]);
      expect(locator.locations?.progression, 0.4);
      expect(locator.text?.highlight, 'a grey cat');
      expect(locator.text?.before, 'There was ');
      expect(locator.text?.after, ' on the wall');
    });

    test(
      'highlights it in one group, with the same locator and a tint',
      () async {
        final session = await open(bookA);

        await session.showPassage(target);

        final decoration = fake.decorations[passageHighlightGroup]!.single;
        expect(decoration.locator.toJson(), fake.goToLocators.first.toJson());
        expect(decoration.style.style, DecorationStyle.highlight);
        // Android drops a decoration without a tint, so the JSON must carry it.
        expect(decoration.style.toJson(), contains('tint'));
      },
    );

    test('a second passage replaces the first in the same group', () async {
      final session = await open(bookA);

      await session.showPassage(target);
      await session.showPassage(
        const PassageTarget(
          sectionIndex: 1,
          progression: 0.1,
          highlight: 'the harbor',
        ),
      );

      expect(fake.decorations.keys, [passageHighlightGroup]);
      expect(fake.decorations[passageHighlightGroup], hasLength(1));
      expect(
        fake.decorations[passageHighlightGroup]!.single.locator.text?.highlight,
        'the harbor',
      );
    });

    test('a section outside the reading order does nothing', () async {
      final session = await open(bookA);

      await session.showPassage(
        const PassageTarget(
          sectionIndex: 9,
          progression: 0.5,
          highlight: 'a footnote',
        ),
      );

      expect(fake.calls, ['open a.epub']);
    });

    test('clearing applies an empty list to the group', () async {
      final session = await open(bookA);
      await session.showPassage(target);

      await session.clearPassageHighlight();

      expect(fake.decorations[passageHighlightGroup], isEmpty);
    });
  });

  group('opening another book', () {
    test('closes the previous book first', () async {
      await open(bookA);

      await open(bookB);

      expect(fake.calls, [
        'open a.epub',
        'close start',
        'close end',
        'open b.epub',
      ]);
      expect(fake.openBook, 'b.epub');
    });

    test('never lets the old close shut the new book', () async {
      final a = await open(bookA);
      fake.closeGate = Completer<void>();

      final closingA = a.close();
      final openingB = open(bookB);
      // Let B get to its turn in the queue while A's close is in flight.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      fake.closeGate!.complete();
      await closingA;
      await openingB;

      expect(fake.calls, [
        'open a.epub',
        'close start',
        'close end',
        'open b.epub',
      ]);
      expect(fake.openBook, 'b.epub');
      expect(fake.closeCount, 1);
    });

    test('a failed close does not block the next open', () async {
      final a = await open(bookA);
      fake.closeError = StateError('native close failed');

      await expectLater(a.close(), throwsStateError);
      fake.closeError = null;
      await open(bookB);

      expect(fake.openBook, 'b.epub');
    });

    test('stops the previous session from reporting', () async {
      final a = await open(bookA);
      final aPositions = <ReaderPosition>[];
      final aDone = Completer<void>();
      a.positions.listen(aPositions.add, onDone: aDone.complete);
      final b = await open(bookB);
      final bPositions = collect(b);

      await send([_bare(1, 0.2)]);
      await a.close();

      await aDone.future.timeout(const Duration(seconds: 5));
      expect(aPositions, isEmpty);
      expect(bPositions, [const ReaderPosition(1, 0.2)]);
      // Closing A again leaves B's publication alone.
      expect(fake.openBook, 'b.epub');
      expect(fake.closeCount, 1);
    });
  });
}
