/// Where the page the reader is on starts.
///
/// [cssSelector] finds the first element showing on the page, in the spine item
/// at [sectionIndex]. Everything before that element is on earlier pages, so the
/// reader has turned past it. The element itself may carry on from an earlier
/// page, so it doesn't count as read.
///
/// It names an element rather than a page number, so it stays right when the
/// font size or the screen changes.
class PageStart {
  const PageStart(this.sectionIndex, this.cssSelector);

  /// Reads a page start saved by [toJson].
  ///
  /// Throws a [FormatException] if the data is missing or out of range.
  factory PageStart.fromJson(Map<String, dynamic> json) {
    final sectionIndex = json['sectionIndex'];
    final cssSelector = json['cssSelector'];
    if (sectionIndex is! int ||
        sectionIndex < 0 ||
        cssSelector is! String ||
        cssSelector.isEmpty) {
      throw FormatException('Invalid PageStart: $json');
    }
    return PageStart(sectionIndex, cssSelector);
  }

  final int sectionIndex;
  final String cssSelector;

  Map<String, dynamic> toJson() => {
    'sectionIndex': sectionIndex,
    'cssSelector': cssSelector,
  };

  @override
  bool operator ==(Object other) =>
      other is PageStart &&
      other.sectionIndex == sectionIndex &&
      other.cssSelector == cssSelector;

  @override
  int get hashCode => Object.hash(sectionIndex, cssSelector);

  @override
  String toString() => 'PageStart($sectionIndex, $cssSelector)';
}
