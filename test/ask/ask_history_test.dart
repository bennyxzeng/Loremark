import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/ask/ask_history.dart';
import 'package:loremark/reading/text_position.dart';

void main() {
  late Directory temp;
  late AskHistoryStore store;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('ask_history_');
    store = AskHistoryStore(temp);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  AskExchange exchange(int n, {bool cutOff = false}) => AskExchange(
    question: 'Q$n',
    answer: 'A$n [s1/p0001]',
    limit: TextPosition(n, 0.5),
    askedAt: DateTime.utc(2026, 11, 9, 12, n),
    cutOff: cutOff,
  );

  test('keeps a conversation across restarts', () async {
    await store.save('book', [exchange(1), exchange(2, cutOff: true)]);
    final loaded = await AskHistoryStore(temp).load('book');
    expect([for (final e in loaded) e.question], ['Q1', 'Q2']);
    expect(loaded.first.answer, 'A1 [s1/p0001]');
    expect(loaded.first.limit, const TextPosition(1, 0.5));
    expect(loaded.first.askedAt, DateTime.utc(2026, 11, 9, 12, 1));
    expect(loaded.first.cutOff, isFalse);
    expect(loaded.last.cutOff, isTrue);
    expect(loaded.last.turn.limit, const TextPosition(2, 0.5));
  });

  test('keeps each book apart', () async {
    await store.save('one', [exchange(1)]);
    expect(await store.load('two'), isEmpty);
  });

  test('keeps only the latest', () async {
    await store.save('book', [
      for (var n = 0; n < maxKeptExchanges + 5; n++) exchange(n),
    ]);
    final loaded = await store.load('book');
    expect(loaded, hasLength(maxKeptExchanges));
    expect(loaded.first.question, 'Q5');
  });

  test('a file it can\'t read is an empty conversation', () async {
    final file = store.file('book')..parent.createSync(recursive: true);
    for (final broken in [
      'not json',
      '[]',
      '{"version":2,"exchanges":[]}',
      '{"version":1,"exchanges":[{"question":1}]}',
      '{"version":1}',
    ]) {
      file.writeAsStringSync(broken);
      expect(await store.load('book'), isEmpty, reason: broken);
    }
  });

  test('forgets a conversation', () async {
    await store.save('book', [exchange(1)]);
    await store.delete('book');
    expect(await store.load('book'), isEmpty);
    await store.delete('book');
  });

  test('never builds a path from a strange id', () {
    expect(() => store.file('../escape'), throwsArgumentError);
  });
}
