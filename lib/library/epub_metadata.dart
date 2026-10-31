import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// What the library shows for a book, read from the EPUB's package document.
class EpubMetadata {
  const EpubMetadata({
    required this.title,
    required this.author,
    required this.cover,
    required this.coverExtension,
  });

  final String title;
  final String? author;
  final Uint8List? cover;

  /// File extension for [cover], such as `jpg`.
  final String? coverExtension;
}

/// Reads the title, first author, and cover of the EPUB in [bytes].
///
/// Throws a [FormatException] if [bytes] is not an EPUB.
EpubMetadata readEpubMetadata(
  Uint8List bytes, {
  required String fallbackTitle,
}) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on Object {
    throw const FormatException('Not a zip archive');
  }

  final container = _parseXml(archive, 'META-INF/container.xml');
  final opfPath = container
      .findAllElements('rootfile', namespaceUri: '*')
      .firstOrNull
      ?.getAttribute('full-path');
  if (opfPath == null) throw const FormatException('No package document');
  final opf = _parseXml(archive, opfPath);

  String? text(String name) {
    final value = opf
        .findAllElements(name, namespaceUri: '*')
        .firstOrNull
        ?.innerText
        .trim();
    return value == null || value.isEmpty ? null : value;
  }

  final coverHref = _coverHref(opf);
  final coverPath = coverHref == null ? null : _resolve(opfPath, coverHref);
  final cover = coverPath == null ? null : archive.findFile(coverPath)?.content;

  return EpubMetadata(
    title: text('title') ?? fallbackTitle,
    author: text('creator'),
    cover: cover,
    coverExtension: cover == null
        ? null
        : coverPath!.split('.').last.toLowerCase(),
  );
}

XmlDocument _parseXml(Archive archive, String path) {
  final file = archive.findFile(path);
  if (file == null) throw FormatException('Missing $path');
  try {
    return XmlDocument.parse(utf8.decode(file.content, allowMalformed: true));
  } on XmlException {
    throw FormatException('Unreadable $path');
  }
}

/// The manifest href of the cover image: EPUB 3 marks it with a
/// `cover-image` property, EPUB 2 names it in a `cover` meta tag.
String? _coverHref(XmlDocument opf) {
  final items = opf.findAllElements('item', namespaceUri: '*').toList();
  final epub3 = items.where(
    (item) => (item.getAttribute('properties') ?? '')
        .split(' ')
        .contains('cover-image'),
  );
  if (epub3.isNotEmpty) return epub3.first.getAttribute('href');

  final coverId = opf
      .findAllElements('meta', namespaceUri: '*')
      .where((meta) => meta.getAttribute('name') == 'cover')
      .firstOrNull
      ?.getAttribute('content');
  return items
      .where((item) => item.getAttribute('id') == coverId)
      .firstOrNull
      ?.getAttribute('href');
}

/// Resolves [href], relative to the package document at [opfPath], to a path
/// inside the archive.
String _resolve(String opfPath, String href) {
  final base = opfPath.contains('/')
      ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
      : '';
  final parts = <String>[];
  for (final part in Uri.decodeFull('$base$href').split('/')) {
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (part != '.' && part.isNotEmpty) {
      parts.add(part);
    }
  }
  return parts.join('/');
}
