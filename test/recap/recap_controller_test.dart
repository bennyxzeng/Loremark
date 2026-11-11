import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/recap/recap_backend.dart';
import 'package:loremark/recap/recap_client.dart';
import 'package:loremark/recap/recap_controller.dart';
import 'package:loremark/recap/recap_source.dart';
import 'package:loremark/settings/ai_settings.dart';
import 'package:loremark/story_update/story_store.dart';

import 'recap_test_book.dart';

const _credentials = AiCredentials(
  provider: AiProvider.deepseek,
  apiKey: 'sk-test',
);

/// A source for a reader [paragraphs] paragraphs into chapter 2.
RecapSource _sourceAt(int paragraphs) => RecapSource(
  sectionTitle: 'Chapter 2: The Letter',
  sectionLabel: 'Chapter 2',
  partway: true,
  place: (finished: 1, paragraphsRead: paragraphs, revision: 2),
  events: const [],
  characters: const [],
  openQuestions: const [],
  recentText: 'Mara reads the letter by the quay.',
);

Recap _recapOf(RecapSource source) => Recap(
  items: const [
    RecapItem(
      title: 'Mara reaches the harbor.',
      summary: 'She comes looking for work.',
      chapter: 'Chapter 1',
    ),
  ],
  stopsAt: source.stopsAt,
  place: source.place,
);

/// Answers each look at the reader's place, and each recap, when told to.
class _Backend implements RecapBackend {
  final looks = <Completer<RecapStart>>[];
  final recaps = <Completer<RecapResult>>[];
  final asked = <RecapSource>[];

  @override
  Future<RecapStart> prepare(Book book) {
    final look = Completer<RecapStart>();
    looks.add(look);
    return look.future;
  }

  @override
  Future<RecapResult> recap(RecapSource source, AiCredentials credentials) {
    asked.add(source);
    final answer = Completer<RecapResult>();
    recaps.add(answer);
    return answer.future;
  }
}

void main() {
  late _Backend backend;
  late RecapController controller;

  setUp(() {
    backend = _Backend();
    controller = RecapController(book: recapTestBook, backend: backend);
  });

  tearDown(() => controller.dispose());

  /// Finds the reader at [start].
  Future<void> lookAt(RecapStart start) async {
    final looking = controller.prepare();
    backend.looks.last.complete(start);
    await looking;
  }

  /// Writes a recap of the current source, answered with [result] or a recap
  /// of it.
  Future<void> writeRecap([RecapResult? result]) async {
    final writing = controller.write(_credentials);
    backend.recaps.last.complete(
      result ?? RecapReady(_recapOf(controller.source!)),
    );
    await writing;
  }

  test('nothing is sent until a recap is asked for', () async {
    await lookAt(RecapCanStart(_sourceAt(2)));

    expect(controller.prepared, isTrue);
    expect(controller.source?.place.paragraphsRead, 2);
    expect(backend.recaps, isEmpty);
  });

  test('with nothing read, no recap and no request', () async {
    await lookAt(const RecapNeedsReading());
    await controller.write(_credentials);

    expect(controller.start, isA<RecapNeedsReading>());
    expect(controller.source, isNull);
    expect(controller.recap, isNull);
    expect(backend.asked, isEmpty);
  });

  test('without a Story Map, no recap and no request', () async {
    await lookAt(const RecapNeedsStoryMap());
    await controller.write(_credentials);

    expect(controller.start, isA<RecapNeedsStoryMap>());
    expect(backend.asked, isEmpty);
  });

  test(
    'after turning back, the recap ends earlier, never the old one',
    () async {
      await lookAt(RecapCanStart(_sourceAt(4)));
      await writeRecap();
      expect(controller.recap?.place.paragraphsRead, 4);

      await lookAt(RecapCanStart(_sourceAt(2)));

      expect(controller.recap, isNull);
      expect(controller.source?.place.paragraphsRead, 2);
      await writeRecap();
      expect(backend.asked.last.place.paragraphsRead, 2);
    },
  );

  test('in the same place, the recap stays', () async {
    await lookAt(RecapCanStart(_sourceAt(2)));
    await writeRecap();
    final recap = controller.recap;

    await lookAt(RecapCanStart(_sourceAt(2)));

    expect(controller.recap, same(recap));
  });

  test('text that can’t be read ends in an error, with no recap', () async {
    await lookAt(RecapCanStart(_sourceAt(2)));
    await writeRecap();

    final looking = controller.prepare();
    backend.looks.last.completeError(const StoryStoreError('missing text'));
    await looking;
    await controller.write(_credentials);

    expect(controller.prepareError, isNotNull);
    expect(controller.source, isNull);
    expect(controller.recap, isNull);
    expect(backend.asked, hasLength(1));
  });

  test('a slower, older look can’t replace a newer one', () async {
    final older = controller.prepare();
    final newer = controller.prepare();

    backend.looks.last.complete(RecapCanStart(_sourceAt(3)));
    await newer;
    backend.looks.first.complete(RecapCanStart(_sourceAt(1)));
    await older;

    expect(controller.source?.place.paragraphsRead, 3);
    expect(controller.preparing, isFalse);
  });

  group('writing', () {
    setUp(() => lookAt(RecapCanStart(_sourceAt(2))));

    test('one request at a time', () async {
      final writing = controller.write(_credentials);
      unawaited(controller.write(_credentials));

      expect(controller.writing, isTrue);
      expect(backend.recaps, hasLength(1));

      backend.recaps.single.complete(RecapReady(_recapOf(_sourceAt(2))));
      await writing;

      expect(controller.writing, isFalse);
      expect(controller.recap, isNotNull);
      expect(controller.error, isNull);
    });

    test('a failure keeps the last recap and says why', () async {
      await writeRecap();
      final recap = controller.recap;

      await writeRecap(const RecapFailed('DeepSeek is busy.'));

      expect(controller.recap, same(recap));
      expect(controller.error, 'DeepSeek is busy.');
    });

    test('an answer after the book closes is dropped quietly', () async {
      final writing = controller.write(_credentials);
      controller.dispose();
      // Replaced so tearDown has something to dispose.
      controller = RecapController(book: recapTestBook, backend: _Backend());

      backend.recaps.single.complete(RecapReady(_recapOf(_sourceAt(2))));
      await expectLater(writing, completes);
    });
  });
}
