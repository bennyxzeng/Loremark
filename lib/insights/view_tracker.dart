import 'dart:math';

import '../reader/reader_position.dart';
import 'book_units.dart';
import 'insights_config.dart';
import 'reading_insights.dart';
import 'reading_log.dart';

/// How a [PageView] ended.
enum ViewEnd {
  /// The reader moved to another position.
  moved,

  /// The reader screen closed.
  closed,

  /// The app stayed in the background long enough to end the session. The
  /// reader may come back to the same page, which starts a new view.
  background,

  /// The log shows no end: the app was killed, or this is the last event so
  /// far. The time is credited as one clamped dwell at most.
  lost,
}

/// Where the reader went after a view, judged by distance rather than by the
/// recorded cause alone, since a swipe can cover any distance.
enum MoveKind { none, forwardPage, backwardPage, forwardJump, backwardJump }

/// One stretch of time during which the page starting at a position was on
/// screen.
///
/// Positions are where a page starts, so the page's text runs from
/// [startOffset] to the next view's start, in the cumulative units of
/// `BookUnits`. The start fields are final; the rest are filled in when the
/// view ends.
class PageView {
  PageView({
    required this.startMs,
    required this.section,
    required this.progression,
    required this.startOffset,
    required this.cause,
    required this.prevOffset,
    required this.sessionId,
    required this.sessionStartMs,
    required this.tz,
    required this.resumed,
    required this.furthestBefore,
  });

  final int startMs;
  final int section;
  final double progression;
  final double startOffset;
  final NavigationCause cause;

  /// Where the reader came from, or null if they didn't move to get here.
  final double? prevOffset;
  final int sessionId;
  final int sessionStartMs;

  /// Minutes east of UTC, which decides the local day.
  final int tz;

  /// True if the view started because the book opened or the app came back,
  /// not because the reader moved. Its first part was spent before.
  final bool resumed;

  /// The furthest start offset reached before this view.
  final double furthestBefore;

  // Set when the view ends.
  var end = ViewEnd.lost;
  var endMs = 0;

  /// Seconds the page was on screen, not counting time in the background.
  var dwellSec = 0.0;

  /// Seconds that count as reading: zero for a flip-through, and capped.
  var activeSec = 0.0;
  var hadBackground = false;
  double? nextOffset;
  NavigationCause? nextCause;
  var move = MoveKind.none;

  /// The typical page length when the view ended, for views whose end says
  /// nothing about how long the page is.
  var pageUnits = 0.0;

  /// The reader got here by going back.
  bool get arrivedBackward =>
      prevOffset != null && startOffset < prevOffset! - 0.5;

  /// The view shows the last position of a section: the first half of a
  /// section turn.
  bool get isSectionEnd => progression >= 0.9999;

  /// Everything before this page had already been shown.
  bool get isRevisit => startOffset < furthestBefore - 0.5;

  /// How many units the reader moved past, when they turned a page forward.
  double get forwardUnits =>
      move == MoveKind.forwardPage ? nextOffset! - startOffset : 0;

  /// The text this view covers, in units: up to the next page when the
  /// reader turned forward, else one typical page.
  (double, double) get span => move == MoveKind.forwardPage
      ? (startOffset, nextOffset!)
      : (startOffset, startOffset + pageUnits);

  bool get movedForward =>
      move == MoveKind.forwardPage || move == MoveKind.forwardJump;
  bool get movedBackward =>
      move == MoveKind.backwardPage || move == MoveKind.backwardJump;
}

sealed class ViewEvent {
  const ViewEvent();
}

class ViewStarted extends ViewEvent {
  const ViewStarted(this.view);

  final PageView view;
}

class ViewEnded extends ViewEvent {
  const ViewEnded(this.view);

  final PageView view;
}

enum LifecycleKind { open, close, background, foreground }

/// A lifecycle record, with the session it belongs to afterwards.
class LifecycleEvent extends ViewEvent {
  const LifecycleEvent({
    required this.kind,
    required this.ms,
    required this.sessionId,
    required this.sessionStartMs,
    required this.newSession,
  });

  final LifecycleKind kind;
  final int ms;
  final int sessionId;
  final int sessionStartMs;

  /// True if this record started a session.
  final bool newSession;
}

/// Turns the log's records into [PageView]s, one record at a time.
///
/// This is the one place that knows how dwell, pauses, turns and sessions
/// work, so replaying a log and following it live give the same answers.
///
/// - A page's dwell is the time it was on screen. Time in the background is
///   taken out, but what was spent on the page before it is kept, as in
///   KOReader's statistics plugin.
/// - Two positions less than [InsightsConfig.mergeWindow] apart are one
///   turn: Readium reports the end of a section and then the start of the
///   next with one timestamp. The first is not a view of its own.
/// - A session ends after [InsightsConfig.sessionGap] without activity, on
///   close, on a long stay in the background, and on a new open.
/// - A view with no end in the log (a crash) is credited at most one clamped
///   dwell, never the time until the next launch.
class ViewTracker {
  ViewTracker(this.units, this.config)
    : _defaultPage = units.defaultPageUnits(config);

  final BookUnits units;
  final InsightsConfig config;
  final double _defaultPage;

  PageView? _view;
  var _accruedMs = 0;
  var _segmentStartMs = 0;
  var _inBackground = false;
  var _hadBackground = false;
  int? _backgroundMs;

  var _sessionId = -1;
  var _sessionStartMs = 0;
  var _sessionOpen = false;
  int? _lastActivityMs;
  var _tz = 0;

  final _pageSamples = <double>[];
  double _furthestOffset = -1;
  ReaderPosition? _furthest;

  /// The furthest position reached so far, including what `fur` records say.
  ReaderPosition? get furthest => _furthest;

  /// The view on screen now, still running.
  PageView? get current => _view;

  int get sessionId => _sessionId;
  int get sessionStartMs => _sessionStartMs;
  int get tz => _tz;

  /// The typical page length: the median of recent forward page turns, or a
  /// default until [InsightsConfig.minPageUnitSamples] have been seen.
  double get pageUnits {
    if (_pageSamples.length < config.minPageUnitSamples) return _defaultPage;
    final sorted = [..._pageSamples]..sort();
    return sorted[sorted.length ~/ 2];
  }

  /// Takes the next record and returns what it settled.
  List<ViewEvent> add(LogRecord record) => switch (record) {
    OpenRecord() => _open(record),
    PositionRecord() => _position(record),
    BackgroundRecord() => _background(record),
    ForegroundRecord() => _foreground(record),
    CloseRecord() => _close(record),
    FurthestRecord() => _furthestRecord(record),
    HeaderRecord() || DayRecord() => const [],
  };

  List<ViewEvent> _open(OpenRecord record) {
    final events = <ViewEvent>[];
    final view = _view;
    if (view != null) {
      events.add(ViewEnded(_finish(view, record.t, ViewEnd.lost)));
    }
    _inBackground = false;
    _backgroundMs = null;
    _tz = record.tz;
    _startSession(record.t);
    _lastActivityMs = record.t;
    events.add(_lifecycle(LifecycleKind.open, record.t, newSession: true));
    return events;
  }

  List<ViewEvent> _close(CloseRecord record) {
    final events = <ViewEvent>[];
    final view = _view;
    if (view != null) {
      events.add(ViewEnded(_finish(view, record.t, ViewEnd.closed)));
    }
    _inBackground = false;
    _backgroundMs = null;
    _sessionOpen = false;
    events.add(_lifecycle(LifecycleKind.close, record.t));
    return events;
  }

  List<ViewEvent> _background(BackgroundRecord record) {
    if (_view != null && !_inBackground) {
      _accruedMs += max(0, record.t - _segmentStartMs);
      _inBackground = true;
      _hadBackground = true;
    }
    _backgroundMs ??= record.t;
    _lastActivityMs = record.t;
    return [_lifecycle(LifecycleKind.background, record.t)];
  }

  List<ViewEvent> _foreground(ForegroundRecord record) {
    _tz = record.tz;
    final t = record.t;
    final events = <ViewEvent>[];
    final left = _backgroundMs;
    _backgroundMs = null;
    final view = _view;
    final breaks =
        left != null &&
        t - left >= config.backgroundSessionBreak.inMilliseconds;
    if (!breaks) {
      if (view != null && _inBackground) {
        _inBackground = false;
        _segmentStartMs = t;
      }
      events.add(_lifecycle(LifecycleKind.foreground, t));
    } else {
      // The page was left up in the background long enough to end the
      // session. It starts a view of its own, which no move led to.
      if (view != null) {
        events.add(
          ViewEnded(_finish(view, t, ViewEnd.background, endAt: left)),
        );
      }
      _startSession(t);
      events.add(_lifecycle(LifecycleKind.foreground, t, newSession: true));
      if (view != null) {
        events.add(
          ViewStarted(
            _newView(
              t: t,
              section: view.section,
              progression: view.progression,
              cause: NavigationCause.open,
              prevOffset: null,
              resumed: true,
            ),
          ),
        );
      }
    }
    _lastActivityMs = t;
    return events;
  }

  List<ViewEvent> _position(PositionRecord record) {
    final events = <ViewEvent>[];
    final t = record.t;
    var current = _view;
    if (current != null &&
        current.section == record.section &&
        (current.progression - record.progression).abs() < 1e-6) {
      // The same position reported again, such as after coming back.
      if (_inBackground) {
        _inBackground = false;
        _backgroundMs = null;
        _segmentStartMs = t;
      }
      return events;
    }

    if (current != null &&
        !_inBackground &&
        t - current.startMs >= 0 &&
        t - current.startMs < config.mergeWindow.inMilliseconds) {
      // The second half of a turn replaces the transient first half.
      events.add(
        ViewStarted(
          _newView(
            t: t,
            section: record.section,
            progression: record.progression,
            cause: current.resumed ? current.cause : record.cause,
            prevOffset: current.prevOffset,
            resumed: current.resumed,
            furthestBefore: current.furthestBefore,
          ),
        ),
      );
      _lastActivityMs = t;
      return events;
    }

    final from = current?.startOffset;
    var breakSession = false;
    if (current != null && _inBackground) {
      // Moved without a foreground record, so the app must have come back.
      final left = _backgroundMs;
      _backgroundMs = null;
      if (left != null &&
          t - left >= config.backgroundSessionBreak.inMilliseconds) {
        events.add(
          ViewEnded(_finish(current, t, ViewEnd.background, endAt: left)),
        );
        current = null;
        breakSession = true;
      } else {
        _inBackground = false;
        _segmentStartMs = t;
      }
    }
    if (current != null) {
      events.add(
        ViewEnded(
          _finish(
            current,
            t,
            ViewEnd.moved,
            nextOffset: units.offsetAt(record.section, record.progression),
            nextCause: record.cause,
          ),
        ),
      );
    }
    final idle = _lastActivityMs == null ? 0 : t - _lastActivityMs!;
    if (breakSession ||
        !_sessionOpen ||
        idle > config.sessionGap.inMilliseconds) {
      _startSession(t);
    }
    events.add(
      ViewStarted(
        _newView(
          t: t,
          section: record.section,
          progression: record.progression,
          cause: record.cause,
          prevOffset: from,
          resumed: false,
        ),
      ),
    );
    _lastActivityMs = t;
    return events;
  }

  List<ViewEvent> _furthestRecord(FurthestRecord record) {
    _noteFurthest(
      record.section,
      record.progression,
      units.offsetAt(record.section, record.progression),
    );
    return const [];
  }

  void _noteFurthest(int section, double progression, double offset) {
    if (offset > _furthestOffset) {
      _furthestOffset = offset;
      _furthest = ReaderPosition(section, progression);
    }
  }

  void _startSession(int t) {
    _sessionId++;
    _sessionStartMs = t;
    _sessionOpen = true;
  }

  LifecycleEvent _lifecycle(
    LifecycleKind kind,
    int t, {
    bool newSession = false,
  }) => LifecycleEvent(
    kind: kind,
    ms: t,
    sessionId: _sessionId,
    sessionStartMs: _sessionStartMs,
    newSession: newSession,
  );

  PageView _newView({
    required int t,
    required int section,
    required double progression,
    required NavigationCause cause,
    required double? prevOffset,
    required bool resumed,
    double? furthestBefore,
  }) {
    final offset = units.offsetAt(section, progression);
    final view = PageView(
      startMs: t,
      section: section,
      progression: progression,
      startOffset: offset,
      cause: cause,
      prevOffset: prevOffset,
      sessionId: _sessionId,
      sessionStartMs: _sessionStartMs,
      tz: _tz,
      resumed: resumed,
      furthestBefore: furthestBefore ?? _furthestOffset,
    );
    _view = view;
    _accruedMs = 0;
    _segmentStartMs = t;
    _inBackground = false;
    _hadBackground = false;
    _noteFurthest(section, progression, offset);
    return view;
  }

  /// Ends [view] at [t]. [endAt] is when it really ended, for a page left in
  /// the background whose end is only noticed on return.
  PageView _finish(
    PageView view,
    int t,
    ViewEnd end, {
    int? endAt,
    double? nextOffset,
    NavigationCause? nextCause,
  }) {
    var ms = _accruedMs;
    if (!_inBackground) ms += max(0, t - _segmentStartMs);
    final maxMs = config.maxDwell.inMilliseconds;
    // Nothing shows how long a lost page was read; one clamped dwell is the
    // most we credit, and never the time until the next launch.
    if (end == ViewEnd.lost) ms = min(ms, maxMs);
    view
      ..end = end
      ..endMs =
          endAt ??
          (end == ViewEnd.lost && _inBackground ? _backgroundMs ?? t : t)
      ..dwellSec = ms / 1000
      ..hadBackground = _hadBackground
      ..pageUnits = pageUnits;
    view.activeSec = view.dwellSec < config.minDwell.inMilliseconds / 1000
        ? 0
        : min(view.dwellSec, maxMs / 1000);
    if (nextOffset != null) {
      view
        ..nextOffset = nextOffset
        ..nextCause = nextCause
        ..move = _classify(view.startOffset, nextOffset, nextCause!);
      if (view.move == MoveKind.forwardPage) {
        _pageSamples.add(nextOffset - view.startOffset);
        if (_pageSamples.length > config.pageUnitsWindow) {
          _pageSamples.removeAt(0);
        }
      }
    }
    _view = null;
    _inBackground = false;
    return view;
  }

  /// A move is a jump if it was a contents or search jump, or if it covered
  /// far more than a page. The page buttons only count beyond several pages,
  /// so a larger font doesn't make every page a jump.
  MoveKind _classify(double from, double to, NavigationCause cause) {
    final delta = to - from;
    final distance = delta.abs();
    final page = pageUnits;
    final jump = switch (cause) {
      NavigationCause.tocJump || NavigationCause.searchJump => true,
      NavigationCause.pageForward ||
      NavigationCause.pageBackward => distance > config.buttonJumpFactor * page,
      _ => distance > config.swipeJumpFactor * page,
    };
    if (delta > 0) return jump ? MoveKind.forwardJump : MoveKind.forwardPage;
    return jump ? MoveKind.backwardJump : MoveKind.backwardPage;
  }
}
