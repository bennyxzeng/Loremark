import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/story_map/chapter_digest_view.dart';
import 'package:loremark/story_map/character_card_view.dart';
import 'package:loremark/story_map/character_graph_view.dart';
import 'package:loremark/story_map/graph_guide_sheet.dart';
import 'package:loremark/story_map/label_guide_sheet.dart';
import 'package:loremark/story_map/story_facts.dart';
import 'package:loremark/story_map/story_map_screen.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/story_model/story_snapshot.dart';

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

  Future<void> showPage(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(ChoiceChip),
        matching: find.textContaining(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The last because the page bar above the list scrolls too.
  final factList = find
      .descendant(
        of: find.byType(ChapterDigestView),
        matching: find.byType(Scrollable),
      )
      .last;

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
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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

  testWidgets('cards group changes under what they did', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpStoryMap(tester);
    await showTab(tester, 'Characters');

    await tester.tap(find.text('Mara Quinn'));
    await tester.pumpAndSettle();

    expect(find.text('Changes: Replaced'), findsOne);
    expect(find.text('Changes: Retracted'), findsOne);
    expect(find.text('Changes: Answered'), findsNothing);
    expect(find.text('Changes'), findsNothing);
  });

  group('relationship names on a card', () {
    // The top card only, as the character list behind it has the names too.
    final topCard = find.byType(CharacterCardView).last;

    Finder linkOnTopCard(String name) => find.descendant(
      of: topCard,
      matching: find.widgetWithText(FactLink, name),
    );

    Future<void> openMarasCard(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpStoryMap(tester);
      await showTab(tester, 'Characters');
      await tester.tap(find.text('Mara Quinn'));
      await tester.pumpAndSettle();
    }

    testWidgets('link to the other end, not the card\'s own entity', (
      tester,
    ) async {
      await openMarasCard(tester);
      final snapshot = tester.widget<CharacterCardView>(topCard).snapshot;

      expect(
        [
          for (final link in tester.widgetList<FactLink>(
            find.descendant(of: topCard, matching: find.byType(FactLink)),
          ))
            link.name,
        ],
        unorderedEquals([
          'Harbor Guild',
          snapshot.displayName('c002'),
          'Elian',
        ]),
      );
    });

    testWidgets('each open its own card', (tester) async {
      await openMarasCard(tester);

      // "Elian sibling of Mara Quinn": Elian comes first in the row.
      await tester.tap(linkOnTopCard('Elian'));
      await tester.pumpAndSettle();

      expect(find.byType(CharacterCardView), findsNWidgets(2));
      expect(
        find.descendant(of: topCard, matching: find.text('Elian')),
        findsOne,
      );
      expect(
        find.descendant(
          of: topCard,
          matching: find.text('character · First seen in Chapter 2'),
        ),
        findsOne,
      );

      // The same row on Elian's card: Mara Quinn comes second.
      await tester.tap(linkOnTopCard('Mara Quinn'));
      await tester.pumpAndSettle();

      expect(find.byType(CharacterCardView), findsNWidgets(3));
      expect(
        find.descendant(
          of: topCard,
          matching: find.text('Also known as the harbor girl'),
        ),
        findsOne,
      );
    });

    testWidgets('open places and groups too', (tester) async {
      await openMarasCard(tester);

      await tester.tap(linkOnTopCard('Harbor Guild'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: topCard,
          matching: find.text('organization · First seen in Chapter 1'),
        ),
        findsOne,
      );
    });

    testWidgets('look like links, and the rest of the row doesn\'t', (
      tester,
    ) async {
      await openMarasCard(tester);
      final primary = Theme.of(tester.element(topCard)).colorScheme.primary;
      final link = linkOnTopCard('Elian');
      final linkStyle = tester
          .widget<Text>(find.descendant(of: link, matching: find.byType(Text)))
          .style!;
      final row = find.ancestor(of: link, matching: find.byType(FactTile));
      final rowStyle = tester
          .widget<Text>(
            find.descendant(of: row, matching: find.byType(Text)).first,
          )
          .style!;

      expect(linkStyle.color, primary);
      expect(linkStyle.decoration, TextDecoration.underline);
      expect(rowStyle.color, isNot(primary));
      expect(rowStyle.decoration, isNot(TextDecoration.underline));
      // Only the names are tappable, not the whole row.
      expect(
        find.ancestor(of: row, matching: find.byType(InkWell)),
        findsNothing,
      );
    });
  });

  testWidgets('chapter view lists what changed', (tester) async {
    await pumpStoryMap(tester);
    await showTab(tester, 'Chapter');

    expect(find.text('What’s new in Chapter 2: The Letter'), findsOne);
    expect(find.text('Mara → Mara Quinn'), findsOne);

    await showPage(tester, 'Entities');

    expect(find.widgetWithText(ActionChip, 'Elian'), findsOne);
  });

  testWidgets('events show the temporal context as the model words it', (
    tester,
  ) async {
    await pumpStoryMap(tester);
    await showTab(tester, 'Chapter');
    await showPage(tester, 'Events');

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
    await showPage(tester, 'Relationships');

    expect(tagsOf(tester, 'Elian sibling of Mara Quinn'), [
      'current',
      'explicit',
    ]);

    await showPage(tester, 'Events');

    expect(tagsOf(tester, '2. Elian hands Mara a letter.'), [
      'current',
      'explicit',
    ]);
  });

  group('chapter pages', () {
    testWidgets('list each kind of fact with its count', (tester) async {
      await pumpStoryMap(tester);
      await showTab(tester, 'Chapter');

      for (final label in [
        'Changes 3',
        'Entities 1',
        'Relationships 1',
        'Events 2',
        'Questions 1',
      ]) {
        expect(find.widgetWithText(ChoiceChip, label), findsOne, reason: label);
      }
    });

    testWidgets('leave out kinds the chapter has none of', (tester) async {
      await pumpStoryMap(tester);
      await showTab(tester, 'Chapter');
      await slideToFirstChapter(tester);

      expect(find.textContaining('Changes'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Entities 3'), findsOne);
    });

    testWidgets('show one kind of fact at a time', (tester) async {
      await pumpStoryMap(tester);
      await showTab(tester, 'Chapter');

      expect(find.text('Mara → Mara Quinn'), findsOne);
      expect(find.text('2. Elian hands Mara a letter.'), findsNothing);

      await showPage(tester, 'Events');

      expect(find.text('Mara → Mara Quinn'), findsNothing);
      expect(find.text('2. Elian hands Mara a letter.'), findsOne);
    });

    testWidgets('group changes under what they did', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpStoryMap(tester);
      await showTab(tester, 'Chapter');
      double top(String text) => tester.getTopLeft(find.text(text)).dy;

      expect(
        [
          top('Replaced'),
          top('Mara → Mara Quinn'),
          top('Retracted'),
          top('No longer holds: age: sixteen'),
          top('Answered'),
          top('Who is the stranger? — He is Captain Vell.'),
        ],
        orderedEquals(
          [
            top('Replaced'),
            top('Mara → Mara Quinn'),
            top('Retracted'),
            top('No longer holds: age: sixteen'),
            top('Answered'),
            top('Who is the stranger? — He is Captain Vell.'),
          ]..sort(),
        ),
      );
    });

    testWidgets('mark the current one', (tester) async {
      await pumpStoryMap(tester);
      await showTab(tester, 'Chapter');
      bool isSelected(String label) => tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
          .selected;

      expect(isSelected('Changes 3'), isTrue);
      expect(isSelected('Events 2'), isFalse);

      await showPage(tester, 'Events');

      expect(isSelected('Changes 3'), isFalse);
      expect(isSelected('Events 2'), isTrue);
    });

    testWidgets('stay on the same kind across chapters', (tester) async {
      await pumpStoryMap(tester);
      await showTab(tester, 'Chapter');
      await showPage(tester, 'Events');

      await slideToFirstChapter(tester);

      expect(find.text('1. Mara arrives at the harbor.'), findsOne);
    });

    testWidgets('come back to a kind a chapter was missing', (tester) async {
      // Chapter 1 has no events here, and Events is not the first page.
      final json = storyModelFixtureJson();
      ((json['records'] as Map)['events'] as List).removeWhere(
        (record) => (record as Map)['learned_in_section_id'] == 's1',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StoryMapScreen(model: StoryModel.fromJson(json)),
          ),
        ),
      );
      await showTab(tester, 'Chapter');
      await showPage(tester, 'Events');
      expect(find.text('2. Elian hands Mara a letter.'), findsOne);

      await slideToFirstChapter(tester);
      expect(find.textContaining('Events'), findsNothing);
      expect(find.widgetWithText(ActionChip, 'Mara'), findsOne);

      await tester.drag(find.byType(Slider), const Offset(1000, 0));
      await tester.pumpAndSettle();
      expect(find.text('2. Elian hands Mara a letter.'), findsOne);
    });

    testWidgets('start from the top', (tester) async {
      tester.view.physicalSize = const Size(800, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpStoryMap(tester);
      await showTab(tester, 'Chapter');
      double scrolled() =>
          tester.state<ScrollableState>(factList).position.pixels;

      await tester.drag(factList, const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(scrolled(), greaterThan(0));

      await showPage(tester, 'Events');
      expect(scrolled(), 0);
    });

    testWidgets('say so when a chapter has nothing new', (tester) async {
      final json = storyModelFixtureJson();
      (json['processed_sections'] as List).add(<String, dynamic>{
        'section_id': 's3',
        'section_order': 3,
        'chapter_number': 3,
        'title': 'Chapter 3: Silence',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StoryMapScreen(model: StoryModel.fromJson(json)),
          ),
        ),
      );
      await showTab(tester, 'Chapter');

      expect(find.text('Nothing new in this chapter.'), findsOne);
      expect(find.byType(ChoiceChip), findsNothing);
    });
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

    testWidgets('says which model label each change heading stands for', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpStoryMap(tester);
      await showTab(tester, 'Chapter');

      await tester.tap(guideButton);
      await tester.pumpAndSettle();

      final guide = find.byType(LabelGuideView);
      for (final (heading, label) in [
        ('Replaced', 'supersede'),
        ('Retracted', 'retract'),
        ('Answered', 'resolve'),
      ]) {
        expect(
          find.descendant(of: guide, matching: find.text(heading)),
          findsOne,
          reason: heading,
        );
        expect(
          find.descendant(
            of: guide,
            matching: find.textContaining('Model label: $label.'),
          ),
          findsOne,
          reason: label,
        );
      }
    });

    testWidgets('stays reachable while the chapter scrolls', (tester) async {
      await pumpStoryMap(tester);
      await showTab(tester, 'Chapter');

      await tester.drag(factList, const Offset(0, -300));
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

  group('graph lines', () {
    var nextId = 100;

    // The fixture already has c002 watches c001 from Chapter 1, and c004 is
    // revealed to be c002.
    Map<String, dynamic> relationship(
      String source,
      String label,
      String target, {
      String section = 's2',
      String assertion = 'explicit',
      String temporal = 'current',
    }) => {
      'id': 'f${nextId++}',
      'introduced_revision': section == 's1' ? 1 : 2,
      'learned_in_section_id': section,
      'legacy_id': null,
      'payload': {
        'source_id': source,
        'target_id': target,
        'label': label,
        'description': '$source $label $target',
        'assertion': assertion,
        'attributed_to_id': null,
        'temporal_context': temporal,
      },
      'evidence': <Map<String, dynamic>>[],
    };

    StorySnapshot snapshotWith(List<Map<String, dynamic>> extra) {
      final json = storyModelFixtureJson();
      final records = json['records'] as Map<String, dynamic>;
      (records['relationships'] as List).addAll(extra);
      final model = StoryModel.fromJson(json);
      return StorySnapshot(model, model.sections[1]);
    }

    List<GraphLine> linesOf(StorySnapshot snapshot) => GraphLine.merge(
      snapshot.relationships,
      canonicalId: snapshot.canonicalId,
      isNew: snapshot.isNewRecord,
    );

    GraphLine lineOf(StorySnapshot snapshot, String source, String target) =>
        linesOf(snapshot).singleWhere(
          (line) => line.sourceId == source && line.targetId == target,
        );

    List<String> textsOf(GraphLine line) => [
      for (final label in line.labels) label.text,
    ];

    test('relationships going the same way share one line', () {
      final line = lineOf(
        snapshotWith([
          relationship('c002', 'follows_closely', 'c001'),
          relationship('c002', 'fears', 'c001'),
        ]),
        'c002',
        'c001',
      );

      expect(textsOf(line), ['watches', 'follows closely', 'fears']);
    });

    test('opposite directions get a line each', () {
      final snapshot = snapshotWith([relationship('c001', 'avoids', 'c002')]);

      expect(textsOf(lineOf(snapshot, 'c002', 'c001')), ['watches']);
      expect(textsOf(lineOf(snapshot, 'c001', 'c002')), ['avoids']);
    });

    test('a revealed identity joins the line of who they really are', () {
      final line = lineOf(
        snapshotWith([relationship('c004', 'hires', 'c001')]),
        'c002',
        'c001',
      );

      expect(textsOf(line), ['watches', 'hires']);
    });

    test('a repeated relationship is listed once', () {
      final line = lineOf(
        snapshotWith([relationship('c002', 'watches', 'c001')]),
        'c002',
        'c001',
      );

      expect(textsOf(line), ['watches']);
      expect(line.labels.single.isNew, isTrue);
    });

    test('a line is new if any of its relationships is', () {
      final line = lineOf(
        snapshotWith([relationship('c002', 'fears', 'c001')]),
        'c002',
        'c001',
      );

      expect(line.isNew, isTrue);
      expect([for (final label in line.labels) label.isNew], [false, true]);
    });

    test('a line is dashed only if all of it is in the past', () {
      final allPast = lineOf(
        snapshotWith([
          relationship('c003', 'taught', 'c002', temporal: 'past'),
          relationship('c003', 'fought', 'c002', temporal: 'past'),
        ]),
        'c003',
        'c002',
      );
      expect(allPast.isPast, isTrue);
      expect(textsOf(allPast), ['taught', 'fought']);

      final mixed = lineOf(
        snapshotWith([relationship('c002', 'hated', 'c001', temporal: 'past')]),
        'c002',
        'c001',
      );
      expect(mixed.isPast, isFalse);
      expect(textsOf(mixed), ['watches', 'hated (past)']);
    });

    test('a line is faded only if none of it is stated directly', () {
      final allInferred = lineOf(
        snapshotWith([
          relationship('c003', 'knows', 'c002', assertion: 'inferred'),
          relationship('c003', 'trusts', 'c002', assertion: 'reported'),
        ]),
        'c003',
        'c002',
      );
      expect(allInferred.isInferred, isTrue);
      expect(allInferred.labels.any((label) => label.isFaded), isFalse);

      final mixed = lineOf(
        snapshotWith([
          relationship(
            'c002',
            'fears',
            'c001',
            section: 's1',
            assertion: 'inferred',
          ),
        ]),
        'c002',
        'c001',
      );
      expect(mixed.isInferred, isFalse);
      expect([for (final label in mixed.labels) label.isFaded], [false, true]);
    });

    test('a new inferred relationship is not faded', () {
      final line = lineOf(
        snapshotWith([
          relationship('c002', 'fears', 'c001', assertion: 'inferred'),
        ]),
        'c002',
        'c001',
      );

      expect(line.labels.last.isFaded, isFalse);
    });

    testWidgets('one line per direction, with every label once zoomed in', (
      tester,
    ) async {
      final snapshot = snapshotWith([
        relationship('c002', 'follows', 'c001'),
        relationship('c002', 'fears', 'c001'),
        relationship('c001', 'avoids', 'c002'),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CharacterGraphView(
              snapshot: snapshot,
              onEntityTap: (_) {},
              onGuideTap: () {},
            ),
          ),
        ),
      );

      final graph = tester.renderObject(
        find.descendant(
          of: find.byType(InteractiveViewer),
          matching: find.byType(CustomPaint),
        ),
      );
      // c002 -> c001, c001 -> c002 and c003 -> c001.
      expect(graph, paintsExactlyCountTimes(#drawLine, 3));

      // The test font is wide, so it takes more than one pinch to make room.
      final center = tester.getCenter(find.byType(InteractiveViewer));
      for (var pinch = 0; pinch < 2; pinch++) {
        final left = await tester.startGesture(center - const Offset(20, 0));
        final right = await tester.startGesture(center + const Offset(20, 0));
        await tester.pump();
        await left.moveBy(const Offset(-100, 0));
        await right.moveBy(const Offset(100, 0));
        await tester.pump();
        await left.up();
        await right.up();
        await tester.pumpAndSettle();
      }

      // Those three lines' labels, and three names.
      expect(graph, paintsExactlyCountTimes(#drawParagraph, 6));
    });
  });

  group('past where the reader has read', () {
    final latest = find.text('Known by the end of Chapter 2: The Letter');
    final earliest = find.textContaining('Known by the end of Chapter 1');
    final warning = find.text('Past where you’ve read');

    Future<void> pumpAt(WidgetTester tester, int finished) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StoryMapScreen(
              model: storyModelFixture(),
              finishedSections: finished,
            ),
          ),
        ),
      );
    }

    Future<void> slideToEnd(WidgetTester tester) async {
      await tester.drag(find.byType(Slider), const Offset(1000, 0));
      await tester.pumpAndSettle();
    }

    testWidgets('starts at the last section they finished', (tester) async {
      await pumpAt(tester, 1);
      expect(earliest, findsOne);
      expect(latest, findsNothing);
    });

    testWidgets('sliding past it shows nothing until they let go', (
      tester,
    ) async {
      await pumpAt(tester, 1);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Slider)),
      );
      await gesture.moveBy(const Offset(1000, 0));
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 1);
      expect(earliest, findsOne, reason: 'still the finished section');
      expect(latest, findsNothing);
      expect(warning, findsNothing);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(warning, findsOne);
      expect(latest, findsNothing, reason: 'not behind the dialog either');
    });

    testWidgets('confirming shows it', (tester) async {
      await pumpAt(tester, 1);
      await slideToEnd(tester);
      expect(find.textContaining('may spoil the story'), findsOne);
      await tester.tap(find.text('Show anyway'));
      await tester.pumpAndSettle();
      expect(latest, findsOne);
    });

    testWidgets('cancelling goes back', (tester) async {
      await pumpAt(tester, 1);
      await slideToEnd(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(earliest, findsOne);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 0);
    });

    testWidgets('confirmed once, it doesn\'t ask again', (tester) async {
      await pumpAt(tester, 1);
      await slideToEnd(tester);
      await tester.tap(find.text('Show anyway'));
      await tester.pumpAndSettle();

      await slideToFirstChapter(tester);
      expect(earliest, findsOne);
      await slideToEnd(tester);
      expect(warning, findsNothing);
      expect(latest, findsOne);
    });

    testWidgets('sections they finished never ask', (tester) async {
      await pumpAt(tester, 2);
      expect(latest, findsOne);
      await slideToFirstChapter(tester);
      await slideToEnd(tester);
      expect(warning, findsNothing);
    });

    testWidgets('with nothing finished, offers to show the first section', (
      tester,
    ) async {
      await pumpAt(tester, 0);
      expect(find.textContaining('Known by the end'), findsNothing);
      expect(find.byType(CharacterGraphView), findsNothing);

      await tester.tap(find.textContaining('anyway'));
      await tester.pumpAndSettle();
      expect(warning, findsOne);
      await tester.tap(find.text('Show anyway'));
      await tester.pumpAndSettle();
      expect(earliest, findsOne);
      expect(find.byType(CharacterGraphView), findsOne);
    });

    testWidgets('with nothing finished, cancelling keeps it hidden', (
      tester,
    ) async {
      await pumpAt(tester, 0);
      await tester.tap(find.textContaining('anyway'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Known by the end'), findsNothing);
    });

    testWidgets('follows the reader reading on', (tester) async {
      await pumpAt(tester, 1);
      expect(earliest, findsOne);
      await pumpAt(tester, 2);
      expect(latest, findsOne);
    });

    testWidgets('turning back takes the map back with the reader', (
      tester,
    ) async {
      await pumpAt(tester, 2);
      expect(latest, findsOne);
      await pumpAt(tester, 1);
      expect(earliest, findsOne);
      expect(latest, findsNothing);
      await slideToEnd(tester);
      expect(warning, findsOne);
    });

    testWidgets('a section they agreed to see stays agreed', (tester) async {
      await pumpAt(tester, 1);
      await slideToEnd(tester);
      await tester.tap(find.text('Show anyway'));
      await tester.pumpAndSettle();
      expect(latest, findsOne);
      await pumpAt(tester, 1);
      expect(latest, findsOne);
      await slideToFirstChapter(tester);
      await slideToEnd(tester);
      expect(warning, findsNothing);
    });

    group('partway through a section', () {
      final soFar = find.text('Known so far in Chapter 2: The Letter');
      final wholeChapter = find.byType(Switch);

      Future<void> pumpPartway(
        WidgetTester tester,
        Set<String> hidden, {
        int finished = 1,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StoryMapScreen(
                model: storyModelFixture(),
                finishedSections: finished,
                hiddenInNext: hidden,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> switchToWhole(WidgetTester tester) async {
        await tester.tap(wholeChapter);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Show anyway'));
        await tester.pumpAndSettle();
      }

      testWidgets('shows only what has been reached', (tester) async {
        await pumpPartway(tester, {'f004', 'f012', 'f014'});
        expect(soFar, findsOne);
        // Elian's name, learned in chapter 2, is still ahead of the reader.
        expect(find.textContaining('Elian'), findsNothing);
      });

      testWidgets('showing the whole chapter asks first', (tester) async {
        await pumpPartway(tester, {'f004'});
        await tester.tap(wholeChapter);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('The rest of Chapter 2: The Letter'),
          findsOne,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(soFar, findsOne);
        expect(tester.widget<Switch>(wholeChapter).value, isFalse);

        await switchToWhole(tester);
        expect(latest, findsOne);
        expect(soFar, findsNothing);
        expect(tester.widget<Switch>(wholeChapter).value, isTrue);
      });

      testWidgets('can go back to what has been read, without asking', (
        tester,
      ) async {
        await pumpPartway(tester, {'f004', 'f012', 'f014'});
        await switchToWhole(tester);
        await tester.tap(wholeChapter);
        await tester.pumpAndSettle();

        expect(warning, findsNothing);
        expect(soFar, findsOne);
        expect(tester.widget<Switch>(wholeChapter).value, isFalse);
      });

      testWidgets('stays on while reading on in that section', (tester) async {
        await pumpPartway(tester, {'f004'});
        await switchToWhole(tester);
        await pumpPartway(tester, const {});
        expect(latest, findsOne);
      });

      testWidgets('doesn\'t carry over to the next section', (tester) async {
        await pumpPartway(tester, const {'f001'}, finished: 0);
        await switchToWhole(tester);
        expect(earliest, findsOne);

        await pumpPartway(tester, {'f004'});
        expect(soFar, findsOne);
        expect(tester.widget<Switch>(wholeChapter).value, isFalse);
      });

      testWidgets('agreeing to a later section leaves this one partial', (
        tester,
      ) async {
        await pumpPartway(tester, const {'f001'}, finished: 0);
        await slideToEnd(tester);
        await tester.tap(find.text('Show anyway'));
        await tester.pumpAndSettle();
        expect(latest, findsOne);

        await slideToFirstChapter(tester);
        expect(find.text('Known so far in Chapter 1: Arrival'), findsOne);
      });

      testWidgets('there is no switch on a finished section', (tester) async {
        await pumpPartway(tester, {'f004'});
        await slideToFirstChapter(tester);
        expect(earliest, findsOne);
        expect(wholeChapter, findsNothing);
      });

      testWidgets('follows the reader on as they read', (tester) async {
        await pumpPartway(tester, {'f004'});
        await pumpAt(tester, 2);
        await tester.pumpAndSettle();
        expect(latest, findsOne);
        expect(soFar, findsNothing);
      });
    });

    Future<void> pumpGrowing(
      WidgetTester tester, {
      required bool complete,
      required int? finished,
    }) async {
      final json = storyModelFixtureJson();
      if (!complete) {
        (json['processed_sections'] as List).removeWhere(
          (section) => (section as Map)['section_id'] == 's2',
        );
        final records = json['records'] as Map;
        for (final list in records.values) {
          (list as List).removeWhere(
            (record) => (record as Map)['learned_in_section_id'] == 's2',
          );
        }
        json['transitions'] = <Object>[];
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StoryMapScreen(
              model: StoryModel.fromJson(json),
              finishedSections: finished,
            ),
          ),
        ),
      );
    }

    testWidgets('a section added past the reader doesn\'t show by itself', (
      tester,
    ) async {
      await pumpGrowing(tester, complete: false, finished: 1);
      expect(earliest, findsOne);
      await pumpGrowing(tester, complete: true, finished: 1);
      expect(earliest, findsOne);
      expect(latest, findsNothing);
      await slideToEnd(tester);
      expect(warning, findsOne);
    });

    testWidgets('a section added that they have read does', (tester) async {
      await pumpGrowing(tester, complete: false, finished: 2);
      expect(earliest, findsOne);
      await pumpGrowing(tester, complete: true, finished: 2);
      expect(latest, findsOne);
    });
  });

  test('a section remembers whether its quotes were checked', () {
    StorySection parse(Map<String, dynamic> extra) => StorySection.fromJson({
      'section_id': 's',
      'section_order': 1,
      'chapter_number': null,
      'title': 'S',
      ...extra,
    });
    expect(parse(const {}).quotesChecked, isTrue);
    expect(parse(const {'quotes_checked': false}).quotesChecked, isFalse);
    expect(parse(const {'href': 'a.xhtml'}).href, 'a.xhtml');
  });
}
