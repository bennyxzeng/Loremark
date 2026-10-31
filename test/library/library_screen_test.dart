import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/book_screen.dart';
import 'package:loremark/library/book_repository.dart';
import 'package:loremark/main.dart';

import 'test_epub.dart';

void main() {
  late Directory temp;
  late BookRepository repository;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('loremark_library_');
    repository = BookRepository(Directory('${temp.path}/library'));
  });

  tearDown(() => temp.delete(recursive: true));

  /// Writes an EPUB to disk; file input and output must run outside the
  /// widget test's fake clock.
  Future<String> writeEpub(WidgetTester tester, String title) async {
    final file = File('${temp.path}/$title.epub');
    await tester.runAsync(
      () => file.writeAsBytes(buildEpub(title: title, cover: CoverStyle.none)),
    );
    return file.path;
  }

  /// Lets real file work started by the app finish, pumping frames so its
  /// callbacks run, until [done].
  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(done(), isTrue, reason: 'timed out');
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(WidgetTester tester, {String? picked}) async {
    await tester.pumpWidget(
      LoremarkApp(
        repository: Future.value(repository),
        pickEpub: () async => picked,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an empty library offers to import', (tester) async {
    await pumpApp(tester);

    expect(find.text('Books'), findsOne);
    expect(find.text('Import EPUB'), findsOne);
  });

  testWidgets('the first import opens the book', (tester) async {
    final path = await writeEpub(tester, 'The Glass Harbor');
    await pumpApp(tester, picked: path);

    await tester.tap(find.text('Import EPUB'));
    await waitFor(tester, () => find.byType(BookScreen).evaluate().isNotEmpty);

    expect(repository.books, hasLength(1));
    expect(find.text('CURRENTLY READING'), findsOne);

    // Opening saves the book as last opened; let that write finish so the
    // temporary folder can be deleted.
    var saved = false;
    repository.saved.then((_) => saved = true);
    await waitFor(tester, () => saved);
  });

  testWidgets('cancelling the picker changes nothing', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Import EPUB'));
    await tester.pumpAndSettle();

    expect(repository.books, isEmpty);
    expect(find.byType(BookScreen), findsNothing);
  });

  testWidgets('resumes the last book and returns to the library', (
    tester,
  ) async {
    final path = await writeEpub(tester, 'The Glass Harbor');
    await tester.runAsync(() async {
      final (:book, isNew: _) = await repository.importEpub(path);
      await repository.markOpened(book);
    });

    await pumpApp(tester);
    expect(find.byType(BookScreen), findsOne);

    await tester.tap(find.text('CURRENTLY READING'));
    await tester.pumpAndSettle();

    expect(find.byType(BookScreen), findsNothing);
    expect(find.text('LAST OPENED'), findsOne);
    expect(find.text('The Glass Harbor'), findsOne);
  });
}
