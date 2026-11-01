import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/read_screen.dart';
import 'package:loremark/insights/reading_insights.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/theme/loremark_theme.dart';

import '../insights/fake_reading_insights.dart';
import 'fake_epub_reader_service.dart';

void main() {
  final book = Book(
    id: 'abc',
    title: 'The Glass Harbor',
    author: null,
    epubPath: 'glass.epub',
    coverPath: null,
    importedAt: DateTime(2026),
  );

  late FakeEpubReaderService service;
  late FakeReadingPositionStore store;
  late FakeReadingInsights insights;
  late ReadScreenController controller;
  late int storyMapOpens;

  setUp(() {
    service = FakeEpubReaderService();
    store = FakeReadingPositionStore();
    insights = FakeReadingInsights();
    controller = ReadScreenController();
    storyMapOpens = 0;
  });

  Widget screen({
    Future<ReadingInsights> Function()? openInsights,
    VoidCallback? onSearchChapter,
    bool withInsights = true,
  }) => MaterialApp(
    theme: buildLoremarkTheme(),
    home: Scaffold(
      body: ReadScreen(
        book: book,
        readerService: service,
        openPositionStore: () async => store,
        openInsights: withInsights
            ? (openInsights ?? () async => insights)
            : null,
        onOpenStoryMap: () => storyMapOpens++,
        onSearchChapter: onSearchChapter,
        controller: controller,
      ),
    ),
  );

  Future<FakeEpubReaderSession> openBook(
    WidgetTester tester, {
    Future<ReadingInsights> Function()? openInsights,
    VoidCallback? onSearchChapter,
    bool withInsights = true,
  }) async {
    await tester.pumpWidget(
      screen(
        openInsights: openInsights,
        onSearchChapter: onSearchChapter,
        withInsights: withInsights,
      ),
    );
    await tester.pumpAndSettle();
    return service.sessions.single;
  }

  Future<void> emit(
    WidgetTester tester,
    FakeEpubReaderSession session,
    ReaderPosition position,
  ) async {
    session.emit(position);
    await tester.idle();
    await tester.pump();
  }

  String label(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('progress-label'))).data!;

  const start = ReaderPosition(1, 0.0, totalProgression: 0.42);

  group('cause tagging', () {
    testWidgets('the first position is the open', (tester) async {
      final session = await openBook(tester);

      await emit(tester, session, start);

      expect(insights.positions, [(start, NavigationCause.open)]);
    });

    testWidgets('page buttons tag the position that follows', (tester) async {
      final session = await openBook(tester);
      await emit(tester, session, start);

      await tester.tap(find.byTooltip('Next page'));
      await emit(tester, session, const ReaderPosition(1, 0.1));
      await tester.tap(find.byTooltip('Previous page'));
      await emit(tester, session, const ReaderPosition(1, 0.05));

      expect(insights.causes, [
        NavigationCause.open,
        NavigationCause.pageForward,
        NavigationCause.pageBackward,
      ]);
    });

    testWidgets('a contents jump is a tocJump', (tester) async {
      final session = await openBook(tester);
      await emit(tester, session, start);

      await tester.tap(find.byTooltip('Contents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chapter Two'));
      await tester.pumpAndSettle();
      await emit(tester, session, const ReaderPosition(4, 0.0));

      expect(insights.causes.last, NavigationCause.tocJump);
    });

    testWidgets('a position nobody asked for is a swipe', (tester) async {
      final session = await openBook(tester);
      await emit(tester, session, start);

      await emit(tester, session, const ReaderPosition(1, 0.1));

      expect(insights.causes.last, NavigationCause.swipe);
    });

    testWidgets('each request tags only one position', (tester) async {
      final session = await openBook(tester);
      await emit(tester, session, start);

      await tester.tap(find.byTooltip('Next page'));
      await emit(tester, session, const ReaderPosition(1, 0.1));
      await emit(tester, session, const ReaderPosition(1, 0.2));

      expect(insights.causes.sublist(1), [
        NavigationCause.pageForward,
        NavigationCause.swipe,
      ]);
    });

    testWidgets('a position that arrives too late is a swipe', (tester) async {
      final session = await openBook(tester);
      await emit(tester, session, start);

      await tester.tap(find.byTooltip('Next page'));
      await tester.pump(const Duration(seconds: 2));
      await emit(tester, session, const ReaderPosition(1, 0.1));

      expect(insights.causes.last, NavigationCause.swipe);
    });

    testWidgets('a section turn tags both of its positions', (tester) async {
      final session = await openBook(tester);
      await emit(tester, session, const ReaderPosition(1, 0.9));

      await tester.tap(find.byTooltip('Next page'));
      await emit(tester, session, const ReaderPosition(1, 1.0));
      await emit(tester, session, const ReaderPosition(2, 0.0));
      await emit(tester, session, const ReaderPosition(2, 0.1));

      expect(insights.causes.sublist(1), [
        NavigationCause.pageForward,
        NavigationCause.pageForward,
        NavigationCause.swipe,
      ]);
    });

    testWidgets('a jump from the controller can say it is a search jump', (
      tester,
    ) async {
      final session = await openBook(tester);
      await emit(tester, session, start);
      const target = ReaderPosition(3, 0.5);

      await controller.goToPosition(target);
      await emit(tester, session, target);

      expect(session.goToPositionCalls, [target]);
      expect(insights.causes.last, NavigationCause.searchJump);
    });

    testWidgets('positions are still saved', (tester) async {
      final session = await openBook(tester);

      await emit(tester, session, start);

      expect(store.saves, [('abc', start)]);
    });
  });

  group('time left label', () {
    testWidgets('shows the percentage without insights', (tester) async {
      final session = await openBook(tester, withInsights: false);

      await emit(tester, session, start);

      expect(label(tester), '42%');
      expect(find.byTooltip('Reading insights'), findsNothing);
    });

    testWidgets('shows the percentage until the pace is known', (tester) async {
      final session = await openBook(tester);

      await emit(tester, session, start);

      expect(label(tester), '42%');
    });

    testWidgets('shows minutes left in the chapter, then cycles', (
      tester,
    ) async {
      insights.timeLeftValue = const TimeLeft(
        chapter: Duration(minutes: 12),
        book: Duration(hours: 1, minutes: 5),
      );
      final session = await openBook(tester);
      await emit(tester, session, start);

      expect(label(tester), '12 min left in chapter');

      await tester.tap(find.byKey(const ValueKey('progress-label')));
      await tester.pump();
      expect(label(tester), '1 h 05 min left in book');

      await tester.tap(find.byKey(const ValueKey('progress-label')));
      await tester.pump();
      expect(label(tester), '42%');

      await tester.tap(find.byKey(const ValueKey('progress-label')));
      await tester.pump();
      expect(label(tester), '12 min left in chapter');
    });

    testWidgets('says when less than a minute is left', (tester) async {
      insights.timeLeftValue = const TimeLeft(
        chapter: Duration(seconds: 40),
        book: Duration(minutes: 30),
      );
      final session = await openBook(tester);
      await emit(tester, session, start);

      expect(label(tester), 'Less than a minute left');
    });

    testWidgets('follows new estimates from the insights', (tester) async {
      insights.timeLeftValue = const TimeLeft(
        chapter: Duration(minutes: 12),
        book: Duration(minutes: 90),
      );
      final session = await openBook(tester);
      await emit(tester, session, start);

      insights.timeLeftValue = const TimeLeft(
        chapter: Duration(minutes: 7),
        book: Duration(minutes: 85),
      );
      insights.changed();
      await tester.pump();

      expect(label(tester), '7 min left in chapter');
    });

    testWidgets('describes the label in a full sentence', (tester) async {
      final handle = tester.ensureSemantics();
      insights.timeLeftValue = const TimeLeft(
        chapter: Duration(minutes: 12),
        book: Duration(hours: 1, minutes: 5),
      );
      final session = await openBook(tester);
      await emit(tester, session, start);

      expect(
        find.bySemanticsLabel('About 12 minutes left in the chapter'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('progress-label')));
      await tester.pump();
      expect(
        find.bySemanticsLabel('About 1 hour 5 minutes left in the book'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('ends the chapter at the next contents entry', (tester) async {
      final session = await openBook(tester);

      // Contents entries start at sections 1, 2 and 4.
      await emit(tester, session, const ReaderPosition(0, 0.5));
      await emit(tester, session, const ReaderPosition(1, 0.5));
      await emit(tester, session, const ReaderPosition(2, 0.5));
      await emit(tester, session, const ReaderPosition(3, 0.5));
      await emit(tester, session, const ReaderPosition(4, 0.5));
      await emit(tester, session, const ReaderPosition(5, 0.5));

      final ends = {
        for (final (position, end) in insights.timeLeftCalls)
          position.sectionIndex: end,
      };
      expect(ends, {0: 1, 1: 2, 2: 4, 3: 4, 4: null, 5: null});
    });
  });

  group('insights sheet', () {
    testWidgets('opens from the chapter bar next to Contents', (tester) async {
      insights.timeLeftValue = const TimeLeft(
        chapter: Duration(minutes: 12),
        book: Duration(hours: 1, minutes: 5),
      );
      insights.summary = FakeReadingInsights.emptySummary();
      final session = await openBook(tester);
      await emit(tester, session, start);

      await tester.tap(find.byTooltip('Reading insights'));
      await tester.pumpAndSettle();

      expect(find.text('READING INSIGHTS'), findsOneWidget);
      expect(find.text('12 min'), findsOneWidget);
      expect(find.text('1 h 05 min'), findsOneWidget);
      expect(find.byTooltip('Contents'), findsOneWidget);
    });
  });

  group('nudge', () {
    testWidgets('appears under the book and closes with the button', (
      tester,
    ) async {
      final session = await openBook(tester);
      await emit(tester, session, start);
      expect(find.byKey(const ValueKey('reading-nudge')), findsNothing);

      insights.emitSignal(testSignal());
      await tester.pumpAndSettle();

      expect(find.text('Rereading this part?'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      // Between the book and the page controls, without hiding either.
      final nudge = tester.getRect(find.byKey(const ValueKey('reading-nudge')));
      expect(
        nudge.top,
        greaterThanOrEqualTo(
          tester.getRect(find.text('Fake reader view')).bottom,
        ),
      );
      expect(
        nudge.bottom,
        lessThanOrEqualTo(tester.getRect(find.byTooltip('Next page')).top + 1),
      );

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();

      expect(insights.dismissCalls, 1);
      expect(find.byKey(const ValueKey('reading-nudge')), findsNothing);
    });

    testWidgets('hides itself after 12 seconds', (tester) async {
      final session = await openBook(tester);
      await emit(tester, session, start);
      insights.emitSignal(testSignal());
      await tester.pump();

      await tester.pump(const Duration(seconds: 11));
      expect(insights.dismissCalls, 0);

      await tester.pump(const Duration(seconds: 2));
      expect(insights.dismissCalls, 1);
    });

    testWidgets('Story Map button opens it and hides the nudge', (
      tester,
    ) async {
      final session = await openBook(tester);
      await emit(tester, session, start);
      insights.emitSignal(testSignal());
      await tester.pumpAndSettle();

      await tester.tap(find.text("See who's who so far"));
      await tester.pumpAndSettle();

      expect(storyMapOpens, 1);
      expect(insights.dismissCalls, 1);
    });

    testWidgets('offers chapter search only when it is available', (
      tester,
    ) async {
      final session = await openBook(tester);
      await emit(tester, session, start);
      insights.emitSignal(testSignal());
      await tester.pumpAndSettle();
      expect(find.text('Search this chapter'), findsNothing);

      var searches = 0;
      await tester.pumpWidget(const SizedBox());
      insights = FakeReadingInsights();
      service = FakeEpubReaderService();
      final second = await openBook(tester, onSearchChapter: () => searches++);
      await emit(tester, second, start);
      insights.emitSignal(testSignal());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Search this chapter'));
      await tester.pumpAndSettle();
      expect(searches, 1);
    });

    testWidgets('is not shown while reading hints are off', (tester) async {
      insights.hintsEnabled = false;
      final session = await openBook(tester);
      await emit(tester, session, start);

      insights.emitSignal(testSignal());
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('reading-nudge')), findsNothing);
    });

    testWidgets('has calm wording for each kind', (tester) async {
      final session = await openBook(tester);
      await emit(tester, session, start);

      for (final kind in ConfusionKind.values) {
        insights.emitSignal(testSignal(kind: kind));
        await tester.pump();
        final text = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('reading-nudge')),
                matching: find.byType(Text),
              ),
            )
            .map((text) => text.data!)
            .join(' ')
            .toLowerCase();
        expect(text, isNot(contains('confus')), reason: '$kind');
        expect(text, isNot(contains('struggl')), reason: '$kind');
        expect(text, isNot(contains('!')), reason: '$kind');
      }
    });

    testWidgets('keeps the reader view through nudges and label changes', (
      tester,
    ) async {
      final session = await openBook(tester);
      await emit(tester, session, start);

      insights.emitSignal(testSignal());
      await tester.pumpAndSettle();
      insights.dismissNudge();
      await tester.pumpAndSettle();

      expect(session.builtViews, hasLength(1));
    });
  });

  group('opening and closing', () {
    testWidgets('reading works when the insights fail to open', (tester) async {
      final session = await openBook(
        tester,
        openInsights: () async => throw const FormatException('no log'),
      );

      await emit(tester, session, start);

      expect(tester.takeException(), isNull);
      expect(find.text('Fake reader view'), findsOneWidget);
      expect(label(tester), '42%');
      expect(find.byTooltip('Reading insights'), findsNothing);
      expect(store.saves, [('abc', start)]);
    });

    testWidgets('reading works when the insights throw while recording', (
      tester,
    ) async {
      final broken = _ThrowingInsights();
      final session = await openBook(tester, openInsights: () async => broken);

      await emit(tester, session, start);
      await tester.tap(find.byTooltip('Next page'));

      expect(tester.takeException(), isNull);
      expect(find.text('Fake reader view'), findsOneWidget);
      expect(store.saves, [('abc', start)]);
    });

    testWidgets('closes the insights with the screen', (tester) async {
      await openBook(tester);
      expect(insights.closeCalls, 0);

      await tester.pumpWidget(const SizedBox());

      expect(insights.closeCalls, 1);
    });

    testWidgets('closes insights that open after the screen is gone', (
      tester,
    ) async {
      final gate = Completer<ReadingInsights>();
      await tester.pumpWidget(screen(openInsights: () => gate.future));
      await tester.pumpWidget(const SizedBox());

      gate.complete(insights);
      await tester.pump();

      expect(insights.closeCalls, 1);
    });

    testWidgets('closes the insights when the book fails to open', (
      tester,
    ) async {
      service.error = StateError('boom');

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      expect(insights.closeCalls, 1);
    });
  });

  group('app lifecycle', () {
    /// The states Android goes through when the app leaves and returns.
    void background(WidgetTester tester) {
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    void foreground(WidgetTester tester) {
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    testWidgets('hiding and showing the app is reported', (tester) async {
      await openBook(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      background(tester);
      expect(insights.hiddenCalls, 1);
      expect(insights.shownCalls, 0);

      foreground(tester);
      expect(insights.shownCalls, 1);
      expect(insights.hiddenCalls, 1);
    });

    testWidgets('stops listening when the screen is disposed', (tester) async {
      await openBook(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());

      background(tester);
      foreground(tester);

      expect(insights.hiddenCalls, 0);
      expect(insights.shownCalls, 0);
    });
  });
}

/// Insights whose every call fails, to show reading doesn't depend on them.
class _ThrowingInsights extends FakeReadingInsights {
  @override
  void recordPosition(ReaderPosition position, NavigationCause cause) =>
      throw const FormatException('disk full');

  @override
  TimeLeft? timeLeft(ReaderPosition position, {int? chapterEndSection}) =>
      throw const FormatException('bad log');

  @override
  Future<void> close() async => throw const FormatException('cannot close');
}
