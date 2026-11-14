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

  /// The reading frontier, as a start offset, before this view.
  final double furthestBefore;

  /// The section of the reading frontier once this view started. A jump
  /// ahead leaves it behind the view's own section.
  var frontierSection = 0;

  /// The reader got here by turning a page forward, not by a jump.
  var turnedForward = false;

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

  /// Everything before this page had already been read through.
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

  /// The reading frontier: how far the reader has got by turning pages one
  /// after another, including what `fur` records say.
  ///
  /// A jump ahead (contents, search, or a swipe over many pages) is visited
  /// but not read through, so it doesn't move this. Search and other spoiler
  /// boundaries rely on that.
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

  /// Whether [section] is outside the book. A damaged line can name any
  /// section, and one past the end would let a cutoff open the whole book. A
  /// book that couldn't be counted has no sections to check against.
  bool _outsideBook(int section) =>
      !units.isEmpty && section >= units.sectionCount;

  /// Takes the next record and returns what it settled.
  List<ViewEvent> add(LogRecord record) => switch (record) {
    OpenRecord() => _open(record),
    PositionRecord(:final section) ||
    FurthestRecord(:final section) when _outsideBook(section) => const [],
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
            turnedForward: current.turnedForward,
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
    var turnedForward = false;
    if (current != null) {
      final finished = _finish(
        current,
        t,
        ViewEnd.moved,
        nextOffset: units.offsetAt(record.section, record.progression),
        nextSection: record.section,
        nextCause: record.cause,
      );
      turnedForward = finished.move == MoveKind.forwardPage;
      events.add(ViewEnded(finished));
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
          turnedForward: turnedForward,
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

  /// Moves the frontier to the position if it is later than the frontier.
  void _noteFurthest(int section, double progression, double offset) {
    _furthestOffset = max(_furthestOffset, offset);
    final previous = _furthest;
    if (previous == null ||
        section > previous.sectionIndex ||
        (section == previous.sectionIndex &&
            progression > previous.progression)) {
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
    bool turnedForward = false,
    double? furthestBefore,
  }) {
    final offset = units.offsetAt(section, progression);
    final extendsFrontier = _extendsFrontier(
      prevOffset: prevOffset,
      offset: offset,
      cause: cause,
      resumed: resumed,
      turnedForward: turnedForward,
    );
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
    if (extendsFrontier) _noteFurthest(section, progression, offset);
    view
      ..frontierSection = _furthest?.sectionIndex ?? section
      ..turnedForward = turnedForward;
    return view;
  }

  /// Whether arriving at [offset] extends the frontier: the reader turned a
  /// page forward from a page at or just behind it, which includes the two
  /// positions of a section turn. Anything else, such as a jump ahead, only
  /// records where the reader is.
  bool _extendsFrontier({
    required double? prevOffset,
    required double offset,
    required NavigationCause cause,
    required bool resumed,
    required bool turnedForward,
  }) {
    // The first position ever seen is where reading starts. A book with no
    // measurable text can't tell a jump from a page, so position decides.
    if (_furthest == null || units.total <= 0) return true;
    if (resumed) return false;
    if (cause == NavigationCause.open) {
      // The reader may have turned a few pages before the log was ready.
      return offset - _furthestOffset <= config.buttonJumpFactor * pageUnits;
    }
    return turnedForward &&
        prevOffset != null &&
        prevOffset <= _furthestOffset + pageUnits;
  }

  /// Ends [view] at [t]. [endAt] is when it really ended, for a page left in
  /// the background whose end is only noticed on return.
  PageView _finish(
    PageView view,
    int t,
    ViewEnd end, {
    int? endAt,
    double? nextOffset,
    int? nextSection,
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
        ..move = _classify(view, nextOffset, nextSection!, nextCause!);
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
  ///
  /// The page length is only known from forward turns, which a long page
  /// would never produce under that rule, so until enough are seen a
  /// longer move inside a section is also a page, if it was read for a
  /// normal time and isn't absurdly long.
  MoveKind _classify(
    PageView view,
    double to,
    int toSection,
    NavigationCause cause,
  ) {
    final delta = to - view.startOffset;
    var jump = _isJump(delta.abs(), cause);
    if (jump &&
        delta > 0 &&
        _looksLikeFirstPage(view, delta, toSection, cause)) {
      jump = false;
    }
    if (delta > 0) return jump ? MoveKind.forwardJump : MoveKind.forwardPage;
    return jump ? MoveKind.backwardJump : MoveKind.backwardPage;
  }

  bool _looksLikeFirstPage(
    PageView view,
    double delta,
    int toSection,
    NavigationCause cause,
  ) =>
      _pageSamples.length < config.minPageUnitSamples &&
      cause != NavigationCause.tocJump &&
      cause != NavigationCause.searchJump &&
      toSection == view.section &&
      view.dwellSec >= config.minDwell.inMilliseconds / 1000 &&
      view.dwellSec <= config.maxDwell.inMilliseconds / 1000 &&
      delta <= config.bootstrapPageFactor * _defaultPage;

  bool _isJump(double distance, NavigationCause cause) {
    final page = pageUnits;
    return switch (cause) {
      NavigationCause.tocJump || NavigationCause.searchJump => true,
      NavigationCause.pageForward ||
      NavigationCause.pageBackward => distance > config.buttonJumpFactor * page,
      _ => distance > config.swipeJumpFactor * page,
    };
  }
}
