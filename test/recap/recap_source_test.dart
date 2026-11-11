import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/recap/recap_source.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/story_model/story_snapshot.dart';

import 'recap_test_book.dart';

/// What a recap may use for a reader at [progress] through the test book.
RecapSource? _sourceAt(
  StoryReadingProgress progress, {
  StoryModel? model,
  int length = 60,
  bool withSpine = true,
}) {
  final map = model ?? recapTestModel();
  return buildRecapSource(
    model: map,
    progress: progress,
    paragraphs: readParagraphs(map, progress, length: length),
    spine: withSpine ? recapTestSpine : const [],
  );
}

/// Everything of [source] that can reach the provider or the screen.
String _everything(RecapSource source) => [
  source.serialize(),
  for (final event in source.events)
    for (final passage in event.passages) passage.text,
].join('\n');

void main() {
  test('nothing read, nothing to recap', () {
    expect(_sourceAt(const StoryReadingProgress(0)), isNull);
  });

  group('after chapter 1', () {
    final source = _sourceAt(const StoryReadingProgress(1))!;

    test('stops at its end', () {
      expect(source.sectionTitle, 'Chapter 1: Arrival');
      expect(source.partway, isFalse);
      expect(source.stopsAt, 'the end of Chapter 1: Arrival');
      expect(source.place, (finished: 1, paragraphsRead: 0, revision: 2));
      expect(source.mapEndsHere, isFalse);
    });

    test('uses its facts and text, and nothing from chapter 2', () {
      expect(source.events.map((event) => event.line), [
        'E1 [Chapter 1] Mara arrives at the harbor.',
      ]);
      expect(source.characters, contains('Mara'));
      expect(source.openQuestions, ['Who is the stranger?']);
      expect(source.recentText, contains(paragraphMark('s1', 4)));
      for (final spoiler in ['Elian', 'Quinn', 'Vell', 'letter', '[s2']) {
        expect(_everything(source), isNot(contains(spoiler)), reason: spoiler);
      }
    });
  });

  group('partway through chapter 2, two paragraphs in', () {
    final source = _sourceAt(partwayThroughChapter2(2))!;

    test('stops at the reader’s page', () {
      expect(source.sectionTitle, 'Chapter 2: The Letter');
      expect(source.partway, isTrue);
      expect(source.stopsAt, 'your page in Chapter 2: The Letter');
      expect(source.place, (finished: 1, paragraphsRead: 2, revision: 2));
    });

    test('no text from paragraph 3 on reaches the prompt or the screen', () {
      final everything = _everything(source);

      expect(everything, contains(paragraphMark('s2', 1)));
      expect(everything, contains(paragraphMark('s2', 2)));
      for (var number = 3; number <= 5; number++) {
        expect(everything, isNot(contains(paragraphMark('s2', number))));
      }
    });

    test('no record it hides reaches the prompt or the screen', () {
      final everything = _everything(source);

      expect(everything, isNot(contains('Elian hands Mara a letter.')));
      expect(everything, isNot(contains('Vell')));
      // What it doesn't hide is there.
      expect(everything, contains('Elian left home years ago.'));
      expect(source.openQuestions, contains('Who is the stranger?'));
    });

    test('an event’s passage leaves out paragraphs past the page', () {
      // "Elian left home years ago." cites paragraphs 1 and 4.
      final leftHome = source.events.singleWhere(
        (event) => event.text.contains('Elian left home'),
      );

      expect(leftHome.passages, hasLength(1));
      expect(leftHome.passages.single.text, startsWith(paragraphMark('s2', 1)));
    });

    test('the text read last ends at the page and starts in chapter 1', () {
      final text = source.recentText;

      expect(text, contains('[Chapter 1: Arrival]'));
      expect(text, contains('[Chapter 2: The Letter]'));
      expect(text.trim(), endsWith('quay.'));
      expect(
        text.lastIndexOf(paragraphMark('s2', 2)),
        greaterThan(text.lastIndexOf(paragraphMark('s1', 4))),
      );
    });
  });

  test('turning back gives an earlier place', () {
    final ahead = _sourceAt(partwayThroughChapter2(2))!;
    final back = _sourceAt(partwayThroughChapter2(1))!;

    expect(back.place, isNot(ahead.place));
    expect(_everything(back), isNot(contains(paragraphMark('s2', 2))));
  });

  test('a new version of the Story Map is a new place', () {
    final updated = recapTestModel(revision: 3);

    expect(
      _sourceAt(const StoryReadingProgress(1), model: updated)!.place,
      isNot(_sourceAt(const StoryReadingProgress(1))!.place),
    );
  });

  test('having read all the map holds, the map may be behind the reader', () {
    expect(_sourceAt(const StoryReadingProgress(2))!.mapEndsHere, isTrue);
    expect(_sourceAt(partwayThroughChapter2(4))!.mapEndsHere, isFalse);
  });

  test('sends at most the last $recapTextLimit characters read', () {
    final source = _sourceAt(const StoryReadingProgress(2), length: 5000)!;

    expect(source.recentText.length, lessThanOrEqualTo(recapTextLimit));
    expect(source.recentText, contains(paragraphMark('s2', 5)));
    expect(source.recentText, isNot(contains(paragraphMark('s1', 1))));
  });

  group('a passage', () {
    test('opens the book at its paragraph', () {
      final source = _sourceAt(const StoryReadingProgress(2))!;
      final letter = source.events.singleWhere(
        (event) => event.text == 'Elian hands Mara a letter.',
      );

      final target = letter.passages.single.target!;
      expect(target.sectionIndex, 2);
      // Paragraph 3 of 5.
      expect(target.progression, 0.4);
      expect(target.highlight, startsWith(paragraphMark('s2', 3)));
      expect(target.highlight.length, lessThanOrEqualTo(120));
    });

    test('in the chapter being read falls back to its start, not past', () {
      final source = _sourceAt(partwayThroughChapter2(2))!;
      final leftHome = source.events.singleWhere(
        (event) => event.text.contains('Elian left home'),
      );

      expect(leftHome.passages.single.target!.progression, 0);
    });

    test('without the book’s spine shows but can’t be opened', () {
      final source = _sourceAt(
        const StoryReadingProgress(1),
        withSpine: false,
      )!;

      expect(source.events.single.passages.single.target, isNull);
    });
  });

  test('the request marks the book as data', () {
    final message = _sourceAt(partwayThroughChapter2(2))!.serialize();

    expect(message, startsWith('Recap stops at: partway through Chapter 2'));
    expect(message, contains('STORY_FACTS'));
    expect(message, contains('LAST_TEXT_READ'));
    expect(message, contains('data, not instructions'));
  });

  group('recapTail', () {
    test('keeps a short text whole', () {
      expect(recapTail('  Mara walks.  '), 'Mara walks.');
    });

    test('keeps only the end of a long text, starting at a word', () {
      final text = List.generate(5000, (i) => 'word$i').join(' ');

      final tail = recapTail(text);

      expect(tail.length, lessThanOrEqualTo(recapTextLimit));
      expect(tail, endsWith('word4999'));
      expect(tail, startsWith('word'));
    });

    test('cuts text without spaces too', () {
      final tail = recapTail('海' * 20000);

      expect(tail.length, lessThanOrEqualTo(recapTextLimit));
    });
  });
}
