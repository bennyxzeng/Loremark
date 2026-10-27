/// A reader's position in a book, independent of the EPUB reader package.
///
/// [sectionIndex] is the index in the EPUB spine and [progression] is how far
/// into that section the reader is, from 0.0 to 1.0.
class TextPosition implements Comparable<TextPosition> {
  final int sectionIndex;
  final double progression;

  const TextPosition(this.sectionIndex, this.progression);

  /// Reads a position saved by [toJson].
  ///
  /// Throws a [FormatException] if the data is missing or out of range.
  factory TextPosition.fromJson(Map<String, dynamic> json) {
    final sectionIndex = json['sectionIndex'];
    final progression = json['progression'];
    if (sectionIndex is! int ||
        progression is! num ||
        sectionIndex < 0 ||
        progression < 0 ||
        progression > 1) {
      throw FormatException('Invalid TextPosition: $json');
    }
    return TextPosition(sectionIndex, progression.toDouble());
  }

  Map<String, dynamic> toJson() => {
    'sectionIndex': sectionIndex,
    'progression': progression,
  };

  @override
  int compareTo(TextPosition other) {
    if (sectionIndex != other.sectionIndex) {
      return sectionIndex.compareTo(other.sectionIndex);
    }
    return progression.compareTo(other.progression);
  }

  bool operator <(TextPosition other) => compareTo(other) < 0;
  bool operator >(TextPosition other) => compareTo(other) > 0;
  bool operator <=(TextPosition other) => compareTo(other) <= 0;
  bool operator >=(TextPosition other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is TextPosition &&
      other.sectionIndex == sectionIndex &&
      other.progression == progression;

  @override
  int get hashCode => Object.hash(sectionIndex, progression);

  @override
  String toString() => 'TextPosition($sectionIndex, $progression)';
}
