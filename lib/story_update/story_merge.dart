import 'story_book.dart';

/// The record collections, in the order IDs are assigned and records listed.
const storyCollections = [
  'names',
  'aliases',
  'attributes',
  'relationships',
  'events',
  'uncertainties',
  'identity_links',
];

const _entityPrefixes = {
  'character': 'c',
  'location': 'l',
  'organization': 'g',
};
const _scalarRefFields = [
  'entity_id',
  'attributed_to_id',
  'source_id',
  'target_id',
  'location_id',
  'left_entity_id',
  'right_entity_id',
];
const _listRefFields = ['participant_ids', 'related_entity_ids'];

/// The stable IDs [applyDelta] gave a delta's local IDs.
class StoryIdMap {
  final entities = <String, String>{};
  final records = <String, String>{};
  final transitions = <String>[];

  JsonMap toJson() => {
    'entities': entities,
    'records': records,
    'transitions': [
      for (var i = 0; i < transitions.length; i++)
        {'delta_index': i, 'id': transitions[i]},
    ],
  };
}

/// Every record of [model] with its collection and index, in the fixed order.
Iterable<(String, int, JsonMap)> iterRecords(JsonMap model) sync* {
  final records = model['records'] as JsonMap;
  for (final collection in storyCollections) {
    final items = records[collection] as List;
    for (var i = 0; i < items.length; i++) {
      yield (collection, i, items[i] as JsonMap);
    }
  }
}

/// Active records, resolved uncertainties and explicit identity groups, computed
/// from the history. A record is active until a transition targets it, and
/// inactive records stay in the model.
JsonMap projectCurrent(JsonMap model) {
  final transitions = (model['transitions'] as List).cast<JsonMap>();
  final targets = {for (final t in transitions) t['target_record_id']};
  final active = [
    for (final (_, _, record) in iterRecords(model))
      if (!targets.contains(record['id'])) record['id'] as String,
  ];
  return {
    'active_record_ids': active,
    'resolved_uncertainty_ids': [
      for (final t in transitions)
        if (t['action'] == 'resolve') t['target_record_id'],
    ],
    'identity_groups': identityGroups(model, active.toSet()),
  };
}

/// Entities joined by active `explicit` identity links of the same kind. The
/// canonical ID is the earliest-introduced member, ties broken by ID. Inferred
/// or reported links never merge entities.
List<JsonMap> identityGroups(JsonMap model, Set<String> active) {
  final entities = {
    for (final entity in (model['entities'] as List).cast<JsonMap>())
      entity['id'] as String: entity,
  };
  final parent = <String, String>{};
  String find(String entityId) {
    var id = entityId;
    while ((parent[id] ??= id) != id) {
      id = parent[id]!;
    }
    return id;
  }

  final links = <(String, JsonMap)>[];
  final records = model['records'] as JsonMap;
  for (final record in (records['identity_links'] as List).cast<JsonMap>()) {
    final link = record['payload'] as JsonMap;
    final left = entities[link['left_entity_id']];
    final right = entities[link['right_entity_id']];
    if (active.contains(record['id']) &&
        link['assertion'] == 'explicit' &&
        left != null &&
        right != null &&
        left['id'] != right['id'] &&
        left['kind'] == right['kind']) {
      links.add((record['id'] as String, link));
      final leftRoot = find(left['id'] as String);
      parent[leftRoot] = find(right['id'] as String);
    }
  }

  final members = <String, List<String>>{};
  for (final entityId in parent.keys.toList()) {
    (members[find(entityId)] ??= []).add(entityId);
  }
  final groups = <JsonMap>[];
  for (final ids in members.values) {
    if (ids.length < 2) continue;
    final ordered = [...ids]
      ..sort((a, b) {
        final order = (entities[a]!['introduced_revision'] as int).compareTo(
          entities[b]!['introduced_revision'] as int,
        );
        return order != 0 ? order : a.compareTo(b);
      });
    groups.add({
      'canonical_id': ordered.first,
      'member_ids': ordered,
      'link_record_ids': [
        for (final (id, link) in links)
          if (ids.contains(link['left_entity_id'])) id,
      ],
    });
  }
  groups.sort(
    (a, b) =>
        (a['canonical_id'] as String).compareTo(b['canonical_id'] as String),
  );
  return groups;
}

/// One more than the largest `<prefix><digits>` number in use, or 1.
int nextStoryNumber(Iterable<String> ids, String prefix) {
  final pattern = RegExp('^${RegExp.escape(prefix)}(\\d+)\$');
  var largest = 0;
  for (final id in ids) {
    final number = pattern.firstMatch(id)?.group(1);
    if (number != null && int.parse(number) > largest) {
      largest = int.parse(number);
    }
  }
  return largest + 1;
}

JsonMap _translatePayload(JsonMap payload, Map<String, String> mapping) {
  final data = JsonMap.of(payload);
  for (final name in _scalarRefFields) {
    final value = data[name];
    if (mapping.containsKey(value)) data[name] = mapping[value];
  }
  for (final name in _listRefFields) {
    final values = data[name] as List?;
    if (values != null) {
      data[name] = [for (final value in values) mapping[value] ?? value];
    }
  }
  return data;
}

/// Appends [delta] as revision `revision['number']`; [base] is not modified.
///
/// Local IDs must be unique and well-formed, which `checkDeltaIds` checks first.
/// IDs continue after the largest number in use: entities per kind in
/// `new_entities` order, records over the fixed collection order and then array
/// order, transitions in array order. Earlier items are kept as they are.
(JsonMap, StoryIdMap) applyDelta(
  JsonMap base,
  JsonMap delta, {
  required JsonMap section,
  required JsonMap revision,
}) {
  final number = revision['number'] as int;
  final sectionId = section['section_id'];
  final idMap = StoryIdMap();

  final entities = [...base['entities'] as List];
  final entityIds = [
    for (final entity in entities) (entity as JsonMap)['id'] as String,
  ];
  final entityNumbers = {
    for (final MapEntry(key: kind, value: prefix) in _entityPrefixes.entries)
      kind: nextStoryNumber(entityIds, prefix),
  };
  for (final item in (delta['new_entities'] as List).cast<JsonMap>()) {
    final kind = item['kind'] as String;
    final stable =
        '${_entityPrefixes[kind]}${'${entityNumbers[kind]}'.padLeft(3, '0')}';
    entityNumbers[kind] = entityNumbers[kind]! + 1;
    idMap.entities[item['local_id'] as String] = stable;
    entities.add({'id': stable, 'kind': kind, 'introduced_revision': number});
  }

  final baseRecords = base['records'] as JsonMap;
  final newRecords = delta['new_records'] as JsonMap;
  var recordNumber = nextStoryNumber([
    for (final (_, _, record) in iterRecords(base)) record['id'] as String,
  ], 'f');
  final records = <String, dynamic>{};
  for (final collection in storyCollections) {
    final items = [...baseRecords[collection] as List];
    for (final item in (newRecords[collection] as List).cast<JsonMap>()) {
      final stable = 'f${'$recordNumber'.padLeft(6, '0')}';
      recordNumber++;
      idMap.records[item['local_id'] as String] = stable;
      items.add({
        'id': stable,
        'introduced_revision': number,
        'learned_in_section_id': sectionId,
        'payload': _translatePayload(
          item['payload'] as JsonMap,
          idMap.entities,
        ),
        'evidence': item['evidence'],
      });
    }
    records[collection] = items;
  }

  final transitions = [...base['transitions'] as List];
  var transitionNumber = nextStoryNumber([
    for (final transition in transitions)
      (transition as JsonMap)['id'] as String,
  ], 't');
  for (final item in (delta['transitions'] as List).cast<JsonMap>()) {
    final stable = 't${'$transitionNumber'.padLeft(6, '0')}';
    transitionNumber++;
    idMap.transitions.add(stable);
    final replacement = item['replacement_local_id'] as String?;
    transitions.add({
      'id': stable,
      'introduced_revision': number,
      'learned_in_section_id': sectionId,
      'target_record_id': item['target_record_id'],
      'action': item['action'],
      'replacement_record_id': replacement == null
          ? null
          : idMap.records[replacement] ?? replacement,
      'resolution': item['resolution'],
      'reason': item['reason'],
      'evidence': item['evidence'],
    });
  }

  final after = <String, dynamic>{
    'schema_version': base['schema_version'],
    'scope': base['scope'],
    'book': base['book'],
    'revision': revision,
    'processed_sections': [...base['processed_sections'] as List, section],
    'coverage': base['coverage'],
    'entities': entities,
    'records': records,
    'transitions': transitions,
    'current': const <String, dynamic>{},
    'provenance': base['provenance'],
  };
  after['current'] = projectCurrent(after);
  return (after, idMap);
}
