/// Line coverage of one source file, from its `DA:` records.
class FileCoverage {
  const FileCoverage(this.path, {required this.covered, required this.total});

  /// Relative, with forward slashes, e.g. `lib/reader/reader_page.dart`.
  final String path;
  final int covered;
  final int total;
}

/// Turns an `SF:` path into the form used everywhere else: forward slashes,
/// no leading `./`. `flutter test --coverage` writes backslashes on Windows.
String normalizePath(String path) {
  var result = path.trim().replaceAll('\\', '/');
  while (result.startsWith('./')) {
    result = result.substring(2);
  }
  return result;
}

/// Reads lcov text into one entry per source file, sorted by path.
///
/// Only `SF:` and `DA:<line>,<hits>` are used. The `LF:`/`LH:` totals are
/// ignored so the numbers come from a single source. A file that appears in
/// two records is merged line by line.
List<FileCoverage> parseLcov(String text) {
  final hitsByFile = <String, Map<int, int>>{};
  Map<int, int>? current;
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('SF:')) {
      current = hitsByFile.putIfAbsent(
        normalizePath(line.substring(3)),
        () => <int, int>{},
      );
    } else if (line == 'end_of_record') {
      current = null;
    } else if (line.startsWith('DA:') && current != null) {
      // `DA:<line>,<hits>` with an optional checksum after a second comma.
      final parts = line.substring(3).split(',');
      final number = int.tryParse(parts[0]);
      final hits = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (number == null || hits == null) continue;
      current[number] = (current[number] ?? 0) + hits;
    }
  }
  final files = [
    for (final entry in hitsByFile.entries)
      FileCoverage(
        entry.key,
        covered: entry.value.values.where((hits) => hits > 0).length,
        total: entry.value.length,
      ),
  ];
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// The group a file is reported under: `lib/reader` for
/// `lib/reader/a/b.dart`, and `lib` for a file directly in `lib/`.
String folderOf(String path) {
  final parts = path.split('/');
  if (parts.length == 1) return 'other';
  if (parts.length == 2) return parts.first;
  return '${parts[0]}/${parts[1]}';
}

/// Covered and total line counts for a group of files.
class CoverageTotals {
  const CoverageTotals(this.covered, this.total);

  final int covered;
  final int total;

  /// Null when there are no lines, so a report never shows 0 of 0 as 0%.
  double? get percent => total == 0 ? null : covered * 100 / total;

  String get percentText {
    final value = percent;
    return value == null ? 'n/a' : '${value.toStringAsFixed(1)}%';
  }
}

/// Sums [files] per top-level folder, keyed and sorted by folder name.
Map<String, CoverageTotals> totalsByFolder(Iterable<FileCoverage> files) {
  final covered = <String, int>{};
  final total = <String, int>{};
  for (final file in files) {
    final folder = folderOf(file.path);
    covered[folder] = (covered[folder] ?? 0) + file.covered;
    total[folder] = (total[folder] ?? 0) + file.total;
  }
  final folders = covered.keys.toList()..sort();
  return {for (final f in folders) f: CoverageTotals(covered[f]!, total[f]!)};
}

/// Every path in [libFiles] that no lcov record mentions, sorted.
///
/// `flutter test --coverage` only records files some test loads. A file that
/// no test imports is missing from the lcov file altogether, which makes the
/// percentage look better than it is.
List<String> unloadedFiles(
  Iterable<FileCoverage> files,
  Iterable<String> libFiles,
) {
  final loaded = {for (final file in files) file.path};
  final missing = {
    for (final path in libFiles.map(normalizePath))
      if (!loaded.contains(path)) path,
  };
  return missing.toList()..sort();
}

/// The Markdown report: overall line coverage, one table row per folder and a
/// list of the files the numbers cannot see.
String renderReport(Iterable<FileCoverage> files, Iterable<String> libFiles) {
  final list = files.toList();
  final overall = CoverageTotals(
    list.fold(0, (sum, f) => sum + f.covered),
    list.fold(0, (sum, f) => sum + f.total),
  );
  final buffer = StringBuffer('## Code coverage\n\n');
  if (list.isEmpty) {
    buffer.writeln('No coverage data: the lcov file has no source files.');
  } else {
    buffer
      ..writeln(
        '**Line coverage: ${overall.percentText}** '
        '(${overall.covered} of ${overall.total} lines, '
        '${list.length} files loaded by tests).',
      )
      ..writeln()
      ..writeln('| Folder | Covered | Total | % |')
      ..writeln('| --- | ---: | ---: | ---: |');
    for (final entry in totalsByFolder(list).entries) {
      buffer.writeln(
        '| `${entry.key}` | ${entry.value.covered} | ${entry.value.total} '
        '| ${entry.value.percentText} |',
      );
    }
  }

  final unloaded = unloadedFiles(list, libFiles);
  buffer
    ..writeln()
    ..writeln('### Not loaded by any test (not counted above)')
    ..writeln();
  if (unloaded.isEmpty) {
    buffer.writeln(
      'None: every `.dart` file under `lib/` is loaded by a test.',
    );
  } else {
    buffer
      ..writeln(
        'No test imports these ${unloaded.length} files, so they are missing '
        'from the lcov file and are not in the percentage. The real figure '
        'is lower.',
      )
      ..writeln();
    for (final path in unloaded) {
      buffer.writeln('- `$path`');
    }
  }
  return buffer.toString();
}
