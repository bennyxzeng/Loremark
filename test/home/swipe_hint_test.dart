import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/home/swipe_hint.dart';

/// Remembers the hint in memory instead of on the device.
class _MemoryFlag implements SwipeHintFlag {
  bool isSeen = false;

  @override
  Future<bool> seen() async => isSeen;

  @override
  Future<void> markSeen() async => isSeen = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const hint = 'Swipe left or right to turn pages';
  late _MemoryFlag flag;

  setUp(() => flag = _MemoryFlag());

  Future<void> pumpHint(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeHint(flag: flag, child: const SizedBox.expand()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> swipeSideways(WidgetTester tester) async {
    await tester.dragFrom(const Offset(600, 200), const Offset(-200, 0));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the first time a book opens', (tester) async {
    await pumpHint(tester);
    expect(find.text(hint), findsOne);
  });

  testWidgets('stays while the reader scrolls up or down', (tester) async {
    await pumpHint(tester);
    await tester.dragFrom(const Offset(400, 300), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.text(hint), findsOne);
    expect(flag.isSeen, isFalse);
  });

  testWidgets('goes after the first sideways swipe', (tester) async {
    await pumpHint(tester);
    await swipeSideways(tester);
    expect(find.text(hint), findsNothing);
    expect(flag.isSeen, isTrue);
  });

  testWidgets('does not show again once seen', (tester) async {
    await pumpHint(tester);
    await swipeSideways(tester);

    // A new book screen, as when a book is opened again.
    await tester.pumpWidget(const SizedBox());
    await pumpHint(tester);
    expect(find.text(hint), findsNothing);
  });

  testWidgets('goes when tapped', (tester) async {
    await pumpHint(tester);
    await tester.tap(find.text(hint));
    await tester.pumpAndSettle();
    expect(find.text(hint), findsNothing);
    expect(flag.isSeen, isTrue);
  });

  group('on the device', () {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('swipe_hint_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => temp.path);
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      temp.deleteSync(recursive: true);
    });

    test('remembers that the hint was seen', () async {
      const flag = SwipeHintFlag();
      expect(await flag.seen(), isFalse);
      await flag.markSeen();
      expect(await flag.seen(), isTrue);
      expect(File('${temp.path}/swipe_hint_seen').existsSync(), isTrue);
    });
  });
}
