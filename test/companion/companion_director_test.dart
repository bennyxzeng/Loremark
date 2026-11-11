import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/companion/companion_director.dart';

Duration ms(int milliseconds) => Duration(milliseconds: milliseconds);

/// Plays [director] from [from] to [to], and returns each change of what
/// [part] picks out of the pose, with when it happened.
List<(Duration, T)> play<T>(
  CompanionDirector director,
  Duration from,
  Duration to,
  T Function(CompanionPose pose) part,
) {
  final changes = <(Duration, T)>[(from, part(director.pose))];
  while (true) {
    final next = director.nextChange;
    if (next == null || next > to) return changes;
    director.advance(next);
    final now = part(director.pose);
    if (now != changes.last.$2) changes.add((next, now));
  }
}

/// How long each value in [changes] lasted, but the last.
List<(T, int)> lengths<T>(List<(Duration, T)> changes) => [
  for (var i = 0; i + 1 < changes.length; i++)
    (changes[i].$2, (changes[i + 1].$1 - changes[i].$1).inMilliseconds),
];

void main() {
  late CompanionDirector director;

  setUp(() => director = CompanionDirector(random: Random(7)));

  test('holds still until started, and once stopped', () {
    expect(director.pose, CompanionPose.still);
    expect(director.nextChange, isNull);
    director
      ..start(Duration.zero)
      ..stop();
    expect(director.pose, CompanionPose.still);
    expect(director.nextChange, isNull);
  });

  test('says what it hears, hopping on each open mouth', () {
    director
      ..start(Duration.zero)
      ..setMood(CompanionMood.talking, Duration.zero)
      ..hear('Hello, world.', Duration.zero);
    final poses = play(director, Duration.zero, ms(4000), (pose) => pose);
    expect(
      poses.map((change) => change.$2.mouth),
      contains(CompanionMouth.open),
    );
    for (final (_, pose) in poses) {
      expect(
        pose.hop,
        pose.mouth == CompanionMouth.open ? CompanionDirector.talkHop : 0,
        reason: '$pose',
      );
    }

    // The comma closes the mouth for a while; between syllables it doesn't
    // close at all, and at the end of a word only briefly.
    final mouth = <(Duration, CompanionMouth)>[];
    for (final (at, pose) in poses) {
      if (mouth.isEmpty || mouth.last.$2 != pose.mouth) {
        mouth.add((at, pose.mouth));
      }
    }
    final closed = [
      for (final (shape, length) in lengths(mouth))
        if (shape == CompanionMouth.closed) length,
    ];
    expect(closed, contains(220));
    expect(
      closed.where((length) => length != 220),
      everyElement(lessThanOrEqualTo(80)),
    );
    // Then it stays closed, with all of it said.
    expect(director.pose.mouth, CompanionMouth.closed);
  });

  test('says one CJK character a syllable, pausing at its punctuation', () {
    director
      ..start(Duration.zero)
      ..setMood(CompanionMood.talking, Duration.zero)
      ..hear('她来了。好', Duration.zero);
    final mouth = play(director, Duration.zero, ms(4000), (p) => p.mouth);
    final opens = mouth.where((change) => change.$2 == CompanionMouth.open);
    expect(opens, hasLength(4));
    final closed = [
      for (final (shape, length) in lengths(mouth))
        if (shape == CompanionMouth.closed) length,
    ];
    // Straight on from one character to the next, then the full stop.
    expect(closed, [380]);
  });

  test('closes its mouth at once when the answer ends', () {
    director
      ..start(Duration.zero)
      ..setMood(CompanionMood.talking, Duration.zero)
      ..hear('A long answer that keeps on going and going.', Duration.zero);
    final open = play(
      director,
      Duration.zero,
      ms(2000),
      (pose) => pose.mouth,
    ).firstWhere((change) => change.$2 == CompanionMouth.open).$1;
    final fresh = CompanionDirector(random: Random(7))
      ..start(Duration.zero)
      ..setMood(CompanionMood.talking, Duration.zero)
      ..hear('A long answer that keeps on going and going.', Duration.zero);
    fresh.advance(open);
    expect(fresh.pose.mouth, CompanionMouth.open);

    fresh.setMood(CompanionMood.idle, open);
    expect(fresh.pose.mouth, CompanionMouth.closed);
    expect(fresh.pose.hop, 0);
    // And more words don't open it again.
    fresh.hear('More.', open);
    final later = play(fresh, open, open + ms(3000), (pose) => pose.mouth);
    expect(later.map((change) => change.$2), [CompanionMouth.closed]);
  });

  test('falls behind the text by no more than its backlog', () {
    director
      ..start(Duration.zero)
      ..setMood(CompanionMood.talking, Duration.zero)
      ..hear('很' * 300, Duration.zero);
    final mouth = play(director, Duration.zero, ms(60000), (p) => p.mouth);
    // Said out loud, three hundred characters would take over a minute.
    expect(mouth.last.$2, CompanionMouth.closed);
    expect(mouth.last.$1, lessThan(CompanionDirector.backlog + ms(500)));
  });

  test('blinks open, half, closed, half, open', () {
    director.start(Duration.zero);
    final eyes = play(director, Duration.zero, ms(7000), (pose) => pose.eyes);
    expect(
      [for (final (_, state) in eyes.take(5)) state],
      [
        CompanionEyes.open,
        CompanionEyes.half,
        CompanionEyes.closed,
        CompanionEyes.half,
        CompanionEyes.open,
      ],
    );
    expect(
      [for (final (_, length) in lengths(eyes).skip(1).take(3)) length],
      [65, 85, 65],
    );
  });

  test('greets by pointing: rest, lift, point, lift, rest', () {
    director.start(Duration.zero, greet: true);
    final hand = play(director, Duration.zero, ms(3000), (pose) => pose.hand);
    expect(
      [for (final (_, state) in hand) state],
      [
        CompanionHand.rest,
        CompanionHand.lift,
        CompanionHand.point,
        CompanionHand.lift,
        CompanionHand.rest,
      ],
    );
    expect(hand[1].$1, lessThanOrEqualTo(ms(900)));
  });

  test('a citation brings the next point forward', () {
    director
      ..start(Duration.zero)
      ..setMood(CompanionMood.talking, Duration.zero);
    // The first point comes early in an answer, then not for five seconds.
    final first = play(director, Duration.zero, ms(5000), (p) => p.hand);
    expect(first.last.$2, CompanionHand.rest);

    director.emphasize(ms(5000));
    final next = play(director, ms(5000), ms(6000), (p) => p.hand);
    expect(next[1].$2, CompanionHand.lift);
    expect(next[1].$1, lessThanOrEqualTo(ms(5400)));
  });

  test('thinks with a raised hand, breathing faster', () {
    director
      ..start(Duration.zero)
      ..setMood(CompanionMood.thinking, Duration.zero);
    expect(director.pose.hand, CompanionHand.lift);
    final hop = play(director, Duration.zero, ms(2500), (pose) => pose.hop);
    expect([for (final (_, value) in hop) value], [0, 1, 0, 1, 0]);
    expect(hop[1].$1, ms(600));
    expect(director.pose.hand, CompanionHand.lift);
  });

  test('breathes slowly while idle', () {
    director.start(Duration.zero);
    final hop = play(director, Duration.zero, ms(5000), (pose) => pose.hop);
    expect([for (final (_, value) in hop) value], [0, 1, 0, 1, 0]);
    expect(hop[1].$1, ms(1200));
  });
}
