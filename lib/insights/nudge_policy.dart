import 'book_units.dart';
import 'confusion_detector.dart';
import 'insights_config.dart';
import 'reading_insights.dart';
import 'reading_timeline.dart';
import 'view_tracker.dart';

/// Decides which confusion signals become a nudge on screen.
///
/// The detector emits every signal, because future features want them all.
/// Showing one costs the reader's attention, so this is much stricter, and it
/// is kept apart so the two can be tuned and tested separately:
///
/// - Severity: a strong signal can nudge alone, a medium one only with
///   another signal nearby in time or place, a weak one never.
/// - A passage is nudged about once, unless the reader has since moved a
///   chapter further and come back.
/// - After a nudge, none for 30 minutes and 25 forward pages. At most two a
///   session and four a day.
/// - Dismissing holds nudges back for an hour; two dismissals in a row end
///   them for the session.
/// - A nudge is dropped, silently, once the reader moves three pages past
///   its passage, and only shows while they are within two pages of it.
/// - None in the first two minutes of a session, nor soon after the app came
///   back from the background.
///
/// Time is the time of the records it is fed, so replaying a log decides the
/// same as following it live. A nudge that can't show yet waits a few minutes
/// at most; after that it is about something the reader has left behind.
class NudgePolicy {
  NudgePolicy({
    required this.units,
    this.config = const InsightsConfig(),
    bool hintsEnabled = true,
  }) : _pageUnits = units.defaultPageUnits(config) {
    _hintsEnabled = hintsEnabled;
  }

  final BookUnits units;
  final InsightsConfig config;

  var _hintsEnabled = true;

  /// Whether nudges are shown. Signals are still judged either way, so
  /// turning hints back on has the right history.
  bool get hintsEnabled => _hintsEnabled;
  set hintsEnabled(bool value) {
    _hintsEnabled = value;
    if (!value) _current = null;
  }

  ConfusionSignal? _current;
  final _candidates = <_Candidate>[];
  final _recent = <_Candidate>[];
  final _nudged = <_Nudged>[];

  var _now = 0;
  var _tz = 0;
  var _position = 0.0;
  var _furthestSection = 0;
  var _pageUnits = 0.0;

  var _sessionId = -1;
  var _sessionStartMs = 0;
  var _sessionNudges = 0;
  var _dismissals = 0;
  var _sessionDone = false;

  int? _lastNudgeMs;
  var _pagesSinceNudge = 0;
  int? _lastDismissMs;
  int? _lastAppSwitchMs;
  final _perDay = <String, int>{};

  /// The signal to show now, or null.
  ConfusionSignal? get current => _current;

  /// Signals waiting for a better moment, for tests.
  int get waiting => _candidates.length;

  /// Takes the events a record settled and the signals the detector made
  /// from them.
  void process(Iterable<ViewEvent> events, Iterable<ConfusionSignal> signals) {
    for (final event in events) {
      switch (event) {
        case ViewStarted(:final view):
          _now = view.startMs;
          _tz = view.tz;
          _position = view.startOffset;
          if (view.frontierSection > _furthestSection) {
            _furthestSection = view.frontierSection;
          }
          _enterSession(view.sessionId, view.sessionStartMs);
        case ViewEnded(:final view):
          _pageUnits = view.pageUnits;
          if (view.move == MoveKind.forwardPage) _pagesSinceNudge++;
        case LifecycleEvent():
          _now = event.ms;
          _enterSession(event.sessionId, event.sessionStartMs);
          if (event.kind == LifecycleKind.background ||
              event.kind == LifecycleKind.foreground) {
            _lastAppSwitchMs = event.ms;
          }
      }
    }
    for (final signal in signals) {
      final (start, end) = _anchor(signal);
      final candidate = _Candidate(
        signal,
        signal.at.millisecondsSinceEpoch,
        start,
        end,
      );
      _recent
        ..add(candidate)
        ..removeWhere((c) => _now - c.ms > config.dedupWindow.inMilliseconds);
      _candidates.add(candidate);
    }
    _decide();
  }

  /// The reader dismissed the nudge, or it timed out.
  void dismiss(int nowMs) {
    if (_current == null) return;
    _current = null;
    _lastDismissMs = nowMs;
    if (++_dismissals >= config.dismissalsPerSession) _sessionDone = true;
  }

  /// Forgets signals and the nudge on screen, but not the history that limits
  /// later nudges. Used after replaying a log at the start, so an old signal
  /// isn't shown for a passage the reader left days ago.
  void endReplay() {
    _current = null;
    _candidates.clear();
  }

  void _enterSession(int id, int startMs) {
    if (id == _sessionId) return;
    _sessionId = id;
    _sessionStartMs = startMs;
    _sessionNudges = 0;
    _dismissals = 0;
    _sessionDone = false;
  }

  /// The range a signal is about, in units. For a bounce it is where the
  /// reader is when it fires, since the passage itself is far behind them.
  (double, double) _anchor(ConfusionSignal signal) {
    if (signal.kind == ConfusionKind.chapterBounce) {
      return (_position, _position);
    }
    return (units.offsetOf(signal.start), units.offsetOf(signal.end));
  }

  void _decide() {
    final page = _pageUnits;
    final current = _current;
    if (current != null) {
      final shown = _nudged.last;
      if (_position > shown.end + config.nudgeMovedOnPages * page) {
        _current = null;
      }
    }
    for (final candidate in [..._candidates]) {
      final tooOld =
          _now - candidate.ms > config.nudgeCandidateTtl.inMilliseconds;
      final movedOn =
          _position > candidate.end + config.nudgeMovedOnPages * page;
      final severity = candidate.signal.kind.severity;
      if (tooOld || movedOn || !hintsEnabled || severity == Severity.weak) {
        _candidates.remove(candidate);
        continue;
      }
      if (_current != null || !_allowed(candidate, page)) continue;
      _show(candidate);
      break;
    }
  }

  bool _allowed(_Candidate candidate, double page) {
    final near = config.nudgeNearPages * page;
    if (_position < candidate.start - near ||
        _position > candidate.end + near) {
      return false;
    }
    if (candidate.signal.kind.severity == Severity.medium &&
        !_hasPartner(candidate)) {
      return false;
    }
    if (_sessionDone || _sessionNudges >= config.nudgesPerSession) return false;
    if (_perDay[dayKey(_now, _tz)] case final today?
        when today >= config.nudgesPerDay) {
      return false;
    }
    if (_now - _sessionStartMs < config.nudgeWarmUp.inMilliseconds) {
      return false;
    }
    if (_lastAppSwitchMs != null &&
        _now - _lastAppSwitchMs! < config.nudgeAfterBackground.inMilliseconds) {
      return false;
    }
    if (_lastDismissMs != null &&
        _now - _lastDismissMs! < config.dismissSuppression.inMilliseconds) {
      return false;
    }
    if (_lastNudgeMs != null &&
        (_now - _lastNudgeMs! < config.nudgeCooldown.inMilliseconds ||
            _pagesSinceNudge < config.nudgeCooldownPages)) {
      return false;
    }
    // A passage is nudged about once, unless the reader has been a chapter
    // further since.
    return !_nudged.any(
      (n) =>
          candidate.start < n.end &&
          n.start < candidate.end &&
          _furthestSection < n.furthestSection + 1,
    );
  }

  /// Whether another signal makes a medium one worth showing: one on the
  /// same passage, or close in time.
  bool _hasPartner(_Candidate candidate) => _recent.any(
    (other) =>
        !identical(other, candidate) &&
        ((other.ms - candidate.ms).abs() <=
                config.nudgeNeighbourhood.inMilliseconds ||
            (candidate.start < other.end && other.start < candidate.end)),
  );

  void _show(_Candidate candidate) {
    _candidates.remove(candidate);
    _current = candidate.signal;
    _sessionNudges++;
    _lastNudgeMs = _now;
    _pagesSinceNudge = 0;
    _perDay.update(dayKey(_now, _tz), (n) => n + 1, ifAbsent: () => 1);
    _nudged.add(_Nudged(candidate.start, candidate.end, _furthestSection));
  }
}

class _Candidate {
  _Candidate(this.signal, this.ms, this.start, this.end);

  final ConfusionSignal signal;
  final int ms;
  final double start;
  final double end;
}

class _Nudged {
  _Nudged(this.start, this.end, this.furthestSection);

  final double start;
  final double end;
  final int furthestSection;
}
