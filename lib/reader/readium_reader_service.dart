import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../reading/text_position.dart';
import '../theme/loremark_theme.dart';
import 'epub_reader_service.dart';
import 'epub_sections.dart';
import 'position_normalizer.dart';
import 'reader_position.dart';
import 'toc_builder.dart';

/// Renders EPUBs with Readium through the `flutter_readium` plugin.
///
/// This is the only file that imports the plugin.
class ReadiumReaderService implements EpubReaderService {
  const ReadiumReaderService();

  /// How long a jump to another book file waits for it to show before asking
  /// again. Tests shorten it.
  @visibleForTesting
  static Duration arrivalTimeout = const Duration(seconds: 2);

  // The plugin has one open publication at a time, so the service tracks the
  // open session globally and closes it before opening another book.
  static _ReadiumSession? _current;

  // Every native open and close runs through this chain, one at a time. Without
  // it, an old session's slow close could land after the next book opened and
  // close that book instead.
  static Future<void> _queue = Future.value();

  /// Runs [task] after every earlier one finished.
  ///
  /// A failing task fails its own caller only, never the ones queued behind
  /// it. A task already running in the queue must not call this: it would wait
  /// for itself.
  static Future<T> _serially<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<EpubReaderSession> open(String epubPath) async {
    if (!await File(epubPath).exists()) {
      throw const EpubOpenException(EpubOpenFailure.missingFile);
    }

    final List<SpineItem> spine;
    try {
      spine = await readSpine(epubPath);
    } on FormatException catch (error) {
      throw EpubOpenException(EpubOpenFailure.unreadable, error);
    }

    return _serially(() async {
      await _current?._release();
      final readium = FlutterReadium();
      // Added to every chapter the book loads, so registered first. Without
      // it search still works, one finished chapter file at a time.
      try {
        await readium.setJavaScriptInjections(const [
          InjectionAsset(assetPath: pageEndScriptAsset),
        ]);
      } on Object catch (error) {
        debugPrint('Could not add the page script: $error');
      }
      final Publication publication;
      try {
        // The plugin wants a URL, not a path.
        publication = await readium.openPublication(
          Uri.file(epubPath).toString(),
        );
      } on Object catch (error) {
        throw EpubOpenException(EpubOpenFailure.unreadable, error);
      }

      // Read by the reader view when it is built, so set it first.
      readium.setDefaultPreferences(_readerPreferences);

      final session = _ReadiumSession(
        readium,
        publication,
        spine,
        epubPath,
        await _tableOfContents(publication, spine, epubPath),
      );
      _current = session;
      return session;
    });
  }
}

/// The script that reports where each page ends: assets/reader/page_end.js.
const pageEndScriptAsset = 'assets/reader/page_end.js';

/// Makes the web view serve [pageEndScriptAsset].
///
/// The plugin only serves its own assets and the fonts an app declares, so
/// without this the page asks for the script and gets an error page. The
/// declaration is a workaround: the "font" is never used by any text, and only
/// its asset path matters. Drop it if the plugin ever serves app assets.
final _servedScript = [
  ReaderFontFamily(
    name: 'loremark-page-script',
    faces: const [ReaderFontFace(asset: pageEndScriptAsset)],
  ),
];

/// The prefix of the `physicalPage` marker the script sets on a page.
const _pageEndMarker = 'loremark-end:';

/// Where the page [locator] is ends, as reported by the page script: the
/// number of the first text block that doesn't fit on it, and how many of
/// that block's characters, not counting whitespace, do. Null if the script
/// reported none.
///
/// The plugin passes `physicalPage` through to the locator's other locations.
@visibleForTesting
({int block, int characters})? pageEnd(Locator locator) {
  final value = locator.locations?.additionalProperties['physicalPage'];
  if (value is! String || !value.startsWith(_pageEndMarker)) return null;
  final parts = value.substring(_pageEndMarker.length).split(':');
  if (parts.isEmpty || parts.length > 2) return null;
  final block = int.tryParse(parts[0]);
  final characters = parts.length == 2 ? int.tryParse(parts[1]) : 0;
  if (block == null || characters == null) return null;
  if (block < 0 || characters < 0) return null;
  return (block: block, characters: characters);
}

/// The book's own table of contents, or sections of about 5,000 words when
/// it has none the reader can use.
///
/// "Can use" means at least two entries that point into the spine: a book
/// whose contents list is missing, empty, or all links to nowhere has the
/// same problem, and a single entry is not something to navigate with.
Future<List<TocEntry>> _tableOfContents(
  Publication publication,
  List<SpineItem> spine,
  String epubPath,
) async {
  final own = tocEntriesFromLinks(
    publication.tableOfContents,
    (href) => spineIndexOf(spine, href),
  );
  if (own.where((entry) => entry.sectionIndex != null).length >= 2) return own;
  try {
    final texts = await readSectionTexts(epubPath);
    final sections = sectionsWithoutToc(texts, spine);
    return sections.isEmpty ? own : sections;
  } on Object catch (error) {
    debugPrint('Could not split the book into sections: $error');
    return own;
  }
}

/// Paginated pages in the app's paper and ink colors.
const _readerPreferences = EPUBPreferences(
  scroll: false,
  backgroundColor: LoremarkColors.paper,
  textColor: LoremarkColors.readerText,
);

class _ReadiumSession implements EpubReaderSession {
  _ReadiumSession(
    this._readium,
    this._publication,
    this._spine,
    this._epubPath,
    this.tableOfContents,
  ) : _normalizer = PositionNormalizer(_spine) {
    // Subscribed now, before the view exists, so the first locator isn't
    // missed. The plugin buffers it natively and the controller below buffers
    // it until the Read tab listens.
    _locatorSubscription = _readium.onTextLocatorChanged.listen(_onLocator);
    _statusSubscription = _readium.onReaderStatusChanged.listen(_onStatus);
  }

  final FlutterReadium _readium;
  final Publication _publication;
  final List<SpineItem> _spine;
  final String _epubPath;
  final PositionNormalizer _normalizer;
  late final StreamSubscription<Locator> _locatorSubscription;
  late final StreamSubscription<ReadiumReaderStatus> _statusSubscription;
  bool _closed = false;

  // Single-subscription: it holds the early positions until the Read tab
  // listens, which it does once. A broadcast stream would drop them.
  final _positions = StreamController<ReaderPosition>();
  final _pageTextEnds = StreamController<TextPosition>();
  final _chapterChanges = StreamController<TocEntry>();

  @override
  final List<TocEntry> tableOfContents;

  @override
  int get sectionCount => _spine.length;

  @override
  Stream<ReaderPosition> get positions => _positions.stream;

  @override
  Stream<TextPosition> get pageTextEnds => _pageTextEnds.stream;

  @override
  Stream<TocEntry> get chapterChanges => _chapterChanges.stream;

  int? _indexOf(String href) => spineIndexOf(_spine, href);

  ReaderPosition? _lastRaw;
  bool _lastHadPageInfo = false;

  void _onLocator(Locator locator) {
    // Tracked before the checks below, so a dropped duplicate still counts.
    final previousHadPageInfo = _lastHadPageInfo;
    _lastHadPageInfo = _hasPageInfo(locator.locations);
    final raw = positionFromLocator(locator, _indexOf);
    // Before the duplicate check: the page script's marker comes with the
    // second, full locator of a page, which has the same position as the bare
    // one.
    _reportChapter(locator);
    if (raw != null && raw.sectionIndex == _arrivalSection) {
      _arrival?.complete();
      _arrival = null;
      _arrivalSection = null;
    }
    final end = pageEnd(locator);
    if (raw != null && end != null) {
      unawaited(_onPageEnd(raw.sectionIndex, end.block, end.characters));
    }
    // Readium reports every page twice, a bare locator and then a full one
    // with the same position.
    if (raw == null || raw == _lastRaw) return;
    _lastRaw = raw;
    // With page info the last page already reached 1.0, so leaving a section
    // below it is a jump, not a page turn through its end.
    _emit(_normalizer.normalize(raw, mayFinishPrevious: !previousHadPageInfo));
  }

  void _onStatus(ReadiumReaderStatus status) {
    // flutter_readium 0.8.0 never sends this for EPUBs; the last page already
    // reaches 1.0 through positionFromLocator. Kept for later versions.
    if (status == ReadiumReaderStatus.reachedEndOfPublication) {
      _emit(_normalizer.finish());
    }
  }

  TocEntry? _lastChapter;

  /// Reports the chapter the plugin says [locator]'s page is in, if it is
  /// one of ours. The plugin works it out from where the page starts, so it
  /// is right for chapters that share a file, which the spine index is not.
  void _reportChapter(Locator locator) {
    final tocHref = locator.locations?.tocHref;
    if (tocHref == null || _closed) return;
    final entry = chapterForTocHref(tableOfContents, tocHref, _indexOf);
    if (entry == null || identical(entry, _lastChapter)) return;
    _lastChapter = entry;
    _chapterChanges.add(entry);
  }

  (int, int, int)? _lastPageEnd;
  int? _markupSection;
  Future<String?>? _markup;

  /// Finds where the page ends in [section]'s text, inside the text block
  /// [block] after [characters] of it, and reports it on [pageTextEnds].
  Future<void> _onPageEnd(int section, int block, int characters) async {
    if (_lastPageEnd == (section, block, characters)) return;
    _lastPageEnd = (section, block, characters);
    // One section's markup is kept, since most page turns stay in it.
    if (_markupSection != section) {
      _markupSection = section;
      _markup = readSectionMarkup(_epubPath, _spine[section].path);
    }
    final xhtml = await _markup;
    if (xhtml == null) return;
    final progression = await Isolate.run(
      () => textProgressionOfBlock(xhtml, block, characters: characters),
    );
    // Debug and profile builds only; for checking cutoffs on a device.
    if (kDebugMode || kProfileMode) {
      final fields = {
        'section': section,
        'block': block,
        'characters': characters,
        'textProgression': progression,
      };
      debugPrintSynchronously('LOREMARK_PAGE_TEXT ${jsonEncode(fields)}');
    }
    if (progression == null || _closed) return;
    _pageTextEnds.add(TextPosition(section, progression));
  }

  void _emit(List<ReaderPosition> positions) {
    if (_closed) return;
    for (final position in positions) {
      _positions.add(position);
    }
  }

  Locator? _locatorFor(ReaderPosition position) =>
      locatorFromPosition(position, _publication.readingOrder, _indexOf);

  @override
  Widget buildView({ReaderPosition? initialPosition}) {
    // Plugin issue #298: the view ignores callbacks changed on rebuild, so none
    // are passed. Positions come from the streams instead.
    return ReadiumReaderWidget(
      publication: _publication,
      fontFamilyDeclarations: _servedScript,
      initialLocator: initialPosition == null
          ? null
          : _locatorFor(initialPosition),
      loadingWidget: const ColoredBox(
        color: LoremarkColors.paper,
        child: Center(child: Text('Opening book…')),
      ),
    );
  }

  @override
  Future<void> goTo(TocEntry entry) async {
    final position = entry.position;
    if (position != null) return goToPosition(position);
    for (final link in _publication.tocFlattened) {
      if (link.href != entry.href) continue;
      final locator = _publication.locatorFromLink(link);
      if (locator != null) await _go(locator);
      return;
    }
  }

  @override
  Future<void> goToPosition(ReaderPosition position) async {
    final locator = _locatorFor(position);
    if (locator != null) await _go(locator);
  }

  Completer<void>? _arrival;
  int? _arrivalSection;

  /// Jumps to [locator], and asks again once its file is showing if it was in
  /// another one.
  ///
  /// Readium opens the file a jump leaves for at its last page and ignores
  /// the chapter or text asked for, as if the reader had turned back into it
  /// (seen with chapters that start part way through a file). Once the file
  /// is showing, a second jump scrolls to the right place. A jump inside the
  /// file the reader is already in needs only one.
  Future<void> _go(Locator locator) async {
    final target = _indexOf(locator.href);
    final from = _lastRaw?.sectionIndex;
    final arrived = Completer<void>();
    if (target != null && from != target) {
      _arrival = arrived;
      _arrivalSection = target;
    }
    await _readium.goToLocator(locator);
    if (target == null || from == target) return;
    await arrived.future.timeout(
      ReadiumReaderService.arrivalTimeout,
      onTimeout: () {},
    );
    if (identical(_arrival, arrived)) _arrival = null;
    if (_closed) return;
    await _readium.goToLocator(locator);
  }

  @override
  Future<void> showPassage(PassageTarget target) async {
    final locator = locatorForPassage(
      target,
      _publication.readingOrder,
      _indexOf,
    );
    if (locator == null) return;
    // Readium draws a decoration only where the text quote is found, and finds
    // it again whichever page loads, so the order of the two calls is free.
    await _readium.applyDecorations(passageHighlightGroup, [
      ReaderDecoration(
        id: 'hit',
        locator: locator,
        style: passageHighlightStyle,
      ),
    ]);
    await _go(locator);
  }

  @override
  Future<void> clearPassageHighlight() =>
      _readium.applyDecorations(passageHighlightGroup, const []);

  @override
  Future<void> goForward() => _readium.goForward();

  @override
  Future<void> goBackward() => _readium.goBackward();

  @override
  Future<void> close() {
    // Stops emitting now; the native close waits its turn in the queue.
    _closed = true;
    return ReadiumReaderService._serially(_release);
  }

  /// Tears the session down. Safe to call again.
  ///
  /// The publication is closed only while this session is still the open one,
  /// since a newer book may have replaced it. Runs inside the service's queue.
  Future<void> _release() async {
    _closed = true;
    await _locatorSubscription.cancel();
    await _statusSubscription.cancel();
    // Not awaited: the future of a controller nobody listened to never
    // completes.
    unawaited(_positions.close());
    unawaited(_pageTextEnds.close());
    unawaited(_chapterChanges.close());
    if (!identical(ReadiumReaderService._current, this)) return;
    ReadiumReaderService._current = null;
    await _readium.closePublication();
  }
}

/// Flattens [links] into table-of-contents entries, parents before their
/// children, each carrying its nesting [depth].
///
/// [indexOf] finds the spine item an href points to, so entries outside the
/// spine get a null `sectionIndex`.
List<TocEntry> tocEntriesFromLinks(
  List<Link> links,
  int? Function(String href) indexOf, {
  int depth = 0,
}) => [
  for (final link in links) ...[
    TocEntry(
      title: link.title ?? '',
      href: link.href,
      sectionIndex: indexOf(link.href),
      depth: depth,
    ),
    ...tocEntriesFromLinks(link.children, indexOf, depth: depth + 1),
  ],
];

/// The position [locator] stands for, or null if its href isn't a spine item.
///
/// On the last page of a section the progression is exactly 1.0. Readium
/// reports where the page starts, which never reaches 1.0, so the plugin's
/// page count is used instead; otherwise the end of the book could never
/// count as finished.
ReaderPosition? positionFromLocator(
  Locator locator,
  int? Function(String href) indexOf,
) {
  final sectionIndex = indexOf(locator.href);
  if (sectionIndex == null) return null;
  final locations = locator.locations;
  return ReaderPosition(
    sectionIndex,
    _isLastPage(locations) ? 1.0 : locations?.progression ?? 0,
    totalProgression: locations?.totalProgression,
  );
}

/// Whether [locations] is on the last page of its section, from the
/// zero-based `currentPage` and `totalPages` the plugin adds to full locators.
bool _isLastPage(Locations? locations) {
  final properties = locations?.additionalProperties;
  final currentPage = properties?['currentPage'];
  final totalPages = properties?['totalPages'];
  return currentPage is int &&
      totalPages is int &&
      totalPages > 0 &&
      currentPage >= totalPages - 1;
}

/// Whether [locations] carries the plugin's page numbers, which the bare
/// locator of each page lacks.
bool _hasPageInfo(Locations? locations) {
  final properties = locations?.additionalProperties;
  return properties?['currentPage'] is int && properties?['totalPages'] is int;
}

/// The locator that opens the reader at [position], or null if the section
/// isn't in [readingOrder], as for a non-linear spine item.
Locator? locatorFromPosition(
  ReaderPosition position,
  List<Link> readingOrder,
  int? Function(String href) indexOf,
) {
  for (final link in readingOrder) {
    if (indexOf(link.href) != position.sectionIndex) continue;
    // No `position`: Readium's positions count pages, not spine items, and the
    // navigator restores from href and progression.
    return Locator(
      href: link.href,
      type: link.type ?? 'application/xhtml+xml',
      title: link.title,
      locations: Locations(
        progression: position.progression,
        totalProgression: position.totalProgression,
      ),
    );
  }
  return null;
}

/// The decoration group of the search highlight. Applying a new list under the
/// same id replaces the old decorations, and an empty list clears them.
const passageHighlightGroup = 'loremark-search';

/// A translucent amber with the stronger "current result" look.
///
/// The tint must always be set: flutter_readium 0.8.0 leaves it out of the JSON
/// when null, and Android then drops the whole decoration without a trace.
const passageHighlightStyle = ReaderDecorationStyle(
  style: DecorationStyle.highlight,
  tint: Color(0x66FFC107),
  isActive: true,
);

/// The locator that jumps to and highlights [target], or null if its section
/// isn't in [readingOrder], as for a non-linear spine item.
///
/// Readium looks the text quote up first and only falls back to the
/// progression when the quote isn't found, so both are set.
Locator? locatorForPassage(
  PassageTarget target,
  List<Link> readingOrder,
  int? Function(String href) indexOf,
) {
  final base = locatorFromPosition(
    ReaderPosition(target.sectionIndex, target.progression),
    readingOrder,
    indexOf,
  );
  return base?.copyWith(
    text: LocatorText(
      before: target.before,
      highlight: target.highlight,
      after: target.after,
    ),
  );
}

/// The entry of [entries] the plugin's `tocHref` ("path#fragment") names, or
/// null if none does.
///
/// Entries match by spine item and fragment, so how the path is written
/// (leading slash, percent-encoding) does not matter.
TocEntry? chapterForTocHref(
  List<TocEntry> entries,
  String tocHref,
  int? Function(String href) indexOf,
) {
  final section = indexOf(tocHref);
  if (section == null) return null;
  final fragment = _fragmentOf(tocHref);
  for (final entry in entries) {
    if (entry.isSynthetic || entry.sectionIndex != section) continue;
    if (_fragmentOf(entry.href) == fragment) return entry;
  }
  return null;
}

String _fragmentOf(String href) {
  final at = href.indexOf('#');
  return at == -1 ? '' : Uri.decodeComponent(href.substring(at + 1));
}
