import 'dart:typed_data';

/// One `itemref` of an EPUB spine.
class SpineItem {
  const SpineItem({required this.path, required this.linear});

  /// The item's path inside the archive, such as `OEBPS/ch1.xhtml`.
  final String path;

  /// False for `linear="no"` items, such as footnotes, which renderers skip
  /// when turning pages.
  final bool linear;

  @override
  String toString() => 'SpineItem($path, linear: $linear)';
}

/// Every spine item of the EPUB in [bytes], in spine order, including
/// non-linear items, so index `i` is section `i`.
///
/// Throws a [FormatException] if [bytes] is not an EPUB.
List<SpineItem> spineFromBytes(Uint8List bytes) => throw UnimplementedError();

/// Plain text of every spine item of the EPUB in [bytes], in spine order.
///
/// Element `i` is the text of section `i`, the same index the reader reports
/// in `ReaderPosition.sectionIndex`. Throws a [FormatException] if [bytes] is
/// not an EPUB.
List<String> sectionTextsFromBytes(Uint8List bytes) =>
    throw UnimplementedError();

/// [spineFromBytes] for the file at [epubPath], parsed off the UI isolate.
Future<List<SpineItem>> readSpine(String epubPath) =>
    throw UnimplementedError();

/// [sectionTextsFromBytes] for the file at [epubPath], parsed off the UI
/// isolate.
Future<List<String>> readSectionTexts(String epubPath) =>
    throw UnimplementedError();

/// The index in [spine] of the item [href] points to, or null.
///
/// [href] may have a leading `/`, a `#fragment` or `?query`, and
/// percent-encoding, as renderers report it.
int? spineIndexOf(List<SpineItem> spine, String href) =>
    throw UnimplementedError();
