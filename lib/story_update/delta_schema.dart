import 'dart:convert';

import 'story_book.dart';

/// One problem with a story model or an update to it.
class StoryIssue {
  const StoryIssue(
    this.severity,
    this.code,
    this.path,
    this.message, [
    this.recordId,
  ]);

  /// `error` or `warning`.
  final String severity;
  final String code;

  /// Where it is, such as `new_records.names[0].evidence[1]`.
  final String path;
  final String message;
  final String? recordId;

  bool get isError => severity == 'error';

  @override
  String toString() => '$severity $code at $path: $message';
}

/// Checks what the model returned against the JSON Schema it was asked to fill.
///
/// Providers don't all enforce a schema strictly, so its answer is checked here
/// too. The schema is the one sent with the request, so there is no second copy
/// of the delta's shape to keep in step.
class StoryDeltaSchema {
  StoryDeltaSchema(this.schema) : _defs = schema[r'$defs'] as JsonMap;

  factory StoryDeltaSchema.parse(String text) =>
      StoryDeltaSchema(jsonDecode(text) as JsonMap);

  final JsonMap schema;
  final JsonMap _defs;

  /// [candidate] with every object's fields in schema order, which is the order
  /// a story model stores them in, and the problems found.
  (Object?, List<StoryIssue>) check(Object? candidate) {
    final issues = <StoryIssue>[];
    final normalized = _check(schema, candidate, '', issues);
    return (normalized, issues);
  }

  Object? _check(
    JsonMap node,
    Object? value,
    String path,
    List<StoryIssue> issues,
  ) {
    final ref = node[r'$ref'] as String?;
    if (ref != null) {
      return _check(
        _defs[ref.substring(ref.lastIndexOf('/') + 1)] as JsonMap,
        value,
        path,
        issues,
      );
    }
    final anyOf = node['anyOf'] as List?;
    if (anyOf != null) {
      // Only `T | null` is used, so a null either fits or T's problems apply.
      if (value == null &&
          anyOf.any((option) => (option as JsonMap)['type'] == 'null')) {
        return null;
      }
      final option = anyOf.firstWhere(
        (option) => (option as JsonMap)['type'] != 'null',
      );
      return _check(option as JsonMap, value, path, issues);
    }

    void problem(String message) => issues.add(
      StoryIssue('error', 'schema', path.isEmpty ? '(root)' : path, message),
    );

    final allowed = node['enum'] as List?;
    if (allowed != null && !allowed.contains(value)) {
      problem('Input should be one of ${allowed.join(', ')}');
      return value;
    }
    switch (node['type']) {
      case 'object':
        if (value is! Map) {
          problem('Input should be an object');
          return value;
        }
        return _checkObject(node, value, path, issues);
      case 'array':
        if (value is! List) {
          problem('Input should be a list');
          return value;
        }
        final items = node['items'] as JsonMap;
        return [
          for (var i = 0; i < value.length; i++)
            _check(items, value[i], '$path[$i]', issues),
        ];
      case 'string':
        if (value is! String) problem('Input should be a valid string');
      case 'integer':
        if (value is double && value == value.truncateToDouble()) {
          return value.toInt();
        }
        if (value is! int) problem('Input should be a valid integer');
      case 'null':
        if (value != null) problem('Input should be null');
    }
    return value;
  }

  JsonMap _checkObject(
    JsonMap node,
    Map<dynamic, dynamic> value,
    String path,
    List<StoryIssue> issues,
  ) {
    final properties = node['properties'] as JsonMap;
    final required = (node['required'] as List?) ?? const [];
    final result = <String, dynamic>{};
    String child(Object name) => path.isEmpty ? '$name' : '$path.$name';
    for (final MapEntry(key: name, value: property) in properties.entries) {
      if (value.containsKey(name)) {
        result[name] = _check(
          property as JsonMap,
          value[name],
          child(name),
          issues,
        );
      } else if (required.contains(name)) {
        issues.add(
          StoryIssue('error', 'schema', child(name), 'Field required'),
        );
      }
    }
    for (final name in value.keys) {
      if (!properties.containsKey(name)) {
        issues.add(
          StoryIssue(
            'error',
            'schema',
            child(name as Object),
            'Extra inputs are not permitted',
          ),
        );
      }
    }
    return result;
  }
}
