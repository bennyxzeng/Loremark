import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/story_map/chapter_digest_view.dart';
import 'package:loremark/story_map/character_graph_view.dart';
import 'package:loremark/story_map/graph_guide_sheet.dart';
import 'package:loremark/story_map/label_guide_sheet.dart';
import 'package:loremark/story_map/story_facts.dart';
import 'package:loremark/story_map/story_map_screen.dart';
import 'package:loremark/story_model/story_model.dart';

import '../story_model/story_model_fixture.dart';

void main() {
  Future<void> pumpStoryMap(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StoryMapScreen(model: storyModelFixture())),
      ),
    );
  }

  Future<void> showTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  List<String> tagsOf(WidgetTester tester, String fact) => [
    for (final tag in tester.widgetList<FactTag>(
      find.descendant(
        of: find.widgetWithText(FactTile, fact),
        matching: find.byType(FactTag),
      ),
    ))
      tag.label,
  ];

  Future<void> slideToFirstChapter(WidgetTester tester) async {
    await tester.drag(find.byType(Slider), const Offset(-1000, 0));
    await tester.pumpAndSettle();
  }

  testWidgets('starts at the latest chapter with the graph', (tester) async {
    await pumpStoryMap(tester);

    expect(find.text('Known by the end of Chapter 2: The Letter'), findsOne);
    expect(find.byType(CharacterGraphView), findsOne);
  });

  testWidgets('character list follows the chapter slider', (tester) async {
    await pumpStoryMap(tester);
    await showTab(tester, 'Characters');

    expect(find.text('Mara Quinn'), findsOne);
    expect(find.text('Elian'), findsOne);

    await slideToFirstChapter(tester);

    expect(find.text('Known by the end of Chapter 1: Arrival'), findsOne);
    expect(find.text('Mara'), findsOne);
    expect(find.text('Mara Quinn'), findsNothing);
    expect(find.text('Elian'), findsNothing);
  });

  testWidgets('search filters by name and alias', (tester) async {
    await pumpStoryMap(tester);
    await showTab(tester, 'Characters');

    await tester.enterText(find.byType(TextField), 'harbor girl');
    await tester.pump();

    expect(find.text('Mara Quinn'), findsOne);
    expect(find.text('Elian'), findsNothing);
  });

  testWidgets('tapping a character opens its card', (tester) async {
    await pumpStoryMap(tester);
    await showTab(tester, 'Characters');

    await tester.tap(find.text('Mara Quinn'));
    await tester.pumpAndSettle();

    expect(find.text('character · First seen in Chapter 1'), findsOne);
    expect(find.text('Also known as the harbor girl'), findsOne);
    expect(find.text('role: dock clerk'), findsOne);
    expect(tagsOf(tester, 'role: dock clerk'), ['explicit']);
    expect(find.text('age: sixteen'), findsNothing);
  });

  testWidgets('chapter view lists what changed', (tester) async {
    await pumpStoryMap(tester);
    await showTab(tester, 'Chapter');

    expect(find.text('What’s new in Chapter 2: The Letter'), findsOne);
    expect(find.text('Mara → Mara Quinn'), findsOne);
    expect(find.widgetWithText(ActionChip, 'Elian'), findsOne);
  });

  testWidgets('events show the temporal context as the model words it', (
    tester,
  ) async {
    await pumpStoryMap(tester);
    await showTab(tester, 'Chapter');

    await tester.scrollUntilVisible(
      find.text('1. Elian left home years ago.'),
      200,
      scrollable: find.descendant(
        of: find.byType(ChapterDigestView),
        matching: find.byType(Scrollable),
      ),
    );

    expect(tagsOf(tester, '1. Elian left home years ago.'), [
      'past',
      'explicit',
    ]);
    expect(find.textContaining('flashback'), findsNothing);
  });

  testWidgets('entity kinds show as the model words them', (tester) async {
    await pumpStoryMap(tester);

    expect(find.widgetWithText(FilterChip, 'organization'), findsOne);
    expect(find.widgetWithText(FilterChip, 'location'), findsOne);

    await showTab(tester, 'Chapter');
    await slideToFirstChapter(tester);

    expect(find.text('New locations and organizations'), findsOne);

    await tester.tap(find.widgetWithText(ActionChip, 'Harbor Guild'));
    await tester.pumpAndSettle();

    expect(find.text('organization · First seen in Chapter 1'), findsOne);
  });

  testWidgets('facts show their default labels too', (tester) async {
    await pumpStoryMap(tester);
    await showTab(tester, 'Chapter');

    expect(tagsOf(tester, 'Elian sibling of Mara Quinn'), [
      'current',
      'explicit',
    ]);

    await tester.scrollUntilVisible(
      find.text('2. Elian hands Mara a letter.'),
      200,
      scrollable: find.descendant(
        of: find.byType(ChapterDigestView),
        matching: find.byType(Scrollable),
      ),
    );

    expect(tagsOf(tester, '2. Elian hands Mara a letter.'), [
      'current',
      'explicit',
    ]);
  });

  test('only the usual labels count as defaults', () {
    final defaults = [
      for (final label in [
        for (final time in TemporalContext.values) time.name,
        for (final assertion in Assertion.values) assertion.name,
      ])
        if (FactTag(label).isDefault) label,
    ];

    expect(defaults, ['current', 'explicit']);
  });

  group('label guide', () {
    final guideButton = find.byTooltip('Label guide');

    testWidgets('explains every label the model can use', (tester) async {
      tester.view.physicalSize = const Size(1000, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpStoryMap(tester);
      await showTab(tester, 'Chapter');

      await tester.tap(guideButton);
      await tester.pumpAndSettle();

      for (final label in [
        for (final context in TemporalContext.values) context.name,
        for (final assertion in Assertion.values) assertion.name,
      ]) {
        expect(
          find.descendant(
            of: find.byType(LabelGuideView),
            matching: find.text(label),
          ),
          findsOne,
          reason: label,
        );
      }
    });

    testWidgets('stays reachable while the chapter scrolls', (tester) async {
      await pumpStoryMap(tester);
      await showTab(tester, 'Chapter');

      await tester.drag(
        find.descendant(
          of: find.byType(ChapterDigestView),
          matching: find.byType(Scrollable),
        ),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(guideButton);
      await tester.pumpAndSettle();

      expect(find.byType(LabelGuideView), findsOne);
    });

    testWidgets('only the Chapter tab has the button', (tester) async {
      await pumpStoryMap(tester);
      expect(guideButton, findsNothing);

      await showTab(tester, 'Characters');
      expect(guideButton, findsNothing);

      await showTab(tester, 'Chapter');
      expect(guideButton, findsOne);
    });
  });

  group('graph guide', () {
    final guideButton = find.byTooltip('Graph guide');

    Future<void> pumpTallStoryMap(WidgetTester tester) async {
      // Tall enough for the whole guide to be built without scrolling.
      tester.view.physicalSize = const Size(1000, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpStoryMap(tester);
    }

    testWidgets('explains the graph in the model\'s words', (tester) async {
      await pumpTallStoryMap(tester);

      await tester.tap(guideButton);
      await tester.pumpAndSettle();

      expect(find.byType(GraphGuideView), findsOne);
      for (final heading in ['Nodes', 'Lines', 'Using the graph']) {
        expect(find.text(heading), findsOne);
      }
      for (final label in ['character', 'past', 'inferred or reported']) {
        expect(find.text(label), findsOne);
      }
      // The sheet covers the filter chips of the same names, which stay built.
      expect(find.text('organization'), findsNWidgets(2));
      expect(find.text('location'), findsNWidgets(2));
      expect(find.text('New or revealed in Chapter 2'), findsOne);
      expect(find.text('New in Chapter 2'), findsOne);
      expect(find.byType(GraphLegendSample), findsNWidgets(10));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is GraphLegendSample && widget.label == 'member of',
        ),
        findsOne,
      );
    });

    testWidgets('follows the chapter slider', (tester) async {
      await pumpTallStoryMap(tester);
      await slideToFirstChapter(tester);

      await tester.tap(guideButton);
      await tester.pumpAndSettle();

      expect(find.text('New or revealed in Chapter 1'), findsOne);
      expect(find.text('New in Chapter 1'), findsOne);
    });

    testWidgets('closing it keeps the filters as they were', (tester) async {
      await pumpTallStoryMap(tester);
      final chip = find.widgetWithText(FilterChip, 'organization');
      await tester.tap(chip);
      await tester.pumpAndSettle();

      await tester.tap(guideButton);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(GraphGuideView), findsNothing);
      expect(tester.widget<FilterChip>(chip).selected, isTrue);
    });

    testWidgets('only the graph has the button', (tester) async {
      await pumpStoryMap(tester);
      expect(guideButton, findsOne);

      await showTab(tester, 'Characters');
      expect(guideButton, findsNothing);

      await showTab(tester, 'Chapter');
      expect(guideButton, findsNothing);
    });
  });

  test('graph layout is the same every time', () {
    const nodes = ['a', 'b', 'c'];
    const edges = [('a', 'b'), ('b', 'c')];
    final first = GraphLayout.compute(nodes, edges);
    final second = GraphLayout.compute(nodes, edges);

    expect(first.positions, second.positions);
    for (final position in first.positions.values) {
      expect((Offset.zero & first.size).contains(position), isTrue);
    }
  });
}
