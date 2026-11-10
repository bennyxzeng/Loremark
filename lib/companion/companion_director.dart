import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';

enum CompanionEyes { open, half, closed }

enum CompanionMouth { closed, half, open }

enum CompanionHand { rest, lift, point }

/// What the companion is doing.
enum CompanionMood {
  /// Waiting: breathing, blinking, and now and then raising a finger.
  idle,

  /// A question is under way and its answer hasn't started arriving.
  thinking,

  /// The answer is arriving: she says it.
  talking,
}

/// Which picture of each part shows, and how far she is raised.
@immutable
class CompanionPose {
  const CompanionPose({
    this.eyes = CompanionEyes.open,
    this.mouth = CompanionMouth.closed,
    this.hand = CompanionHand.rest,
    this.hop = 0,
  });

  /// Eyes open, mouth closed, hand down: the artist's idle picture.
  static const still = CompanionPose();

  final CompanionEyes eyes;
  final CompanionMouth mouth;
  final CompanionHand hand;

  /// How far she is raised, in hundredths of her height on screen.
  final int hop;

  /// Whether [other] needs the same picture, wherever it's placed.
  bool looksLike(CompanionPose other) =>
      eyes == other.eyes && mouth == other.mouth && hand == other.hand;

  @override
  bool operator ==(Object other) =>
      other is CompanionPose && looksLike(other) && hop == other.hop;

  @override
  int get hashCode => Object.hash(eyes, mouth, hand, hop);

  @override
  String toString() =>
      'CompanionPose(${eyes.name}, ${mouth.name}, '
      '${hand.name}, hop $hop)';
}

/// Decides, moment to moment, how the companion looks, the way a pixel game
/// animates a character: whole frames held for set times, with no easing.
///
/// Eyes, mouth and hand each run on their own. Times are on one clock that
/// the caller keeps; [advance] moves to a time and [nextChange] says when to
/// call it again.
class CompanionDirector {
  CompanionDirector({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// How high she hops on each open mouth while talking.
  static const talkHop = 3;

  /// How high she rises when breathing in.
  static const breathHop = 1;

  /// Most of a sentence she can be behind the text by. When words arrive
  /// faster than she says them, the oldest are skipped, so she stops soon
  /// after the text does.
  static const backlog = Duration(milliseconds: 1500);

  /// How late a frame can start and still keep to the beat. Later than this,
  /// as after the app was held back, the next one starts afresh.
  static const _lag = Duration(milliseconds: 500);

  CompanionMood _mood = CompanionMood.idle;
  CompanionMood get mood => _mood;

  bool _running = false;

  final _eyes = _Track(CompanionEyes.open);
  final _mouth = _Track(CompanionMouth.closed);
  final _hand = _Track(CompanionHand.rest);
  final _breath = _Track(0);

  /// Words heard but not yet said.
  String _unsaid = '';

  CompanionPose get pose => _running
      ? CompanionPose(
          eyes: _eyes.value,
          mouth: _mouth.value,
          hand: _hand.value,
          hop: _mouth.value == CompanionMouth.open ? talkHop : _breath.value,
        )
      : CompanionPose.still;

  /// When the pose may next change, or null while it holds until told
  /// something.
  Duration? get nextChange {
    if (!_running) return null;
    Duration? soonest;
    for (final until in [
      _eyes.until,
      _mouth.until,
      _hand.until,
      _breath.until,
    ]) {
      if (until != null && (soonest == null || until < soonest)) {
        soonest = until;
      }
    }
    return soonest;
  }

  /// Starts animating at [now], from the still pose. With [greet], she raises
  /// a finger soon after.
  void start(Duration now, {bool greet = false}) {
    _running = true;
    _eyes.play(now, _blink());
    _mouth.hold(CompanionMouth.closed);
    _unsaid = '';
    _startBreath(now);
    _startHand(now, firstIn: greet ? _between(500, 900) : null);
  }

  /// Back to the still pose, holding.
  void stop() {
    _running = false;
    _eyes.hold(CompanionEyes.open);
    _mouth.hold(CompanionMouth.closed);
    _hand.hold(CompanionHand.rest);
    _breath.hold(0);
    _unsaid = '';
  }

  void setMood(CompanionMood mood, Duration now) {
    if (mood == _mood) return;
    _mood = mood;
    if (!_running) return;
    if (mood == CompanionMood.talking) {
      _speak(now);
    } else {
      // Done or interrupted: the mouth closes at once.
      _unsaid = '';
      _mouth.hold(CompanionMouth.closed);
    }
    _startBreath(now);
    _startHand(
      now,
      // The first point comes early in an answer, as in the artist's preview.
      firstIn: mood == CompanionMood.talking ? _between(800, 2000) : null,
    );
  }

  /// [text] has arrived and is for her to say.
  void hear(String text, Duration now) {
    if (!_running || _mood != CompanionMood.talking || text.isEmpty) return;
    _unsaid = _trimmed(_unsaid + text);
    if (_mouth.until == null) _speak(now);
  }

  /// Something worth pointing at, like a citation: she raises her finger
  /// soon, unless it's up, about to go up, or only just came down.
  void emphasize(Duration now) {
    if (!_running || _mood != CompanionMood.talking) return;
    if (_hand.value != CompanionHand.rest) return;
    if (now - _hand.since < const Duration(milliseconds: 1000)) return;
    final until = _hand.until;
    if (until != null && until - now < const Duration(milliseconds: 400)) {
      return;
    }
    _hand.play(now, [(CompanionHand.rest, _between(150, 400)), ..._point()]);
  }

  /// Moves to [now].
  void advance(Duration now) {
    if (!_running) return;
    _run(_eyes, now, _blink, CompanionEyes.open);
    _run(_mouth, now, _syllable, CompanionMouth.closed);
    _run(_hand, now, _handFrames, CompanionHand.rest);
    _run(_breath, now, _breathFrames, 0);
  }

  /// Plays [track]'s frames up to [now], asking [next] for more as they run
  /// out; when there are none, it holds [idle].
  void _run<T>(
    _Track<T> track,
    Duration now,
    List<(T, int)> Function() next,
    T idle,
  ) {
    while (true) {
      final until = track.until;
      if (until == null || until > now) return;
      final from = now - until > _lag ? now : until;
      if (track.step(from)) continue;
      final frames = next();
      if (frames.isEmpty) {
        track.hold(idle);
        return;
      }
      track.play(from, frames);
    }
  }

  int _between(int low, int high) => low + _random.nextInt(high - low + 1);

  List<(CompanionEyes, int)> _blink() {
    const open = CompanionEyes.open;
    const half = CompanionEyes.half;
    const closed = CompanionEyes.closed;
    return [
      (open, _between(2500, 6000)),
      (half, 65),
      (closed, 85),
      (half, 65),
      // Now and then, twice.
      if (_random.nextDouble() < 0.15) ...[
        (open, 110),
        (half, 65),
        (closed, 85),
        (half, 65),
      ],
    ];
  }

  void _startBreath(Duration now) {
    if (_mood == CompanionMood.talking) {
      _breath.hold(0);
    } else {
      _breath.play(now, _breathFrames());
    }
  }

  List<(int, int)> _breathFrames() => switch (_mood) {
    CompanionMood.idle => [(0, 1200), (breathHop, 1200)],
    CompanionMood.thinking => [(0, 600), (breathHop, 600)],
    CompanionMood.talking => const [],
  };

  void _startHand(Duration now, {int? firstIn}) {
    if (_mood == CompanionMood.thinking) {
      _hand.hold(CompanionHand.lift);
    } else if (firstIn != null) {
      _hand.play(now, [(CompanionHand.rest, firstIn), ..._point()]);
    } else {
      _hand.play(now, _handFrames());
    }
  }

  List<(CompanionHand, int)> _handFrames() => switch (_mood) {
    CompanionMood.idle => [
      (CompanionHand.rest, _between(12000, 20000)),
      ..._point(),
    ],
    CompanionMood.talking => [
      (CompanionHand.rest, _between(5000, 9000)),
      ..._point(),
    ],
    CompanionMood.thinking => const [],
  };

  /// Raises the finger, holds it, and lowers it.
  List<(CompanionHand, int)> _point() => [
    (CompanionHand.lift, 100),
    (CompanionHand.point, _between(500, 800)),
    (CompanionHand.lift, 110),
  ];

  void _speak(Duration now) {
    final frames = _syllable();
    if (frames.isEmpty) {
      _mouth.hold(CompanionMouth.closed);
    } else {
      _mouth.play(now, frames);
    }
  }

  /// The mouth's frames for the next syllable or pause of what's unsaid, or
  /// none when all of it is said.
  List<(CompanionMouth, int)> _syllable() {
    if (_mood != CompanionMood.talking) return const [];
    const closed = CompanionMouth.closed;
    const half = CompanionMouth.half;
    const open = CompanionMouth.open;
    final text = _unsaid;
    var at = 0;
    while (at < text.length && _isSilent(text.codeUnitAt(at))) {
      at++;
    }
    if (at == text.length) {
      _unsaid = '';
      return const [];
    }
    final first = text.codeUnitAt(at);
    if (_pause(first) case final pause?) {
      // Punctuation together, like "?”" or "...", is one pause.
      var longest = pause;
      at++;
      while (at < text.length) {
        final unit = text.codeUnitAt(at);
        final next = _pause(unit);
        if (next == null && !_isSilent(unit)) break;
        if (next != null && next > longest) longest = next;
        at++;
      }
      _unsaid = text.substring(at);
      return [(half, 70), (closed, longest)];
    }
    // One CJK character, or up to three letters of a word, is a syllable.
    var end = at + 1;
    if (!_isCjk(first)) {
      while (end < text.length &&
          end - at < 3 &&
          _isWordUnit(text.codeUnitAt(end))) {
        end++;
      }
    }
    _unsaid = text.substring(end);
    // Between words the mouth closes for a moment. Within a word or a run of
    // CJK characters it goes straight on, and before punctuation the pause
    // closes it.
    final wordEnds = end == text.length || _isSilent(text.codeUnitAt(end));
    return [
      (half, _between(80, 120)),
      (open, _between(130, 190)),
      if (wordEnds) ...[(half, _between(60, 90)), (closed, _between(40, 80))],
    ];
  }

  /// [text] with its start dropped, if saying all of it would take longer
  /// than [backlog].
  String _trimmed(String text) {
    var total = 0;
    for (var at = text.length - 1; at >= 0; at--) {
      total += _cost(text.codeUnitAt(at));
      if (total > backlog.inMilliseconds) return text.substring(at + 1);
    }
    return text;
  }

  /// Roughly how long a character takes to say, in milliseconds.
  static int _cost(int unit) {
    if (_pause(unit) case final pause?) return pause + 70;
    if (_isCjk(unit)) return 260;
    if (_isWordUnit(unit)) return 85;
    if (unit == 0x20) return 120;
    return 0;
  }

  /// How long a punctuation mark stops her, in milliseconds.
  static int? _pause(int unit) => switch (unit) {
    0x0A => 450,
    0x2E || 0x21 || 0x3F || 0x3002 || 0xFF01 || 0xFF1F || 0x2026 => 380,
    0x2C ||
    0x3B ||
    0x3A ||
    0xFF0C ||
    0x3001 ||
    0xFF1B ||
    0xFF1A ||
    0x2014 => 220,
    _ => null,
  };

  static bool _isCjk(int unit) =>
      (unit >= 0x3040 && unit <= 0x30FF) ||
      (unit >= 0x3400 && unit <= 0x9FFF) ||
      (unit >= 0xF900 && unit <= 0xFAFF) ||
      (unit >= 0xAC00 && unit <= 0xD7AF);

  static bool _isWordUnit(int unit) =>
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A) ||
      (unit >= 0xC0 && unit <= 0x24F) ||
      unit == 0x27 ||
      unit == 0x2019;

  /// Spaces, quotes, brackets and the like: said as nothing.
  static bool _isSilent(int unit) =>
      _pause(unit) == null && !_isCjk(unit) && !_isWordUnit(unit);
}

/// One part's frames: the one showing, until when, and those after it.
class _Track<T> {
  _Track(this.value);

  T value;

  /// When [value] started showing.
  Duration since = Duration.zero;

  /// When [value] ends, or null while it holds.
  Duration? until;

  final _frames = Queue<(T, int)>();

  void hold(T value) {
    this.value = value;
    until = null;
    _frames.clear();
  }

  void play(Duration from, List<(T, int)> frames) {
    _frames
      ..clear()
      ..addAll(frames);
    step(from);
  }

  /// Shows the next frame from [from]; false if there is none.
  bool step(Duration from) {
    if (_frames.isEmpty) return false;
    final (next, milliseconds) = _frames.removeFirst();
    value = next;
    since = from;
    until = from + Duration(milliseconds: milliseconds);
    return true;
  }
}
