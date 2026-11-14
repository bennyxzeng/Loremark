import 'package:xml/xml.dart';

/// One node of a `uiautomator dump`.
///
/// Flutter semantics show up as `content-desc`; `text` stays empty, and
/// `resource-id` is never set, so the harness matches on [contentDesc].
class UiNode {
  const UiNode({
    required this.className,
    required this.contentDesc,
    required this.bounds,
    required this.clickable,
  });

  final String className;
  final String contentDesc;
  final UiBounds? bounds;
  final bool clickable;

  @override
  String toString() => '$className "$contentDesc" $bounds';
}

/// A node's `[left,top][right,bottom]` rectangle in screen pixels.
class UiBounds {
  const UiBounds(this.left, this.top, this.right, this.bottom);

  final int left;
  final int top;
  final int right;
  final int bottom;

  int get centerX => (left + right) ~/ 2;
  int get centerY => (top + bottom) ~/ 2;

  @override
  String toString() => '[$left,$top][$right,$bottom]';
}

final _boundsPattern = RegExp(r'\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]');

UiBounds? _parseBounds(String? raw) {
  final match = raw == null ? null : _boundsPattern.firstMatch(raw);
  if (match == null) return null;
  final n = [for (var i = 1; i <= 4; i++) int.parse(match.group(i)!)];
  return UiBounds(n[0], n[1], n[2], n[3]);
}

/// All nodes of a `uiautomator dump`, in document order.
///
/// [dump] may carry the "UI hierchary dumped to: ..." line that follows the
/// XML, and uiautomator's own error text instead of XML ("ERROR: could not get
/// idle state", a null root node). Anything that isn't a hierarchy gives an
/// empty list, so a polling caller just tries again.
List<UiNode> parseUiDump(String dump) {
  final start = dump.indexOf('<?xml');
  final hierarchy = dump.indexOf('<hierarchy');
  final from = start >= 0 ? start : hierarchy;
  final end = dump.lastIndexOf('</hierarchy>');
  if (from < 0 || end < 0) return const [];
  final XmlDocument document;
  try {
    document = XmlDocument.parse(
      dump.substring(from, end + '</hierarchy>'.length),
    );
  } on XmlException {
    return const [];
  }
  return [
    for (final element in document.findAllElements('node'))
      UiNode(
        className: element.getAttribute('class') ?? '',
        contentDesc: element.getAttribute('content-desc') ?? '',
        bounds: _parseBounds(element.getAttribute('bounds')),
        clickable: element.getAttribute('clickable') == 'true',
      ),
  ];
}

/// The first node whose content description contains [needle].
///
/// Flutter merges descendants and appends hints ("Read\nTab 1 of 4"), so an
/// exact match would be brittle.
UiNode? findByDesc(List<UiNode> nodes, String needle) {
  for (final node in nodes) {
    if (node.contentDesc.contains(needle)) return node;
  }
  return null;
}

/// The last node whose content description contains [needle].
///
/// A dialog comes after the page under it in the dump, so the last "Skip for
/// now" is the dialog's button. The first could be the page's own button
/// under the modal barrier, and tapping it would only dismiss the dialog.
UiNode? findLastByDesc(List<UiNode> nodes, String needle) {
  for (final node in nodes.reversed) {
    if (node.contentDesc.contains(needle)) return node;
  }
  return null;
}
