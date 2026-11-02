import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'epub_package.dart';

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
  final package = EpubPackage.fromBytes(bytes);
  final opf = package.opf;

  String? text(String name) {
    final value = opf
        .findAllElements(name, namespaceUri: '*')
        .firstOrNull
        ?.innerText
        .trim();
    return value == null || value.isEmpty ? null : value;
  }

  final coverHref = _coverHref(opf);
  final coverPath = coverHref == null ? null : package.resolve(coverHref);
  final cover = coverPath == null
      ? null
      : package.archive.findFile(coverPath)?.content;

  return EpubMetadata(
    title: text('title') ?? fallbackTitle,
    author: text('creator'),
    cover: cover,
    coverExtension: cover == null
        ? null
        : coverPath!.split('.').last.toLowerCase(),
  );
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
