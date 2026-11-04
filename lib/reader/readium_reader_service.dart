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
        // flutter_readium 0.8.0's iOS bridge uses URL(fileURLWithPath:),
        // so it needs a raw path. Android's AbsoluteUrl needs a file URI.
        publication = await readium.openPublication(
          defaultTargetPlatform == TargetPlatform.iOS
              ? File(epubPath).absolute.path
              : Uri.file(File(epubPath).absolute.path).toString(),
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
/// number of the first text block that doesn't fit on it, how many of that
/// block's characters, not counting whitespace, do, and the last few
/// characters before the end to check the count against. Null if the script
/// reported none.
///
/// The plugin passes `physicalPage` through to the locator's other locations.
@visibleForTesting
({int block, int characters, String? tail})? pageEnd(Locator locator) {
  final value = locator.locations?.additionalProperties['physicalPage'];
  if (value is! String || !value.startsWith(_pageEndMarker)) return null;
  final parts = value.substring(_pageEndMarker.length).split(':');
  if (parts.isEmpty || parts.length > 3) return null;
  final block = int.tryParse(parts[0]);
  final characters = parts.length >= 2 ? int.tryParse(parts[1]) : 0;
  if (block == null || characters == null) return null;
  if (block < 0 || characters < 0) return null;
  String? tail;
  if (parts.length == 3 && parts[2].isNotEmpty) {
    try {
      tail = Uri.decodeComponent(parts[2]);
    } on FormatException {
      return null;
    }
  }
  return (block: block, characters: characters, tail: tail);
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
    final sections = await readSectionsWithoutToc(epubPath, spine);
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
  final _selections = StreamController<PassageSelection>();
  final _highlightTaps = StreamController<String>();

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

  @override
  Stream<PassageSelection> get selections => _selections.stream;

  @override
  Stream<String> get highlightTaps => _highlightTaps.stream;

  void _onSelectionAction(SelectionActionEvent event) {
    final selection = passageSelectionFrom(event, _indexOf);
    if (selection != null && !_closed) _selections.add(selection);
  }

  void _onDecorationInteraction(DecorationInteractionEvent event) {
    if (event.group != noteHighlightGroup || _closed) return;
    _highlightTaps.add(event.decorationId);
  }

  int? _indexOf(String href) => spineIndexOf(_spine, href);

  ReaderPosition? _lastRaw;
  bool _lastHadPageInfo = false;

  void _onLocator(Locator locator) {
    // Tracked before the checks below, so a dropped duplicate still counts.
    final previousHadPageInfo = _lastHadPageInfo;
    _lastHadPageInfo = _hasPageInfo(locator.locations);
    final raw = positionFromLocator(locator, _indexOf);
    // Debug and profile builds only; tool/acceptance reads it from logcat.
    if (kDebugMode || kProfileMode) {
      final line = positionLogLine(locator, raw?.sectionIndex);
      if (line != null) debugPrintSynchronously(line);
    }
    if (raw != null) {
      _redrawOnNewPage((raw.sectionIndex, locator.locations?.progression));
    }
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
      unawaited(
        _onPageEnd(raw.sectionIndex, end.block, end.characters, end.tail),
      );
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

  (int, int, int, String?)? _lastPageEnd;
  int? _markupSection;
  Future<String?>? _markup;

  /// Finds where the page ends in [section]'s text, inside the text block
  /// [block] after [characters] of it, and reports it on [pageTextEnds].
  Future<void> _onPageEnd(
    int section,
    int block,
    int characters,
    String? tail,
  ) async {
    if (_lastPageEnd == (section, block, characters, tail)) return;
    _lastPageEnd = (section, block, characters, tail);
    // One section's markup is kept, since most page turns stay in it.
    if (_markupSection != section) {
      _markupSection = section;
      _markup = readSectionMarkup(_epubPath, _spine[section].path);
    }
    final xhtml = await _markup;
    if (xhtml == null) return;
    final progression = await Isolate.run(
      () => textProgressionOfBlock(
        xhtml,
        block,
        characters: characters,
        tail: tail,
      ),
    );
    // Debug and profile builds only; for checking cutoffs on a device.
    if (kDebugMode || kProfileMode) {
      final fields = {
        'section': section,
        'block': block,
        'characters': characters,
        'tail': tail,
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
    // Plugin issue #298: the view ignores callbacks changed on rebuild.
    // Positions come from the streams instead, and the two callbacks below are
    // this session's own methods, which never change.
    return ReadiumReaderWidget(
      publication: _publication,
      fontFamilyDeclarations: _servedScript,
      selectionActions: selectionMenu,
      onSelectionAction: _onSelectionAction,
      onDecorationInteraction: _onDecorationInteraction,
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

  /// The decorations last applied, by group, kept to draw them again.
  final _decorations = <String, List<ReaderDecoration>>{};

  /// The page, as section and progression, the decorations were last drawn
  /// again for.
  (int, double?)? _decoratedPage;

  Future<void> _decorate(String group, List<ReaderDecoration> decorations) {
    _decorations[group] = decorations;
    return _readium.applyDecorations(group, decorations);
  }

  /// Applies every decoration group again each time the reader shows another
  /// page, starting with the first one it shows. Readium reports each page
  /// twice with the same progression, so that counts as one page.
  ///
  /// flutter_readium 0.8.0's Android navigator clears all decorations when the
  /// page it shows moves to another file (`EpubNavigator.onPageChanged`), but
  /// only puts them back when a file finishes loading (`onPageLoaded`). A file
  /// the pager already holds, such as the one the reader just turned back
  /// into, doesn't load again, so its highlights showed for a moment and were
  /// gone. Decorations applied before the reader view exists are also dropped,
  /// since the plugin has no view to send them to.
  ///
  /// Every page, not only a new file, because highlights were also seen to
  /// vanish after turning one page and back. Readium compares the list with
  /// the one it has, so this draws nothing new when nothing was cleared.
  void _redrawOnNewPage((int, double?) page) {
    if (page == _decoratedPage || _closed) return;
    _decoratedPage = page;
    for (final MapEntry(key: group, value: decorations)
        in _decorations.entries) {
      // An empty group is already what the plugin left.
      if (decorations.isEmpty) continue;
      unawaited(
        _readium.applyDecorations(group, decorations).catchError((
          Object error,
        ) {
          debugPrint('Could not draw the $group decorations again: $error');
        }),
      );
    }
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
    await _decorate(passageHighlightGroup, [
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
      _decorate(passageHighlightGroup, const []);

  @override
  Future<void> showNoteHighlights(List<NoteHighlight> highlights) => _decorate(
    noteHighlightGroup,
    noteDecorations(highlights, _publication.readingOrder, _indexOf),
  );

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
    unawaited(_selections.close());
    unawaited(_highlightTaps.close());
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
    isLastPage(locations) ? 1.0 : locations?.progression ?? 0,
    totalProgression: locations?.totalProgression,
  );
}

/// Whether [locations] is on the last page of its section, from the
/// `currentPage` and `totalPages` the plugin adds to full locators.
///
/// A book read right to left numbers its pages the other way: the first page
/// of a file is `totalPages - 1` and the last is 0. Taken at face value that
/// would call every file finished on its first page, and search would open
/// the whole file, so the page index is read in the direction the progression
/// runs (see [pageIndexOf]).
@visibleForTesting
bool isLastPage(Locations? locations) {
  final properties = locations?.additionalProperties;
  final totalPages = properties?['totalPages'];
  if (totalPages is! int || totalPages <= 0) return false;
  final index = pageIndexOf(locations);
  return index != null && index >= totalPages - 1;
}

/// The zero-based page of [locations] counted in reading order, or null if
/// the plugin gave no page numbers.
///
/// `currentPage` counts in reading order in a book read left to right and
/// backwards in one read right to left. The progression is where the page
/// starts, as a share of the file, so it always runs in reading order and
/// `progression * totalPages` is about the page. Whichever of `currentPage` and
/// its mirror is closer to that is the page. Without a progression,
/// `currentPage` is taken as it is.
///
/// flutter_readium 0.8.0 counts pages differently per platform: Android passes
/// the Kotlin navigator's zero-based page index, while iOS reads a one-based
/// page number from its JavaScript helper, so iOS numbers are moved down by
/// one first.
@visibleForTesting
int? pageIndexOf(Locations? locations) {
  final properties = locations?.additionalProperties;
  final pageNumber = properties?['currentPage'];
  final totalPages = properties?['totalPages'];
  if (pageNumber is! int || totalPages is! int || totalPages <= 0) {
    return null;
  }
  final currentPage = defaultTargetPlatform == TargetPlatform.iOS
      ? pageNumber - 1
      : pageNumber;
  final progression = locations?.progression;
  if (progression == null) return currentPage;
  final expected = progression * totalPages;
  final mirrored = totalPages - 1 - currentPage;
  return (mirrored - expected).abs() < (currentPage - expected).abs()
      ? mirrored
      : currentPage;
}

/// The `LOREMARK_POSITION {json}` logcat line the acceptance harness reads
/// for [locator] on [section], or null for the bare locator that lacks page
/// numbers.
///
/// The harness measures "within one page" in Readium pages, which the saved
/// position file doesn't hold. Printed synchronously, unlike `debugPrint`,
/// so a line survives a SIGKILL right after the page turn.
@visibleForTesting
String? positionLogLine(Locator locator, int? section, {DateTime? now}) {
  final locations = locator.locations;
  if (!_hasPageInfo(locations)) return null;
  final properties = locations!.additionalProperties;
  final fields = {
    'section': section,
    'progression': locations.progression,
    'currentPage': properties['currentPage'],
    'totalPages': properties['totalPages'],
    'tUs': (now ?? DateTime.now()).microsecondsSinceEpoch,
  };
  return 'LOREMARK_POSITION ${jsonEncode(fields)}';
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

/// The menu over selected text, one action per [SelectionCommand], each with
/// the command's name as its id.
///
/// On Android these replace the system menu, Copy included, which is why Copy
/// is one of ours.
const selectionMenu = [
  SelectionAction(id: 'highlight', title: 'Highlight'),
  SelectionAction(id: 'addNote', title: 'Add note'),
  SelectionAction(id: 'copy', title: 'Copy'),
];

/// The selection [event] reports, or null if its action isn't one of
/// [selectionMenu], it is outside the spine, or no text came with it.
///
/// Readium puts the selected text and the text around it in the locator's
/// quote; the event's own text is only the fallback.
PassageSelection? passageSelectionFrom(
  SelectionActionEvent event,
  int? Function(String href) indexOf,
) {
  final command = SelectionCommand.values
      .where((command) => command.name == event.actionId)
      .firstOrNull;
  final sectionIndex = indexOf(event.locator.href);
  final quote = event.locator.text;
  final text = quote?.highlight ?? event.selectedText ?? '';
  if (command == null || sectionIndex == null || text.trim().isEmpty) {
    return null;
  }
  return PassageSelection(
    command: command,
    sectionIndex: sectionIndex,
    progression: event.locator.locations?.progression ?? 0,
    text: text,
    before: quote?.before ?? '',
    after: quote?.after ?? '',
  );
}

/// The decoration group of saved notes and highlights, apart from
/// [passageHighlightGroup] so search and notes never clear each other.
const noteHighlightGroup = 'loremark-notes';

/// The decorations that draw [highlights], each at its text quote. A highlight
/// whose section isn't in [readingOrder] is left out.
///
/// Every style has a tint, which Android needs (see [passageHighlightStyle]).
List<ReaderDecoration> noteDecorations(
  List<NoteHighlight> highlights,
  List<Link> readingOrder,
  int? Function(String href) indexOf,
) => [
  for (final highlight in highlights)
    if (locatorForPassage(highlight.target, readingOrder, indexOf)
        case final locator?)
      ReaderDecoration(
        id: highlight.id,
        locator: locator,
        style: ReaderDecorationStyle(
          style: DecorationStyle.highlight,
          tint: highlight.color,
        ),
      ),
];

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
