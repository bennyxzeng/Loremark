import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/epub_reader_service.dart';
import 'package:loremark/search/snippet.dart';

/// The matches of [word] in [text], all for the same query part.
List<TextMatch> matchesOf(String text, String word, {int key = 0}) => [
  for (final m in RegExp(RegExp.escape(word)).allMatches(text))
    TextMatch(m.start, m.end, key),
];

void main() {
  group('buildSnippet', () {
    test('shows a short paragraph whole', () {
      const text = 'Ryn walked in with a lamp.';
      final snippet = buildSnippet(text, matchesOf(text, 'lamp'));
      expect(snippet.text, text);
      expect(snippet.spans.map((s) => (s.start, s.end)), [(21, 25)]);
      expect(snippet.focusStart, 21);
    });

    test('cuts a long paragraph to a window around the match', () {
      final filler = List.filled(50, 'word').join(' ');
      final text = '$filler lamp $filler';
      final snippet = buildSnippet(text, matchesOf(text, 'lamp'));
      expect(snippet.text, startsWith('…'));
      expect(snippet.text, endsWith('…'));
      expect(snippet.text.length, lessThanOrEqualTo(snippetWidth + 2 * 25 + 2));
      final span = snippet.spans.single;
      expect(snippet.text.substring(span.start, span.end), 'lamp');
      // The match is near the middle of the window.
      final middle = (span.start + span.end) / 2;
      expect((middle - snippet.text.length / 2).abs(), lessThan(40));
    });

    test('does not cut words in half', () {
      final text = List.generate(80, (i) => 'abcdefghij$i').join(' ');
      final snippet = buildSnippet(text, matchesOf(text, 'abcdefghij40'));
      final words = snippet.text.replaceAll('…', '').trim().split(' ');
      expect(
        words.every((w) => RegExp(r'^abcdefghij\d+$').hasMatch(w)),
        isTrue,
      );
    });

    test('has no ellipsis on the side that reaches the paragraph edge', () {
      final filler = List.filled(60, 'word').join(' ');
      final text = 'lamp $filler';
      final snippet = buildSnippet(text, matchesOf(text, 'lamp'));
      expect(snippet.text, startsWith('lamp'));
      expect(snippet.text, endsWith('…'));
    });

    test('prefers the window with the most different query parts', () {
      final filler = List.filled(40, 'nothing here').join(' ');
      final text = 'alpha $filler alpha $filler alpha beta $filler';
      final matches = [
        ...matchesOf(text, 'alpha', key: 0),
        ...matchesOf(text, 'beta', key: 1),
      ];
      final snippet = buildSnippet(text, matches);
      expect(snippet.text, contains('alpha beta'));
      expect(snippet.spans, hasLength(2));
    });

    test('prefers a window that starts a sentence', () {
      final filler = List.filled(12, 'quiet').join(' ');
      final text =
          '$filler lamp $filler. The lamp $filler is on $filler plain end.';
      final snippet = buildSnippet(text, matchesOf(text, 'lamp'));
      expect(snippet.text, contains('lamp'));
    });

    test('merges overlapping and touching matches', () {
      const text = 'abcdef';
      final snippet = buildSnippet(text, [
        const TextMatch(0, 3, 0),
        const TextMatch(2, 4, 0),
        const TextMatch(4, 6, 1),
      ]);
      expect(snippet.spans.map((s) => (s.start, s.end)), [(0, 6)]);
    });

    test('shows line breaks as spaces without moving offsets', () {
      const text = 'first\nsecond lamp';
      final snippet = buildSnippet(text, matchesOf(text, 'lamp'));
      expect(snippet.text, 'first second lamp');
      expect(snippet.spans.single.start, 13);
    });

    test('uses a narrower window for Chinese', () {
      final text = '${'的' * 200}克莱恩${'的' * 200}';
      final snippet = buildSnippet(text, matchesOf(text, '克莱恩'));
      expect(snippet.text.length, lessThan(snippetWidthCjk + 10));
      expect(snippet.text, contains('克莱恩'));
    });

    test('keeps surrogate pairs whole', () {
      final text = '\u{20000}' * 300;
      final snippet = buildSnippet(text, [const TextMatch(300, 302, 0)]);
      for (var i = 0; i < snippet.text.length; i++) {
        final unit = snippet.text.codeUnitAt(i);
        if (unit >= 0xD800 && unit <= 0xDBFF) {
          expect(i + 1 < snippet.text.length, isTrue);
          expect(snippet.text.codeUnitAt(i + 1) & 0xFC00, 0xDC00);
          i++;
        } else {
          expect(unit == 0x2026 || unit < 0xD800, isTrue);
        }
      }
    });

    test('no matches gives the start of the paragraph and no spans', () {
      final text = 'word ' * 100;
      final snippet = buildSnippet(text, const []);
      expect(snippet.spans, isEmpty);
      expect(snippet.text, text.replaceAll('\n', ' '));
    });

    test('random matches always give consistent spans', () {
      final random = Random(7);
      for (var trial = 0; trial < 200; trial++) {
        final text = List.generate(
          1 + random.nextInt(120),
          (_) => ['lamp', 'ship', 'x', 'harbor', 'ünï'][random.nextInt(5)],
        ).join(random.nextBool() ? ' ' : ', ');
        final found = [
          ...matchesOf(text, 'lamp', key: 0),
          ...matchesOf(text, 'ship', key: 1),
        ];
        final snippet = buildSnippet(text, found);
        var end = 0;
        for (final span in snippet.spans) {
          expect(span.start, greaterThanOrEqualTo(end));
          expect(span.end, greaterThan(span.start));
          expect(span.end, lessThanOrEqualTo(snippet.text.length));
          expect(
            snippet.text.substring(span.start, span.end),
            matches(r'^(lamp|ship)+$'),
          );
          end = span.end;
        }
        final inner = snippet.text.replaceAll('…', '');
        expect(text.replaceAll('\n', ' '), contains(inner.trim()));
      }
    });
  });

  group('buildPassageTarget', () {
    PassageTarget check(String section, String word, {int? visible}) {
      final at = section.indexOf(word);
      final paragraphStart = section.lastIndexOf('\n\n', at) + 2;
      var paragraphEnd = section.indexOf('\n\n', at);
      if (paragraphEnd == -1) paragraphEnd = section.length;
      final target = buildPassageTarget(
        sectionIndex: 3,
        sectionText: section,
        paragraphStart: paragraphStart,
        paragraphEnd: paragraphEnd,
        matchStart: at,
        matchEnd: at + word.length,
        visibleEnd: visible ?? section.length,
      );
      return target;
    }

    final long =
        'The old keeper of the harbor walked slowly along the quay, past the '
        'nets and the lamps and the sleeping gulls, until he reached the '
        'place where the dragon had first been seen by the fishermen.';
    final section = 'Before.\n\n$long\n\nAfter the paragraph there is more.';

    test('quotes between 40 and 120 characters of one line', () {
      final c = check(section, 'dragon');
      expect(c.highlight.length, inInclusiveRange(40, 120));
      expect(c.highlight, contains('dragon'));
      expect(c.highlight.contains('\n'), isFalse);
      expect(long, contains(c.highlight));
    });

    test('cuts at word boundaries', () {
      final h = check(section, 'dragon').highlight;
      expect(h, matches(r'^\S.*\S$'));
      final at = section.indexOf(h);
      expect(section[at - 1], anyOf(' ', '\n'));
      expect(section[at + h.length], anyOf(' ', '\n', ',', '.'));
    });

    test('context is adjacent text of at most 32 characters', () {
      final c = check(section, 'dragon');
      expect(c.before.length, lessThanOrEqualTo(32));
      expect(c.after.length, lessThanOrEqualTo(32));
      expect(section, contains(c.before + c.highlight + c.after));
      expect(c.before.length, 32);
    });

    test('progression is where the quote starts in the section', () {
      final c = check(section, 'dragon');
      expect(
        c.progression,
        closeTo(section.indexOf(c.highlight) / section.length, 1e-12),
      );
      expect(c.sectionIndex, 3);
    });

    test('a short line is quoted whole', () {
      const text = 'First.\n\n"Ryn?" he asked.\n\nLast.';
      final c = check(text, 'Ryn');
      expect(c.highlight, '"Ryn?" he asked.');
    });

    test('an overlong match is cut to 120 characters', () {
      final text = 'start ${List.filled(60, 'longword').join(' ')} end';
      final target = buildPassageTarget(
        sectionIndex: 0,
        sectionText: text,
        paragraphStart: 0,
        paragraphEnd: text.length,
        matchStart: 6,
        matchEnd: text.length - 4,
        visibleEnd: text.length,
      );
      expect(target.highlight.length, inInclusiveRange(40, 120));
    });

    test('a match at the start or end of a line still reaches 40', () {
      final text = 'lamp ${'x' * 5} ${List.filled(20, 'word').join(' ')} end';
      final atStart = buildPassageTarget(
        sectionIndex: 0,
        sectionText: text,
        paragraphStart: 0,
        paragraphEnd: text.length,
        matchStart: 0,
        matchEnd: 4,
        visibleEnd: text.length,
      );
      expect(atStart.highlight.length, inInclusiveRange(40, 120));
      expect(atStart.before, isEmpty);
      final atEnd = buildPassageTarget(
        sectionIndex: 0,
        sectionText: text,
        paragraphStart: 0,
        paragraphEnd: text.length,
        matchStart: text.length - 3,
        matchEnd: text.length,
        visibleEnd: text.length,
      );
      expect(atEnd.highlight.length, inInclusiveRange(40, 120));
      expect(atEnd.after, isEmpty);
    });

    test('stays on the line of the match when the paragraph has line breaks', () {
      final text =
          'First line of the verse is long enough to be a quote on its own.\n'
          'Second line also runs on for a while and mentions the dragon here.\n'
          'Third line.';
      final c = check(text, 'dragon');
      expect(c.highlight.contains('\n'), isFalse);
      expect(c.highlight, contains('dragon'));
    });

    test('context never reaches past the visible text', () {
      // The reader has passed only up to the end of the long paragraph.
      final end = section.indexOf('\n\nAfter');
      final c = check(section, 'been seen by', visible: end);
      expect(c.after.length, lessThan(32));
      expect(section.substring(0, end), contains(c.highlight + c.after));
    });
  });
}
