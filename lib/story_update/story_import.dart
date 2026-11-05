import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../story_model/story_model.dart';
import 'story_book.dart';
import 'story_run_folder.dart';
import 'story_store.dart';
import 'story_updater.dart';
import 'story_validation.dart';

const _maxFileBytes = 256 * 1024 * 1024;
const _maxUnpackedBytes = 1024 * 1024 * 1024;
const _maxEntries = 50000;

const _tooLarge = 'That file is too large to be a Story Map.';
const _unsafe = 'That zip has a file in it that Loremark won’t unpack.';
const _notAMap = 'That file isn’t a Story Map.';

const _storeEntries = ['revisions/', 'inputs/', 'provenance/'];
const _latestFile = 'story_model.json';

/// A file can't be loaded as this book's Story Map. [message] says why.
class StoryImportError implements Exception {
  const StoryImportError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A file checked and unpacked, and ready to take the place of the store.
class StagedStoryImport {
  const StagedStoryImport({
    required this.path,
    required this.revision,
    required this.sectionCount,
    required this.viewOnly,
  });

  final String path;
  final int revision;
  final int sectionCount;

  /// Whether this is only the latest model, which can't be added to.
  final bool viewOnly;
}

/// The folders that belong with the store at [storePath], for removing it all.
List<String> storySidePaths(String storePath) => [
  storyRunsPath(storePath),
  replacedStorePath(storePath),
  _stagingPath(storePath),
];

String _stagingPath(String storePath) => '$storePath.importing';

/// Unpacks and checks the file at [filePath] beside the store at [storePath],
/// leaving the store as it is. Takes a zip of a store, or a `story_model.json` on
/// its own, and never trusts either. Throws a [StoryImportError] if it won't do.
///
/// Tests lower [maxFileBytes] and [maxUnpackedBytes].
StagedStoryImport stageStoryImport({
  required String filePath,
  required String epubPath,
  required String storePath,
  int maxFileBytes = _maxFileBytes,
  int maxUnpackedBytes = _maxUnpackedBytes,
}) {
  final staging = Directory(_stagingPath(storePath));
  void clean() {
    if (staging.existsSync()) staging.deleteSync(recursive: true);
  }

  clean();
  try {
    final file = File(filePath);
    if (file.lengthSync() > maxFileBytes) {
      throw const StoryImportError(_tooLarge);
    }
    final bytes = file.readAsBytesSync();
    if (_isZip(bytes)) {
      _unpack(bytes, staging.path, maxUnpackedBytes);
    } else {
      File('${staging.path}/store/$_latestFile')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
    }
    return _check(staging.path, epubPath);
  } on StoryImportError {
    clean();
    rethrow;
  } on FileSystemException {
    clean();
    throw const StoryImportError('Couldn’t read that file.');
  } on StoryEpubError catch (error) {
    clean();
    throw StoryImportError(error.message);
  } on Object {
    // A file made to look like a Story Map can fail in any number of ways.
    clean();
    throw const StoryImportError(_notAMap);
  }
}

bool _isZip(Uint8List bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x50 &&
    bytes[1] == 0x4b &&
    (bytes[2] == 0x03 || bytes[2] == 0x05) &&
    (bytes[3] == 0x04 || bytes[3] == 0x06);

void _unpack(Uint8List bytes, String staging, int maxBytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on Object {
    throw const StoryImportError('That zip can’t be read.');
  }
  if (archive.length > _maxEntries) throw const StoryImportError(_tooLarge);

  final files = <String, ArchiveFile>{};
  var total = 0;
  for (final entry in archive) {
    if (!_isSafeName(entry.name) || entry.isSymbolicLink) {
      throw const StoryImportError(_unsafe);
    }
    if (!entry.isFile || _isClutter(entry.name)) continue;
    // Decoding stops at the size an entry declares, so this is the real limit.
    total += entry.size;
    if (total > maxBytes) throw const StoryImportError(_tooLarge);
    files[entry.name] = entry;
  }

  final root = _storeRoot(files.keys);
  final runsRoot = root == 'store/' || root.endsWith('/store/')
      ? '${root.substring(0, root.length - 'store/'.length)}runs/'
      : null;
  files.forEach((name, entry) {
    String? target;
    if (name.startsWith(root)) {
      final relative = name.substring(root.length);
      if (relative == _latestFile ||
          _storeEntries.any((folder) => relative.startsWith(folder))) {
        target = 'store/$relative';
      }
    } else if (runsRoot != null && name.startsWith(runsRoot)) {
      target = 'runs/${name.substring(runsRoot.length)}';
    }
    if (target == null) return;
    File('$staging/$target')
      ..createSync(recursive: true)
      ..writeAsBytesSync(entry.content);
  });
}

bool _isSafeName(String name) {
  final path = name.endsWith('/') ? name.substring(0, name.length - 1) : name;
  final parts = path.split('/');
  return path.isNotEmpty &&
      !path.startsWith('/') &&
      !path.contains(r'\') &&
      !path.contains('\u0000') &&
      !parts.any((part) => part.isEmpty || part == '.' || part == '..');
}

/// What a computer adds to a zip, or an unfinished write left behind.
bool _isClutter(String name) =>
    name.startsWith('__MACOSX/') ||
    name.split('/').last == '.DS_Store' ||
    name.endsWith('.tmp');

/// Where in a zip the store is: at the top, or in a folder or two, as zipping a
/// store's folder leaves it.
String _storeRoot(Iterable<String> names) {
  final roots = [
    for (final name in names)
      if (name == _latestFile || name.endsWith('/$_latestFile'))
        name.substring(0, name.length - _latestFile.length),
  ].where((root) => '/'.allMatches(root).length <= 2).toList();
  if (roots.isEmpty) throw const StoryImportError(_notAMap);
  if (roots.length > 1) {
    throw const StoryImportError('That zip holds more than one Story Map.');
  }
  return roots.single;
}

StagedStoryImport _check(String staging, String epubPath) {
  final storePath = '$staging/store';
  final decoded = jsonDecode(
    utf8.decode(File('$storePath/$_latestFile').readAsBytesSync()),
  );
  if (decoded is! JsonMap || decoded['book'] is! JsonMap) {
    throw const StoryImportError(_notAMap);
  }
  final book = StoryBook.open(File(epubPath).readAsBytesSync());
  if ((decoded['book'] as JsonMap)['epub_sha256'] != book.sha256Hash) {
    throw const StoryImportError(
      'That Story Map was built from a different EPUB file.',
    );
  }
  final StoryModel parsed;
  try {
    parsed = StoryModel.fromJson(decoded);
  } on Object {
    throw const StoryImportError(
      'That Story Map is in a form this version of Loremark can’t read.',
    );
  }

  final viewOnly = !_storeEntries.any(
    (folder) => Directory('$storePath/$folder').existsSync(),
  );
  if (viewOnly) {
    _checkAgainstBook(decoded, book);
  } else {
    try {
      StoryStore(Directory(storePath)).load();
    } on StoryStoreError catch (error) {
      throw StoryImportError('That Story Map is damaged: ${error.message}');
    }
  }
  return StagedStoryImport(
    path: staging,
    revision: parsed.revision,
    sectionCount: parsed.sections.length,
    viewOnly: viewOnly,
  );
}

/// Checks a model that came without its saved text against the book's own. It
/// can't be continued, but what it shows still has to be true of this book.
void _checkAgainstBook(JsonMap model, StoryBook book) {
  checkStoryContinues(model, book);
  final inputs = <String, JsonMap>{};
  for (final section in (model['processed_sections'] as List).cast<JsonMap>()) {
    final id = section['section_id'] as String;
    inputs[id] = book.extract(
      book.sections.firstWhere((source) => source.sectionId == id),
    );
  }
  final errors = validateCumulative(model, inputs).errors;
  if (errors.isNotEmpty) {
    throw StoryImportError(
      'That Story Map failed ${errors.length} check(s). The first: '
      '${errors.first.message}.',
    );
  }
}

/// Puts [staged] in place of the store at [storePath], and adds its run folders
/// to those already kept. Going by renames, the store is always either the old
/// one or the new: see [recoverReplacedStore].
void commitStoryImport(StagedStoryImport staged, String storePath) {
  recoverReplacedStore(storePath);
  final store = Directory(storePath);
  final replaced = replacedStorePath(storePath);
  if (store.existsSync()) store.renameSync(replaced);
  Directory('${staged.path}/store').renameSync(storePath);
  recoverReplacedStore(storePath);
  try {
    _addRuns('${staged.path}/runs', storyRunsPath(storePath));
    Directory(staged.path).deleteSync(recursive: true);
  } on FileSystemException {
    // The map is in place, and only records of old runs are missing. Whatever
    // is left is cleared by the next load, or with the book.
  }
}

void _addRuns(String from, String to) {
  final source = Directory(from);
  if (!source.existsSync()) return;
  Directory(to).createSync(recursive: true);
  for (final run in source.listSync().whereType<Directory>()) {
    final target = '$to/${run.uri.pathSegments.lastWhere((s) => s.isNotEmpty)}';
    if (!Directory(target).existsSync()) run.renameSync(target);
  }
}

/// Throws [staged] away, leaving the store as it is.
void discardStoryImport(StagedStoryImport staged) {
  final folder = Directory(staged.path);
  if (folder.existsSync()) folder.deleteSync(recursive: true);
}
