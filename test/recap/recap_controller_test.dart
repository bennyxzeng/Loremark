import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/recap/recap_backend.dart';
import 'package:loremark/recap/recap_client.dart';
import 'package:loremark/recap/recap_controller.dart';
import 'package:loremark/recap/recap_source.dart';
import 'package:loremark/settings/ai_settings.dart';

final _book = Book(
  id: 'book-1',
  title: 'The Glass Harbor',
  author: null,
  epubPath: '/nowhere.epub',
  coverPath: null,
  importedAt: DateTime.utc(2026),
);

const _credentials = AiCredentials(
  provider: AiProvider.deepseek,
  apiKey: 'sk-test',
);

RecapSource _sourceThrough(String label) => RecapSource(
  cutoffLabel: label,
  events: const [],
  characters: const [],
  openQuestions: const [],
  sectionText: 'Mara walks along the quay.',
);

const _recap = Recap(
  items: [
    RecapItem(
      title: 'Mara reaches the harbor.',
      summary: 'She comes looking for work.',
      chapter: 'Chapter 1',
    ),
  ],
  cutoffLabel: 'Chapter 1',
  usedStoryMap: false,
);

/// Answers each look at the reader's place, and each recap, when told to.
class _Backend implements RecapBackend {
  final looks = <Completer<RecapSource?>>[];
  final recaps = <Completer<RecapResult>>[];

  @override
  Future<RecapSource?> prepare(Book book) {
    final look = Completer<RecapSource?>();
    looks.add(look);
    return look.future;
  }

  @override
  Future<RecapResult> recap(RecapSource source, AiCredentials credentials) {
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
    controller = RecapController(book: _book, backend: backend);
  });

  tearDown(() => controller.dispose());

  test('nothing is sent until a recap is asked for', () async {
    final looking = controller.prepare();
    backend.looks.single.complete(_sourceThrough('Chapter 1'));
    await looking;

    expect(controller.prepared, isTrue);
    expect(controller.source?.cutoffLabel, 'Chapter 1');
    expect(backend.recaps, isEmpty);
  });

  test('a slower, older look can’t replace a newer one', () async {
    final older = controller.prepare();
    final newer = controller.prepare();

    backend.looks.last.complete(_sourceThrough('Chapter 2'));
    await newer;
    backend.looks.first.complete(_sourceThrough('Chapter 1'));
    await older;

    expect(controller.source?.cutoffLabel, 'Chapter 2');
    expect(controller.preparing, isFalse);
  });

  test('a book that can’t be read says so', () async {
    final looking = controller.prepare();
    backend.looks.single.completeError(const FormatException('bad zip'));
    await looking;

    expect(controller.source, isNull);
    expect(controller.prepareError, contains('couldn’t read this book'));
  });

  test('without a finished section, there is nothing to write', () async {
    await controller.write(_credentials);

    expect(backend.recaps, isEmpty);
  });

  group('writing', () {
    setUp(() async {
      final looking = controller.prepare();
      backend.looks.single.complete(_sourceThrough('Chapter 1'));
      await looking;
    });

    test('one request at a time', () async {
      final writing = controller.write(_credentials);
      unawaited(controller.write(_credentials));

      expect(controller.writing, isTrue);
      expect(backend.recaps, hasLength(1));

      backend.recaps.single.complete(const RecapReady(_recap));
      await writing;

      expect(controller.writing, isFalse);
      expect(controller.recap, same(_recap));
      expect(controller.error, isNull);
    });

    test('a failure keeps the last recap and says why', () async {
      var writing = controller.write(_credentials);
      backend.recaps.last.complete(const RecapReady(_recap));
      await writing;

      writing = controller.write(_credentials);
      backend.recaps.last.complete(const RecapFailed('DeepSeek is busy.'));
      await writing;

      expect(controller.recap, same(_recap));
      expect(controller.error, 'DeepSeek is busy.');
    });

    test('an answer after the book closes is dropped quietly', () async {
      final writing = controller.write(_credentials);
      controller.dispose();
      // Replaced so tearDown has something to dispose.
      controller = RecapController(book: _book, backend: _Backend());

      backend.recaps.single.complete(const RecapReady(_recap));
      await expectLater(writing, completes);
    });
  });
}
