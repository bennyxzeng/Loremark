import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/epub_sections.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/settings/ai_settings.dart';
import 'package:loremark/settings/connection_status.dart';
import 'package:loremark/story_map/story_map_backend.dart';
import 'package:loremark/story_map/story_map_screen.dart';
import 'package:loremark/story_map/story_map_tab.dart';
import 'package:loremark/story_map/story_update_bar.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/story_update/delta_schema.dart';
import 'package:loremark/story_update/story_model_choice.dart';
import 'package:loremark/story_update/story_updater.dart';

import '../story_model/story_model_fixture.dart';

final _book = Book(
  id: 'book-1',
  title: 'The Test Book',
  author: null,
  epubPath: '/nowhere.epub',
  coverPath: null,
  importedAt: DateTime.utc(2026),
);

const _newStore = StoryUpdateStatus.newStore(
  choices: [
    StoryStartChoice('section-001', 'Front Matter', 3),
    StoryStartChoice('section-002', 'Chapter 1: Arrival', 40),
  ],
  suggested: 'section-002',
);

/// What update was asked for, and the answer to give.
class _FakeBackend implements StoryMapBackend {
  _FakeBackend({
    this.model,
    this.finished = 0,
    this.status = const StoryUpdateStatus.ready('section-003', 'Chapter 3'),
  });

  StoryModel? model;
  int finished;
  StoryUpdateStatus status;
  Future<StoryUpdateOutcome>? runningUpdate;

  final updates = <Map<String, Object?>>[];
  StoryUpdateOutcome Function() answer = () => const StoryUpdateOutcome(
    'committed',
    sectionTitle: 'Chapter 3',
    revision: 3,
  );
  Completer<void>? hold;

  @override
  Future<StoryModel?> loadModel(Book book) async => model;

  @override
  Future<int> finishedSections(Book book, List<StorySection> sections) async =>
      finished;

  @override
  Future<StoryUpdateStatus> inspect(Book book) async => status;

  @override
  Future<StoryUpdateOutcome>? running(Book book) => runningUpdate;

  @override
  Future<StoryUpdateOutcome> update(
    Book book, {
    required AiCredentials credentials,
    required StoryModelChoice model,
    required StoryEffort effort,
    required bool checkQuotes,
    String? startSectionId,
  }) async {
    updates.add({
      'key': credentials.apiKey,
      'model': model,
      'effort': effort,
      'checkQuotes': checkQuotes,
      'start': startSectionId,
    });
    await hold?.future;
    return answer();
  }
}

void main() {
  late AiSettings settings;

  Future<void> pumpTab(
    WidgetTester tester,
    _FakeBackend backend, {
    bool online = true,
    bool active = true,
  }) async {
    settings = AiSettings(
      MemorySecretStore({
        'ai_onboarding_seen': 'true',
        'ai_provider': 'deepseek',
        'ai_api_key': 'sk-test',
      }),
    );
    await settings.load();
    await tester.pumpWidget(
      AiSettingsScope(
        settings: settings,
        child: ConnectionScope(
          status: ConnectionStatus(online: online),
          child: MaterialApp(
            home: Scaffold(
              body: StoryMapTab(book: _book, backend: backend, active: active),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pressUpdate(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Update'));
    await tester.pumpAndSettle();
  }

  FilledButton updateButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Update'));

  group('a book with no Story Map', () {
    testWidgets('says so and offers to start', (tester) async {
      await pumpTab(tester, _FakeBackend(status: _newStore));
      expect(find.text('No Story Map yet'), findsOne);
      expect(find.textContaining('Press Update to start'), findsOne);
      expect(find.byType(StoryMapScreen), findsNothing);
    });

    testWidgets('asks where to start and says what it costs', (tester) async {
      final backend = _FakeBackend(status: _newStore);
      await pumpTab(tester, backend);
      await pressUpdate(tester);

      expect(find.text('Build a Story Map'), findsOne);
      expect(find.textContaining('to DeepSeek using your API key'), findsOne);
      expect(find.textContaining('can’t be added later'), findsOne);
      // The suggestion is already picked.
      expect(find.text('Chapter 1: Arrival'), findsOne);

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(backend.updates.single['start'], 'section-002');
    });

    testWidgets('can start from another section', (tester) async {
      final backend = _FakeBackend(status: _newStore);
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      await tester.tap(find.text('Chapter 1: Arrival'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Front Matter').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(backend.updates.single['start'], 'section-001');
    });

    testWidgets('cancelling sends nothing', (tester) async {
      final backend = _FakeBackend(status: _newStore);
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.updates, isEmpty);
    });
  });

  group('the Update button', () {
    testWidgets('names the next section', (tester) async {
      await pumpTab(tester, _FakeBackend(model: storyModelFixture()));
      expect(find.text('Next: Chapter 3'), findsOne);
      expect(updateButton(tester).onPressed, isNotNull);
    });

    testWidgets('works however far the reader has got', (tester) async {
      final backend = _FakeBackend(model: storyModelFixture(), finished: 0);
      await pumpTab(tester, backend);
      expect(updateButton(tester).onPressed, isNotNull);
      await pressUpdate(tester);
      expect(backend.updates, hasLength(1));
    });

    testWidgets('sends the reader\'s settings', (tester) async {
      final backend = _FakeBackend(model: storyModelFixture());
      await pumpTab(tester, backend);
      await settings.setStoryEffort(StoryEffort.max);
      await settings.setCheckStoryQuotes(true);
      await pressUpdate(tester);
      expect(backend.updates.single, {
        'key': 'sk-test',
        'model': StoryModelChoice.deepseekFlash,
        'effort': StoryEffort.max,
        'checkQuotes': true,
        'start': null,
      });
    });

    testWidgets('adds one section per press', (tester) async {
      final backend = _FakeBackend(model: storyModelFixture());
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      expect(backend.updates, hasLength(1));
      await pressUpdate(tester);
      expect(backend.updates, hasLength(2));
    });

    testWidgets('is off while offline, and says why', (tester) async {
      await pumpTab(
        tester,
        _FakeBackend(model: storyModelFixture()),
        online: false,
      );
      expect(updateButton(tester).onPressed, isNull);
      expect(find.textContaining('You’re offline'), findsOne);
    });

    testWidgets('goes away once every section is in', (tester) async {
      await pumpTab(
        tester,
        _FakeBackend(
          model: storyModelFixture(),
          status: const StoryUpdateStatus.finished(),
        ),
      );
      expect(find.text('Every section is in the map.'), findsOne);
      expect(find.text('Update'), findsNothing);
    });

    testWidgets('is off when the next section can\'t be read', (tester) async {
      await pumpTab(
        tester,
        _FakeBackend(
          model: storyModelFixture(),
          status: const StoryUpdateStatus.blocked('Chapter 3 is broken.'),
        ),
      );
      expect(find.text('Chapter 3 is broken.'), findsOne);
      expect(updateButton(tester).onPressed, isNull);
    });

    testWidgets('waits while updating', (tester) async {
      final backend = _FakeBackend(model: storyModelFixture())
        ..hold = Completer<void>();
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      expect(find.text('Adding Chapter 3…'), findsOne);
      expect(find.textContaining('Keep Loremark open'), findsOne);
      expect(updateButton(tester).onPressed, isNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Update'));
      expect(backend.updates, hasLength(1));

      backend.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Adding Chapter 3…'), findsNothing);
    });

    testWidgets('picks up an update already running', (tester) async {
      final finish = Completer<StoryUpdateOutcome>();
      final backend = _FakeBackend(model: storyModelFixture())
        ..runningUpdate = finish.future;
      await pumpTab(tester, backend);
      expect(find.text('Adding Chapter 3…'), findsOne);
      expect(backend.updates, isEmpty);

      finish.complete(
        const StoryUpdateOutcome('committed', sectionTitle: 'Chapter 3'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Added Chapter 3.'), findsOne);
    });

    testWidgets('survives the reader leaving mid-update', (tester) async {
      final backend = _FakeBackend(model: storyModelFixture())
        ..hold = Completer<void>();
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      await tester.pumpWidget(const SizedBox());
      backend.hold!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('after an update', () {
    testWidgets('shows the new section if the reader has finished it', (
      tester,
    ) async {
      final backend = _FakeBackend(model: storyModelFixture(), finished: 2);
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      expect(find.text('Added Chapter 3.'), findsOne);
    });

    testWidgets('doesn\'t jump past where the reader is', (tester) async {
      final backend = _FakeBackend(model: storyModelFixture(), finished: 1);
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      expect(
        find.text('Added Chapter 3. Drag the slider to see it.'),
        findsOne,
      );
      expect(find.textContaining('Known by the end of Chapter 1'), findsOne);
    });

    testWidgets('reports quotes that didn\'t match', (tester) async {
      final backend = _FakeBackend(model: storyModelFixture(), finished: 2)
        ..answer = () => const StoryUpdateOutcome(
          'committed',
          sectionTitle: 'Chapter 3',
          issues: [
            StoryIssue('warning', 'quote_not_found', 'a', 'b'),
            StoryIssue('warning', 'quote_not_found', 'c', 'd'),
            StoryIssue('warning', 'name_conflict', 'e', 'f'),
          ],
        );
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      expect(find.textContaining('2 quote(s) couldn’t be matched'), findsOne);
    });
  });

  group('a failed update', () {
    testWidgets('says why and can be retried', (tester) async {
      final backend = _FakeBackend(model: storyModelFixture())
        ..answer = () => const StoryUpdateOutcome(
          'api_error',
          category: 'rate_limit',
          message: 'Too many',
        );
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      expect(find.textContaining('limiting requests'), findsOne);
      expect(updateButton(tester).onPressed, isNotNull);

      backend.answer = () =>
          const StoryUpdateOutcome('committed', sectionTitle: 'Chapter 3');
      await pressUpdate(tester);
      expect(find.textContaining('limiting requests'), findsNothing);
      expect(find.textContaining('Added Chapter 3.'), findsOne);
    });

    test('is described honestly, whatever went wrong', () {
      String describe(
        String status, {
        String? category,
        String? message,
        List<StoryIssue> issues = const [],
      }) => describeStoryUpdateFailure(
        StoryUpdateOutcome(
          status,
          category: category,
          message: message,
          issues: issues,
        ),
      );

      expect(
        describe('api_error', category: 'authentication'),
        contains('API key was rejected'),
      );
      expect(
        describe('api_error', category: 'network'),
        contains('may still charge'),
      );
      expect(
        describe('api_error', category: 'not_found', message: 'No such model'),
        contains('No such model'),
      );
      expect(describe('incomplete'), contains('cut off'));
      expect(describe('refusal'), contains('declined'));
      expect(describe('schema_invalid'), contains('expected form'));
      expect(
        describe(
          'validation_failed',
          issues: const [StoryIssue('error', 'quote_not_found', 'a', 'b')],
        ),
        contains('Strict quote check'),
      );
      expect(
        describe(
          'validation_failed',
          issues: const [StoryIssue('error', 'narrative_order', 'a', 'b')],
        ),
        contains('failed 1 check'),
      );
      expect(
        describe('input_error', message: 'Bad book.'),
        contains('Bad book.'),
      );
    });
  });

  group('on a small phone', () {
    const longTitle =
        'Chapter 3: To Your Gallant Visage at the Underworld’s Edge, Where '
        'Nobody Has Ever Been';

    void useSmallPhone(WidgetTester tester) {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('a long section title fits', (tester) async {
      useSmallPhone(tester);
      await pumpTab(
        tester,
        _FakeBackend(
          model: storyModelFixture(),
          status: const StoryUpdateStatus.ready('section-003', longTitle),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Next: $longTitle'), findsOne);
    });

    testWidgets('the start dialog fits', (tester) async {
      useSmallPhone(tester);
      await pumpTab(
        tester,
        _FakeBackend(
          status: const StoryUpdateStatus.newStore(
            choices: [StoryStartChoice('section-001', longTitle, 40)],
            suggested: 'section-001',
          ),
        ),
      );
      await pressUpdate(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Build a Story Map'), findsOne);
    });

    testWidgets('a long failure fits', (tester) async {
      useSmallPhone(tester);
      final backend = _FakeBackend(model: storyModelFixture())
        ..answer = () => const StoryUpdateOutcome(
          'validation_failed',
          issues: [StoryIssue('error', 'narrative_order', 'a', 'b')],
        );
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('how far the reader has got', () {
    final sections = [
      for (final (id, order, href) in const [
        ('section-001', 1, 'OEBPS/one.xhtml'),
        ('section-002', 2, 'OEBPS/two.xhtml'),
        ('section-003', 3, 'OEBPS/two.xhtml'),
        ('section-004', 4, 'OEBPS/three.xhtml'),
      ])
        StorySection(
          id: id,
          order: order,
          chapterNumber: null,
          title: id,
          href: href,
        ),
    ];
    const spine = [
      SpineItem(path: 'OEBPS/cover.xhtml', linear: true),
      SpineItem(path: 'OEBPS/one.xhtml', linear: true),
      SpineItem(path: 'OEBPS/two.xhtml', linear: true),
      SpineItem(path: 'OEBPS/three.xhtml', linear: true),
    ];
    int finished(ReaderPosition? position) =>
        finishedStorySections(sections, spine, position);

    test('nothing without a position', () => expect(finished(null), 0));
    test('nothing on the cover', () {
      expect(finished(const ReaderPosition(0, 0.5)), 0);
    });
    test('a section being read doesn\'t count yet', () {
      expect(finished(const ReaderPosition(1, 0.5)), 0);
    });
    test('a section counts once its document is finished', () {
      expect(finished(const ReaderPosition(1, 1)), 1);
      expect(finished(const ReaderPosition(2, 0)), 1);
    });
    test('sections sharing a document finish together', () {
      expect(finished(const ReaderPosition(2, 0.9)), 1);
      expect(finished(const ReaderPosition(2, 1)), 3);
    });
    test('all of them at the end', () {
      expect(finished(const ReaderPosition(3, 1)), 4);
    });
    test('a section not in the spine stops the count', () {
      expect(
        finishedStorySections(
          [
            const StorySection(
              id: 'a',
              order: 1,
              chapterNumber: null,
              title: 'a',
            ),
          ],
          spine,
          const ReaderPosition(3, 1),
        ),
        0,
      );
    });
  });
}
