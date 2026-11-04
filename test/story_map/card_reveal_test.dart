import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/story_map/card_reveal.dart';
import 'package:loremark/story_map/card_sounds.dart';
import 'package:loremark/story_map/character_card_view.dart';
import 'package:loremark/story_map/collectible_card.dart';
import 'package:loremark/story_map/story_map_screen.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/theme/loremark_theme.dart';

import '../story_model/story_model_fixture.dart';
import 'fake_card_sounds.dart';

void main() {
  late FakeCardSounds sounds;

  setUp(() => sounds = FakeCardSounds());

  Future<void> pumpStoryMap(WidgetTester tester, {StoryModel? model}) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLoremarkTheme(),
        home: Scaffold(
          body: StoryMapScreen(
            model: model ?? storyModelFixture(),
            sounds: sounds,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Characters'));
    await tester.pumpAndSettle();
  }

  Future<void> slideToChapter1(WidgetTester tester) async {
    await tester.drag(find.byType(Slider), const Offset(-1000, 0));
    await tester.pumpAndSettle();
  }

  Future<void> slideToChapter2(WidgetTester tester) async {
    await tester.drag(find.byType(Slider), const Offset(1000, 0));
    await tester.pumpAndSettle();
  }

  /// Taps a name in the list and lets the card's route open.
  Future<void> open(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
  }

  StoryModel withRenamedMara() {
    final json = storyModelFixtureJson();
    final names = (json['records'] as Map)['names'] as List;
    final name = names.cast<Map>().singleWhere((r) => r['id'] == 'f006');
    (name['payload'] as Map)['text'] = 'Captain Rowe';
    return StoryModel.fromJson(json);
  }

  /// Gives Elian, who is new in chapter 2, [count] more attributes.
  StoryModel withElianFacts(int count) {
    final json = storyModelFixtureJson();
    final attributes = (json['records'] as Map)['attributes'] as List;
    for (var i = 0; i < count; i++) {
      attributes.add(<String, dynamic>{
        'id': 'extra$i',
        'introduced_revision': 2,
        'learned_in_section_id': 's2',
        'legacy_id': null,
        'payload': <String, dynamic>{
          'entity_id': 'c003',
          'label': 'detail_$i',
          'value': 'fact $i',
          'assertion': 'explicit',
          'attributed_to_id': null,
        },
        'evidence': <Map<String, dynamic>>[],
      });
    }
    return StoryModel.fromJson(json);
  }

  group('a reveal', () {
    testWidgets('plays when a new character first opens', (tester) async {
      await pumpStoryMap(tester);

      await open(tester, 'Elian');
      expect(find.byType(CardCover), findsOne);
      expect(find.text('Unknown'), findsOne);

      await tester.pumpAndSettle();
      expect(find.byType(CardCover), findsNothing);
      expect(find.byType(CardFront), findsOne);
      expect(find.text('First appearance'), findsOne);
    });

    testWidgets('plays its sounds in order, by the card\'s stars', (
      tester,
    ) async {
      await pumpStoryMap(tester);

      await open(tester, 'Elian');
      await tester.pumpAndSettle();

      // Elian has 3 facts, so 2 stars.
      expect(sounds.played, [
        CardSound.chargeShort,
        CardSound.burstLow,
        CardSound.flip,
        CardSound.star1,
        CardSound.star2,
      ]);
    });

    testWidgets('sounds bigger for a high-star card', (tester) async {
      await pumpStoryMap(tester, model: withElianFacts(12));

      await open(tester, 'Elian');
      await tester.pumpAndSettle();

      // 3 facts and 12 more make 15, so 4 stars.
      expect(sounds.played, [
        CardSound.chargeLong,
        CardSound.burstHigh,
        CardSound.flip,
        CardSound.star1,
        CardSound.star2,
        CardSound.star3,
        CardSound.star4,
      ]);
    });

    testWidgets('plays once per chapter', (tester) async {
      await pumpStoryMap(tester);
      await open(tester, 'Elian');
      await tester.pumpAndSettle();
      await close(tester);
      sounds.played.clear();

      await open(tester, 'Elian');

      expect(find.byType(CardCover), findsNothing);
      expect(find.byType(CardFront), findsOne);
      await tester.pumpAndSettle();
      expect(sounds.played, isEmpty);
    });

    testWidgets('plays when a new name reveals who someone is', (tester) async {
      await pumpStoryMap(tester, model: withRenamedMara());

      await open(tester, 'Captain Rowe');
      expect(
        find.descendant(
          of: find.byType(CardCover),
          matching: find.text('Mara'),
        ),
        findsOne,
      );

      await tester.pumpAndSettle();
      expect(find.text('Revealed · was Mara'), findsOne);
    });

    testWidgets('plays again in the next chapter that reveals more', (
      tester,
    ) async {
      await pumpStoryMap(tester, model: withRenamedMara());
      await slideToChapter1(tester);

      await open(tester, 'Mara');
      expect(find.byType(CardCover), findsOne);
      await tester.pumpAndSettle();
      await close(tester);

      await slideToChapter2(tester);
      await open(tester, 'Captain Rowe');
      expect(find.byType(CardCover), findsOne);
      await tester.pumpAndSettle();
    });

    testWidgets('plays when an identity link reveals who someone is', (
      tester,
    ) async {
      await pumpStoryMap(tester);

      await open(tester, 'the stranger');
      expect(find.byType(CardCover), findsOne);

      await tester.pumpAndSettle();
      expect(find.text('Revealed · also Captain Vell'), findsOne);
    });

    testWidgets('does not play for someone nothing new happened to', (
      tester,
    ) async {
      await pumpStoryMap(tester);

      // Mara only had her name spelled out in chapter 2.
      await open(tester, 'Mara Quinn');

      expect(find.byType(CardCover), findsNothing);
      expect(find.byType(CardFront), findsOne);
      expect(find.textContaining('Revealed'), findsNothing);
      await tester.pumpAndSettle();
      expect(sounds.played, isEmpty);
    });

    testWidgets('does not play for places and groups', (tester) async {
      await pumpStoryMap(tester);
      await slideToChapter1(tester);
      await tester.tap(find.text('Chapter'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ActionChip, 'Harbor Guild'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(CardCover), findsNothing);
      expect(find.text('First appearance'), findsOne);
      await tester.pumpAndSettle();
      expect(sounds.played, isEmpty);
    });

    testWidgets('does not play when animations are turned off', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpStoryMap(tester);

      await open(tester, 'Elian');

      expect(find.byType(CardCover), findsNothing);
      expect(find.byType(CardFront), findsOne);
      await tester.pumpAndSettle();
      expect(sounds.played, isEmpty);
    });

    testWidgets('can be skipped with a tap', (tester) async {
      await pumpStoryMap(tester);
      await open(tester, 'Elian');

      await tester.tapAt(const Offset(400, 700));
      await tester.pumpAndSettle();

      expect(find.byType(CardCover), findsNothing);
      expect(find.byType(CardFront), findsOne);
      expect(sounds.stops, greaterThan(0));
      // It was skipped before the first sound was due.
      expect(sounds.played, isEmpty);
      expect(
        tester.widget<CardStars>(find.byType(CardStars)).lit,
        tester.widget<CardStars>(find.byType(CardStars)).stars,
      );
    });
  });

  group('a card', () {
    testWidgets('shows who this is on the front', (tester) async {
      await pumpStoryMap(tester);

      await open(tester, 'Mara Quinn');

      final front = find.byType(CardFront);
      for (final text in [
        'CHARACTER',
        'CHAPTER 2',
        'Mara Quinn',
        'Also the harbor girl',
      ]) {
        expect(
          find.descendant(of: front, matching: find.text(text)),
          findsOne,
          reason: text,
        );
      }
      final stars = tester.widget<CardStars>(find.byType(CardStars));
      expect(stars.stars, 3);
      expect(stars.lit, 3);
    });

    testWidgets('never shows a later chapter on the front', (tester) async {
      await pumpStoryMap(tester);
      await slideToChapter1(tester);

      await open(tester, 'Mara');
      await tester.pumpAndSettle();

      final front = find.byType(CardFront);
      expect(
        find.descendant(of: front, matching: find.textContaining('Quinn')),
        findsNothing,
      );
      expect(tester.widget<CardStars>(find.byType(CardStars)).stars, 2);
    });

    const details = 'character · First seen in Chapter 1';
    final phones = TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    });
    const page = Rect.fromLTRB(80, 48, 720, 1400);

    /// Opens Mara's card, turned over to the page of details. Returns where the
    /// card rests.
    Future<Rect> openPage(WidgetTester tester) async {
      await pumpStoryMap(tester);
      await open(tester, 'Mara Quinn');
      await tester.pumpAndSettle();
      final card = tester.getRect(find.byType(CardFlip));
      await tester.tap(find.byType(CardFront));
      await tester.pumpAndSettle();
      return card;
    }

    testWidgets('turns over to a page of details', (tester) async {
      await openPage(tester);

      expect(find.byType(CardFront), findsNothing);
      expect(find.text(details), findsOne);
      expect(find.text('Tap to flip · Drag to tilt'), findsNothing);
      expect(sounds.played, [CardSound.flip]);

      // A page for reading: a stray tap doesn't turn it back.
      await tester.tap(find.text(details));
      await tester.pumpAndSettle();
      expect(find.text(details), findsOne);
    });

    testWidgets('pulling the handle turns it back to the front', (
      tester,
    ) async {
      final card = await openPage(tester);

      await tester.drag(find.byType(CardPageHandle), const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(find.byType(CardFront), findsOne);
      expect(find.byType(CharacterCardView), findsNothing);
      expect(find.text('Tap to flip · Drag to tilt'), findsOne);
      expect(tester.getRect(find.byType(CardFlip)), card);
      expect(sounds.played, [CardSound.flip, CardSound.flip]);

      // And it opens again just the same.
      await tester.tap(find.byType(CardFront));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(CardFlip)), page);
    }, variant: phones);

    testWidgets('shrinks with the finger, and turns back without waiting', (
      tester,
    ) async {
      await openPage(tester);

      final drag = await tester.startGesture(
        tester.getCenter(find.byType(CardPageHandle)),
      );
      await tester.pump();
      await drag.moveBy(const Offset(0, 40));
      await tester.pump();
      await drag.moveBy(const Offset(0, 40));
      await tester.pump();
      final pulled = tester.getSize(find.byType(CardFlip));
      expect(pulled.width, lessThan(page.width));
      expect(find.byType(CharacterCardView), findsOne);

      await drag.moveBy(const Offset(0, 40));
      await tester.pump();
      await drag.moveBy(const Offset(0, 40));
      await tester.pump();
      final further = tester.getSize(find.byType(CardFlip));
      expect(further.width, lessThan(pulled.width));

      // The finger is still down.
      await tester.pumpAndSettle();
      expect(find.byType(CardFront), findsOne);

      await drag.up();
      await tester.pumpAndSettle();
      expect(find.byType(CardFront), findsOne);
      expect(sounds.played, [CardSound.flip, CardSound.flip]);
    });

    testWidgets('springs back when let go early', (tester) async {
      await openPage(tester);

      final drag = await tester.startGesture(
        tester.getCenter(find.byType(CardPageHandle)),
      );
      await tester.pump();
      await drag.moveBy(const Offset(0, 30));
      await tester.pump();
      await drag.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(tester.getSize(find.byType(CardFlip)).width, lessThan(page.width));

      await tester.pump(const Duration(seconds: 1));
      await drag.up();
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byType(CardFlip)), page);
      expect(find.text(details), findsOne);
      expect(sounds.played, [CardSound.flip]);
    });

    testWidgets('dragging back up undoes the pull', (tester) async {
      await openPage(tester);

      final drag = await tester.startGesture(
        tester.getCenter(find.byType(CardPageHandle)),
      );
      await tester.pump();
      await drag.moveBy(const Offset(0, 30));
      await tester.pump();
      await drag.moveBy(const Offset(0, 40));
      await tester.pump();
      expect(tester.getSize(find.byType(CardFlip)).width, lessThan(page.width));

      await drag.moveBy(const Offset(0, -100));
      await tester.pump();
      expect(tester.getRect(find.byType(CardFlip)), page);

      await drag.up();
      await tester.pumpAndSettle();
      expect(find.text(details), findsOne);
    });

    testWidgets('a quick flick down is enough', (tester) async {
      await openPage(tester);

      await tester.fling(
        find.byType(CardPageHandle),
        const Offset(0, 80),
        1500,
      );
      await tester.pumpAndSettle();

      expect(find.byType(CardFront), findsOne);
    });

    testWidgets('can be pulled however far the list has scrolled', (
      tester,
    ) async {
      await openPage(tester);
      tester.view.physicalSize = const Size(800, 400);
      await tester.pumpAndSettle();
      final scrollable = find.descendant(
        of: find.byType(CharacterCardView),
        matching: find.byType(Scrollable),
      );

      await tester.drag(scrollable, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        greaterThan(150),
      );

      await tester.drag(find.byType(CardPageHandle), const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(find.byType(CardFront), findsOne);
    });

    testWidgets('dragging the list only ever scrolls it', (tester) async {
      await openPage(tester);

      await tester.drag(find.text(details), const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byType(CardFlip)), page);
      expect(find.text(details), findsOne);
      expect(sounds.played, [CardSound.flip]);
    }, variant: phones);

    testWidgets('screen readers can turn it back from the handle', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await openPage(tester);

      tester.semantics.tap(find.semantics.byLabel('Back to card'));
      await tester.pumpAndSettle();

      expect(find.byType(CardFront), findsOne);
      semantics.dispose();
    });

    testWidgets('keeps the same buttons on the card and the page', (
      tester,
    ) async {
      await pumpStoryMap(tester);
      await open(tester, 'Mara Quinn');
      await tester.pumpAndSettle();
      final back = tester.getCenter(find.byTooltip('Back'));
      final mute = tester.getCenter(find.byTooltip('Mute card sounds'));
      expect(find.byTooltip('Close'), findsNothing);

      await tester.tap(find.byType(CardFront));
      await tester.pumpAndSettle();

      expect(tester.getCenter(find.byTooltip('Back')), back);
      expect(tester.getCenter(find.byTooltip('Mute card sounds')), mute);
      expect(find.byTooltip('Close'), findsNothing);
    });

    testWidgets('the back arrow leaves the card altogether', (tester) async {
      await pumpStoryMap(tester);
      await open(tester, 'Mara Quinn');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.byType(CardFront), findsNothing);
      expect(find.text('Mara Quinn'), findsOne);
    });

    testWidgets('the back arrow leaves the open page altogether', (
      tester,
    ) async {
      await openPage(tester);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.byType(CharacterCardView), findsNothing);
      expect(find.byType(CardFront), findsNothing);
      expect(find.text('Mara Quinn'), findsOne);
    });

    testWidgets('finishes turning over before it opens up', (tester) async {
      await pumpStoryMap(tester);
      await open(tester, 'Mara Quinn');
      await tester.pumpAndSettle();
      final card = tester.getSize(find.byType(CardFlip));

      await tester.tap(find.byType(CardFront));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getSize(find.byType(CardFlip)), card);

      await tester.pump(const Duration(milliseconds: 350));
      final growing = tester.getSize(find.byType(CardFlip));
      expect(growing.width, greaterThan(card.width));
      expect(find.byType(CardFront), findsNothing);
      final laidOut = tester.getSize(find.byType(CharacterCardView));

      await tester.pumpAndSettle();
      final opened = tester.getRect(find.byType(CardFlip));
      expect(opened.width, greaterThan(growing.width));
      // Below the buttons, as wide as a sheet, down to the bottom of the screen.
      expect(opened, page);
      // The text never reflowed on the way.
      expect(tester.getSize(find.byType(CharacterCardView)), laidOut);
      expect(laidOut.width, opened.width);
    });

    testWidgets('opens and turns back at once when animations are turned off', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpStoryMap(tester);
      await open(tester, 'Mara Quinn');
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CardFront));
      await tester.pump();
      expect(tester.getRect(find.byType(CardFlip)), page);

      await tester.drag(find.byType(CardPageHandle), const Offset(0, 300));
      await tester.pump();
      expect(find.byType(CardFront), findsOne);
      expect(sounds.played, isEmpty);
    });

    testWidgets('closes when tapping above the open page', (tester) async {
      await pumpStoryMap(tester);
      await open(tester, 'Mara Quinn');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CardFront));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(400, 20));
      await tester.pumpAndSettle();

      expect(find.byType(CharacterCardView), findsNothing);
    });

    testWidgets('tilts when dragged, without turning over', (tester) async {
      await pumpStoryMap(tester);
      await open(tester, 'Mara Quinn');
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.byType(CardFront));
      final drag = await tester.startGesture(center);
      await tester.pump();
      await drag.moveBy(const Offset(60, 60));
      await tester.pump();
      await drag.moveBy(const Offset(40, 40));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.widget<CardFront>(find.byType(CardFront)).sheen, isNotNull);

      await drag.up();
      await tester.pumpAndSettle();

      expect(find.byType(CardFront), findsOne);
      expect(tester.widget<CardFront>(find.byType(CardFront)).sheen, isNull);
    });

    testWidgets('lets the light fade with the card after letting go', (
      tester,
    ) async {
      await pumpStoryMap(tester);
      await open(tester, 'Mara Quinn');
      await tester.pumpAndSettle();
      CardSheen? sheen() =>
          tester.widget<CardFront>(find.byType(CardFront)).sheen;
      double fromCenter() => (sheen()!.at - const Offset(0.5, 0.5)).distance;

      final drag = await tester.startGesture(
        tester.getCenter(find.byType(CardFront)),
      );
      await tester.pump();
      await drag.moveBy(const Offset(60, 60));
      await tester.pump();
      await drag.moveBy(const Offset(40, 40));
      await tester.pump(const Duration(milliseconds: 300));
      expect(sheen()!.amount, 1);
      final heldAt = fromCenter();

      await drag.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final fading = sheen()!.amount;
      final fadingAt = fromCenter();
      expect(fading, inExclusiveRange(0, 1));
      expect(fadingAt, lessThan(heldAt));

      await tester.pump(const Duration(milliseconds: 200));
      expect(sheen()!.amount, lessThan(fading));
      expect(fromCenter(), lessThan(fadingAt));

      await tester.pumpAndSettle();
      expect(sheen(), isNull);
    });

    testWidgets('opens a related card on top, and returns to it', (
      tester,
    ) async {
      await pumpStoryMap(tester);
      await open(tester, 'Mara Quinn');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CardFront));
      await tester.pumpAndSettle();

      const related = 'Mara Quinn member of Harbor Guild';
      await tester.scrollUntilVisible(
        find.text(related),
        100,
        scrollable: find.descendant(
          of: find.byType(CharacterCardView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.ensureVisible(find.text(related));
      await tester.pumpAndSettle();
      await tester.tap(find.text(related));
      await tester.pumpAndSettle();

      expect(find.text('ORGANIZATION'), findsOne);

      await tester.tapAt(const Offset(10, 700));
      await tester.pumpAndSettle();

      expect(find.text('ORGANIZATION'), findsNothing);
      expect(find.text(related), findsOne);
    });

    testWidgets('closes when tapping outside it', (tester) async {
      await pumpStoryMap(tester);
      await open(tester, 'Mara Quinn');
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 700));
      await tester.pumpAndSettle();

      expect(find.byType(CardFront), findsNothing);
    });
  });

  group('sound', () {
    testWidgets('can be muted from the card', (tester) async {
      await pumpStoryMap(tester);
      await open(tester, 'Mara Quinn');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Mute card sounds'));
      await tester.pumpAndSettle();

      expect(sounds.enabled, isFalse);
      expect(find.byTooltip('Unmute card sounds'), findsOne);

      await close(tester);
      await open(tester, 'Elian');
      await tester.pumpAndSettle();

      expect(sounds.played, isEmpty);
    });

    group('preference', () {
      late Directory directory;
      late CardSoundPreference preference;

      setUp(() async {
        directory = await Directory.systemTemp.createTemp('card_sounds');
        preference = CardSoundPreference(File('${directory.path}/a/b.json'));
      });

      tearDown(() => directory.delete(recursive: true));

      test('is on until the reader turns it off', () async {
        expect(await preference.load(), isTrue);
      });

      test('remembers the choice', () async {
        await preference.save(enabled: false);
        expect(await preference.load(), isFalse);

        await preference.save(enabled: true);
        expect(await preference.load(), isTrue);
      });

      test('counts a damaged file as on', () async {
        await preference.file.create(recursive: true);
        await preference.file.writeAsString('not json');

        expect(await preference.load(), isTrue);
      });
    });

    test('every sound has a file', () {
      for (final sound in CardSound.values) {
        final file = File('assets/sounds/${sound.file}.wav');
        expect(file.existsSync(), isTrue, reason: file.path);
        expect(file.lengthSync(), greaterThan(44), reason: file.path);
      }
    });

    test('each star has its own sound', () {
      expect({for (var n = 1; n <= 5; n++) CardSound.star(n)}, hasLength(5));
    });
  });
}
