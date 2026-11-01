import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
    });
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
