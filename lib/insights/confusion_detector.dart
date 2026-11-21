import 'dart:math';

import '../reader/reader_position.dart';
import 'book_units.dart';
import 'insights_config.dart';
import 'reading_insights.dart';
import 'reading_log.dart';
import 'reading_timeline.dart';
import 'view_tracker.dart';

/// How much a signal says on its own.
enum Severity { weak, medium, strong }

extension ConfusionKindSeverity on ConfusionKind {
  /// A strong signal can prompt a nudge alone, a medium one only with
  /// another signal nearby, a weak one never.
  Severity get severity => switch (this) {
    ConfusionKind.reread => Severity.strong,
    ConfusionKind.stall || ConfusionKind.chapterBounce => Severity.medium,
    ConfusionKind.searchBurst => Severity.weak,
  };
}

/// Spots signs that the reader may have lost the thread, from the stream of
/// log records.
///
/// There are no validated thresholds for confusion in e-books, so every value
/// is a design choice, in [InsightsConfig], and the rules are conservative:
/// re-reading is normal (about one in ten eye movements is a regression, and
/// regressions help comprehension), so one look back never fires anything.
///
/// - R1 `reread`: the same span visited [InsightsConfig.rereadVisits] times
///   in a short window, at least two of them by going back to it. Repeat
///   visits are the best simple log signal, as with re-watch peaks in lecture
///   videos (Kim et al., L@S 2014), but ambiguous, hence several visits.
/// - R2 `stall`: a page whose dwell is far above the reader's own norm (a
///   modified z-score on the log of seconds per unit, with median and MAD as
///   in Iglewicz and Hoaglin) and which is followed at once by looking back.
///   A long dwell alone could be anything.
/// - R3 `chapterBounce`: going back to the same earlier chapter and returning
///   twice in half an hour.
/// - R4 `searchBurst`: several searches in a few minutes.
///
/// Spans are in cumulative units, and two views are the same span if they
/// overlap by half of the shorter, which survives font changes better than
/// fixed page numbers. The detector emits every signal; whether to show
/// one is `NudgePolicy`'s business.
class ConfusionDetector {
  ConfusionDetector({
    required this.units,
    this.config = const InsightsConfig(),
    List<PaceSample> externalBaseline = const [],
  }) : _external = externalBaseline,
       _pageUnits = units.defaultPageUnits(config);

  final BookUnits units;
  final InsightsConfig config;

  /// Samples from the reader's other books, used as the norm until this book
  /// has enough of its own.
  final List<PaceSample> _external;

  late final ViewTracker _tracker = ViewTracker(units, config);

  final _clusters = <_Cluster>[];
  _Cluster? _previousCluster;
  var _previousDwell = 0.0;
  var _previousBack = false;

  final _baseline = <PaceSample>[];
  _StallCandidate? _stall;
  var _pageUnits = 0.0;

  _Trip? _trip;
  final _bounces = <_Bounce>[];
  final _searches = <int>[];
  final _emitted = <_Emitted>[];

  var _sessionId = -1;
  var _sessionStartMs = 0;
  var _resumeOffset = 0.0;

  /// Takes the next log record and returns the signals it causes, usually
  /// none.
  List<ConfusionSignal> process(LogRecord record) =>
      processEvents(_tracker.add(record));

  /// [process] for events a shared `ViewTracker` already settled.
  List<ConfusionSignal> processEvents(Iterable<ViewEvent> events) {
    if (units.isEmpty) return const [];
    final signals = <ConfusionSignal>[];
    for (final event in events) {
      switch (event) {
        case ViewEnded(:final view):
          _viewEnded(view, signals);
        case ViewStarted(:final view):
          _viewStarted(view, signals);
        case LifecycleEvent(:final newSession) when newSession:
          // A new session forgets half-finished patterns.
          _stall = null;
          _trip = null;
        case LifecycleEvent():
      }
    }
    return signals;
  }

  void _viewEnded(PageView view, List<ConfusionSignal> out) {
    _pageUnits = view.pageUnits;
    _reread(view, out);
    _considerStall(view);
    final sample = paceSampleOf(view, config);
    if (sample != null) {
      _baseline.add(sample);
      if (_baseline.length > config.stallBaselineWindow) {
        _baseline.removeAt(0);
      }
    }
  }

  void _viewStarted(PageView view, List<ConfusionSignal> out) {
    if (view.sessionId != _sessionId) {
      _sessionId = view.sessionId;
      _sessionStartMs = view.sessionStartMs;
      _resumeOffset = view.startOffset;
    }
    _confirmStall(view, out);
    if (!view.isSectionEnd) _bounce(view, out);
    if (view.cause == NavigationCause.searchJump) _searchBurst(view, out);
  }

  // R1

  void _reread(PageView view, List<ConfusionSignal> out) {
    final (start, rawEnd) = view.span;
    final end = max(rawEnd, start + 1);
    final cluster = _clusters
        .where((c) => _sameSpan(c.start, c.end, start, end))
        .firstOrNull;
    final consecutive = cluster != null && identical(cluster, _previousCluster);
    final carried = consecutive ? _previousDwell : 0.0;
    final total = carried + view.dwellSec;
    final back = consecutive ? _previousBack : _countsAsBackArrival(view);
    _previousCluster = cluster;
    _previousDwell = total;
    _previousBack = back;
    final minVisit = config.minVisit.inMilliseconds / 1000;
    if (total < minVisit) return;
    if (consecutive && carried >= minVisit) return;

    final found = cluster ?? _Cluster(start, end);
    if (cluster == null) _clusters.add(found);
    _previousCluster = found;
    found.visits.add(_Visit(view.startMs, back));
    _pruneClusters(view.startMs);

    final recent = found.visits
        .where((v) => v.ms >= view.startMs - config.rereadWindow.inMilliseconds)
        .toList();
    if (recent.length < config.rereadVisits ||
        recent.where((v) => v.back).length < config.rereadBackArrivals) {
      return;
    }
    final minutes = max(1, ((view.endMs - recent.first.ms) / 60000).ceil());
    _emit(
      out,
      ConfusionKind.reread,
      view.endMs,
      start,
      end,
      "You've gone back to this passage ${recent.length} times in "
      '$minutes ${minutes == 1 ? 'minute' : 'minutes'}',
    );
  }

  /// Going back to a page counts as a revisit, except in the first moments of
  /// a session, when everyone steps back a page or two to regain the thread.
  bool _countsAsBackArrival(PageView view) {
    if (!view.arrivedBackward) return false;
    final early =
        view.startMs - _sessionStartMs <= config.warmUpGrace.inMilliseconds;
    // Landing up to two pages behind the page the reader resumed on, or on
    // it. A page read since resuming is a real look back.
    final nearResume =
        view.startOffset >=
            _resumeOffset - config.warmUpGracePages * _pageUnits &&
        view.startOffset <= _resumeOffset + 1;
    return !(early && nearResume);
  }

  bool _sameSpan(double aStart, double aEnd, double bStart, double bEnd) {
    final overlap = min(aEnd, bEnd) - max(aStart, bStart);
    final shorter = min(aEnd - aStart, bEnd - bStart);
    return overlap > 0 && overlap >= config.spanOverlap * shorter;
  }

  void _pruneClusters(int nowMs) {
    final oldest = nowMs - config.rereadWindow.inMilliseconds;
    _clusters.removeWhere((c) => c.visits.isEmpty || c.visits.last.ms < oldest);
  }

  // R2

  void _considerStall(PageView view) {
    final dwell = view.dwellSec;
    if (view.end != ViewEnd.moved ||
        view.hadBackground ||
        dwell < config.stallMinDwell.inMilliseconds / 1000 ||
        dwell > config.stallMaxDwell.inMilliseconds / 1000) {
      return;
    }
    final baseline = _normalBaseline();
    if (baseline == null) return;
    final spanUnits = view.move == MoveKind.forwardPage
        ? view.forwardUnits
        : view.pageUnits;
    if (spanUnits <= 0) return;

    final logs = [for (final s in baseline) log(s.secPerUnit)]..sort();
    final median = _median(logs);
    final deviations = [for (final x in logs) (x - median).abs()]..sort();
    final sigma = max(1.4826 * _median(deviations), config.stallSigmaFloor);
    final z = (log(dwell / spanUnits) - median) / sigma;
    final usual = _median([for (final s in baseline) s.sec]..sort());
    if (z < config.stallZ || dwell < config.stallDwellFactor * usual) return;

    _stall = _StallCandidate(
      view,
      view.endMs + config.stallLookback.inMilliseconds,
      dwell / usual,
    );
  }

  /// The samples that say what is normal for this reader, or null if there
  /// are too few to judge by.
  List<PaceSample>? _normalBaseline() {
    final source = _baseline.length >= config.stallMinBaseline
        ? _baseline
        : _external.length >= config.stallMinBaseline
        ? _external
        : null;
    if (source == null) return null;
    return source.length > config.stallBaselineWindow
        ? source.sublist(source.length - config.stallBaselineWindow)
        : source;
  }

  void _confirmStall(PageView arrival, List<ConfusionSignal> out) {
    final stall = _stall;
    if (stall == null) return;
    if (arrival.startMs > stall.deadlineMs) {
      _stall = null;
    } else if (arrival.arrivedBackward) {
      _stall = null;
      final (start, end) = stall.view.span;
      _emit(
        out,
        ConfusionKind.stall,
        arrival.startMs,
        start,
        end,
        'That page took about ${stall.ratio.round()} times longer than '
        'usual, and then you went back',
      );
    }
  }

  // R3

  void _bounce(PageView view, List<ConfusionSignal> out) {
    final trip = _trip;
    if (trip != null &&
        view.startMs - trip.startMs > config.bounceWindow.inMilliseconds) {
      _trip = null;
    }
    final open = _trip;
    if (open != null) {
      if (view.startOffset >= open.originOffset - _pageUnits) {
        _trip = null;
        _completeBounce(view, open, out);
      }
      return;
    }
    if (!view.arrivedBackward) return;
    final from = units.positionAt(view.prevOffset!).sectionIndex;
    final toBack =
        view.cause == NavigationCause.tocJump ||
        view.cause == NavigationCause.searchJump ||
        view.prevOffset! - view.startOffset >
            config.bounceBackPages * _pageUnits;
    if (view.section < from && toBack) {
      _trip = _Trip(
        originOffset: view.prevOffset!,
        section: view.section,
        landing: view.startOffset,
        startMs: view.startMs,
      );
    }
  }

  void _completeBounce(PageView view, _Trip trip, List<ConfusionSignal> out) {
    final window = config.bounceWindow.inMilliseconds;
    _bounces.removeWhere((b) => view.startMs - b.ms > window);
    final same = _bounces
        .where(
          (b) => (b.section - trip.section).abs() <= config.bounceSectionSlack,
        )
        .toList();
    _bounces.add(_Bounce(trip.section, view.startMs));
    if (same.length + 1 < config.bounceCount) return;
    final minutes = max(1, ((view.startMs - same.first.ms) / 60000).ceil());
    _emit(
      out,
      ConfusionKind.chapterBounce,
      view.startMs,
      trip.landing,
      trip.landing + _pageUnits,
      "You've gone back to the same earlier chapter ${same.length + 1} times "
      'in the last $minutes ${minutes == 1 ? 'minute' : 'minutes'}',
      section: trip.section,
    );
  }

  // R4

  void _searchBurst(PageView view, List<ConfusionSignal> out) {
    _searches
      ..add(view.startMs)
      ..removeWhere(
        (t) => view.startMs - t > config.searchBurstWindow.inMilliseconds,
      );
    if (_searches.length < config.searchBurstCount) return;
    _emit(
      out,
      ConfusionKind.searchBurst,
      view.startMs,
      view.startOffset,
      view.startOffset + _pageUnits,
      'You searched ${_searches.length} times in a few minutes',
    );
  }

  // Shared

  void _emit(
    List<ConfusionSignal> out,
    ConfusionKind kind,
    int ms,
    double start,
    double end,
    String reason, {
    int? section,
  }) {
    final window = config.dedupWindow.inMilliseconds;
    _emitted.removeWhere((e) => ms - e.ms > window);
    final duplicate = _emitted.any(
      (e) =>
          e.kind == kind &&
          (section != null
              ? (e.section! - section).abs() <= config.bounceSectionSlack
              : start < e.end && e.start < end),
    );
    if (duplicate) return;
    _emitted.add(_Emitted(kind, ms, start, end, section));

    final from = units.positionAt(start);
    var to = units.positionAt(end);
    if (to.sectionIndex > from.sectionIndex) {
      // Progression is within one section: a span that crosses into the next
      // ends where that begins.
      to = to.sectionIndex + 1 < units.sectionCount
          ? ReaderPosition(from.sectionIndex + 1, 0)
          : ReaderPosition(from.sectionIndex, 1);
    }
    out.add(
      ConfusionSignal(
        kind: kind,
        at: DateTime.fromMillisecondsSinceEpoch(ms),
        start: from,
        end: to,
        reason: reason,
      ),
    );
  }

  static double _median(List<double> sorted) {
    final n = sorted.length;
    return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  }
}

class _Visit {
  _Visit(this.ms, this.back);

  final int ms;
  final bool back;
}

class _Cluster {
  _Cluster(this.start, this.end);

  final double start;
  final double end;
  final visits = <_Visit>[];
}

class _StallCandidate {
  _StallCandidate(this.view, this.deadlineMs, this.ratio);

  final PageView view;
  final int deadlineMs;
  final double ratio;
}

class _Trip {
  _Trip({
    required this.originOffset,
    required this.section,
    required this.landing,
    required this.startMs,
  });

  final double originOffset;
  final int section;
  final double landing;
  final int startMs;
}

class _Bounce {
  _Bounce(this.section, this.ms);

  final int section;
  final int ms;
}

class _Emitted {
  _Emitted(this.kind, this.ms, this.start, this.end, this.section);

  final ConfusionKind kind;
  final int ms;
  final double start;
  final double end;
  final int? section;
}
