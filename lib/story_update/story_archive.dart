import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'story_run_folder.dart';

/// Everything kept about a book's Story Map as a zip, or null if there is nothing
/// yet. A first update can fail, leaving run folders and no store.
///
///     store/   the store, which the lab's `story-model show` can read
///     runs/    a folder for each update
///
/// A zip like this loads back in: see `stageStoryImport`.
Uint8List? buildStoryArchive(String storePath) {
  final archive = Archive();
  void addFolder(String path, String prefix) {
    final folder = Directory(path);
    if (!folder.existsSync()) return;
    final files =
        folder
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            // A leftover of a write that never finished.
            .where((file) => !file.path.endsWith('.tmp'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final name = file.path.substring(path.length + 1);
      archive.addFile(
        ArchiveFile.bytes('$prefix/$name', file.readAsBytesSync()),
      );
    }
  }

  addFolder(storePath, 'store');
  addFolder(storyRunsPath(storePath), 'runs');
  if (archive.isEmpty) return null;
  return ZipEncoder().encodeBytes(archive);
}

/// A name for the zip of the book called [title], safe on any file system.
String storyArchiveName(String title, DateTime date) {
  final safe = title.replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f]'), '-').trim();
  String two(int value) => '$value'.padLeft(2, '0');
  final day = '${date.year}-${two(date.month)}-${two(date.day)}';
  return '${safe.isEmpty ? 'Book' : safe} Story Map $day.zip';
}
