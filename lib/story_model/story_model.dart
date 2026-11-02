/// The cumulative story model written by the story model lab (schema 2.0).
///
/// Mirrors `tools/story_model_lab/src/loremark_story_lab/cumulative_schemas.py`.
/// Knowledge is stored as immutable records, each tagged with the section the
/// reader learned it in. Later sections never edit a record; they add new
/// records and transitions (supersede, retract, resolve). `StorySnapshot`
/// turns this history into what the reader knows at a given section.
library;

enum EntityKind { character, location, organization }

/// How directly the text states a fact.
enum Assertion { explicit, reported, inferred }

/// When a fact holds relative to the main narrative.
enum TemporalContext { current, past, future, hypothetical, unknown }

enum TransitionAction { supersede, retract, resolve }

/// A short quote from the book that supports a record.
class Evidence {
  const Evidence({
    required this.sectionId,
    required this.paragraphId,
    required this.quote,
  });

  factory Evidence.fromJson(Map<String, dynamic> json) => Evidence(
    sectionId: json['section_id'] as String,
    paragraphId: json['paragraph_id'] as String,
    quote: json['quote'] as String,
  );

  final String sectionId;
  final String paragraphId;
  final String quote;
}

/// A processed section of the book, usually a chapter.
class StorySection {
  const StorySection({
    required this.id,
    required this.order,
    required this.chapterNumber,
    required this.title,
  });

  factory StorySection.fromJson(Map<String, dynamic> json) => StorySection(
    id: json['section_id'] as String,
    order: json['section_order'] as int,
    chapterNumber: json['chapter_number'] as int?,
    title: json['title'] as String,
  );

  final String id;

  /// Position in the book's reading order.
  final int order;
  final int? chapterNumber;
  final String title;

  /// A short label such as "Chapter 2", or the title if there is no number.
  String get label => chapterNumber == null ? title : 'Chapter $chapterNumber';
}

/// A character, location or organization. Its names and facts are records.
class StoryEntity {
  const StoryEntity({
    required this.id,
    required this.kind,
    required this.introducedRevision,
  });

  factory StoryEntity.fromJson(Map<String, dynamic> json) => StoryEntity(
    id: json['id'] as String,
    kind: EntityKind.values.byName(json['kind'] as String),
    introducedRevision: json['introduced_revision'] as int,
  );

  final String id;
  final EntityKind kind;
  final int introducedRevision;
}

/// The fact a record holds.
sealed class RecordPayload {
  const RecordPayload();

  /// Every entity the fact refers to.
  Iterable<String> get entityIds;
}

/// A name or an alias of one entity.
class EntityText extends RecordPayload {
  const EntityText({required this.entityId, required this.text});

  factory EntityText.fromJson(Map<String, dynamic> json) => EntityText(
    entityId: json['entity_id'] as String,
    text: json['text'] as String,
  );

  final String entityId;
  final String text;

  @override
  Iterable<String> get entityIds => [entityId];
}

class Attribute extends RecordPayload {
  const Attribute({
    required this.entityId,
    required this.label,
    required this.value,
    required this.assertion,
    required this.attributedToId,
  });

  factory Attribute.fromJson(Map<String, dynamic> json) => Attribute(
    entityId: json['entity_id'] as String,
    label: json['label'] as String,
    value: json['value'] as String,
    assertion: Assertion.values.byName(json['assertion'] as String),
    attributedToId: json['attributed_to_id'] as String?,
  );

  final String entityId;
  final String label;
  final String value;
  final Assertion assertion;
  final String? attributedToId;

  @override
  Iterable<String> get entityIds => [entityId, ?attributedToId];
}

class Relationship extends RecordPayload {
  const Relationship({
    required this.sourceId,
    required this.targetId,
    required this.label,
    required this.description,
    required this.assertion,
    required this.attributedToId,
    required this.temporalContext,
  });

  factory Relationship.fromJson(Map<String, dynamic> json) => Relationship(
    sourceId: json['source_id'] as String,
    targetId: json['target_id'] as String,
    label: json['label'] as String,
    description: json['description'] as String,
    assertion: Assertion.values.byName(json['assertion'] as String),
    attributedToId: json['attributed_to_id'] as String?,
    temporalContext: TemporalContext.values.byName(
      json['temporal_context'] as String,
    ),
  );

  final String sourceId;
  final String targetId;

  /// A snake_case label such as `member_of`.
  final String label;
  final String description;
  final Assertion assertion;
  final String? attributedToId;
  final TemporalContext temporalContext;

  @override
  Iterable<String> get entityIds => [sourceId, targetId, ?attributedToId];
}

class StoryEvent extends RecordPayload {
  const StoryEvent({
    required this.description,
    required this.participantIds,
    required this.locationId,
    required this.narrativeOrder,
    required this.temporalContext,
    required this.storyTime,
    required this.assertion,
    required this.attributedToId,
  });

  factory StoryEvent.fromJson(Map<String, dynamic> json) => StoryEvent(
    description: json['description'] as String,
    participantIds: List<String>.from(json['participant_ids'] as List),
    locationId: json['location_id'] as String?,
    narrativeOrder: json['narrative_order'] as int,
    temporalContext: TemporalContext.values.byName(
      json['temporal_context'] as String,
    ),
    storyTime: json['story_time'] as String?,
    assertion: Assertion.values.byName(json['assertion'] as String),
    attributedToId: json['attributed_to_id'] as String?,
  );

  final String description;
  final List<String> participantIds;
  final String? locationId;

  /// Order in which the section tells the event.
  final int narrativeOrder;
  final TemporalContext temporalContext;
  final String? storyTime;
  final Assertion assertion;
  final String? attributedToId;

  @override
  Iterable<String> get entityIds => [
    ...participantIds,
    ?locationId,
    ?attributedToId,
  ];
}

/// A question the text has raised but not answered.
class Uncertainty extends RecordPayload {
  const Uncertainty({required this.question, required this.relatedEntityIds});

  factory Uncertainty.fromJson(Map<String, dynamic> json) => Uncertainty(
    question: json['question'] as String,
    relatedEntityIds: List<String>.from(json['related_entity_ids'] as List),
  );

  final String question;
  final List<String> relatedEntityIds;

  @override
  Iterable<String> get entityIds => relatedEntityIds;
}

/// A claim that two entities are the same, such as a revealed identity.
class IdentityLink extends RecordPayload {
  const IdentityLink({
    required this.leftEntityId,
    required this.rightEntityId,
    required this.assertion,
    required this.explanation,
  });

  factory IdentityLink.fromJson(Map<String, dynamic> json) => IdentityLink(
    leftEntityId: json['left_entity_id'] as String,
    rightEntityId: json['right_entity_id'] as String,
    assertion: Assertion.values.byName(json['assertion'] as String),
    explanation: json['explanation'] as String,
  );

  final String leftEntityId;
  final String rightEntityId;
  final Assertion assertion;
  final String explanation;

  @override
  Iterable<String> get entityIds => [leftEntityId, rightEntityId];
}

/// One immutable fact and the section where the reader learned it.
class StoryRecord<P extends RecordPayload> {
  const StoryRecord({
    required this.id,
    required this.learnedInSectionId,
    required this.payload,
    required this.evidence,
  });

  factory StoryRecord.fromJson(
    Map<String, dynamic> json,
    P Function(Map<String, dynamic>) parsePayload,
  ) => StoryRecord(
    id: json['id'] as String,
    learnedInSectionId: json['learned_in_section_id'] as String,
    payload: parsePayload(json['payload'] as Map<String, dynamic>),
    evidence: _evidenceList(json),
  );

  final String id;
  final String learnedInSectionId;
  final P payload;
  final List<Evidence> evidence;
}

/// A later section replacing, withdrawing or answering an earlier record.
class RecordTransition {
  const RecordTransition({
    required this.id,
    required this.learnedInSectionId,
    required this.targetRecordId,
    required this.action,
    required this.replacementRecordId,
    required this.resolution,
    required this.reason,
    required this.evidence,
  });

  factory RecordTransition.fromJson(Map<String, dynamic> json) =>
      RecordTransition(
        id: json['id'] as String,
        learnedInSectionId: json['learned_in_section_id'] as String,
        targetRecordId: json['target_record_id'] as String,
        action: TransitionAction.values.byName(json['action'] as String),
        replacementRecordId: json['replacement_record_id'] as String?,
        resolution: json['resolution'] as String?,
        reason: json['reason'] as String,
        evidence: _evidenceList(json),
      );

  final String id;
  final String learnedInSectionId;
  final String targetRecordId;
  final TransitionAction action;
  final String? replacementRecordId;

  /// The answer, for a `resolve` of an uncertainty.
  final String? resolution;
  final String reason;
  final List<Evidence> evidence;
}

List<Evidence> _evidenceList(Map<String, dynamic> json) => [
  for (final item in json['evidence'] as List)
    Evidence.fromJson(item as Map<String, dynamic>),
];

/// Everything the lab has extracted from one book so far.
class StoryModel {
  StoryModel({
    required this.bookTitle,
    required this.revision,
    required this.sections,
    required this.entities,
    required this.names,
    required this.aliases,
    required this.attributes,
    required this.relationships,
    required this.events,
    required this.uncertainties,
    required this.identityLinks,
    required this.transitions,
  });

  /// Parses a `story_model.json` file.
  ///
  /// Throws a [FormatException] if it is not a cumulative (2.0) model.
  factory StoryModel.fromJson(Map<String, dynamic> json) {
    final version = json['schema_version'];
    if (version != '2.0') {
      throw FormatException('Unsupported story model schema: $version');
    }
    final records = json['records'] as Map<String, dynamic>;
    List<StoryRecord<P>> collection<P extends RecordPayload>(
      String name,
      P Function(Map<String, dynamic>) parsePayload,
    ) => [
      for (final record in records[name] as List)
        StoryRecord.fromJson(record as Map<String, dynamic>, parsePayload),
    ];

    return StoryModel(
      bookTitle: (json['book'] as Map<String, dynamic>)['title'] as String,
      revision: (json['revision'] as Map<String, dynamic>)['number'] as int,
      sections: [
        for (final section in json['processed_sections'] as List)
          StorySection.fromJson(section as Map<String, dynamic>),
      ]..sort((a, b) => a.order.compareTo(b.order)),
      entities: {
        for (final entity in json['entities'] as List)
          entity['id'] as String: StoryEntity.fromJson(
            entity as Map<String, dynamic>,
          ),
      },
      names: collection('names', EntityText.fromJson),
      aliases: collection('aliases', EntityText.fromJson),
      attributes: collection('attributes', Attribute.fromJson),
      relationships: collection('relationships', Relationship.fromJson),
      events: collection('events', StoryEvent.fromJson),
      uncertainties: collection('uncertainties', Uncertainty.fromJson),
      identityLinks: collection('identity_links', IdentityLink.fromJson),
      transitions: [
        for (final transition in json['transitions'] as List)
          RecordTransition.fromJson(transition as Map<String, dynamic>),
      ],
    );
  }

  final String bookTitle;
  final int revision;

  /// Processed sections in reading order.
  final List<StorySection> sections;
  final Map<String, StoryEntity> entities;
  final List<StoryRecord<EntityText>> names;
  final List<StoryRecord<EntityText>> aliases;
  final List<StoryRecord<Attribute>> attributes;
  final List<StoryRecord<Relationship>> relationships;
  final List<StoryRecord<StoryEvent>> events;
  final List<StoryRecord<Uncertainty>> uncertainties;
  final List<StoryRecord<IdentityLink>> identityLinks;

  /// Transitions in the order they were committed.
  final List<RecordTransition> transitions;

  /// All records of every collection, oldest first within each collection.
  Iterable<StoryRecord> get allRecords => [
    ...names,
    ...aliases,
    ...attributes,
    ...relationships,
    ...events,
    ...uncertainties,
    ...identityLinks,
  ];

  late final Map<String, StoryRecord> recordsById = {
    for (final record in allRecords) record.id: record,
  };

  late final Map<String, StorySection> _sectionsById = {
    for (final section in sections) section.id: section,
  };

  /// The processed section with [id], or null if it was never processed.
  StorySection? sectionById(String id) => _sectionsById[id];
}
