import 'dart:convert';
import 'dart:io';

import 'package:loremark/story_update/delta_schema.dart';
import 'package:loremark/story_update/story_book.dart';

/// What the story model lab produced for the same input, from
/// `tool/story_update/gen_goldens.py`.
const goldenDir = 'test/fixtures/story_update';

JsonMap readGolden(String name) =>
    jsonDecode(File('$goldenDir/$name').readAsStringSync()) as JsonMap;

JsonMap readValidationGolden() => jsonDecode(
  utf8.decode(
    gzip.decode(File('$goldenDir/validation_golden.json.gz').readAsBytesSync()),
  ),
) as JsonMap;

StoryDeltaSchema readDeltaSchema() => StoryDeltaSchema.parse(
  File('assets/story_update/story_delta.schema.json').readAsStringSync(),
);

/// Issues as the golden files list them: code, path and severity.
List<Map<String, String>> issueList(Iterable<StoryIssue> issues) => [
  for (final issue in issues)
    {'severity': issue.severity, 'code': issue.code, 'path': issue.path},
];

List<dynamic> readGoldenList(String name) =>
    jsonDecode(File('$goldenDir/$name').readAsStringSync()) as List<dynamic>;
