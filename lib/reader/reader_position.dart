/// Where the reader is in a book, as the reading view reports it.
///
/// [sectionIndex] is the item's index in the EPUB spine, counting every
/// `itemref` (non-linear ones too), so it lines up with `readSectionTexts`.
/// [progression] is how far into that section the reader is, from 0.0 to 1.0;
/// a finished section is exactly 1.0. [totalProgression] is how far into the
/// whole book, when the renderer knows it.
// TODO(kevin): switch to TextPosition once #2 merges. This is the only place
// the reader's position type is defined, and the JSON keys already match.
class ReaderPosition {
  const ReaderPosition(
    this.sectionIndex,
    this.progression, {
    this.totalProgression,
  });

  /// Reads a position saved by [toJson].
  ///
  /// Throws a [FormatException] if the data is missing or out of range.
  factory ReaderPosition.fromJson(Map<String, dynamic> json) {
    final sectionIndex = json['sectionIndex'];
    final progression = json['progression'];
    final totalProgression = json['totalProgression'];
    if (sectionIndex is! int ||
        sectionIndex < 0 ||
        !_isFraction(progression) ||
        (totalProgression != null && !_isFraction(totalProgression))) {
      throw FormatException('Invalid ReaderPosition: $json');
    }
    return ReaderPosition(
      sectionIndex,
      (progression as num).toDouble(),
      totalProgression: (totalProgression as num?)?.toDouble(),
    );
  }

  final int sectionIndex;
  final double progression;
  final double? totalProgression;

  static bool _isFraction(Object? value) =>
      value is num && value >= 0 && value <= 1;

  Map<String, dynamic> toJson() => {
    'sectionIndex': sectionIndex,
    'progression': progression,
    if (totalProgression != null) 'totalProgression': totalProgression,
  };

  @override
  bool operator ==(Object other) =>
      other is ReaderPosition &&
      other.sectionIndex == sectionIndex &&
      other.progression == progression &&
      other.totalProgression == totalProgression;

  @override
  int get hashCode => Object.hash(sectionIndex, progression, totalProgression);

  @override
  String toString() =>
      'ReaderPosition($sectionIndex, $progression, total: $totalProgression)';
}
