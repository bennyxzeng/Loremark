import 'package:flutter_test/flutter_test.dart';

import '../../tool/acceptance/uiautomator.dart';

/// A dump trimmed from the emulator: Flutter semantics appear as
/// `content-desc`, `text` stays empty, and uiautomator adds a trailer line.
const _dump = '''
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" resource-id="" class="android.widget.FrameLayout" content-desc="" clickable="false" bounds="[0,0][1080,2400]">
    <node index="0" text="" resource-id="" class="android.view.View" content-desc="Chapter 1" clickable="false" bounds="[48,300][400,360]" />
    <node index="1" text="" resource-id="" class="android.widget.Button" content-desc="Next page" clickable="true" bounds="[954,2033][1080,2159]" />
    <node index="2" text="" resource-id="" class="android.view.View" content-desc="Acceptance Harbor&#10;Loremark Test Generator" clickable="true" bounds="[24,500][1056,700]" />
    <node index="3" text="" resource-id="" class="android.view.View" content-desc="Read&#10;Tab 1 of 4" clickable="true" bounds="[0,2200][270,2400]" />
  </node>
</hierarchy>
UI hierchary dumped to: /dev/tty''';

void main() {
  group('parseUiDump', () {
    test('reads content descriptions, bounds and clickability', () {
      final nodes = parseUiDump(_dump);

      expect(nodes, hasLength(5));
      final next = findByDesc(nodes, 'Next page')!;
      expect(next.className, 'android.widget.Button');
      expect(next.clickable, isTrue);
      expect(next.bounds!.left, 954);
      expect(next.bounds!.bottom, 2159);
      expect(next.bounds!.centerX, 1017);
      expect(next.bounds!.centerY, 2096);
    });

    test('keeps the newline of a merged card and matches by substring', () {
      final nodes = parseUiDump(_dump);

      final card = findByDesc(nodes, 'Acceptance Harbor')!;
      expect(card.contentDesc, 'Acceptance Harbor\nLoremark Test Generator');
      expect(findByDesc(nodes, 'Tab 1 of 4')!.contentDesc, startsWith('Read'));
    });

    test('finds nothing for an absent description', () {
      expect(findByDesc(parseUiDump(_dump), 'Previous page'), isNull);
    });

    test('gives an empty list for uiautomator errors and partial output', () {
      expect(parseUiDump(''), isEmpty);
      expect(parseUiDump('ERROR: could not get idle state.'), isEmpty);
      expect(
        parseUiDump('<?xml version="1.0"?><hierarchy rotation="0">'),
        isEmpty,
      );
      expect(parseUiDump('<?xml ?><hierarchy><node </hierarchy>'), isEmpty);
    });

    test('tolerates a node without bounds', () {
      final nodes = parseUiDump(
        '<hierarchy><node class="a" content-desc="X" clickable="false"/></hierarchy>',
      );

      expect(nodes.single.bounds, isNull);
    });
  });
}
