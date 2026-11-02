import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// One `item` of the package manifest.
class EpubManifestItem {
  const EpubManifestItem({
    required this.id,
    required this.href,
    required this.path,
    required this.mediaType,
    required this.properties,
  });

  final String id;

  /// The `href` as written, relative to the package document.
  final String href;

  /// [href] resolved to a path inside the archive.
  final String path;
  final String? mediaType;

  /// The space-separated `properties`, such as `cover-image`.
  final Set<String> properties;
}

/// One `itemref` of the package spine.
class EpubSpineRef {
  const EpubSpineRef({required this.idref, required this.linear});

  /// The id of the manifest item. A broken EPUB may name an id that is not in
  /// the manifest.
  final String idref;

  /// False for `linear="no"`.
  final bool linear;
}

/// The package document of an EPUB, found through `META-INF/container.xml`.
///
/// Everything that reads an EPUB goes through this, so there is one parser.
class EpubPackage {
  EpubPackage._({
    required this.archive,
    required this.opfPath,
    required this.opf,
    required this.manifest,
    required this.spine,
  });

  /// Unzips [bytes] and reads the package document.
  ///
  /// Throws a [FormatException] if [bytes] is not an EPUB.
  factory EpubPackage.fromBytes(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object {
      throw const FormatException('Not a zip archive');
    }
    return EpubPackage.fromArchive(archive);
  }

  /// Throws a [FormatException] if [archive] is not an EPUB.
  factory EpubPackage.fromArchive(Archive archive) {
    final container = _parseXml(archive, 'META-INF/container.xml');
    final opfPath = container
        .findAllElements('rootfile', namespaceUri: '*')
        .firstOrNull
        ?.getAttribute('full-path');
    if (opfPath == null) throw const FormatException('No package document');
    final opf = _parseXml(archive, opfPath);

    final manifest = <String, EpubManifestItem>{};
    for (final item in opf.findAllElements('item', namespaceUri: '*')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      manifest.putIfAbsent(
        id,
        () => EpubManifestItem(
          id: id,
          href: href,
          path: _resolve(opfPath, href),
          mediaType: item.getAttribute('media-type'),
          properties: (item.getAttribute('properties') ?? '')
              .split(' ')
              .where((property) => property.isNotEmpty)
              .toSet(),
        ),
      );
    }

    final spine = [
      for (final itemref in opf.findAllElements('itemref', namespaceUri: '*'))
        EpubSpineRef(
          idref: itemref.getAttribute('idref') ?? '',
          linear: itemref.getAttribute('linear')?.trim().toLowerCase() != 'no',
        ),
    ];

    return EpubPackage._(
      archive: archive,
      opfPath: opfPath,
      opf: opf,
      manifest: manifest,
      spine: spine,
    );
  }

  final Archive archive;
  final String opfPath;
  final XmlDocument opf;

  /// The manifest items by id. The first wins if an id is repeated.
  final Map<String, EpubManifestItem> manifest;

  /// Every `itemref` in spine order, including non-linear ones.
  final List<EpubSpineRef> spine;

  /// Resolves [href], relative to the package document, to a path inside the
  /// archive.
  String resolve(String href) => _resolve(opfPath, href);
}

/// Percent-decodes [path] the way manifests and renderers write it, leaving
/// it as is when it is not valid percent-encoding.
String decodeEpubPath(String path) {
  try {
    return Uri.decodeFull(path);
  } on ArgumentError {
    return path;
  }
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

String _resolve(String opfPath, String href) {
  final base = opfPath.contains('/')
      ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
      : '';
  final parts = <String>[];
  for (final part in decodeEpubPath('$base$href').split('/')) {
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (part != '.' && part.isNotEmpty) {
      parts.add(part);
    }
  }
  return parts.join('/');
}
