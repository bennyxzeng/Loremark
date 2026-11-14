import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/recap/recap_backend.dart';
import 'package:loremark/recap/recap_controller.dart';
import 'package:loremark/recap/recap_stop.dart';

import 'recap_test_book.dart';

RecapCanStart _stoppedIn(String sectionTitle) =>
    RecapCanStart(RecapStop(sectionTitle: sectionTitle, partway: true));

/// Answers each look at the reader's place when told to.
class _Backend implements RecapBackend {
  final looks = <Completer<RecapStart>>[];

  @override
  Future<RecapStart> prepare(Book book) {
    final look = Completer<RecapStart>();
    looks.add(look);
    return look.future;
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

  test('says where the reader stopped', () async {
    var heard = 0;
    controller.addListener(() => heard++);

    final looking = controller.prepare();
    expect(controller.prepared, isFalse);
    backend.looks.single.complete(_stoppedIn('Chapter 2: The Letter'));
    await looking;

    expect(controller.prepared, isTrue);
    expect(controller.stop?.sectionTitle, 'Chapter 2: The Letter');
    expect(heard, 1);
  });

  test('with nothing to recap, has no stop', () async {
    final looking = controller.prepare();
    backend.looks.single.complete(const RecapNeedsReading());
    await looking;

    expect(controller.start, isA<RecapNeedsReading>());
    expect(controller.stop, isNull);
  });

  test('a Story Map that can\'t be read offers nothing', () async {
    final looking = controller.prepare();
    backend.looks.single.completeError(const FormatException('bad map'));
    await looking;

    expect(controller.prepared, isTrue);
    expect(controller.stop, isNull);
  });

  test('a slower, older look can\'t replace a newer one', () async {
    final older = controller.prepare();
    final newer = controller.prepare();

    backend.looks.last.complete(_stoppedIn('Chapter 2: The Letter'));
    await newer;
    backend.looks.first.complete(_stoppedIn('Chapter 1: Arrival'));
    await older;

    expect(controller.stop?.sectionTitle, 'Chapter 2: The Letter');
  });

  test('a look that ends after the book closes is dropped quietly', () async {
    final looking = controller.prepare();
    controller.dispose();
    // Replaced so tearDown has something to dispose.
    controller = RecapController(book: recapTestBook, backend: _Backend());

    backend.looks.single.complete(_stoppedIn('Chapter 1: Arrival'));
    await expectLater(looking, completes);
  });
}
