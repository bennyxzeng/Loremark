import 'dart:convert';

import 'delta_schema.dart';
import 'story_book.dart';
import 'story_merge.dart';

const _maxQuoteChars = 300;
const _allKinds = {'character', 'location', 'organization'};
const _speakerKinds = {'character', 'organization'};
final _entityIdPatterns = {
  'character': RegExp(r'^c\d{3,}$'),
  'location': RegExp(r'^l\d{3,}$'),
  'organization': RegExp(r'^g\d{3,}$'),
};
final _recordIdPattern = RegExp(r'^f\d{6,}$');
final _transitionIdPattern = RegExp(r'^t\d{6,}$');
final _localEntityPattern = RegExp(r'^new_entity_\d{3,}$');
final _localRecordPattern = RegExp(r'^new_record_\d{3,}$');

/// Deep equality of decoded JSON values, regardless of object key order.
bool jsonEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !jsonEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// The result of checking a whole model.
class StoryReport {
  const StoryReport(this.issues);

  final List<StoryIssue> issues;

  Iterable<StoryIssue> get errors => issues.where((issue) => issue.isError);
}

/// The result of checking one update.
class StoryUpdateValidation {
  const StoryUpdateValidation({
    required this.structureValid,
    required this.issues,
    this.delta,
    this.after,
    this.idMap,
  });

  final bool structureValid;
  final List<StoryIssue> issues;

  /// The delta with its fields in schema order, if its structure was valid.
  final JsonMap? delta;

  /// The model with the delta merged, if it could be merged.
  final JsonMap? after;
  final StoryIdMap? idMap;

  Iterable<StoryIssue> get errors => issues.where((issue) => issue.isError);
  Iterable<StoryIssue> get warnings => issues.where((issue) => !issue.isError);

  bool get passed => structureValid && after != null && errors.isEmpty;
}

/// Checks a whole cumulative model against the inputs of its processed sections.
///
/// A port of the lab's `cumulative_validation.py`, with the same codes and paths.
/// [paths] renames items in messages (an update reports `new_records.names[0]`
/// instead of `records.names[57]`). With [focusRevision], per-record warnings are
/// only reported for items of that revision; errors are always reported.
StoryReport validateCumulative(
  JsonMap model,
  Map<String, JsonMap> inputs, {
  Map<String, String> paths = const {},
  int? focusRevision,
}) => _Checker(model, inputs, paths, focusRevision).run();

class _Checker {
  _Checker(this.model, this.inputs, this.paths, this.focus)
    : revision = (model['revision'] as JsonMap)['number'] as int,
      sections = (model['processed_sections'] as List).cast<JsonMap>(),
      transitions = (model['transitions'] as List).cast<JsonMap>() {
    uncheckedSections = {
      for (final section in sections)
        if (section['quotes_checked'] == false) section['section_id'] as String,
    };
  }

  final JsonMap model;
  final Map<String, JsonMap> inputs;
  final Map<String, String> paths;
  final int? focus;
  final int revision;
  final List<JsonMap> sections;
  final List<JsonMap> transitions;
  final issues = <StoryIssue>[];
  final paragraphs = <String, Map<String, String>>{};
  final sectionRevisions = <String, int>{};
  late final Set<String> uncheckedSections;
  final entities = <String, JsonMap>{};
  final records = <String, (String, JsonMap)>{};
  var active = <String>{};

  StoryReport run() {
    _checkRevision();
    _checkSections();
    _checkEntities();
    _checkRecords();
    _checkTransitions();
    final expected = projectCurrent(model);
    active = (expected['active_record_ids'] as List).cast<String>().toSet();
    _checkCurrent(expected);
    _checkNames();
    _checkIdentityConflicts(expected);
    return StoryReport(issues);
  }

  void _error(String code, String path, String message, [String? recordId]) =>
      issues.add(StoryIssue('error', code, path, message, recordId));

  /// A warning; per-record ones, with [itemRevision], only for the focused
  /// revision.
  void _warn(
    String code,
    String path,
    String message, [
    String? recordId,
    int? itemRevision,
  ]) {
    if (itemRevision == null || focus == null || itemRevision == focus) {
      issues.add(StoryIssue('warning', code, path, message, recordId));
    }
  }

  void _nonempty(String path, Object? value, String? recordId) {
    if (pyStrip(value as String).isEmpty) {
      _error('empty_text', path, 'Text is empty', recordId);
    }
  }

  void _checkOrigin(
    String path,
    String itemId,
    int itemRevision,
    String sectionId,
  ) {
    if (itemRevision < 1 || itemRevision > revision) {
      _error(
        'revision_range',
        '$path.introduced_revision',
        '$itemRevision is outside 1..$revision',
        itemId,
      );
    }
    final sectionRevision = sectionRevisions[sectionId];
    if (sectionRevision == null) {
      _error(
        'unknown_section',
        '$path.learned_in_section_id',
        '"$sectionId" is not a processed section',
        itemId,
      );
    } else if (sectionRevision != itemRevision) {
      _error(
        'section_revision_mismatch',
        '$path.learned_in_section_id',
        '$sectionId was processed in revision $sectionRevision, not '
            '$itemRevision',
        itemId,
      );
    }
  }

  void _checkRef(
    String path,
    String ref,
    Set<String> allowed,
    String recordId,
    int itemRevision,
  ) {
    final entity = entities[ref];
    if (entity == null) {
      _error('dangling_reference', path, '"$ref" does not exist', recordId);
    } else if (!allowed.contains(entity['kind'])) {
      final expected = (allowed.toList()..sort()).join(' or ');
      _error(
        'wrong_reference_kind',
        path,
        '"$ref" is a ${entity['kind']}, expected $expected',
        recordId,
      );
    } else if ((entity['introduced_revision'] as int) > itemRevision) {
      _error(
        'reference_from_future',
        path,
        '"$ref" is introduced in revision ${entity['introduced_revision']}, '
            'after this item (revision $itemRevision)',
        recordId,
      );
    }
  }

  void _checkAssertion(
    String path,
    JsonMap payload,
    String recordId,
    int itemRevision,
  ) {
    final attributedTo = payload['attributed_to_id'] as String?;
    if (attributedTo == null) return;
    _checkRef(
      '$path.attributed_to_id',
      attributedTo,
      _speakerKinds,
      recordId,
      itemRevision,
    );
    if (payload['assertion'] != 'reported') {
      _warn(
        'attribution_without_report',
        '$path.attributed_to_id',
        'attributed_to_id is set but assertion is "${payload['assertion']}"',
        recordId,
        itemRevision,
      );
    }
  }

  void _checkEvidence(
    String path,
    List<dynamic> items,
    String recordId,
    String sectionId,
  ) {
    if (items.isEmpty) {
      _error(
        'missing_evidence',
        '$path.evidence',
        'Evidence list is empty',
        recordId,
      );
      return;
    }
    for (var i = 0; i < items.length; i++) {
      final item = items[i] as JsonMap;
      final itemPath = '$path.evidence[$i]';
      final itemSection = item['section_id'] as String;
      final paragraphId = item['paragraph_id'] as String;
      final quote = item['quote'] as String;
      final sectionParagraphs = paragraphs[itemSection];
      final text = sectionParagraphs?[paragraphId];
      if (itemSection != sectionId) {
        _error(
          'evidence_outside_section',
          itemPath,
          'Evidence cites "$itemSection"; it must come from $sectionId, the '
              'section this item was learned in',
          recordId,
        );
      } else if (sectionParagraphs == null) {
        _error(
          'unknown_section',
          itemPath,
          'No input is available for "$itemSection"',
          recordId,
        );
      } else if (text == null) {
        _error(
          'unknown_paragraph',
          itemPath,
          'Paragraph "$paragraphId" is not part of $itemSection',
          recordId,
        );
      } else if (pyStrip(quote).isEmpty) {
        _error('empty_quote', itemPath, 'Quote is empty', recordId);
      } else if (quote.runes.length > _maxQuoteChars) {
        _error(
          'quote_too_long',
          itemPath,
          'Quote has ${quote.runes.length} characters (limit $_maxQuoteChars)',
          recordId,
        );
      } else if (!text.contains(quote)) {
        if (uncheckedSections.contains(itemSection)) {
          _warn(
            'quote_not_found',
            itemPath,
            'Quote is not an exact substring of $itemSection:$paragraphId',
            recordId,
            sectionRevisions[itemSection],
          );
        } else {
          _error(
            'quote_not_found',
            itemPath,
            'Quote is not an exact substring of $itemSection:$paragraphId',
            recordId,
          );
        }
      }
    }
  }

  void _checkRevision() {
    final info = model['revision'] as JsonMap;
    if (revision < 1) {
      _error('revision_range', 'revision.number', '$revision is not positive');
    }
    if (pyStrip(info['id'] as String).isEmpty) {
      _error('empty_id', 'revision.id', 'Revision ID is empty');
    }
    bool has(Object? value) => value != null && value != '';
    final parentPath = info['parent_snapshot_path'];
    final parentHash = info['parent_sha256'];
    if (revision == 1 && (has(parentPath) || has(parentHash))) {
      _error(
        'revision_parent',
        'revision',
        'Revision 1 must not have a parent',
      );
    }
    if (revision > 1 && !(has(parentPath) && has(parentHash))) {
      _error(
        'revision_parent',
        'revision',
        'Revision $revision needs a parent snapshot path and hash',
      );
    }
  }

  void _checkSections() {
    if (sections.length != revision) {
      _error(
        'section_count',
        'processed_sections',
        'Revision $revision must have exactly $revision processed sections '
            '(one per revision), found ${sections.length}',
      );
    }
    var previousOrder = 0;
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      final path = 'processed_sections[$i]';
      final sectionId = section['section_id'] as String;
      if (sectionRevisions.containsKey(sectionId)) {
        _error('duplicate_section', path, '$sectionId is listed twice');
      }
      sectionRevisions[sectionId] = section['introduced_revision'] as int;
      if (section['introduced_revision'] != i + 1) {
        _error(
          'section_revision_mismatch',
          '$path.introduced_revision',
          'Section ${i + 1} must be introduced in revision ${i + 1}',
        );
      }
      if ((section['section_order'] as int) <= previousOrder) {
        _error(
          'section_order',
          '$path.section_order',
          'Processed sections must be in increasing reading order',
        );
      }
      previousOrder = section['section_order'] as int;
      _checkInput(path, section);
    }

    final coverage = model['coverage'] as JsonMap;
    if (sections.isNotEmpty &&
        coverage['start_section_id'] != sections.first['section_id']) {
      _error(
        'coverage',
        'coverage.start_section_id',
        '"${coverage['start_section_id']}" is not the first processed section',
      );
    }
    final overlap = (coverage['omitted_prefix_section_ids'] as List)
        .where(sectionRevisions.containsKey)
        .toList();
    if (overlap.isNotEmpty) {
      _error(
        'coverage',
        'coverage.omitted_prefix_section_ids',
        '${overlap.join(', ')} are listed as omitted but were processed',
      );
    }
  }

  void _checkInput(String path, JsonMap section) {
    final sectionId = section['section_id'] as String;
    final chapter = inputs[sectionId];
    if (chapter == null) {
      _error(
        'missing_input',
        path,
        'No saved input for $sectionId; cannot verify',
      );
      return;
    }
    final saved = (chapter['paragraphs'] as List).cast<JsonMap>();
    final book = model['book'] as JsonMap;
    final expected = <(String, Object?, Object?)>[
      ('section_id', sectionId, chapter['section_id']),
      ('book_sha256', book['epub_sha256'], chapter['book_sha256']),
      ('text_sha256', section['text_sha256'], chapter['text_sha256']),
      ('paragraph_count', section['paragraph_count'], saved.length),
      (
        'extraction_version',
        section['extraction_version'],
        chapter['extraction_version'],
      ),
      ('source_href', section['href'], chapter['source_href']),
      ('source_fragment', section['fragment'], chapter['source_fragment']),
      ('title', section['title'], chapter['title']),
      ('chapter_number', section['chapter_number'], chapter['chapter_number']),
    ];
    final mismatched = [
      for (final (name, want, have) in expected)
        if (want != have) name,
      if (paragraphsSha256(saved) != section['text_sha256']) 'paragraph text',
    ];
    if (mismatched.isNotEmpty) {
      _error(
        'input_mismatch',
        path,
        'Saved input of $sectionId does not match: ${mismatched.join(', ')}',
      );
      return;
    }
    paragraphs[sectionId] = {
      for (final paragraph in saved)
        paragraph['id'] as String: paragraph['text'] as String,
    };
  }

  void _checkEntities() {
    final items = (model['entities'] as List).cast<JsonMap>();
    for (var i = 0; i < items.length; i++) {
      final entity = items[i];
      final id = entity['id'] as String;
      final path = paths[id] ?? 'entities[$i]';
      if (entities.containsKey(id)) {
        _error('duplicate_id', path, 'Duplicate entity ID "$id"', id);
        continue;
      }
      entities[id] = entity;
      final introduced = entity['introduced_revision'] as int;
      if (!_entityIdPatterns[entity['kind']]!.hasMatch(id)) {
        _warn(
          'id_format',
          path,
          '"$id" does not follow the ${entity['kind']} ID pattern',
          id,
          introduced,
        );
      }
      if (introduced < 1 || introduced > revision) {
        _error(
          'revision_range',
          '$path.introduced_revision',
          '$introduced is outside 1..$revision',
          id,
        );
      }
    }
  }

  void _checkRecords() {
    final eventsBySection = <String, List<(String, JsonMap)>>{};
    for (final (collection, index, record) in iterRecords(model)) {
      final id = record['id'] as String;
      final path = paths[id] ?? 'records.$collection[$index]';
      if (records.containsKey(id)) {
        _error('duplicate_id', path, 'Duplicate record ID "$id"', id);
        continue;
      }
      records[id] = (collection, record);
      if (!_recordIdPattern.hasMatch(id)) {
        _error('id_format', path, '"$id" is not a record ID', id);
      }
      final section = record['learned_in_section_id'] as String;
      _checkOrigin(path, id, record['introduced_revision'] as int, section);
      _checkPayload('$path.payload', collection, record);
      _checkEvidence(path, record['evidence'] as List, id, section);
      if (collection == 'events') {
        (eventsBySection[section] ??= []).add((path, record));
      }
    }
    eventsBySection.values.forEach(_checkEventOrder);
    if (focus != null) _checkDuplicateClaims();
  }

  void _checkPayload(String path, String collection, JsonMap record) {
    final rid = record['id'] as String;
    final rev = record['introduced_revision'] as int;
    final payload = record['payload'] as JsonMap;
    void ref(String field, Set<String> allowed) =>
        _checkRef('$path.$field', payload[field] as String, allowed, rid, rev);
    void text(String field) => _nonempty('$path.$field', payload[field], rid);

    switch (collection) {
      case 'names' || 'aliases':
        ref('entity_id', _allKinds);
        text('text');
      case 'attributes':
        ref('entity_id', _allKinds);
        text('label');
        text('value');
        _checkAssertion(path, payload, rid, rev);
      case 'relationships':
        ref('source_id', _allKinds);
        ref('target_id', _allKinds);
        if (payload['source_id'] == payload['target_id']) {
          _warn(
            'self_relationship',
            path,
            'Source and target are the same',
            rid,
            rev,
          );
        }
        text('label');
        text('description');
        _checkAssertion(path, payload, rid, rev);
      case 'events':
        text('description');
        final participants = (payload['participant_ids'] as List)
            .cast<String>();
        for (var i = 0; i < participants.length; i++) {
          _checkRef(
            '$path.participant_ids[$i]',
            participants[i],
            _speakerKinds,
            rid,
            rev,
          );
        }
        if (participants.toSet().length != participants.length) {
          _warn(
            'duplicate_participant',
            path,
            'A participant is listed twice',
            rid,
            rev,
          );
        }
        if (payload['location_id'] != null) {
          ref('location_id', const {'location'});
        }
        _checkAssertion(path, payload, rid, rev);
      case 'uncertainties':
        text('question');
        final related = (payload['related_entity_ids'] as List).cast<String>();
        for (var i = 0; i < related.length; i++) {
          _checkRef(
            '$path.related_entity_ids[$i]',
            related[i],
            _allKinds,
            rid,
            rev,
          );
        }
      case 'identity_links':
        final left = payload['left_entity_id'] as String;
        final right = payload['right_entity_id'] as String;
        ref('left_entity_id', _allKinds);
        ref('right_entity_id', _allKinds);
        text('explanation');
        if (left == right) {
          _error(
            'self_identity',
            path,
            'An entity cannot be linked to itself',
            rid,
          );
        } else if (entities.containsKey(left) && entities.containsKey(right)) {
          final leftKind = entities[left]!['kind'];
          final rightKind = entities[right]!['kind'];
          if (leftKind != rightKind) {
            _error(
              'identity_kind_mismatch',
              path,
              'Cannot link a $leftKind ($left) and a $rightKind ($right)',
              rid,
            );
          }
        }
    }
  }

  /// `narrative_order` counts within the section the event was learned in.
  void _checkEventOrder(List<(String, JsonMap)> events) {
    var previous = 0;
    final seen = <int>{};
    for (final (path, record) in events) {
      final id = record['id'] as String;
      final order = (record['payload'] as JsonMap)['narrative_order'] as int;
      final orderPath = '$path.payload.narrative_order';
      if (order < 1) {
        _error('narrative_order', orderPath, '$order is not positive', id);
      } else if (seen.contains(order)) {
        _error('narrative_order', orderPath, '$order is repeated', id);
      } else if (order < previous) {
        _error(
          'narrative_order',
          orderPath,
          '$order comes after $previous; events must be listed in order',
          id,
        );
      } else if (order != previous + 1) {
        _warn(
          'narrative_order_gap',
          orderPath,
          'Expected ${previous + 1}, got $order',
          id,
          record['introduced_revision'] as int,
        );
      }
      seen.add(order);
      if (order > previous) previous = order;
    }
  }

  /// Flags, never merges, new records whose payload repeats an earlier one.
  void _checkDuplicateClaims() {
    final earlier = <String, String>{};
    for (final (collection, _, record) in iterRecords(model)) {
      final id = record['id'] as String;
      final key = '$collection\u0000${jsonEncode(record['payload'])}';
      if (record['introduced_revision'] != focus) {
        earlier.putIfAbsent(key, () => id);
      } else if (earlier.containsKey(key)) {
        _warn(
          'duplicate_claim',
          paths[id] ?? id,
          'Repeats ${earlier[key]} exactly; kept as a separate record',
          id,
          record['introduced_revision'] as int,
        );
      }
    }
  }

  void _checkTransitions() {
    final targets = <String, String>{};
    final replacements = <String>{};
    final seenIds = <String>{};
    for (var i = 0; i < transitions.length; i++) {
      final item = transitions[i];
      final tid = item['id'] as String;
      final path = paths[tid] ?? 'transitions[$i]';
      if (seenIds.contains(tid) || records.containsKey(tid)) {
        _error('duplicate_id', path, 'Duplicate transition ID "$tid"', tid);
      }
      seenIds.add(tid);
      if (!_transitionIdPattern.hasMatch(tid)) {
        _error('id_format', path, '"$tid" is not a transition ID', tid);
      }
      final itemRevision = item['introduced_revision'] as int;
      final section = item['learned_in_section_id'] as String;
      _checkOrigin(path, tid, itemRevision, section);
      _nonempty('$path.reason', item['reason'], tid);

      final targetId = item['target_record_id'] as String;
      final target = records[targetId];
      final targetPath = '$path.target_record_id';
      if (target == null) {
        _error(
          'dangling_reference',
          targetPath,
          'Target "$targetId" does not exist',
          tid,
        );
      } else {
        final targetRevision = target.$2['introduced_revision'] as int;
        if (targetRevision >= itemRevision) {
          _error(
            'target_not_prior',
            targetPath,
            '$targetId is from revision $targetRevision; only records of '
                'earlier revisions can be changed',
            tid,
          );
        }
        if (targets.containsKey(targetId)) {
          _error(
            'target_already_transitioned',
            targetPath,
            '$targetId is no longer active: ${targets[targetId]} already '
                'changed it',
            tid,
          );
        }
        targets[targetId] = tid;
      }

      final resolution = item['resolution'] as String?;
      final replacementId = item['replacement_record_id'] as String?;
      switch (item['action']) {
        case 'supersede':
          _checkSupersede(path, replacementId, target, item, replacements);
          if (resolution != null) {
            _error(
              'transition_fields',
              '$path.resolution',
              'supersede has no resolution',
              tid,
            );
          }
        case 'retract':
          if (replacementId != null || resolution != null) {
            _error(
              'transition_fields',
              path,
              'retract has neither a replacement nor a resolution',
              tid,
            );
          }
        default:
          if (target != null && target.$1 != 'uncertainties') {
            _error(
              'resolve_non_uncertainty',
              targetPath,
              'resolve only applies to uncertainties, not ${target.$1}',
              tid,
            );
          }
          if (replacementId != null) {
            _error(
              'transition_fields',
              '$path.replacement_record_id',
              'resolve has no replacement; add any new fact as its own record',
              tid,
            );
          }
          if (pyStrip(resolution ?? '').isEmpty) {
            _error(
              'missing_resolution',
              '$path.resolution',
              'resolve needs an answer',
              tid,
            );
          }
      }
      _checkEvidence(path, item['evidence'] as List, tid, section);
    }
  }

  void _checkSupersede(
    String path,
    String? replacementId,
    (String, JsonMap)? target,
    JsonMap item,
    Set<String> replacements,
  ) {
    final tid = item['id'] as String;
    final replacementPath = '$path.replacement_record_id';
    if (replacementId == null) {
      _error(
        'missing_replacement',
        replacementPath,
        'supersede needs a replacement record',
        tid,
      );
      return;
    }
    final replacement = records[replacementId];
    if (replacement == null) {
      _error(
        'dangling_reference',
        replacementPath,
        'Replacement "$replacementId" does not exist',
        tid,
      );
      return;
    }
    final itemRevision = item['introduced_revision'] as int;
    if (replacement.$2['introduced_revision'] != itemRevision) {
      _error(
        'replacement_not_new',
        replacementPath,
        '$replacementId must be a record added in the same revision',
        tid,
      );
    }
    if (replacements.contains(replacementId)) {
      _warn(
        'replacement_reused',
        path,
        '$replacementId replaces more than one record; check manually',
        tid,
        itemRevision,
      );
    }
    replacements.add(replacementId);
    if (target == null) return;
    final (collection, old) = target;
    if (replacement.$1 != collection) {
      _error(
        'supersede_kind_mismatch',
        path,
        'A $collection record can only be replaced by another $collection '
            'record, not by ${replacement.$1}',
        tid,
      );
      return;
    }
    _checkSameSubject(path, collection, old, replacement.$2, item);
  }

  void _checkSameSubject(
    String path,
    String collection,
    JsonMap old,
    JsonMap next,
    JsonMap item,
  ) {
    final tid = item['id'] as String;
    final before = old['payload'] as JsonMap;
    final after = next['payload'] as JsonMap;
    String? problem;
    switch (collection) {
      case 'names' || 'aliases':
        if (before['entity_id'] != after['entity_id']) {
          problem = 'entity ${before['entity_id']} → ${after['entity_id']}';
        }
      case 'attributes':
        if (before['entity_id'] != after['entity_id'] ||
            before['label'] != after['label']) {
          problem =
              '${before['entity_id']}/"${before['label']}" → '
              '${after['entity_id']}/"${after['label']}"; an attribute is '
              'replaced by the same entity\'s attribute with the same label';
        }
      case 'relationships':
        if (before['source_id'] != after['source_id'] ||
            before['target_id'] != after['target_id'] ||
            before['label'] != after['label']) {
          problem =
              'a relationship is replaced only by one with the same direction '
              'and label (use retract plus a new record for a different label)';
        } else if (before['temporal_context'] != after['temporal_context']) {
          _error(
            'temporal_mismatch',
            path,
            'Replacing a "${before['temporal_context']}" relationship with a '
                '"${after['temporal_context']}" one; a flashback adds a record, '
                'it does not replace the current state',
            tid,
          );
        }
      case 'identity_links':
        final beforePair = {
          before['left_entity_id'],
          before['right_entity_id'],
        };
        final afterPair = {after['left_entity_id'], after['right_entity_id']};
        if (beforePair.length != afterPair.length ||
            !beforePair.containsAll(afterPair)) {
          problem =
              'an identity link is replaced only by a link between the same '
              'two entities';
        }
      case 'events' || 'uncertainties':
        _warn(
          'semantic_supersede_review',
          path,
          'Replaces ${collection.substring(0, collection.length - 1)} '
              '${old['id']} with ${next['id']}; code cannot check that both '
              'describe the same thing; review manually',
          tid,
          item['introduced_revision'] as int,
        );
    }
    if (problem != null) {
      _error('supersede_subject_mismatch', path, problem, tid);
    }
  }

  void _checkCurrent(JsonMap expected) {
    final stored = model['current'] as JsonMap;
    for (final name in const [
      'active_record_ids',
      'resolved_uncertainty_ids',
      'identity_groups',
    ]) {
      if (!jsonEquals(stored[name], expected[name])) {
        _error(
          'current_mismatch',
          'current.$name',
          'Does not match the index computed from records and transitions',
        );
      }
    }
  }

  void _checkNames() {
    final names = <String, List<JsonMap>>{};
    final allNames = ((model['records'] as JsonMap)['names'] as List)
        .cast<JsonMap>();
    for (final record in allNames) {
      final payload = record['payload'] as JsonMap;
      (names[payload['entity_id'] as String] ??= []).add(record);
    }
    final items = (model['entities'] as List).cast<JsonMap>();
    for (var i = 0; i < items.length; i++) {
      final entity = items[i];
      final id = entity['id'] as String;
      final path = paths[id] ?? 'entities[$i]';
      final own = names[id] ?? const <JsonMap>[];
      if (!own.any(
        (r) => r['introduced_revision'] == entity['introduced_revision'],
      )) {
        _error(
          'entity_without_name',
          path,
          '$id has no name record from the revision that introduced it',
          id,
        );
      }
      final activeNames = [
        for (final record in own)
          if (active.contains(record['id'])) record['id'],
      ];
      if (activeNames.isEmpty) {
        _warn('no_active_name', path, '$id has no active name', id);
      } else if (activeNames.length > 1) {
        _warn(
          'name_conflict',
          path,
          '$id has several active names (${activeNames.join(', ')})',
          id,
        );
      }
    }
  }

  /// Merged identities don't reconcile their facts; conflicting values are shown.
  void _checkIdentityConflicts(JsonMap expected) {
    final attributes = ((model['records'] as JsonMap)['attributes'] as List)
        .cast<JsonMap>();
    for (final group in (expected['identity_groups'] as List).cast<JsonMap>()) {
      final members = group['member_ids'] as List;
      final values = <String, Map<String, List<String>>>{};
      for (final record in attributes) {
        final payload = record['payload'] as JsonMap;
        if (active.contains(record['id']) &&
            members.contains(payload['entity_id'])) {
          // The lab casefolds; lower case differs only in rare letters, and
          // this is only ever a warning.
          final label = pyStrip(payload['label'] as String).toLowerCase();
          final value = pyStrip(payload['value'] as String).toLowerCase();
          ((values[label] ??= {})[value] ??= []).add(record['id'] as String);
        }
      }
      values.forEach((label, byValue) {
        if (byValue.length > 1) {
          final ids = byValue.values.expand((ids) => ids).join(', ');
          _warn(
            'identity_attribute_conflict',
            'current.identity_groups[${group['canonical_id']}]',
            'Members of ${members.join('/')} have different "$label" values '
                '($ids)',
            group['canonical_id'] as String,
          );
        }
      });
    }
  }
}

/// Earlier knowledge must be an unchanged prefix of the next revision.
List<StoryIssue> checkHistory(JsonMap base, JsonMap after) {
  final issues = <StoryIssue>[];
  void error(String path, String message) =>
      issues.add(StoryIssue('error', 'history_changed', path, message));

  final baseNumber = (base['revision'] as JsonMap)['number'] as int;
  final number = (after['revision'] as JsonMap)['number'] as int;
  if (number != baseNumber + 1) {
    error('revision.number', 'Expected ${baseNumber + 1}, got $number');
  }
  for (final name in const ['book', 'coverage']) {
    if (!jsonEquals(after[name], base[name])) {
      error(name, '$name changed between revisions');
    }
  }
  final baseRecords = base['records'] as JsonMap;
  final afterRecords = after['records'] as JsonMap;
  final pairs = <(String, List<dynamic>, List<dynamic>)>[
    (
      'processed_sections',
      base['processed_sections'] as List,
      after['processed_sections'] as List,
    ),
    ('entities', base['entities'] as List, after['entities'] as List),
    ('transitions', base['transitions'] as List, after['transitions'] as List),
    for (final collection in storyCollections)
      (
        'records.$collection',
        baseRecords[collection] as List,
        afterRecords[collection] as List,
      ),
    (
      'provenance.manual_corrections',
      (base['provenance'] as JsonMap)['manual_corrections'] as List,
      (after['provenance'] as JsonMap)['manual_corrections'] as List,
    ),
  ];
  for (final (path, before, now) in pairs) {
    final kept = now.length < before.length
        ? now
        : now.sublist(0, before.length);
    if (!jsonEquals(kept, before)) {
      error(path, 'Earlier items were changed, removed, or reordered');
    }
    for (var i = before.length; i < now.length; i++) {
      final item = now[i] as JsonMap;
      if ((item['introduced_revision'] ?? item['revision']) != number) {
        error('$path[$i]', 'New item is not marked as revision $number');
      }
    }
  }
  final baseSections = base['processed_sections'] as List;
  if ((after['processed_sections'] as List).length != baseSections.length + 1) {
    error('processed_sections', 'An update adds exactly one processed section');
  }
  return issues;
}

/// Every entity a payload refers to, as (field path, entity ID).
List<(String, String)> _entityRefs(String collection, JsonMap payload) {
  (String, String) field(String name) => (name, payload[name] as String);
  List<(String, String)> list(String name) {
    final values = (payload[name] as List).cast<String>();
    return [for (var i = 0; i < values.length; i++) ('$name[$i]', values[i])];
  }

  return switch (collection) {
    'names' || 'aliases' => [field('entity_id')],
    'attributes' => [
      field('entity_id'),
      if (payload['attributed_to_id'] != null) field('attributed_to_id'),
    ],
    'relationships' => [
      field('source_id'),
      field('target_id'),
      if (payload['attributed_to_id'] != null) field('attributed_to_id'),
    ],
    'events' => [
      ...list('participant_ids'),
      if (payload['location_id'] != null) field('location_id'),
      if (payload['attributed_to_id'] != null) field('attributed_to_id'),
    ],
    'uncertainties' => list('related_entity_ids'),
    _ => [field('left_entity_id'), field('right_entity_id')],
  };
}

/// Local IDs must be unique and well-formed before any stable ID is assigned,
/// and every entity reference must name a prior entity or a new one of this
/// delta: a stable ID the model made up would otherwise bind to whichever new
/// entity receives it.
List<StoryIssue> checkDeltaIds(JsonMap base, JsonMap delta) {
  final issues = <StoryIssue>[];
  final baseEntities = (base['entities'] as List).cast<JsonMap>();
  final existing = <Object?>{
    for (final entity in baseEntities) entity['id'],
    for (final transition in (base['transitions'] as List).cast<JsonMap>())
      transition['id'],
    for (final (_, _, record) in iterRecords(base)) record['id'],
  };
  final seen = <String>{};

  void check(String path, String localId, RegExp pattern, String example) {
    if (seen.contains(localId)) {
      issues.add(
        StoryIssue(
          'error',
          'duplicate_local_id',
          path,
          '"$localId" is used twice',
          localId,
        ),
      );
    } else if (existing.contains(localId) || !pattern.hasMatch(localId)) {
      issues.add(
        StoryIssue(
          'error',
          'local_id_format',
          path,
          '"$localId" is not a new local ID like "$example"',
          localId,
        ),
      );
    }
    seen.add(localId);
  }

  final newEntities = (delta['new_entities'] as List).cast<JsonMap>();
  for (var i = 0; i < newEntities.length; i++) {
    check(
      'new_entities[$i].local_id',
      newEntities[i]['local_id'] as String,
      _localEntityPattern,
      'new_entity_001',
    );
  }
  final knownEntities = <Object?>{
    for (final entity in baseEntities) entity['id'],
    for (final entity in newEntities) entity['local_id'],
  };
  final recordIds = <String>{};
  final newRecords = delta['new_records'] as JsonMap;
  for (final collection in storyCollections) {
    final items = (newRecords[collection] as List).cast<JsonMap>();
    for (var i = 0; i < items.length; i++) {
      final path = 'new_records.$collection[$i]';
      final localId = items[i]['local_id'] as String;
      check('$path.local_id', localId, _localRecordPattern, 'new_record_001');
      recordIds.add(localId);
      final refs = _entityRefs(collection, items[i]['payload'] as JsonMap);
      for (final (fieldPath, ref) in refs) {
        if (!knownEntities.contains(ref)) {
          issues.add(
            StoryIssue(
              'error',
              'unknown_entity_ref',
              '$path.payload.$fieldPath',
              '"$ref" is neither an entity of the prior model nor a '
                  'new_entity_* of this delta',
            ),
          );
        }
      }
    }
  }
  final transitions = (delta['transitions'] as List).cast<JsonMap>();
  for (var i = 0; i < transitions.length; i++) {
    final item = transitions[i];
    if (seen.contains(item['target_record_id'])) {
      issues.add(
        StoryIssue(
          'error',
          'target_is_new',
          'transitions[$i].target_record_id',
          'Transitions can only target records of the prior model',
        ),
      );
    }
    final replacement = item['replacement_local_id'] as String?;
    if (replacement != null && !recordIds.contains(replacement)) {
      issues.add(
        StoryIssue(
          'error',
          'unknown_replacement',
          'transitions[$i].replacement_local_id',
          '"$replacement" is not the local_id of a record in this delta',
        ),
      );
    }
  }
  return issues;
}

bool _deltaIsEmpty(JsonMap delta) {
  final records = delta['new_records'] as JsonMap;
  return (delta['new_entities'] as List).isEmpty &&
      (delta['transitions'] as List).isEmpty &&
      storyCollections.every((name) => (records[name] as List).isEmpty);
}

Map<String, String> _deltaPaths(JsonMap delta, StoryIdMap idMap) {
  final paths = <String, String>{};
  final entities = (delta['new_entities'] as List).cast<JsonMap>();
  for (var i = 0; i < entities.length; i++) {
    paths[idMap.entities[entities[i]['local_id']]!] = 'new_entities[$i]';
  }
  final records = delta['new_records'] as JsonMap;
  for (final collection in storyCollections) {
    final items = (records[collection] as List).cast<JsonMap>();
    for (var i = 0; i < items.length; i++) {
      paths[idMap.records[items[i]['local_id']]!] =
          'new_records.$collection[$i]';
    }
  }
  for (var i = 0; i < idMap.transitions.length; i++) {
    paths[idMap.transitions[i]] = 'transitions[$i]';
  }
  return paths;
}

/// Checks a delta's structure, merges it in memory and checks the result and its
/// history. Nothing is written.
StoryUpdateValidation validateUpdate(
  JsonMap base,
  Object? candidate, {
  required StoryDeltaSchema schema,
  required JsonMap chapter,
  required Map<String, JsonMap> baseInputs,
  required JsonMap section,
  required JsonMap revision,
}) {
  final (normalized, schemaIssues) = schema.check(candidate);
  if (schemaIssues.isNotEmpty) {
    return StoryUpdateValidation(structureValid: false, issues: schemaIssues);
  }
  final delta = normalized! as JsonMap;
  final issues = checkDeltaIds(base, delta);
  if (issues.any((issue) => issue.isError)) {
    return StoryUpdateValidation(
      structureValid: true,
      issues: issues,
      delta: delta,
    );
  }

  final (after, idMap) = applyDelta(
    base,
    delta,
    section: section,
    revision: revision,
  );
  final report = validateCumulative(
    after,
    {...baseInputs, section['section_id'] as String: chapter},
    paths: _deltaPaths(delta, idMap),
    focusRevision: revision['number'] as int,
  );
  issues
    ..addAll(report.issues)
    ..addAll(checkHistory(base, after));
  if (_deltaIsEmpty(delta)) {
    issues.add(
      const StoryIssue(
        'warning',
        'empty_delta',
        '(root)',
        'The model reported nothing new for this section; check manually for '
            'omissions',
      ),
    );
  }
  return StoryUpdateValidation(
    structureValid: true,
    issues: issues,
    delta: delta,
    after: after,
    idMap: idMap,
  );
}
