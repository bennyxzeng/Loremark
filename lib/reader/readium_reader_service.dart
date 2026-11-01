import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../theme/loremark_theme.dart';
import 'epub_reader_service.dart';
import 'epub_sections.dart';
import 'position_normalizer.dart';
import 'reader_position.dart';

/// Renders EPUBs with Readium through the `flutter_readium` plugin.
///
/// This is the only file that imports the plugin.
class ReadiumReaderService implements EpubReaderService {
  const ReadiumReaderService();

  // The plugin has one open publication at a time, so the service tracks the
  // open session globally and closes it before opening another book.
  static _ReadiumSession? _current;

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

    await _current?.close();
    final readium = FlutterReadium();
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

    final session = _ReadiumSession(readium, publication, spine);
    _current = session;
    return session;
  }
}

/// Paginated pages in the app's paper and ink colors.
const _readerPreferences = EPUBPreferences(
  scroll: false,
  backgroundColor: LoremarkColors.paper,
  textColor: LoremarkColors.readerText,
);

class _ReadiumSession implements EpubReaderSession {
  _ReadiumSession(this._readium, this._publication, this._spine)
    : _normalizer = PositionNormalizer(_spine),
      tableOfContents = tocEntriesFromLinks(
        _publication.tableOfContents,
        (href) => spineIndexOf(_spine, href),
      ) {
    // Subscribed now, before the view exists, so the first locator isn't
    // missed. The plugin buffers it natively and the controller below buffers
    // it until the Read tab listens.
    _locatorSubscription = _readium.onTextLocatorChanged.listen(_onLocator);
    _statusSubscription = _readium.onReaderStatusChanged.listen(_onStatus);
  }

  final FlutterReadium _readium;
  final Publication _publication;
  final List<SpineItem> _spine;
  final PositionNormalizer _normalizer;
  late final StreamSubscription<Locator> _locatorSubscription;
  late final StreamSubscription<ReadiumReaderStatus> _statusSubscription;
  bool _closed = false;

  // Single-subscription: it holds the early positions until the Read tab
  // listens, which it does once. A broadcast stream would drop them.
  final _positions = StreamController<ReaderPosition>();

  @override
  final List<TocEntry> tableOfContents;

  @override
  int get sectionCount => _spine.length;

  @override
  Stream<ReaderPosition> get positions => _positions.stream;

  int? _indexOf(String href) => spineIndexOf(_spine, href);

  ReaderPosition? _lastRaw;

  void _onLocator(Locator locator) {
    final raw = positionFromLocator(locator, _indexOf);
    // Readium reports every page twice, a bare locator and then a full one
    // with the same position.
    if (raw == null || raw == _lastRaw) return;
    _lastRaw = raw;
    _emit(_normalizer.normalize(raw));
  }

  void _onStatus(ReadiumReaderStatus status) {
    // flutter_readium 0.8.0 never sends this for EPUBs; the last page already
    // reaches 1.0 through positionFromLocator. Kept for later versions.
    if (status == ReadiumReaderStatus.reachedEndOfPublication) {
      _emit(_normalizer.finish());
    }
  }

  void _emit(List<ReaderPosition> positions) {
    if (_positions.isClosed) return;
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
    for (final link in _publication.tocFlattened) {
      if (link.href != entry.href) continue;
      final locator = _publication.locatorFromLink(link);
      if (locator != null) await _readium.goToLocator(locator);
      return;
    }
  }

  @override
  Future<void> goToPosition(ReaderPosition position) async {
    final locator = _locatorFor(position);
    if (locator != null) await _readium.goToLocator(locator);
  }

  @override
  Future<void> goForward() => _readium.goForward();

  @override
  Future<void> goBackward() => _readium.goBackward();

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (identical(ReadiumReaderService._current, this)) {
      ReadiumReaderService._current = null;
    }
    await _locatorSubscription.cancel();
    await _statusSubscription.cancel();
    await _positions.close();
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
