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
import 'package:loremark/story_model/story_snapshot.dart';
import 'package:loremark/story_update/delta_schema.dart';
import 'package:loremark/story_update/story_import.dart';
import 'package:loremark/story_update/story_model_choice.dart';
import 'package:loremark/story_update/story_paragraphs.dart';
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
    StorySectionChoice('section-001', 'Front Matter', 3),
    StorySectionChoice('section-002', 'Chapter 1: Arrival', 40),
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
  RunningStoryUpdate? runningUpdate;

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
  Future<StoryReadingProgress> readingProgress(
    Book book,
    List<StorySection> sections,
  ) async => StoryReadingProgress(finished, hiddenInNext: hiddenInNext);

  /// What the reader hasn't reached of the section they are partway through.
  Set<String>? hiddenInNext;

  @override
  Future<StoryParagraphs> paragraphs(
    Book book,
    StoryReadingProgress progress,
  ) async => StoryParagraphs(const {});

  @override
  Future<StoryUpdateStatus> inspect(Book book) async => status;

  @override
  RunningStoryUpdate? running(Book book) => runningUpdate;

  var cancels = 0;

  /// What cancelling does to the update under way.
  void Function()? onCancel;

  @override
  void cancelUpdate(Book book) {
    cancels++;
    onCancel?.call();
  }

  @override
  Future<StoryUpdateOutcome> update(
    Book book, {
    required AiCredentials credentials,
    required StoryModelChoice model,
    required StoryEffort effort,
    required bool checkQuotes,
    String? sectionId,
  }) async {
    updates.add({
      'key': credentials.apiKey,
      'model': model,
      'effort': effort,
      'checkQuotes': checkQuotes,
      'section': sectionId,
    });
    await hold?.future;
    return answer();
  }

  StoryExportOutcome Function() exportAnswer = () => StoryExportOutcome.saved;
  Completer<void>? holdFiles;
  var exports = 0;

  /// The file the reader picks, or null if they back out.
  String? picked = '/picked.zip';
  Object? stageError;
  StagedStoryImport staged = const StagedStoryImport(
    path: '/staging',
    revision: 2,
    sectionCount: 2,
    viewOnly: false,
  );

  /// The map that committing puts in place.
  StoryModel? imported;
  final stagedPaths = <String>[];
  var commits = 0;
  var discards = 0;

  @override
  Future<StoryExportOutcome> exportFiles(Book book) async {
    exports++;
    await holdFiles?.future;
    return exportAnswer();
  }

  @override
  Future<String?> pickStoryFile() async => picked;

  @override
  Future<StagedStoryImport> stageImport(Book book, String path) async {
    stagedPaths.add(path);
    await holdFiles?.future;
    if (stageError != null) throw stageError!;
    return staged;
  }

  @override
  Future<void> commitImport(Book book, StagedStoryImport staged) async {
    commits++;
    model = imported ?? model;
  }

  @override
  Future<void> discardImport(StagedStoryImport staged) async => discards++;

  /// Whether the reader closed the intro before. True unless a test says
  /// otherwise, so the other tests don't see it.
  bool seenIntro = true;

  @override
  Future<bool> introSeen() async => seenIntro;

  @override
  Future<void> markIntroSeen() async => seenIntro = true;
}

/// A map whose store can't be read.
class _BrokenMapBackend extends _FakeBackend {
  @override
  Future<StoryModel?> loadModel(Book book) async => throw StateError('Damaged');
}

void main() {
  late AiSettings settings;

  Future<void> pumpTab(
    WidgetTester tester,
    _FakeBackend backend, {
    bool online = true,
    bool active = true,
    bool hasKey = true,
  }) async {
    settings = AiSettings(
      MemorySecretStore({
        'ai_onboarding_seen': 'true',
        if (hasKey) ...{'ai_provider': 'deepseek', 'ai_api_key': 'sk-test'},
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

  FilledButton cancelButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Cancel'));

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
      expect(backend.updates.single['section'], 'section-002');
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
      expect(backend.updates.single['section'], 'section-001');
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
        'section': null,
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

    testWidgets('turns into Cancel while updating', (tester) async {
      final backend = _FakeBackend(model: storyModelFixture())
        ..hold = Completer<void>();
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      expect(find.text('Adding Chapter 3…'), findsOne);
      expect(find.textContaining('Keep Loremark open'), findsOne);
      expect(find.widgetWithText(FilledButton, 'Update'), findsNothing);
      expect(cancelButton(tester).onPressed, isNotNull);
      expect(backend.updates, hasLength(1));

      backend.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Adding Chapter 3…'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Cancel'), findsNothing);
      expect(updateButton(tester).onPressed, isNotNull);
    });

    testWidgets('picks up an update already running', (tester) async {
      final finish = Completer<StoryUpdateOutcome>();
      final backend = _FakeBackend(model: storyModelFixture())
        ..runningUpdate = RunningStoryUpdate(
          finish.future,
          DateTime.now(),
          null,
        );
      await pumpTab(tester, backend);
      expect(find.text('Adding Chapter 3…'), findsOne);
      expect(backend.updates, isEmpty);

      finish.complete(
        const StoryUpdateOutcome('committed', sectionTitle: 'Chapter 3'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Added Chapter 3 in '), findsOne);
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

  group('cancelling an update', () {
    /// A backend with an update under way, which cancelling ends as cancelled.
    _FakeBackend cancellable() {
      final backend = _FakeBackend(model: storyModelFixture())
        ..hold = Completer<void>();
      return backend
        ..onCancel = () {
          backend.answer = () => const StoryUpdateOutcome(
            'cancelled',
            category: 'cancelled',
            sectionTitle: 'Chapter 3',
          );
          backend.hold!.complete();
        };
    }

    Future<void> pressCancel(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel'));
      await tester.pumpAndSettle();
    }

    testWidgets('asks first, and keeping on changes nothing', (tester) async {
      final backend = cancellable();
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      await pressCancel(tester);
      expect(find.text('Cancel this update?'), findsOne);
      expect(find.textContaining('may still charge'), findsOne);

      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();
      expect(backend.cancels, 0);
      expect(find.text('Adding Chapter 3…'), findsOne);
      expect(cancelButton(tester).onPressed, isNotNull);

      backend.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Added Chapter 3 in '), findsOne);
    });

    testWidgets('stops it, and says what that cost', (tester) async {
      final backend = cancellable();
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      await pressCancel(tester);
      await tester.tap(find.text('Cancel update'));
      await tester.pumpAndSettle();

      expect(backend.cancels, 1);
      expect(
        find.textContaining(
          RegExp(
            r'^Cancelled after 0:0\d\. Nothing was saved, but your provider '
            r'may still charge for it\.$',
          ),
        ),
        findsOne,
      );
      // Not shown as a failure, since the reader asked for it.
      final notice = tester.widget<Text>(find.textContaining('Cancelled'));
      expect(
        notice.style?.color,
        isNot(
          Theme.of(tester.element(find.byType(StoryMapTab))).colorScheme.error,
        ),
      );
      expect(find.text('Adding Chapter 3…'), findsNothing);
      expect(updateButton(tester).onPressed, isNotNull);
    });

    testWidgets('waits, unpressable, until it has stopped', (tester) async {
      final backend = cancellable();
      // Cancelling takes a moment to land.
      final stop = backend.onCancel!;
      backend.onCancel = () {};
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      await pressCancel(tester);
      await tester.tap(find.text('Cancel update'));
      await tester.pumpAndSettle();

      expect(find.text('Cancelling…'), findsOne);
      expect(cancelButton(tester).onPressed, isNull);

      stop();
      await tester.pumpAndSettle();
      expect(find.text('Cancelling…'), findsNothing);
      expect(find.textContaining('Cancelled after'), findsOne);
    });

    testWidgets('that had already been answered keeps it', (tester) async {
      final backend = cancellable()..onCancel = null;
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      await pressCancel(tester);
      await tester.tap(find.text('Cancel update'));
      await tester.pumpAndSettle();
      expect(find.text('Cancelling…'), findsOne);

      // The answer was in before the cancel landed.
      backend.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Added Chapter 3 in '), findsOne);
      expect(find.text('Cancelling…'), findsNothing);
      expect(updateButton(tester).onPressed, isNotNull);
    });

    testWidgets('works on one found running on coming back', (tester) async {
      final finish = Completer<StoryUpdateOutcome>();
      final backend = _FakeBackend(model: storyModelFixture())
        ..runningUpdate = RunningStoryUpdate(
          finish.future,
          DateTime.now(),
          null,
        )
        ..onCancel = () => finish.complete(
          const StoryUpdateOutcome('cancelled', category: 'cancelled'),
        );
      await pumpTab(tester, backend);
      await pressCancel(tester);
      await tester.tap(find.text('Cancel update'));
      await tester.pumpAndSettle();
      expect(backend.cancels, 1);
      expect(find.textContaining('Cancelled after'), findsOne);
    });

    testWidgets('does nothing if the update ends while it asks', (
      tester,
    ) async {
      final backend = cancellable();
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      await pressCancel(tester);
      backend.hold!.complete();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel update'));
      await tester.pumpAndSettle();
      expect(backend.cancels, 0);
      expect(find.textContaining('Added Chapter 3 in '), findsOne);
      expect(find.text('Cancelling…'), findsNothing);
    });

    testWidgets('the dialog fits a small phone', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final backend = cancellable();
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      await pressCancel(tester);
      expect(find.text('Cancel this update?'), findsOne);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Keep going'));
      backend.hold!.complete();
      await tester.pumpAndSettle();
    });
  });

  group('after an update', () {
    testWidgets('shows the new section if the reader has finished it', (
      tester,
    ) async {
      final backend = _FakeBackend(model: storyModelFixture(), finished: 2);
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      expect(find.textContaining('Added Chapter 3 in '), findsOne);
      expect(find.textContaining('Drag the slider'), findsNothing);
    });

    testWidgets('doesn\'t jump past where the reader is', (tester) async {
      final backend = _FakeBackend(model: storyModelFixture(), finished: 1);
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      expect(find.textContaining('Drag the slider to see it.'), findsOne);
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
      expect(find.textContaining('Added Chapter 3 in '), findsOne);
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
          issues: const [
            StoryIssue('error', 'narrative_order', 'a', '3 is repeated'),
          ],
        ),
        allOf(
          contains('failed 1 check: 3 is repeated.'),
          contains('may still charge'),
          contains('Update again'),
        ),
      );
      expect(
        describe(
          'validation_failed',
          issues: const [
            StoryIssue('warning', 'empty_delta', 'a', 'not this one'),
            StoryIssue('error', 'narrative_order', 'a', '3 is repeated'),
            StoryIssue('error', 'dangling_reference', 'b', 'not this one'),
          ],
        ),
        contains('failed 2 checks. The first: 3 is repeated.'),
      );
      expect(
        describe('input_error', message: 'Bad book.'),
        contains('Bad book.'),
      );
    });
  });

  group('choosing a section', () {
    const severalChoices = StoryUpdateStatus.ready(
      'section-003',
      'Chapter 3',
      choices: [
        StorySectionChoice('section-003', 'Chapter 3', 40),
        StorySectionChoice(
          'section-004',
          'Interlude',
          10,
          skips: ['Chapter 3'],
        ),
        StorySectionChoice(
          'section-005',
          'Chapter 4',
          40,
          skips: ['Chapter 3', 'Interlude'],
        ),
      ],
    );
    const dialogTitle = 'Choose a section';
    final chooseButton = find.widgetWithText(TextButton, 'Choose');

    _FakeBackend backendWithChoices() =>
        _FakeBackend(model: storyModelFixture(), status: severalChoices);

    TextButton choose(WidgetTester tester) =>
        tester.widget<TextButton>(chooseButton);

    Future<void> pressChoose(WidgetTester tester) async {
      await tester.tap(chooseButton);
      await tester.pumpAndSettle();
    }

    Future<void> pick(WidgetTester tester, String title) async {
      await tester.tap(find.byType(DropdownButton<StorySectionChoice>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(title).last);
      await tester.pumpAndSettle();
    }

    testWidgets('isn\'t offered with nothing to choose from', (tester) async {
      await pumpTab(tester, _FakeBackend(model: storyModelFixture()));
      expect(chooseButton, findsNothing);
    });

    testWidgets('isn\'t offered for a new map, which asks anyway', (
      tester,
    ) async {
      await pumpTab(tester, _FakeBackend(status: _newStore));
      expect(chooseButton, findsNothing);
    });

    testWidgets('leaves Update one press, with no dialog', (tester) async {
      final backend = backendWithChoices();
      await pumpTab(tester, backend);
      expect(chooseButton, findsOne);
      await pressUpdate(tester);
      expect(find.text(dialogTitle), findsNothing);
      expect(backend.updates.single['section'], isNull);
    });

    testWidgets('starts at the next section and warns of nothing', (
      tester,
    ) async {
      final backend = backendWithChoices();
      await pumpTab(tester, backend);
      await pressChoose(tester);
      expect(find.text(dialogTitle), findsOne);
      expect(find.textContaining('This skips'), findsNothing);
      await tester.tap(find.text('Add section'));
      await tester.pumpAndSettle();
      expect(backend.updates.single['section'], 'section-003');
    });

    testWidgets('says what a later section leaves out, then adds it', (
      tester,
    ) async {
      final backend = backendWithChoices();
      await pumpTab(tester, backend);
      await pressChoose(tester);

      await pick(tester, 'Interlude');
      expect(
        find.text('This skips 1 section: Chapter 3. It can’t be added later.'),
        findsOne,
      );
      await pick(tester, 'Chapter 4');
      expect(
        find.text(
          'This skips 2 sections: Chapter 3, Interlude. They can’t be added '
          'later.',
        ),
        findsOne,
      );

      await tester.tap(find.text('Add section'));
      await tester.pumpAndSettle();
      expect(backend.updates.single['section'], 'section-005');
    });

    testWidgets('cancelling sends nothing', (tester) async {
      final backend = backendWithChoices();
      await pumpTab(tester, backend);
      await pressChoose(tester);
      await pick(tester, 'Chapter 4');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.updates, isEmpty);
      expect(find.text('Next: Chapter 3'), findsOne);
    });

    testWidgets('names the chosen section while it runs', (tester) async {
      final backend = backendWithChoices()..hold = Completer<void>();
      await pumpTab(tester, backend);
      await pressChoose(tester);
      await pick(tester, 'Chapter 4');
      await tester.tap(find.text('Add section'));
      await tester.pumpAndSettle();

      expect(find.text('Adding Chapter 4…'), findsOne);
      expect(choose(tester).onPressed, isNull);
      expect(cancelButton(tester).onPressed, isNotNull);

      backend.hold!.complete();
      await tester.pumpAndSettle();
      expect(choose(tester).onPressed, isNotNull);
    });

    testWidgets('finds the chosen section again on coming back', (
      tester,
    ) async {
      final finish = Completer<StoryUpdateOutcome>();
      final backend = backendWithChoices()
        ..runningUpdate = RunningStoryUpdate(
          finish.future,
          DateTime.now(),
          'section-005',
        );
      await pumpTab(tester, backend);
      expect(find.text('Adding Chapter 4…'), findsOne);
      finish.complete(const StoryUpdateOutcome('input_error'));
      await tester.pumpAndSettle();
    });

    testWidgets('is off while offline', (tester) async {
      await pumpTab(tester, backendWithChoices(), online: false);
      expect(choose(tester).onPressed, isNull);
    });

    testWidgets('gets past a section that can\'t be read', (tester) async {
      final backend = _FakeBackend(
        model: storyModelFixture(),
        status: const StoryUpdateStatus.blocked(
          'Chapter 3 cannot be read reliably.',
          choices: [
            StorySectionChoice(
              'section-004',
              'Chapter 4',
              40,
              skips: ['Chapter 3'],
            ),
          ],
        ),
      );
      await pumpTab(tester, backend);
      expect(find.text('Chapter 3 cannot be read reliably.'), findsOne);
      expect(updateButton(tester).onPressed, isNull);
      expect(choose(tester).onPressed, isNotNull);

      await pressChoose(tester);
      expect(find.textContaining('This skips 1 section: Chapter 3'), findsOne);
      await tester.tap(find.text('Add section'));
      await tester.pumpAndSettle();
      expect(backend.updates.single['section'], 'section-004');
    });

    testWidgets('fits a small phone', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const long =
          'Chapter 3: To Your Gallant Visage at the Underworld’s Edge, Where '
          'Nobody Has Ever Been';
      await pumpTab(
        tester,
        _FakeBackend(
          model: storyModelFixture(),
          status: StoryUpdateStatus.ready(
            'section-003',
            long,
            choices: [
              const StorySectionChoice('section-003', long, 40),
              StorySectionChoice(
                'section-009',
                'Chapter 9',
                40,
                skips: [for (var i = 0; i < 6; i++) long],
              ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await pressChoose(tester);
      expect(tester.takeException(), isNull);
      await pick(tester, 'Chapter 9');
      expect(tester.takeException(), isNull);
    });
  });

  group('the timer', () {
    test('reads as minutes and seconds', () {
      String format(int seconds) =>
          formatStoryElapsed(Duration(seconds: seconds));
      expect(format(0), '0:00');
      expect(format(9), '0:09');
      expect(format(65), '1:05');
      expect(format(171), '2:51');
      expect(format(900), '15:00');
      expect(formatStoryElapsed(const Duration(seconds: -5)), '0:00');
    });

    testWidgets('counts up by the clock while updating', (tester) async {
      final started = DateTime.utc(2026);
      var now = started;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StoryUpdateBar(
              status: const StoryUpdateStatus.ready('s', 'Chapter 3'),
              online: true,
              hasKey: true,
              onUpdate: () {},
              onCancel: () {},
              onChoose: () {},
              onLoad: () {},
              onExport: () {},
              updateStartedAt: started,
              now: () => now,
            ),
          ),
        ),
      );
      expect(find.textContaining('0:00 elapsed.'), findsOne);

      now = started.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('0:01 elapsed.'), findsOne);

      // Held back for a while, it shows the real time rather than one more tick.
      now = started.add(const Duration(seconds: 171));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('2:51 elapsed.'), findsOne);
    });

    testWidgets('shows real time on coming back to a running update', (
      tester,
    ) async {
      final finish = Completer<StoryUpdateOutcome>();
      final backend = _FakeBackend(model: storyModelFixture())
        ..runningUpdate = RunningStoryUpdate(
          finish.future,
          DateTime.now().subtract(const Duration(seconds: 125)),
          null,
        );
      await pumpTab(tester, backend);
      expect(find.textContaining(RegExp(r'^2:0[5-9] elapsed\.')), findsOne);

      finish.complete(
        const StoryUpdateOutcome('committed', sectionTitle: 'Chapter 3'),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(RegExp(r'^Added Chapter 3 in 2:0[5-9]\.')),
        findsOne,
      );
    });

    testWidgets('stops once the update is done', (tester) async {
      final backend = _FakeBackend(model: storyModelFixture())
        ..hold = Completer<void>();
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      expect(find.textContaining('elapsed.'), findsOne);
      expect(find.textContaining('Keep Loremark open'), findsOne);

      backend.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('elapsed.'), findsNothing);
      // Nothing keeps ticking: this settles, and no timer is left pending.
      await tester.pump(const Duration(seconds: 5));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a failure says how long it took too', (tester) async {
      final backend = _FakeBackend(model: storyModelFixture())
        ..answer = () =>
            const StoryUpdateOutcome('api_error', category: 'timeout');
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      expect(
        find.textContaining(RegExp(r'may still charge for it\. Took 0:0\d\.')),
        findsOne,
      );
    });

    testWidgets('fits a small phone with both buttons', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final backend = _FakeBackend(
        model: storyModelFixture(),
        status: const StoryUpdateStatus.ready(
          's3',
          'A Very Long Chapter Title That Goes On And On And On',
          choices: [
            StorySectionChoice('s3', 'A', 1),
            StorySectionChoice('s4', 'B', 1),
          ],
        ),
      )..hold = Completer<void>();
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      expect(tester.takeException(), isNull);
      backend.hold!.complete();
      await tester.pumpAndSettle();
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
            choices: [StorySectionChoice('section-001', longTitle, 40)],
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
          issues: [
            StoryIssue(
              'error',
              'evidence_outside_section',
              'a',
              'Evidence cites "section-003"; it must come from section-004, '
                  'the section this item was learned in',
            ),
            StoryIssue('error', 'narrative_order', 'a', 'b'),
          ],
        );
      await pumpTab(tester, backend);
      await pressUpdate(tester);
      expect(find.textContaining('it must come from'), findsOne);
      expect(tester.takeException(), isNull);
    });
  });

  group('the files menu', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Story Map files'));
      await tester.pumpAndSettle();
    }

    Future<void> pick(WidgetTester tester, String item) async {
      await openMenu(tester);
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    bool menuEnabled(WidgetTester tester) => tester
        .widget<PopupMenuButton<VoidCallback>>(
          find.byType(PopupMenuButton<VoidCallback>),
        )
        .enabled;

    testWidgets('offers loading and exporting', (tester) async {
      await pumpTab(tester, _FakeBackend(model: storyModelFixture()));
      await openMenu(tester);
      expect(find.text('Load from file…'), findsOne);
      expect(find.text('Export files…'), findsOne);
    });

    testWidgets('is there with no map', (tester) async {
      await pumpTab(tester, _FakeBackend(status: _newStore));
      expect(menuEnabled(tester), isTrue);
    });

    testWidgets('is there when every section is in the map', (tester) async {
      await pumpTab(
        tester,
        _FakeBackend(
          model: storyModelFixture(),
          status: const StoryUpdateStatus.finished(),
        ),
      );
      expect(find.text('Update'), findsNothing);
      expect(menuEnabled(tester), isTrue);
    });

    testWidgets('waits for an update, which it can’t overlap', (tester) async {
      final backend = _FakeBackend(model: storyModelFixture())
        ..hold = Completer<void>();
      await pumpTab(tester, backend);
      await tester.tap(find.widgetWithText(FilledButton, 'Update'));
      await tester.pump();
      await tester.pump();
      expect(menuEnabled(tester), isFalse);

      backend.hold!.complete();
      await tester.pumpAndSettle();
      expect(menuEnabled(tester), isTrue);
    });

    group('exporting', () {
      testWidgets('says when it’s done', (tester) async {
        final backend = _FakeBackend(model: storyModelFixture());
        await pumpTab(tester, backend);
        await pick(tester, 'Export files…');
        expect(backend.exports, 1);
        expect(find.text('Exported.'), findsOne);
      });

      testWidgets('says nothing if the reader backs out', (tester) async {
        final backend = _FakeBackend(model: storyModelFixture())
          ..exportAnswer = () => StoryExportOutcome.cancelled;
        await pumpTab(tester, backend);
        await pick(tester, 'Export files…');
        expect(find.text('Exported.'), findsNothing);
        expect(find.textContaining('Preparing'), findsNothing);
      });

      testWidgets('says when there’s nothing yet', (tester) async {
        final backend = _FakeBackend(status: _newStore)
          ..exportAnswer = () => StoryExportOutcome.nothing;
        await pumpTab(tester, backend);
        await pick(tester, 'Export files…');
        expect(find.text('Nothing to export yet.'), findsOne);
      });

      testWidgets('says if it fails', (tester) async {
        final backend = _FakeBackend(model: storyModelFixture())
          ..exportAnswer = () => throw StateError('No room');
        await pumpTab(tester, backend);
        await pick(tester, 'Export files…');
        expect(find.text('Couldn’t export the files.'), findsOne);
        expect(menuEnabled(tester), isTrue);
      });

      testWidgets('holds off updating until it’s done', (tester) async {
        final backend = _FakeBackend(model: storyModelFixture())
          ..holdFiles = Completer<void>();
        await pumpTab(tester, backend);
        await pick(tester, 'Export files…');
        expect(updateButton(tester).onPressed, isNull);
        expect(menuEnabled(tester), isFalse);
        expect(find.text('Preparing your files…'), findsOne);

        backend.holdFiles!.complete();
        await tester.pumpAndSettle();
        expect(updateButton(tester).onPressed, isNotNull);
        expect(menuEnabled(tester), isTrue);
      });
    });

    group('loading', () {
      testWidgets('does nothing if the reader backs out', (tester) async {
        final backend = _FakeBackend(model: storyModelFixture())..picked = null;
        await pumpTab(tester, backend);
        await pick(tester, 'Load from file…');
        expect(backend.stagedPaths, isEmpty);
        expect(backend.commits, 0);
      });

      testWidgets('shows a first map without asking', (tester) async {
        final backend = _FakeBackend(status: _newStore)
          ..imported = storyModelFixture();
        await pumpTab(tester, backend);
        expect(find.byType(StoryMapScreen), findsNothing);

        await pick(tester, 'Load from file…');
        expect(backend.stagedPaths, ['/picked.zip']);
        expect(find.text('Replace this Story Map?'), findsNothing);
        expect(backend.commits, 1);
        expect(find.byType(StoryMapScreen), findsOne);
        // The reader hasn't read any of it, and the slider asks before showing it.
        expect(
          find.text('Loaded 2 sections. Drag the slider to see them.'),
          findsOne,
        );
        expect(
          tester
              .widget<StoryMapScreen>(find.byType(StoryMapScreen))
              .finishedSections,
          0,
        );
      });

      testWidgets('asks before replacing a map', (tester) async {
        final model = storyModelFixture();
        final backend = _FakeBackend(model: model)
          ..staged = const StagedStoryImport(
            path: '/staging',
            revision: 1,
            sectionCount: 1,
            viewOnly: false,
          );
        await pumpTab(tester, backend);
        await pick(tester, 'Load from file…');

        expect(find.text('Replace this Story Map?'), findsOne);
        expect(
          find.textContaining(
            'The map here has ${model.sections.length} sections. '
            'The file has 1 section.',
          ),
          findsOne,
        );
        expect(find.textContaining('Export first'), findsOne);
        expect(find.textContaining('only be viewed'), findsNothing);
        expect(backend.commits, 0);
      });

      testWidgets('backing out of replacing changes nothing', (tester) async {
        final backend = _FakeBackend(model: storyModelFixture());
        await pumpTab(tester, backend);
        await pick(tester, 'Load from file…');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(backend.commits, 0);
        expect(backend.discards, 1);
        expect(find.textContaining('Loaded'), findsNothing);
        expect(menuEnabled(tester), isTrue);
      });

      testWidgets('replacing starts the slider afresh', (tester) async {
        final backend = _FakeBackend(model: storyModelFixture(), finished: 1)
          ..imported = storyModelFixture();
        await pumpTab(tester, backend);
        final before = tester.state(find.byType(StoryMapScreen));

        await pick(tester, 'Load from file…');
        await tester.tap(find.text('Replace'));
        await tester.pumpAndSettle();

        expect(backend.commits, 1);
        expect(backend.discards, 0);
        expect(tester.state(find.byType(StoryMapScreen)), isNot(before));
        expect(find.textContaining('Loaded 2 sections.'), findsOne);
      });

      testWidgets('asks before replacing a map that can’t be read', (
        tester,
      ) async {
        final backend = _BrokenMapBackend();
        await pumpTab(tester, backend);
        expect(find.textContaining('Could not load'), findsOne);

        await pick(tester, 'Load from file…');
        expect(find.text('Replace this Story Map?'), findsOne);
        expect(find.textContaining('The map here has'), findsNothing);
      });

      testWidgets('says that a lone model file can only be viewed', (
        tester,
      ) async {
        final backend = _FakeBackend(model: storyModelFixture())
          ..staged = const StagedStoryImport(
            path: '/staging',
            revision: 2,
            sectionCount: 2,
            viewOnly: true,
          );
        await pumpTab(tester, backend);
        await pick(tester, 'Load from file…');
        expect(find.textContaining('can only be viewed'), findsOne);

        backend.status = const StoryUpdateStatus.blocked(storyViewOnlyReason);
        await tester.tap(find.text('Replace'));
        await tester.pumpAndSettle();
        expect(find.text(storyViewOnlyReason), findsOne);
        expect(updateButton(tester).onPressed, isNull);
      });

      testWidgets('says why a file won’t do', (tester) async {
        final backend = _FakeBackend(model: storyModelFixture())
          ..stageError = const StoryImportError('That file isn’t a Story Map.');
        await pumpTab(tester, backend);
        await pick(tester, 'Load from file…');
        expect(find.text('That file isn’t a Story Map.'), findsOne);
        expect(backend.commits, 0);
        expect(menuEnabled(tester), isTrue);
      });

      testWidgets('says if something else goes wrong', (tester) async {
        final backend = _FakeBackend(model: storyModelFixture())
          ..stageError = StateError('Disk on fire');
        await pumpTab(tester, backend);
        await pick(tester, 'Load from file…');
        expect(find.text('Couldn’t load that file.'), findsOne);
        expect(find.textContaining('Disk on fire'), findsNothing);
      });

      testWidgets('holds off updating until it’s done', (tester) async {
        final backend = _FakeBackend(status: _newStore)
          ..holdFiles = Completer<void>();
        await pumpTab(tester, backend);
        await pick(tester, 'Load from file…');
        expect(updateButton(tester).onPressed, isNull);
        expect(find.text('Checking that file…'), findsOne);

        backend.holdFiles!.complete();
        await tester.pumpAndSettle();
        expect(updateButton(tester).onPressed, isNotNull);
      });
    });

    group('on a small phone', () {
      void useSmallPhone(WidgetTester tester) {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
      }

      testWidgets('the bar fits every button', (tester) async {
        useSmallPhone(tester);
        await pumpTab(
          tester,
          _FakeBackend(
            model: storyModelFixture(),
            status: const StoryUpdateStatus.ready(
              's',
              'A very long section title that goes on and on',
              choices: [
                StorySectionChoice('s', 'One', 3),
                StorySectionChoice('t', 'Two', 3),
              ],
            ),
          ),
        );
        expect(find.text('Choose'), findsOne);
        expect(find.byTooltip('Story Map files'), findsOne);
        expect(tester.takeException(), isNull);
        // The title isn't squeezed out, even in the test font, whose letters are
        // all as wide as they are tall. Real text leaves it a good deal more.
        expect(
          tester.getSize(find.textContaining('A very long')).width,
          greaterThan(0),
        );
      });

      testWidgets('the replacing dialog fits', (tester) async {
        useSmallPhone(tester);
        final backend = _FakeBackend(model: storyModelFixture())
          ..staged = const StagedStoryImport(
            path: '/staging',
            revision: 2,
            sectionCount: 2,
            viewOnly: true,
          );
        await pumpTab(tester, backend);
        await pick(tester, 'Load from file…');
        expect(find.text('Replace this Story Map?'), findsOne);
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('without an API key', () {
    testWidgets('a map can be looked at, but not updated', (tester) async {
      final backend = _FakeBackend(model: storyModelFixture());
      await pumpTab(tester, backend, hasKey: false);
      expect(find.byType(StoryMapScreen), findsOne);
      expect(updateButton(tester).onPressed, isNull);
      expect(find.text('Add an API key in Settings to update.'), findsOne);
    });

    testWidgets('that comes before being offline', (tester) async {
      await pumpTab(
        tester,
        _FakeBackend(model: storyModelFixture()),
        hasKey: false,
        online: false,
      );
      expect(find.text('Add an API key in Settings to update.'), findsOne);
      expect(find.textContaining('You’re offline'), findsNothing);
    });

    testWidgets('a section can’t be chosen', (tester) async {
      await pumpTab(
        tester,
        _FakeBackend(
          model: storyModelFixture(),
          status: const StoryUpdateStatus.ready(
            's',
            'One',
            choices: [
              StorySectionChoice('s', 'One', 3),
              StorySectionChoice('t', 'Two', 3),
            ],
          ),
        ),
        hasKey: false,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Choose'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('with no map, it suggests a key or a file', (tester) async {
      await pumpTab(tester, _FakeBackend(status: _newStore), hasKey: false);
      expect(find.textContaining('Add an API key to build'), findsOne);
      expect(find.textContaining('load one'), findsOne);
      expect(find.textContaining('Press Update'), findsNothing);
    });

    testWidgets('a map can still be loaded and exported', (tester) async {
      final backend = _FakeBackend(status: _newStore)
        ..imported = storyModelFixture();
      await pumpTab(tester, backend, hasKey: false);

      await tester.tap(find.byTooltip('Story Map files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load from file…'));
      await tester.pumpAndSettle();
      expect(backend.commits, 1);
      expect(find.byType(StoryMapScreen), findsOne);

      await tester.tap(find.byTooltip('Story Map files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export files…'));
      await tester.pumpAndSettle();
      expect(backend.exports, 1);
    });
  });

  group('the intro', () {
    const title = 'Tap Update to build the Story Map';

    testWidgets('shows on the first visit and goes once closed', (
      tester,
    ) async {
      final backend = _FakeBackend(model: storyModelFixture())
        ..seenIntro = false;
      await pumpTab(tester, backend);
      expect(find.text(title), findsOne);

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.text(title), findsNothing);
      expect(backend.seenIntro, isTrue);
    });

    testWidgets('doesn\'t come back once closed', (tester) async {
      final backend = _FakeBackend(model: storyModelFixture())
        ..seenIntro = false;
      await pumpTab(tester, backend);
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();

      // A new tab, as when the book is opened again.
      await tester.pumpWidget(const SizedBox());
      await pumpTab(tester, backend);
      expect(find.text(title), findsNothing);
    });

    testWidgets('shows above Update before any map is built', (tester) async {
      await pumpTab(tester, _FakeBackend(status: _newStore)..seenIntro = false);
      expect(find.text(title), findsOne);
      expect(
        tester.getTopLeft(find.text(title)).dy,
        lessThan(
          tester.getTopLeft(find.widgetWithText(FilledButton, 'Update')).dy,
        ),
      );
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
    test('a section counts once the reader has turned past it', () {
      expect(finished(const ReaderPosition(1, 1)), 0);
      expect(finished(const ReaderPosition(2, 0)), 1);
    });
    test('sections sharing a document finish together', () {
      expect(finished(const ReaderPosition(2, 0.9)), 1);
      expect(finished(const ReaderPosition(2, 1)), 1);
      expect(finished(const ReaderPosition(3, 0)), 3);
    });
    test('all of them on the last page of the book', () {
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

  group('past the end of the map', () {
    // two.xhtml was left out between the map's two sections, for good.
    final sections = [
      for (final (id, order, href) in const [
        ('section-002', 2, 'OEBPS/one.xhtml'),
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
      SpineItem(path: 'OEBPS/four.xhtml', linear: true),
    ];
    // As Ask counts: the page being read is read.
    bool past(ReaderPosition position, {List<StorySection>? of}) {
      final mapped = of ?? sections;
      return pastStoryMapEnd(
        mapped,
        spine,
        StoryReadingProgress(
          finishedStorySections(mapped, spine, position, wholePage: true),
        ),
        position.sectionIndex,
      );
    }

    test('not before the map starts', () {
      expect(past(const ReaderPosition(0, 0.5)), isFalse);
    });
    test('not in a stretch the map left out, which can\'t be added', () {
      expect(past(const ReaderPosition(2, 0.5)), isFalse);
    });
    test('not partway through the last section', () {
      expect(past(const ReaderPosition(3, 0.5)), isFalse);
      expect(
        pastStoryMapEnd(
          sections,
          spine,
          const StoryReadingProgress(1, hiddenInNext: {}),
          3,
        ),
        isFalse,
      );
    });
    test('not on the last page of the last section, which is still in it', () {
      expect(past(const ReaderPosition(3, 1)), isFalse);
    });
    test('after the last section', () {
      expect(past(const ReaderPosition(4, 0.3)), isTrue);
    });
    test('not without a map', () {
      expect(past(const ReaderPosition(4, 0.3), of: const []), isFalse);
    });
  });
}
