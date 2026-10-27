"""Pydantic models for the cumulative (v2) story model and the StoryDelta the LLM returns.

Knowledge is stored as immutable records. A later section never edits an earlier record; it
adds new records and explicit transitions (supersede / retract / resolve). `current` is an
index computed by code from records and transitions, never taken from the model.

As in schemas.py, these models only describe structure. Cross-record rules live in
cumulative_validation.py.
"""

from __future__ import annotations

from typing import Generic, Literal, TypeVar

from .schemas import Assertion, TemporalContext, _Strict

CUMULATIVE_SCHEMA_VERSION = "2.0"

EntityKind = Literal["character", "location", "organization"]
TransitionAction = Literal["supersede", "retract", "resolve"]

# Fixed order of the record collections: IDs are assigned and records listed in this order.
COLLECTIONS = (
    "names",
    "aliases",
    "attributes",
    "relationships",
    "events",
    "uncertainties",
    "identity_links",
)


class EvidenceV2(_Strict):
    section_id: str
    paragraph_id: str
    quote: str


# --- record payloads (the facts themselves) ---------------------------------------


class EntityTextPayload(_Strict):
    """A name or an alias of one entity."""

    entity_id: str
    text: str


class AttributePayload(_Strict):
    entity_id: str
    label: str
    value: str
    assertion: Assertion
    attributed_to_id: str | None


class RelationshipPayload(_Strict):
    source_id: str
    target_id: str
    label: str
    description: str
    assertion: Assertion
    attributed_to_id: str | None
    temporal_context: TemporalContext


class EventPayload(_Strict):
    description: str
    participant_ids: list[str]
    location_id: str | None
    narrative_order: int
    temporal_context: TemporalContext
    story_time: str | None
    assertion: Assertion
    attributed_to_id: str | None


class UncertaintyPayload(_Strict):
    question: str
    related_entity_ids: list[str]


class IdentityLinkPayload(_Strict):
    left_entity_id: str
    right_entity_id: str
    assertion: Assertion
    explanation: str


Payload = TypeVar("Payload", bound=_Strict)

PAYLOAD_TYPES: dict[str, type[_Strict]] = {
    "names": EntityTextPayload,
    "aliases": EntityTextPayload,
    "attributes": AttributePayload,
    "relationships": RelationshipPayload,
    "events": EventPayload,
    "uncertainties": UncertaintyPayload,
    "identity_links": IdentityLinkPayload,
}


# --- cumulative model (code-generated envelope, immutable records) ----------------------


class Record(_Strict, Generic[Payload]):
    id: str
    introduced_revision: int
    learned_in_section_id: str
    legacy_id: str | None
    payload: Payload
    evidence: list[EvidenceV2]


class RecordCollections(_Strict):
    names: list[Record[EntityTextPayload]]
    aliases: list[Record[EntityTextPayload]]
    attributes: list[Record[AttributePayload]]
    relationships: list[Record[RelationshipPayload]]
    events: list[Record[EventPayload]]
    uncertainties: list[Record[UncertaintyPayload]]
    identity_links: list[Record[IdentityLinkPayload]]


class RecordTransition(_Strict):
    id: str
    introduced_revision: int
    learned_in_section_id: str
    target_record_id: str
    action: TransitionAction
    replacement_record_id: str | None
    resolution: str | None
    reason: str
    evidence: list[EvidenceV2]


class StableEntity(_Strict):
    id: str
    kind: EntityKind
    introduced_revision: int


class SectionSource(_Strict):
    section_id: str
    section_order: int
    chapter_number: int | None
    title: str
    href: str
    fragment: str | None
    text_sha256: str
    extraction_version: str
    paragraph_count: int
    input_relative_path: str
    input_file_sha256: str
    introduced_revision: int


class BookRef(_Strict):
    title: str
    epub_sha256: str


class RevisionInfo(_Strict):
    number: int
    id: str
    created_at: str
    source_run_id: str
    parent_snapshot_path: str | None
    parent_sha256: str | None


class Coverage(_Strict):
    start_section_id: str
    # Sections before the start that were never processed (a prologue, front matter, ...).
    omitted_prefix_section_ids: list[str]


class IdentityGroup(_Strict):
    canonical_id: str
    member_ids: list[str]
    link_record_ids: list[str]


class CurrentIndex(_Strict):
    active_record_ids: list[str]
    resolved_uncertainty_ids: list[str]
    identity_groups: list[IdentityGroup]


class ImportedCorrection(_Strict):
    """A manual correction recorded in the imported v1 run (`run.json.manual_corrections`)."""

    path: str
    original: str
    corrected: str
    reason: str
    corrected_by: str
    corrected_at: str


class UpdateCorrection(_Strict):
    """A manual correction of an update's delta, made before that revision was committed.

    Only evidence locations (paragraph ID or quote) can be corrected, never the facts.
    """

    revision: int
    run_id: str
    path: str  # in the delta, e.g. new_records.names[6].evidence[0].paragraph_id
    record_id: str | None  # the stable record or transition the path belongs to
    original: str
    corrected: str
    reason: str
    corrected_by: str
    corrected_at: str


class Provenance(_Strict):
    initial_run_id: str
    imported_manual_corrections: list[ImportedCorrection]
    migration_version: str
    # Append-only; absent in stores written before corrections of updates existed.
    update_manual_corrections: list[UpdateCorrection] = []


class CumulativeStoryModel(_Strict):
    schema_version: Literal["2.0"] = CUMULATIVE_SCHEMA_VERSION
    scope: Literal["cumulative"] = "cumulative"
    book: BookRef
    revision: RevisionInfo
    processed_sections: list[SectionSource]
    coverage: Coverage
    entities: list[StableEntity]
    records: RecordCollections
    transitions: list[RecordTransition]
    current: CurrentIndex
    provenance: Provenance


# --- LLM output: what one new section adds or changes -------------------------------------


class DeltaEntity(_Strict):
    local_id: str
    kind: EntityKind


class DeltaRecord(_Strict, Generic[Payload]):
    local_id: str
    payload: Payload
    evidence: list[EvidenceV2]


class DeltaRecordCollections(_Strict):
    names: list[DeltaRecord[EntityTextPayload]]
    aliases: list[DeltaRecord[EntityTextPayload]]
    attributes: list[DeltaRecord[AttributePayload]]
    relationships: list[DeltaRecord[RelationshipPayload]]
    events: list[DeltaRecord[EventPayload]]
    uncertainties: list[DeltaRecord[UncertaintyPayload]]
    identity_links: list[DeltaRecord[IdentityLinkPayload]]


class DeltaTransition(_Strict):
    target_record_id: str
    action: TransitionAction
    replacement_local_id: str | None
    resolution: str | None
    reason: str
    evidence: list[EvidenceV2]


class StoryDelta(_Strict):
    new_entities: list[DeltaEntity]
    new_records: DeltaRecordCollections
    transitions: list[DeltaTransition]


# --- helpers ------------------------------------------------------------------------------


def entity_refs(collection: str, payload: _Strict) -> list[tuple[str, str]]:
    """(field path, entity ID) for every entity reference in a payload."""
    if isinstance(payload, EntityTextPayload):
        return [("entity_id", payload.entity_id)]
    if isinstance(payload, AttributePayload):
        refs = [("entity_id", payload.entity_id)]
        if payload.attributed_to_id is not None:
            refs.append(("attributed_to_id", payload.attributed_to_id))
        return refs
    if isinstance(payload, RelationshipPayload):
        refs = [("source_id", payload.source_id), ("target_id", payload.target_id)]
        if payload.attributed_to_id is not None:
            refs.append(("attributed_to_id", payload.attributed_to_id))
        return refs
    if isinstance(payload, EventPayload):
        refs = [(f"participant_ids[{i}]", pid) for i, pid in enumerate(payload.participant_ids)]
        if payload.location_id is not None:
            refs.append(("location_id", payload.location_id))
        if payload.attributed_to_id is not None:
            refs.append(("attributed_to_id", payload.attributed_to_id))
        return refs
    if isinstance(payload, UncertaintyPayload):
        return [
            (f"related_entity_ids[{i}]", ref) for i, ref in enumerate(payload.related_entity_ids)
        ]
    if isinstance(payload, IdentityLinkPayload):
        return [
            ("left_entity_id", payload.left_entity_id),
            ("right_entity_id", payload.right_entity_id),
        ]
    raise TypeError(f"Unknown payload type for {collection}: {type(payload).__name__}")
