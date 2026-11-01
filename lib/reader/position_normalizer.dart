import 'epub_sections.dart';
import 'reader_position.dart';

/// Turns the renderer's raw positions into the ones the app reports.
///
/// Readium reports where the current page starts, so the last page of a
/// section is below 1.0. Reading code needs a finished section at exactly 1.0,
/// so this reports it when the reader turns into the next section.
class PositionNormalizer {
  PositionNormalizer(this.spine);

  /// The book's spine, to know which sections page turns skip.
  final List<SpineItem> spine;

  /// The positions to report for [raw], in order. Empty if nothing changed.
  List<ReaderPosition> normalize(ReaderPosition raw) =>
      throw UnimplementedError();

  /// The positions to report when the reader reaches the end of the book.
  List<ReaderPosition> finish() => throw UnimplementedError();
}
