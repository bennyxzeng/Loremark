import 'dart:convert';
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
    await store.save('book', 'c1', [exchange(1), exchange(2, cutOff: true)]);
    final loaded = await AskHistoryStore(temp).load('book', 'c1');
    expect([for (final e in loaded) e.question], ['Q1', 'Q2']);
    expect(loaded.first.answer, 'A1 [s1/p0001]');
    expect(loaded.first.limit, const TextPosition(1, 0.5));
    expect(loaded.first.askedAt, DateTime.utc(2026, 11, 9, 12, 1));
    expect(loaded.first.cutOff, isFalse);
    expect(loaded.last.cutOff, isTrue);
    expect(loaded.last.turn.answer, 'A2 [s1/p0001]');
  });

  test('keeps each book and each conversation apart', () async {
    await store.save('one', 'c1', [exchange(1)]);
    await store.save('one', 'c2', [exchange(2)]);
    expect(await store.load('two', 'c1'), isEmpty);
    expect(await store.list('two'), isEmpty);
    expect([for (final e in await store.load('one', 'c2')) e.question], ['Q2']);
  });

  test('lists a book\'s conversations, the latest first', () async {
    await store.save('book', 'early', [exchange(1), exchange(5)]);
    await store.save('book', 'late', [exchange(3), exchange(4), exchange(7)]);
    await store.save('book', 'middle', [exchange(6)]);
    final listed = await store.list('book');
    expect([for (final c in listed) c.id], ['late', 'middle', 'early']);
    expect(listed.first.title, 'Q3');
    expect(listed.first.length, 3);
    expect(listed.first.updatedAt, DateTime.utc(2026, 11, 9, 12, 7));
  });

  test('keeps only the latest of a conversation', () async {
    await store.save('book', 'c1', [
      for (var n = 0; n < maxKeptExchanges + 5; n++) exchange(n),
    ]);
    final loaded = await store.load('book', 'c1');
    expect(loaded, hasLength(maxKeptExchanges));
    expect(loaded.first.question, 'Q5');
  });

  test(
    'a file it can\'t read is an empty conversation, and not listed',
    () async {
      await store.save('book', 'good', [exchange(1)]);
      final file = store.file('book', 'broken');
      for (final broken in [
        'not json',
        '[]',
        '{"version":2,"exchanges":[]}',
        '{"version":1,"exchanges":[{"question":1}]}',
        '{"version":1}',
        '{"version":1,"exchanges":[]}',
      ]) {
        file.writeAsStringSync(broken);
        expect(await store.load('book', 'broken'), isEmpty, reason: broken);
        expect(
          [for (final c in await store.list('book')) c.id],
          ['good'],
          reason: broken,
        );
      }
    },
  );

  test('a half-written file isn\'t a conversation', () async {
    await store.save('book', 'c1', [exchange(1)]);
    File('${store.folder('book').path}/c2.json.tmp').writeAsStringSync('{');
    expect([for (final c in await store.list('book')) c.id], ['c1']);
  });

  group('the one conversation a book had before', () {
    File single(String bookId) =>
        File('${temp.path}/chats/$bookId.json')
          ..parent.createSync(recursive: true);

    String saved(List<AskExchange> exchanges) => jsonEncode({
      'version': 1,
      'exchanges': [for (final e in exchanges) e.toJson()],
    });

    test('becomes a conversation of its own, once', () async {
      single('book').writeAsStringSync(saved([exchange(1), exchange(2)]));
      final listed = await store.list('book');
      expect(listed, hasLength(1));
      expect(listed.single.id, AskHistoryStore.newId(exchange(1).askedAt));
      expect(
        [for (final e in listed.single.exchanges) e.question],
        ['Q1', 'Q2'],
      );
      expect(single('book').existsSync(), isFalse);
      expect(await store.list('book'), hasLength(1));
    });

    test('sits beside newer conversations', () async {
      await store.save('book', 'c9', [exchange(9)]);
      single('book').writeAsStringSync(saved([exchange(1)]));
      expect(await store.list('book'), hasLength(2));
    });

    test('is left alone if it can\'t be read', () async {
      single('book').writeAsStringSync('{"version":2}');
      expect(await store.list('book'), isEmpty);
      expect(single('book').existsSync(), isTrue);
    });
  });

  test('forgets a conversation', () async {
    await store.save('book', 'c1', [exchange(1)]);
    await store.save('book', 'c2', [exchange(2)]);
    await store.delete('book', 'c1');
    expect(await store.load('book', 'c1'), isEmpty);
    expect([for (final c in await store.list('book')) c.id], ['c2']);
    await store.delete('book', 'c1');
  });

  test('forgets every conversation about a book, old ones too', () async {
    await store.save('book', 'c1', [exchange(1)]);
    await store.save('other', 'c1', [exchange(1)]);
    File('${temp.path}/chats/book.json').writeAsStringSync('{"version":2}');
    await store.deleteBook('book');
    expect(store.folder('book').existsSync(), isFalse);
    expect(File('${temp.path}/chats/book.json').existsSync(), isFalse);
    expect(await store.list('other'), hasLength(1));
    await store.deleteBook('book');
  });

  test('new ids are valid and differ by time', () {
    final a = AskHistoryStore.newId(DateTime.utc(2026, 11, 9, 12));
    final b = AskHistoryStore.newId(DateTime.utc(2026, 11, 9, 12, 0, 1));
    expect(a, isNot(b));
    expect(() => store.file('book', a), returnsNormally);
  });

  test('never builds a path from a strange id', () {
    expect(() => store.folder('../escape'), throwsArgumentError);
    expect(() => store.file('book', '../escape'), throwsArgumentError);
    expect(() => store.file('../escape', 'c1'), throwsArgumentError);
  });
}
