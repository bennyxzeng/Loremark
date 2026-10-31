import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Bytes standing in for a cover image.
final coverBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3]);

enum CoverStyle { none, epub2, epub3 }

/// A minimal EPUB with its package document in `OEBPS/` and its cover in
/// `OEBPS/images/`.
Uint8List buildEpub({
  String? title = 'The Glass Harbor',
  String? author = 'A. Writer',
  CoverStyle cover = CoverStyle.epub3,
}) {
  final metadata = [
    if (title != null) '<dc:title>$title</dc:title>',
    if (author != null) '<dc:creator>$author</dc:creator>',
    if (cover == CoverStyle.epub2) '<meta name="cover" content="cover-img"/>',
  ].join();
  final properties = cover == CoverStyle.epub3
      ? ' properties="cover-image"'
      : '';
  final coverItem = cover == CoverStyle.none
      ? ''
      : '<item id="cover-img" href="images/cover%20art.jpg" '
            'media-type="image/jpeg"$properties/>';

  final files = {
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<?xml version="1.0"?>'
        '<container version="1.0" '
        'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles>'
        '</container>',
    'OEBPS/content.opf':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">$metadata'
        '</metadata>'
        '<manifest>$coverItem'
        '<item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>'
        '</manifest>'
        '<spine><itemref idref="ch1"/></spine>'
        '</package>',
  };
  final archive = Archive();
  for (final MapEntry(:key, :value) in files.entries) {
    archive.addFile(ArchiveFile.bytes(key, utf8.encode(value)));
  }
  if (cover != CoverStyle.none) {
    archive.addFile(
      ArchiveFile.bytes('OEBPS/images/cover art.jpg', coverBytes),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}
