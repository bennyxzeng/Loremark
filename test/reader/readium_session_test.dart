import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/epub_reader_service.dart';
import 'package:loremark/reader/readium_reader_service.dart';
import 'package:loremark/reader/reader_position.dart';
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

  String? openedLocation;

  /// If set, a close waits for it before it finishes.
  Completer<void>? closeGate;

  /// If set, a close fails with it.
  Object? closeError;

  int get closeCount => calls.where((call) => call == 'close start').length;

  @override
  Future<Publication> openPublication(String pubUrl) async {
    openedLocation = pubUrl;
    final name = Uri.parse(pubUrl).pathSegments.last;
    calls.add('open $name');
    openBook = name;
    return Publication.fromJson({
      'metadata': {'title': 'Test book'},
      'readingOrder': [
        for (final href in _hrefs) {'href': href, 'type': _xhtml},
      ],
      'toc': [
        {'href': _hrefs[1], 'title': 'One'},
        {'href': '${_hrefs[2]}#s', 'title': 'Two'},
      ],
    })!;
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

  @override
  Future<bool> goToLocator(Locator locator) async {
    calls.add('goTo ${locator.href}');
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

  Future<String> writeBook(String name) async {
    final path = '${temp.path}/$name';
    await File(path).writeAsBytes(
      buildEpub(
        chapters: [
          for (var i = 0; i < _hrefs.length; i++)
            EpubChapter(id: 'c$i', fileName: 'ch$i.xhtml', body: '<p>$i</p>'),
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
    debugDefaultTargetPlatformOverride = null;
    // The service keeps the open session in a static, so none may outlive
    // its test.
    for (final session in opened) {
      await session.close();
    }
    opened.clear();
    await temp.delete(recursive: true);
  });

  group('native file location', () {
    test('iOS receives an unescaped absolute path', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final path = await writeBook('86 第 1 卷.epub');

      await open(path);

      expect(fake.openedLocation, File(path).absolute.path);
      expect(await File(fake.openedLocation!).exists(), isTrue);
    });

    test('Android receives an encoded file URI', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final path = await writeBook('86 第 1 卷.epub');

      await open(path);

      final uri = Uri.parse(fake.openedLocation!);
      expect(uri.scheme, 'file');
      // Windows accepts mixed separators, but URI decoding normalizes them.
      // Compare file URIs so equivalent paths don't fail a string comparison.
      expect(uri, File(path).absolute.uri);
      expect(await File.fromUri(uri).exists(), isTrue);
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

      expect(fake.calls.skip(1), ['goTo ${_hrefs[2]}', 'forward', 'backward']);
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
