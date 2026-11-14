import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/eased_keyboard.dart';

void main() {
  const bar = 102.0;

  testWidgets('the page keeps to the keyboard while writing, and eases down '
      'with it all the way as it goes', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final field = find.byType(TextField);
    await tester.pumpWidget(
      const MaterialApp(
        home: EasedKeyboard(
          bar: bar,
          child: Scaffold(
            body: Column(children: [Spacer(), TextField()]),
            bottomNavigationBar: SizedBox(height: bar),
          ),
        ),
      ),
    );
    double bottom() => tester.getBottomLeft(field).dy;
    final rest = bottom();
    expect(rest, 800 - bar);

    await tester.tap(field);
    await tester.pump();
    for (var keyboard = 30.0; keyboard <= 300; keyboard += 30) {
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      await tester.pump();
      // Nothing being written is under the keyboard, nor further up.
      expect(
        bottom(),
        keyboard > bar ? 800 - keyboard : rest,
        reason: 'with the keyboard $keyboard high',
      );
    }

    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pump();
    var last = bottom();
    for (var keyboard = 270.0; keyboard >= 0; keyboard -= 30) {
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      await tester.pump();
      final now = bottom();
      expect(
        now,
        greaterThan(last),
        reason: 'with the keyboard $keyboard high',
      );
      // Still on its way while the keyboard is behind the bar.
      if (keyboard > 0) {
        expect(now, lessThan(rest), reason: 'with the keyboard $keyboard high');
      }
      last = now;
    }
    expect(bottom(), rest);
  });
}
