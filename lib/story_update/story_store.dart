import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'story_book.dart';
import 'story_validation.dart';

const _latestFile = 'story_model.json';
const _manifestFile = 'manifest.json';

/// The store is missing, damaged, or cannot be written.
class StoryStoreError implements Exception {
  const StoryStoreError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The store changed after an update read it, so nothing was committed.
class StaleBaseError extends StoryStoreError {
  const StaleBaseError(super.message);
}

/// The exact bytes a store file holds; stored files are hashed over these.
Uint8List storyJsonBytes(Object? data) =>
    utf8.encode('${const JsonEncoder.withIndent('  ').convert(data)}\n');

String sha256OfBytes(List<int> bytes) => sha256.convert(bytes).toString();

/// [value] with every object's keys sorted, for hashing JSON.
Object? _sortedKeys(Object? value) => switch (value) {
  final Map<dynamic, dynamic> map => {
    for (final key in map.keys.map((key) => key as String).toList()..sort())
      key: _sortedKeys(map[key]),
  },
  final List<dynamic> list => [for (final item in list) _sortedKeys(item)],
  _ => value,
};

/// Hash of [value] as JSON with sorted keys, the same as the lab's.
String sha256OfJson(Object? value) =>
    sha256OfBytes(utf8.encode(jsonEncode(_sortedKeys(value))));

String snapshotRelpath(JsonMap revision) =>
    'revisions/${'${revision['number']}'.padLeft(6, '0')}-${revision['id']}.json';

String inputRelpath(JsonMap chapter) =>
    'inputs/${chapter['section_id']}-'
    '${(chapter['text_sha256'] as String).substring(0, 16)}.json';

/// A processed section's entry in the model, and its input file's path and bytes.
(JsonMap, String, Uint8List) sectionSource(
  JsonMap chapter, {
  required int sectionOrder,
  required int revision,
  bool quotesChecked = true,
}) {
  final relpath = inputRelpath(chapter);
  final data = storyJsonBytes(chapter);
  return (
    {
      'section_id': chapter['section_id'],
      'section_order': sectionOrder,
      'chapter_number': chapter['chapter_number'],
      'title': chapter['title'],
      'href': chapter['source_href'],
      'fragment': chapter['source_fragment'],
      'text_sha256': chapter['text_sha256'],
      'extraction_version': chapter['extraction_version'],
      'paragraph_count': (chapter['paragraphs'] as List).length,
      'input_relative_path': relpath,
      'input_file_sha256': sha256OfBytes(data),
      'introduced_revision': revision,
      'quotes_checked': quotesChecked,
    },
    relpath,
    data,
  );
}

/// Where the store at [storePath] waits while another takes its place.
String replacedStorePath(String storePath) => '$storePath.replaced';

/// Finishes replacing the store at [storePath], if the app stopped partway: the
/// new store is either fully in place, or the old one goes back.
void recoverReplacedStore(String storePath) {
  final replaced = Directory(replacedStorePath(storePath));
  if (!replaced.existsSync()) return;
  if (File('$storePath/$_latestFile').existsSync()) {
    replaced.deleteSync(recursive: true);
  } else {
    final store = Directory(storePath);
    if (store.existsSync()) store.deleteSync(recursive: true);
    replaced.renameSync(storePath);
  }
}

/// What an update builds on.
class StoryStoreState {
  const StoryStoreState({
    required this.model,
    required this.inputs,
    this.latestBytes,
    this.inputFiles = const {},
    this.latestSha256,
    this.snapshotPath,
  });

  final JsonMap model;

  /// Every processed section's saved text, by section ID.
  final Map<String, JsonMap> inputs;

  /// [model] and [inputs] as stored, the inputs by store-relative path. A run
  /// keeps these exact bytes, since the model records their hashes.
  final Uint8List? latestBytes;
  final Map<String, Uint8List> inputFiles;

  /// Null while an update creates the store: its base is an empty revision 0
  /// that is not on disk.
  final String? latestSha256;
  final String? snapshotPath;

  bool get isNew => latestSha256 == null;
}

/// A book's story model on disk: the latest revision, a snapshot of every
/// revision, the text of every section, and where each revision came from.
///
///     <root>/story_model.json          latest; replacing it is the commit point
///     <root>/revisions/NNNNNN-<id>.json  snapshot of every committed revision
///     <root>/inputs/<section>-<hash>.json  normalized text of each section
///     <root>/provenance/<run-id>/...   the delta and ID map of each revision
///
/// The same layout as the lab's `story_store.py`, whose `load_store` can check a
/// store written here. A failure before the latest file is replaced leaves the
/// previous revision in place.
class StoryStore {
  const StoryStore(this.root);

  final Directory root;

  File get _latest => File('${root.path}/$_latestFile');

  bool get exists => _latest.existsSync();

  /// Whether [model], read from this store, has its snapshot. Only a store built
  /// up revision by revision does, and only such a store can be continued: one
  /// loaded from a single `story_model.json` can only be looked at.
  bool hasSnapshotOf(JsonMap model) =>
      _file(snapshotRelpath(model['revision'] as JsonMap)).existsSync();

  /// The path of a store-relative [relpath], refusing anything outside it.
  File _file(String relpath) {
    final parts = relpath.split('/');
    if (relpath.isEmpty ||
        relpath.startsWith('/') ||
        relpath.contains(r'\') ||
        parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw StoryStoreError('Refusing path outside the store: "$relpath"');
    }
    return File('${root.path}/$relpath');
  }

  Uint8List _read(String relpath, String what) {
    try {
      return _file(relpath).readAsBytesSync();
    } on FileSystemException catch (error) {
      throw StoryStoreError('Cannot read $what $relpath: ${error.message}');
    }
  }

  /// The latest model as stored, for showing it, or null if there is none.
  ///
  /// Showing a model needs no more than this; [load] checks everything.
  JsonMap? readLatest() {
    if (!exists) return null;
    try {
      return jsonDecode(_latest.readAsStringSync()) as JsonMap;
    } on FormatException catch (error) {
      throw StoryStoreError('$_latestFile is not valid JSON: ${error.message}');
    } on TypeError {
      throw const StoryStoreError('$_latestFile is not a story model');
    }
  }

  /// Reads and verifies the latest revision, never trusting a saved result: the
  /// snapshot copy, every saved input and its hash, the provenance manifests,
  /// the parent chain, and the full model.
  StoryStoreState load() {
    if (!exists) {
      throw StoryStoreError('${root.path} is not a story store');
    }
    final latest = _latest.readAsBytesSync();
    try {
      final model = jsonDecode(utf8.decode(latest)) as JsonMap;
      final revision = model['revision'] as JsonMap;
      final snapshot = snapshotRelpath(revision);
      if (sha256OfBytes(_read(snapshot, 'snapshot')) != sha256OfBytes(latest)) {
        throw StoryStoreError(
          '$_latestFile differs from its snapshot $snapshot',
        );
      }

      final inputs = <String, JsonMap>{};
      final inputFiles = <String, Uint8List>{};
      for (final raw in model['processed_sections'] as List) {
        final section = raw as JsonMap;
        final relpath = section['input_relative_path'] as String;
        final data = _read(relpath, 'input');
        if (sha256OfBytes(data) != section['input_file_sha256']) {
          throw StoryStoreError('Input $relpath does not match its SHA-256');
        }
        inputs[section['section_id'] as String] =
            jsonDecode(utf8.decode(data)) as JsonMap;
        inputFiles[relpath] = data;
      }

      _verifyManifests();
      final errors = validateCumulative(model, inputs).errors.take(5).toList();
      if (errors.isNotEmpty) {
        throw StoryStoreError(
          'Revision ${revision['number']} fails validation: '
          '${errors.map((e) => '${e.code} at ${e.path}').join('; ')}',
        );
      }
      _verifyParentChain(revision);
      return StoryStoreState(
        model: model,
        inputs: inputs,
        latestBytes: latest,
        inputFiles: inputFiles,
        latestSha256: sha256OfBytes(latest),
        snapshotPath: snapshot,
      );
    } on FormatException catch (error) {
      throw StoryStoreError('The store is not valid JSON: ${error.message}');
    } on TypeError {
      throw const StoryStoreError('The store is not a valid story model');
    }
  }

  void _verifyParentChain(JsonMap latestRevision) {
    var revision = latestRevision;
    _requireProvenance(revision);
    while (revision['parent_snapshot_path'] != null) {
      final relpath = revision['parent_snapshot_path'] as String;
      final data = _read(relpath, 'parent snapshot');
      if (sha256OfBytes(data) != revision['parent_sha256']) {
        throw StoryStoreError(
          'Parent snapshot $relpath does not match the recorded SHA-256',
        );
      }
      final parent =
          (jsonDecode(utf8.decode(data)) as JsonMap)['revision'] as JsonMap;
      if (parent['number'] != (revision['number'] as int) - 1 ||
          snapshotRelpath(parent) != relpath) {
        throw StoryStoreError(
          'Parent snapshot $relpath is not revision '
          '${(revision['number'] as int) - 1}',
        );
      }
      _requireProvenance(parent);
      revision = parent;
    }
    if (revision['number'] != 1) {
      throw StoryStoreError(
        'The parent chain stops at revision ${revision['number']}',
      );
    }
  }

  void _requireProvenance(JsonMap revision) {
    final run = revision['source_run_id'];
    if (!_file('provenance/$run/$_manifestFile').existsSync()) {
      throw StoryStoreError(
        'Missing provenance/$run/$_manifestFile of revision '
        '${revision['number']}',
      );
    }
  }

  void _verifyManifests() {
    final provenance = Directory('${root.path}/provenance');
    if (!provenance.existsSync()) return;
    for (final directory in provenance.listSync().whereType<Directory>()) {
      final name = directory.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      final manifest = File('${directory.path}/$_manifestFile');
      if (!manifest.existsSync()) continue;
      final files =
          (jsonDecode(manifest.readAsStringSync()) as JsonMap)['files']
              as JsonMap;
      for (final MapEntry(key: file, value: expected) in files.entries) {
        final data = _read('provenance/$name/$file', 'provenance file');
        if (sha256OfBytes(data) != expected) {
          throw StoryStoreError(
            'Provenance file provenance/$name/$file does not match its SHA-256',
          );
        }
      }
    }
  }

  /// Refuses to create a store over a folder that holds something else.
  void ensureNew() {
    if (root.existsSync() && root.listSync().isNotEmpty) {
      throw StoryStoreError(
        '${root.path} exists and is neither a story store nor an empty folder',
      );
    }
  }

  /// Writes [files] and the snapshot, then makes [model] the latest revision.
  ///
  /// [expectedBaseSha256] is the latest file's hash when the update started,
  /// null for a new store. Returns the snapshot's path. Throws a
  /// [StaleBaseError] if the store moved on since.
  String commit(
    JsonMap model,
    Map<String, List<int>> files, {
    required String? expectedBaseSha256,
  }) {
    final data = storyJsonBytes(model);
    final snapshot = snapshotRelpath(model['revision'] as JsonMap);
    root.createSync(recursive: true);
    final current = exists ? sha256OfBytes(_latest.readAsBytesSync()) : null;
    if (current != expectedBaseSha256) {
      throw StaleBaseError(
        '$_latestFile changed since this update read it; nothing was committed',
      );
    }
    files.forEach((relpath, content) {
      final file = _file(relpath);
      if (file.existsSync()) {
        if (sha256OfBytes(file.readAsBytesSync()) != sha256OfBytes(content)) {
          throw StoryStoreError(
            '$relpath already exists with different content',
          );
        }
      } else {
        _writeAtomically(file, content);
      }
    });
    final snapshotFile = _file(snapshot);
    if (snapshotFile.existsSync()) {
      throw StoryStoreError('Snapshot $snapshot already exists');
    }
    _writeAtomically(snapshotFile, data);
    _writeAtomically(_latest, data); // The commit point.
    return snapshot;
  }

  /// Writes through a temporary file in the same folder, flushed before the
  /// rename, so a crash leaves the old file or the new one.
  void _writeAtomically(File file, List<int> data) {
    file.parent.createSync(recursive: true);
    final suffix = Random().nextInt(1 << 32).toRadixString(16);
    final temporary = File('${file.path}.$suffix.tmp');
    try {
      temporary.writeAsBytesSync(data, flush: true);
      temporary.renameSync(file.path);
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }
}

/// `manifest.json` of a provenance folder: the hash of each file in it.
Uint8List storyManifestBytes(Map<String, List<int>> files, String sourceRunId) {
  final names = files.keys.toList()..sort();
  return storyJsonBytes({
    'source_run_id': sourceRunId,
    'files': {for (final name in names) name: sha256OfBytes(files[name]!)},
  });
}
