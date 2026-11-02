import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/story_map/character_graph_view.dart';
import 'package:loremark/story_map/story_map_screen.dart';

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

    expect(find.text('Character · First seen in Chapter 1'), findsOne);
    expect(find.text('Also known as the harbor girl'), findsOne);
    expect(find.text('role: dock clerk'), findsOne);
    expect(find.text('age: sixteen'), findsNothing);
  });

  testWidgets('chapter view lists what changed', (tester) async {
    await pumpStoryMap(tester);
    await showTab(tester, 'Chapter');

    expect(find.text('What’s new in Chapter 2: The Letter'), findsOne);
    expect(find.text('Mara → Mara Quinn'), findsOne);
    expect(find.widgetWithText(ActionChip, 'Elian'), findsOne);
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
