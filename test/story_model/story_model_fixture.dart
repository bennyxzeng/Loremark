import 'package:loremark/story_model/story_model.dart';

/// A two-chapter story model in the lab's JSON format.
///
/// Chapter 2 renames Mara, retracts her age, adds her brother Elian, answers
/// who the stranger is, and reveals that the stranger is Captain Vell.
StoryModel storyModelFixture() => StoryModel.fromJson(storyModelFixtureJson());

Map<String, dynamic> storyModelFixtureJson() => {
  'schema_version': '2.0',
  'scope': 'cumulative',
  'book': {'title': 'The Glass Harbor', 'epub_sha256': 'abc'},
  'revision': {'number': 2},
  'processed_sections': [
    _section('s2', 2, 'Chapter 2: The Letter'),
    _section('s1', 1, 'Chapter 1: Arrival'),
  ],
  'entities': [
    _entity('c001', 'character', 1),
    _entity('c002', 'character', 1),
    _entity('g001', 'organization', 1),
    _entity('c003', 'character', 2),
    _entity('c004', 'character', 2),
  ],
  'records': {
    'names': [
      _record('f001', 's1', {'entity_id': 'c001', 'text': 'Mara'}),
      _record('f002', 's1', {'entity_id': 'c002', 'text': 'the stranger'}),
      _record('f003', 's1', {'entity_id': 'g001', 'text': 'Harbor Guild'}),
      _record('f004', 's2', {'entity_id': 'c003', 'text': 'Elian'}),
      _record('f005', 's2', {'entity_id': 'c004', 'text': 'Captain Vell'}),
      _record('f006', 's2', {'entity_id': 'c001', 'text': 'Mara Quinn'}),
    ],
    'aliases': [
      _record('f007', 's1', {'entity_id': 'c001', 'text': 'the harbor girl'}),
    ],
    'attributes': [
      _record('f008', 's1', {
        'entity_id': 'c001',
        'label': 'role',
        'value': 'dock clerk',
        'assertion': 'explicit',
        'attributed_to_id': null,
      }),
      _record('f009', 's1', {
        'entity_id': 'c001',
        'label': 'age',
        'value': 'sixteen',
        'assertion': 'inferred',
        'attributed_to_id': null,
      }),
    ],
    'relationships': [
      _relationship('f010', 's1', 'c001', 'member_of', 'g001'),
      _relationship('f011', 's1', 'c002', 'watches', 'c001'),
      _relationship('f012', 's2', 'c003', 'sibling_of', 'c001'),
    ],
    'events': [
      _event('f013', 's1', 'Mara arrives at the harbor.', ['c001'], 1),
      _event('f014', 's2', 'Elian hands Mara a letter.', ['c003', 'c001'], 2),
      _event(
        'f015',
        's2',
        'Elian left home years ago.',
        ['c003'],
        1,
        temporal: 'past',
      ),
    ],
    'uncertainties': [
      _record('f016', 's1', {
        'question': 'Who is the stranger?',
        'related_entity_ids': ['c002'],
      }),
      _record('f017', 's2', {
        'question': 'Why did Elian leave?',
        'related_entity_ids': ['c003'],
      }),
    ],
    'identity_links': [
      _record('f018', 's2', {
        'left_entity_id': 'c004',
        'right_entity_id': 'c002',
        'assertion': 'explicit',
        'explanation': 'The stranger is Captain Vell.',
      }),
    ],
  },
  'transitions': [
    _transition('t001', 'f001', 'supersede', replacement: 'f006'),
    _transition('t002', 'f009', 'retract'),
    _transition('t003', 'f016', 'resolve', resolution: 'He is Captain Vell.'),
  ],
  'current': <String, dynamic>{},
  'provenance': <String, dynamic>{},
};

Map<String, dynamic> _section(String id, int order, String title) => {
  'section_id': id,
  'section_order': order,
  'chapter_number': order,
  'title': title,
};

Map<String, dynamic> _entity(String id, String kind, int revision) => {
  'id': id,
  'kind': kind,
  'introduced_revision': revision,
};

Map<String, dynamic> _record(
  String id,
  String section,
  Map<String, dynamic> payload,
) => {
  'id': id,
  'introduced_revision': section == 's1' ? 1 : 2,
  'learned_in_section_id': section,
  'legacy_id': null,
  'payload': payload,
  'evidence': [
    {'section_id': section, 'paragraph_id': 'p0001', 'quote': 'quote $id'},
  ],
};

Map<String, dynamic> _relationship(
  String id,
  String section,
  String source,
  String label,
  String target,
) => _record(id, section, {
  'source_id': source,
  'target_id': target,
  'label': label,
  'description': '$source $label $target',
  'assertion': 'explicit',
  'attributed_to_id': null,
  'temporal_context': 'current',
});

Map<String, dynamic> _event(
  String id,
  String section,
  String description,
  List<String> participants,
  int order, {
  String temporal = 'current',
}) => _record(id, section, {
  'description': description,
  'participant_ids': participants,
  'location_id': null,
  'narrative_order': order,
  'temporal_context': temporal,
  'story_time': null,
  'assertion': 'explicit',
  'attributed_to_id': null,
});

Map<String, dynamic> _transition(
  String id,
  String target,
  String action, {
  String? replacement,
  String? resolution,
}) => {
  'id': id,
  'introduced_revision': 2,
  'learned_in_section_id': 's2',
  'target_record_id': target,
  'action': action,
  'replacement_record_id': replacement,
  'resolution': resolution,
  'reason': 'reason $id',
  'evidence': <Map<String, dynamic>>[],
};
