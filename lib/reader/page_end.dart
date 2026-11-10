/// Where the page the reader is on ends.
///
/// [block] counts the text blocks of the spine item at [sectionIndex] (see
/// `textBlocks`), from 0: it is the first one not wholly on the page, so every
/// block before it is on this page or an earlier one. [textProgression] is the
/// same point in the item's plain text, as `pageTextEnds` reports it: inside
/// [block] if the page ends partway through it.
///
/// The last page of a spine item has no block past it and reports nothing; its
/// position's progression is 1.0 instead.
class PageEnd {
  const PageEnd(this.sectionIndex, this.block, this.textProgression);

  /// Reads a page end saved by [toJson].
  ///
  /// Throws a [FormatException] if the data is missing or out of range.
  factory PageEnd.fromJson(Map<String, dynamic> json) {
    final sectionIndex = json['sectionIndex'];
    final block = json['block'];
    final textProgression = json['textProgression'];
    if (sectionIndex is! int ||
        sectionIndex < 0 ||
        block is! int ||
        block < 0 ||
        textProgression is! num ||
        textProgression < 0 ||
        textProgression > 1) {
      throw FormatException('Invalid PageEnd: $json');
    }
    return PageEnd(sectionIndex, block, textProgression.toDouble());
  }

  final int sectionIndex;
  final int block;
  final double textProgression;

  Map<String, dynamic> toJson() => {
    'sectionIndex': sectionIndex,
    'block': block,
    'textProgression': textProgression,
  };

  @override
  bool operator ==(Object other) =>
      other is PageEnd &&
      other.sectionIndex == sectionIndex &&
      other.block == block &&
      other.textProgression == textProgression;

  @override
  int get hashCode => Object.hash(sectionIndex, block, textProgression);

  @override
  String toString() => 'PageEnd($sectionIndex, $block, $textProgression)';
}
