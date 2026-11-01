import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/insights/insights_sheet.dart';
import 'package:loremark/insights/reading_insights.dart';
import 'package:loremark/insights/reading_time_text.dart';
import 'package:loremark/theme/loremark_theme.dart';

import 'fake_reading_insights.dart';

void main() {
  late FakeReadingInsights insights;

  setUp(() => insights = FakeReadingInsights());

  Future<void> showSheet(WidgetTester tester, {TimeLeft? timeLeft}) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLoremarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showInsightsSheet(
                context,
                insights: insights,
                timeLeft: timeLeft,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  InsightsSummary summary({
    Duration today = const Duration(minutes: 25),
    bool personal = true,
    bool characters = false,
    double pace = 247,
    int streak = 4,
    Map<int, int> minutesByDaysAgo = const {0: 25, 1: 40, 3: 10},
  }) {
    final end = DateTime(2026, 11, 1);
    return InsightsSummary(
      today: today,
      unitsPerMinute: pace,
      paceSamples: 31,
      paceIsPersonal: personal,
      countsCharacters: characters,
      streakDays: streak,
      lastDays: [
        for (var i = 13; i >= 0; i--)
          DailyReading(
            day: DateTime(end.year, end.month, end.day - i),
            activeTime: Duration(minutes: minutesByDaysAgo[i] ?? 0),
          ),
      ],
    );
  }

  group('InsightsSheet', () {
    testWidgets('shows today, pace, time left, streak and best day', (
      tester,
    ) async {
      insights.summary = summary();
      await showSheet(
        tester,
        timeLeft: const TimeLeft(
          chapter: Duration(minutes: 12),
          book: Duration(hours: 1, minutes: 5),
        ),
      );

      expect(find.text('READING INSIGHTS'), findsOneWidget);
      expect(find.text('25 min'), findsOneWidget);
      expect(find.text('~250 words/min'), findsOneWidget);
      expect(find.text('Estimated from 31 page turns'), findsOneWidget);
      expect(find.text('12 min'), findsOneWidget);
      expect(find.text('1 h 05 min'), findsOneWidget);
      expect(find.text('4 days'), findsOneWidget);
      expect(find.text('Best day: 40 min'), findsOneWidget);
    });

    testWidgets('says the pace is still being learned', (tester) async {
      insights.summary = summary(
        personal: false,
        streak: 1,
        today: Duration.zero,
      );
      await showSheet(tester);

      expect(find.text('A typical pace until it learns yours'), findsOneWidget);
      expect(find.text('1 day'), findsOneWidget);
      expect(find.text('0 min'), findsOneWidget);
      // No estimate yet for either.
      expect(find.text('--'), findsNWidgets(2));
    });

    testWidgets('counts characters for Chinese, Japanese and Korean', (
      tester,
    ) async {
      insights.summary = summary(characters: true, pace: 403);
      await showSheet(tester);

      expect(find.text('~400 characters/min'), findsOneWidget);
    });

    testWidgets('draws the last 14 days and describes them', (tester) async {
      final handle = tester.ensureSemantics();
      insights.summary = summary();
      await showSheet(tester);

      final chart = find.byKey(const ValueKey('daily-chart'));
      expect(chart, findsOneWidget);
      expect(
        find.descendant(of: chart, matching: find.byType(CustomPaint)),
        findsWidgets,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Reading time per day, last 14 days: .*Sun 25 min$'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the Reading hints switch follows and changes the setting', (
      tester,
    ) async {
      await showSheet(tester);
      Switch hints() => tester.widget<Switch>(
        find.descendant(
          of: find.byKey(const ValueKey('hints-switch')),
          matching: find.byType(Switch),
        ),
      );
      expect(hints().value, isTrue);

      await tester.tap(find.byKey(const ValueKey('hints-switch')));
      await tester.pumpAndSettle();

      expect(insights.hintsSet, [false]);
      expect(hints().value, isFalse);

      await tester.tap(find.byKey(const ValueKey('hints-switch')));
      await tester.pumpAndSettle();
      expect(insights.hintsSet, [false, true]);
      expect(hints().value, isTrue);
    });

    testWidgets('starts with hints off when they are off', (tester) async {
      insights.hintsEnabled = false;
      await showSheet(tester);

      expect(
        tester
            .widget<Switch>(
              find.descendant(
                of: find.byKey(const ValueKey('hints-switch')),
                matching: find.byType(Switch),
              ),
            )
            .value,
        isFalse,
      );
    });
  });

  group('DailyReadingPainter', () {
    test('scales to the next of 15, 30, 60, 120 minutes, then whole hours', () {
      expect(DailyReadingPainter.scaleMax([0, 0]), 15);
      expect(DailyReadingPainter.scaleMax([3, 15]), 15);
      expect(DailyReadingPainter.scaleMax([16]), 30);
      expect(DailyReadingPainter.scaleMax([45]), 60);
      expect(DailyReadingPainter.scaleMax([61]), 120);
      expect(DailyReadingPainter.scaleMax([121]), 180);
    });

    test('repaints only when the data changes', () {
      final painter = DailyReadingPainter(minutes: [1, 2], labels: ['M', 'T']);

      expect(
        painter.shouldRepaint(
          DailyReadingPainter(minutes: [1, 2], labels: ['M', 'T']),
        ),
        isFalse,
      );
      expect(
        painter.shouldRepaint(
          DailyReadingPainter(minutes: [1, 3], labels: ['M', 'T']),
        ),
        isTrue,
      );
    });
  });

  group('formatReadingTime', () {
    test('uses minutes, then hours and zero-padded minutes', () {
      expect(
        formatReadingTime(const Duration(seconds: 59)),
        'Less than a minute',
      );
      expect(formatReadingTime(const Duration(seconds: 60)), '1 min');
      expect(formatReadingTime(const Duration(minutes: 12)), '12 min');
      expect(
        formatReadingTime(const Duration(minutes: 59, seconds: 40)),
        '1 h 00 min',
      );
      expect(formatReadingTime(const Duration(minutes: 65)), '1 h 05 min');
      expect(
        formatReadingTime(const Duration(hours: 12, minutes: 30)),
        '12 h 30 min',
      );
    });

    test('speaks it as a sentence part', () {
      expect(
        spokenReadingTime(const Duration(seconds: 5)),
        'less than a minute',
      );
      expect(spokenReadingTime(const Duration(minutes: 1)), 'about 1 minute');
      expect(
        spokenReadingTime(const Duration(minutes: 12)),
        'about 12 minutes',
      );
      expect(
        spokenReadingTime(const Duration(minutes: 65)),
        'about 1 hour 5 minutes',
      );
      expect(spokenReadingTime(const Duration(hours: 2)), 'about 2 hours');
    });
  });
}
