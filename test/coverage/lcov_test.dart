import 'package:flutter_test/flutter_test.dart';

import '../../tool/coverage/lcov.dart';
import '../../tool/coverage/report.dart' show parseArgs;

void main() {
  group('parseLcov', () {
    test('counts lines with hits as covered and 0-hit lines as missed', () {
      final files = parseLcov('''
SF:lib/reader/a.dart
DA:1,3
DA:2,0
DA:3,1
DA:4,0
LF:4
LH:2
end_of_record
''');

      expect(files, hasLength(1));
      expect(files.single.path, 'lib/reader/a.dart');
      expect(files.single.covered, 2);
      expect(files.single.total, 4);
    });

    test('normalizes Windows backslashes in SF paths', () {
      final files = parseLcov(
        'SF:lib\\library\\book.dart\nDA:1,1\nend_of_record\n',
      );

      expect(files.single.path, 'lib/library/book.dart');
    });

    test('ignores a checksum after the hit count', () {
      final files = parseLcov('SF:lib/a.dart\nDA:1,2,abc123\nend_of_record\n');

      expect(files.single.covered, 1);
      expect(files.single.total, 1);
    });

    test('merges two records of the same file line by line', () {
      final files = parseLcov('''
SF:lib/a.dart
DA:1,1
DA:2,0
end_of_record
SF:lib/a.dart
DA:2,4
DA:3,0
end_of_record
''');

      expect(files, hasLength(1));
      expect(files.single.covered, 2);
      expect(files.single.total, 3);
    });

    test('skips malformed DA lines and handles CRLF', () {
      final files = parseLcov(
        'SF:lib/a.dart\r\nDA:x,1\r\nDA:2\r\nDA:3,1\r\nend_of_record\r\n',
      );

      expect(files.single.total, 1);
      expect(files.single.covered, 1);
    });

    test('empty input has no files', () {
      expect(parseLcov(''), isEmpty);
    });
  });

  group('totalsByFolder', () {
    test('groups by the first folder under lib, root files as lib', () {
      final totals = totalsByFolder(const [
        FileCoverage('lib/search/a.dart', covered: 1, total: 2),
        FileCoverage('lib/search/deep/b.dart', covered: 3, total: 4),
        FileCoverage('lib/main.dart', covered: 5, total: 5),
        FileCoverage('lib/reader/c.dart', covered: 0, total: 3),
      ]);

      expect(totals.keys, ['lib', 'lib/reader', 'lib/search']);
      expect(totals['lib/search']!.covered, 4);
      expect(totals['lib/search']!.total, 6);
      expect(totals['lib']!.percentText, '100.0%');
      expect(totals['lib/reader']!.percentText, '0.0%');
    });
  });

  group('unloadedFiles', () {
    test('lists lib files that the lcov file does not mention', () {
      final files = parseLcov('SF:lib/a.dart\nDA:1,1\nend_of_record\n');

      expect(
        unloadedFiles(files, ['lib/b.dart', 'lib/a.dart', 'lib\\sub\\c.dart']),
        ['lib/b.dart', 'lib/sub/c.dart'],
      );
    });
  });

  group('renderReport', () {
    test('shows the overall figure, a folder table and unloaded files', () {
      final files = parseLcov('''
SF:lib\\reader\\a.dart
DA:1,1
DA:2,0
end_of_record
SF:lib/main.dart
DA:1,1
DA:2,1
end_of_record
''');

      final report = renderReport(files, [
        'lib/reader/a.dart',
        'lib/main.dart',
        'lib/search/never_tested.dart',
      ]);

      expect(report, contains('**Line coverage: 75.0%** (3 of 4 lines'));
      expect(report, contains('| `lib` | 2 | 2 | 100.0% |'));
      expect(report, contains('| `lib/reader` | 1 | 2 | 50.0% |'));
      expect(report, contains('Not loaded by any test'));
      expect(report, contains('not in the percentage'));
      expect(report, contains('- `lib/search/never_tested.dart`'));
      expect(
        report.indexOf('| `lib` |'),
        lessThan(report.indexOf('lib/reader')),
      );
    });

    test('says so when every lib file is loaded', () {
      final files = parseLcov('SF:lib/a.dart\nDA:1,1\nend_of_record\n');

      expect(
        renderReport(files, ['lib/a.dart']),
        contains('every `.dart` file under `lib/` is loaded'),
      );
    });

    test('empty input reports no data and still lists lib files', () {
      final report = renderReport(parseLcov(''), ['lib/a.dart']);

      expect(report, contains('No coverage data'));
      expect(report, isNot(contains('| Folder |')));
      expect(report, contains('- `lib/a.dart`'));
    });

    test('a file with no instrumented lines shows n/a, not 0%', () {
      final report = renderReport(
        const [FileCoverage('lib/a.dart', covered: 0, total: 0)],
        const ['lib/a.dart'],
      );

      expect(report, contains('| `lib` | 0 | 0 | n/a |'));
    });
  });

  group('parseArgs', () {
    test('defaults to coverage/lcov.info and no summary', () {
      final options = parseArgs(const []);

      expect(options.lcov, 'coverage/lcov.info');
      expect(options.summary, isNull);
    });

    test('takes a path and --summary in either form', () {
      expect(
        parseArgs(const ['x.info', '--summary', 'out.md']).summary,
        'out.md',
      );
      expect(parseArgs(const ['--summary=out.md', 'x.info']).lcov, 'x.info');
    });

    test('rejects unknown options and a missing summary path', () {
      expect(() => parseArgs(const ['--nope']), throwsFormatException);
      expect(() => parseArgs(const ['--summary']), throwsFormatException);
    });
  });
}
