"""Pure functions: apply a StoryDelta to a cumulative model, and project the `current` index.

Nothing here reads files, calls the API, or judges meaning. `apply_delta` assigns stable IDs
in a fixed order and appends; earlier entities, records, and transitions are copied
unchanged. Whether the result is acceptable is decided by cumulative_validation.py.
"""

from __future__ import annotations

import re
from collections.abc import Iterable, Iterator
from dataclasses import dataclass, field
from typing import Any

from .cumulative_schemas import (
    COLLECTIONS,
    CumulativeStoryModel,
    CurrentIndex,
    IdentityGroup,
    IdentityLinkPayload,
    Record,
    RecordCollections,
    RecordTransition,
    RevisionInfo,
    SectionSource,
    StableEntity,
    StoryDelta,
    UpdateCorrection,
)
from .schemas import _Strict

ENTITY_PREFIXES = {"character": "c", "location": "l", "organization": "g"}
RECORD_PREFIX, RECORD_WIDTH = "f", 6
TRANSITION_PREFIX, TRANSITION_WIDTH = "t", 6

_SCALAR_REF_FIELDS = (
    "entity_id",
    "attributed_to_id",
    "source_id",
    "target_id",
    "location_id",
    "left_entity_id",
    "right_entity_id",
)
_LIST_REF_FIELDS = ("participant_ids", "related_entity_ids")


@dataclass
class IdMap:
    """local ID -> stable ID, as assigned by apply_delta (saved as id_map.json)."""

    entities: dict[str, str] = field(default_factory=dict)
    records: dict[str, str] = field(default_factory=dict)
    transitions: list[str] = field(default_factory=list)

    def to_json(self) -> dict[str, Any]:
        return {
            "entities": self.entities,
            "records": self.records,
            "transitions": [
                {"delta_index": index, "id": tid} for index, tid in enumerate(self.transitions)
            ],
        }


def iter_records(model: CumulativeStoryModel) -> Iterator[tuple[str, int, Record[Any]]]:
    """(collection, index, record) in the fixed collection order."""
    for collection in COLLECTIONS:
        for index, record in enumerate(getattr(model.records, collection)):
            yield collection, index, record


def record_index(model: CumulativeStoryModel) -> dict[str, tuple[str, Record[Any]]]:
    return {record.id: (collection, record) for collection, _, record in iter_records(model)}


def project_current(model: CumulativeStoryModel) -> CurrentIndex:
    """Active records, resolved uncertainties, and explicit identity groups, from history.

    A record is active until a transition targets it. Inactive records stay in the model.
    """
    targets = {t.target_record_id for t in model.transitions}
    active = [record.id for _, _, record in iter_records(model) if record.id not in targets]
    resolved = [t.target_record_id for t in model.transitions if t.action == "resolve"]
    return CurrentIndex(
        active_record_ids=active,
        resolved_uncertainty_ids=resolved,
        identity_groups=identity_groups(model, set(active)),
    )


def identity_groups(model: CumulativeStoryModel, active: set[str]) -> list[IdentityGroup]:
    """Entities joined by active `explicit` identity links of the same kind.

    The canonical ID is the earliest-introduced member (ties broken by ID). Inferred or
    reported links never merge entities.
    """
    entities = {entity.id: entity for entity in model.entities}
    parent: dict[str, str] = {}

    def find(entity_id: str) -> str:
        while parent.setdefault(entity_id, entity_id) != entity_id:
            entity_id = parent[entity_id]
        return entity_id

    links: list[tuple[str, IdentityLinkPayload]] = []
    for record in model.records.identity_links:
        link = record.payload
        left, right = entities.get(link.left_entity_id), entities.get(link.right_entity_id)
        if (
            record.id in active
            and link.assertion == "explicit"
            and left is not None
            and right is not None
            and left.id != right.id
            and left.kind == right.kind
        ):
            links.append((record.id, link))
            parent[find(left.id)] = find(right.id)

    members: dict[str, list[str]] = {}
    for entity_id in list(parent):
        members.setdefault(find(entity_id), []).append(entity_id)
    groups = []
    for ids in members.values():
        if len(ids) < 2:
            continue
        ordered = sorted(ids, key=lambda eid: (entities[eid].introduced_revision, eid))
        group_links = [rid for rid, link in links if link.left_entity_id in ids]
        groups.append(
            IdentityGroup(canonical_id=ordered[0], member_ids=ordered, link_record_ids=group_links)
        )
    return sorted(groups, key=lambda group: group.canonical_id)


def next_number(ids: Iterable[str], prefix: str) -> int:
    """One more than the largest `<prefix><digits>` number in use (1 when none is)."""
    pattern = re.compile(rf"^{re.escape(prefix)}(\d+)$")
    numbers = [int(m.group(1)) for value in ids if (m := pattern.match(value))]
    return max(numbers, default=0) + 1


def format_entity_id(kind: str, number: int) -> str:
    return f"{ENTITY_PREFIXES[kind]}{number:03d}"


def format_record_id(number: int) -> str:
    return f"{RECORD_PREFIX}{number:0{RECORD_WIDTH}d}"


def format_transition_id(number: int) -> str:
    return f"{TRANSITION_PREFIX}{number:0{TRANSITION_WIDTH}d}"


def translate_payload(payload: _Strict, mapping: dict[str, str]) -> _Strict:
    """A copy of the payload with local entity IDs replaced; unknown IDs are kept as given."""
    data = payload.model_dump()
    for name in _SCALAR_REF_FIELDS:
        if data.get(name) in mapping:
            data[name] = mapping[data[name]]
    for name in _LIST_REF_FIELDS:
        if name in data:
            data[name] = [mapping.get(value, value) for value in data[name]]
    return type(payload).model_validate(data)


def apply_delta(
    base: CumulativeStoryModel,
    delta: StoryDelta,
    *,
    section: SectionSource,
    revision: RevisionInfo,
    corrections: list[dict[str, Any]] | None = None,
) -> tuple[CumulativeStoryModel, IdMap]:
    """Append the delta as revision `revision.number`; `base` is not modified.

    `corrections` (path/original/corrected/reason/corrected_by/corrected_at, paths in the
    delta) are manual fixes already applied to `delta`; they are recorded in provenance.

    Local IDs must be unique and well-formed (checked beforehand). IDs continue after the
    largest number in use: entities per kind in `new_entities` order, records over the
    fixed collection order and then array order, transitions in array order.
    """
    base = base.model_copy(deep=True)
    number = revision.number
    id_map = IdMap()

    entities = list(base.entities)
    entity_numbers = {
        kind: next_number([e.id for e in base.entities], prefix)
        for kind, prefix in ENTITY_PREFIXES.items()
    }
    for item in delta.new_entities:
        stable = format_entity_id(item.kind, entity_numbers[item.kind])
        entity_numbers[item.kind] += 1
        id_map.entities[item.local_id] = stable
        entities.append(StableEntity(id=stable, kind=item.kind, introduced_revision=number))

    record_number = next_number([r.id for _, _, r in iter_records(base)], RECORD_PREFIX)
    collections: dict[str, list[Record[Any]]] = {}
    for collection in COLLECTIONS:
        records = list(getattr(base.records, collection))
        for item in getattr(delta.new_records, collection):
            stable = format_record_id(record_number)
            record_number += 1
            id_map.records[item.local_id] = stable
            records.append(
                Record[Any](
                    id=stable,
                    introduced_revision=number,
                    learned_in_section_id=section.section_id,
                    legacy_id=None,
                    payload=translate_payload(item.payload, id_map.entities),
                    evidence=list(item.evidence),
                )
            )
        collections[collection] = records

    transitions = list(base.transitions)
    transition_number = next_number([t.id for t in base.transitions], TRANSITION_PREFIX)
    for item in delta.transitions:
        stable = format_transition_id(transition_number)
        transition_number += 1
        id_map.transitions.append(stable)
        replacement = None
        if item.replacement_local_id is not None:
            replacement = id_map.records.get(item.replacement_local_id, item.replacement_local_id)
        transitions.append(
            RecordTransition(
                id=stable,
                introduced_revision=number,
                learned_in_section_id=section.section_id,
                target_record_id=item.target_record_id,
                action=item.action,
                replacement_record_id=replacement,
                resolution=item.resolution,
                reason=item.reason,
                evidence=list(item.evidence),
            )
        )

    after = base.model_copy(
        update={
            "revision": revision,
            "processed_sections": [*base.processed_sections, section],
            "entities": entities,
            "records": RecordCollections.model_validate(
                {name: [r.model_dump() for r in records] for name, records in collections.items()}
            ),
            "transitions": transitions,
            "provenance": base.provenance.model_copy(
                update={
                    "update_manual_corrections": [
                        *base.provenance.update_manual_corrections,
                        *(
                            UpdateCorrection(
                                revision=number,
                                run_id=revision.source_run_id,
                                record_id=_correction_target(item["path"], delta, id_map),
                                **item,
                            )
                            for item in corrections or []
                        ),
                    ]
                }
            ),
        }
    )
    after.current = project_current(after)
    return CumulativeStoryModel.model_validate(after.model_dump()), id_map


def _correction_target(path: str, delta: StoryDelta, id_map: IdMap) -> str | None:
    """The stable ID of the delta record or transition a correction path points into."""
    if match := re.match(r"^new_records\.(\w+)\[(\d+)\]", path):
        items = getattr(delta.new_records, match.group(1), None)
        index = int(match.group(2))
        if items is not None and index < len(items):
            return id_map.records.get(items[index].local_id)
    if match := re.match(r"^transitions\[(\d+)\]", path):
        index = int(match.group(1))
        if index < len(id_map.transitions):
            return id_map.transitions[index]
    return None


def knowledge_view(model: CumulativeStoryModel) -> dict[str, Any]:
    """The model without per-run metadata (revision ID/time/run), for determinism checks."""
    data = model.model_dump(mode="json")
    data["revision"] = {"number": model.revision.number}
    return data
