"""Merging a StoryDelta: stable IDs, explicit transitions, history kept, bad deltas refused."""

from __future__ import annotations

import copy
from collections.abc import Callable
from pathlib import Path
from typing import Any

import pytest
from conftest import story_chapter

from loremark_story_lab.cumulative_schemas import CumulativeStoryModel, IdentityGroup, RevisionInfo
from loremark_story_lab.cumulative_validation import (
    UpdateValidation,
    check_history,
    validate_cumulative,
    validate_update,
)
from loremark_story_lab.incremental_reporting import display_names, render_story_markdown
from loremark_story_lab.merge import knowledge_view
from loremark_story_lab.migration import import_v1_run
from loremark_story_lab.schemas import ChapterInput
from loremark_story_lab.story_store import section_source, snapshot_relpath

Delta = dict[str, Any]


@pytest.fixture
def base(v1_run: Path) -> tuple[CumulativeStoryModel, dict[str, ChapterInput]]:
    imported = import_v1_run(
        v1_run, epub_override=None, revision_id="rev1", created_at="2026-10-26T00:00:00Z"
    )
    return imported.model, {imported.chapter.section_id: imported.chapter}


@pytest.fixture
def ch2(story_epub: Path) -> ChapterInput:
    return story_chapter(story_epub, "section-003")


def merge(
    base: tuple[CumulativeStoryModel, dict[str, ChapterInput]],
    ch2: ChapterInput,
    delta: Delta,
    revision_id: str = "rev2",
) -> UpdateValidation:
    model, inputs = base
    section, _, _ = section_source(ch2, section_order=3, revision=2)
    revision = RevisionInfo(
        number=2,
        id=revision_id,
        created_at="2026-10-26T01:00:00Z",
        source_run_id="run2",
        parent_snapshot_path=snapshot_relpath(model.revision),
        parent_sha256="0" * 64,
    )
    return validate_update(
        model, delta, chapter=ch2, base_inputs=inputs, section=section, revision=revision
    )


def _active(model: CumulativeStoryModel) -> set[str]:
    return set(model.current.active_record_ids)


def _codes(result: UpdateValidation) -> set[str]:
    return {issue.code for issue in result.errors}


def test_full_delta_merges_with_stable_ids(base, ch2, ch2_delta: Delta) -> None:
    result = merge(base, ch2, ch2_delta)

    assert result.passed, result.errors
    after = result.after
    assert after is not None and result.id_map is not None
    # c001 reappears and is reused; only the two new characters get IDs.
    assert [e.id for e in after.entities] == [
        "c001",
        "c002",
        "c003",
        "c004",
        "l001",
        "g001",
        "c005",
        "c006",
    ]
    assert result.id_map.entities == {"new_entity_001": "c005", "new_entity_002": "c006"}
    assert result.id_map.records == {f"new_record_{n:03d}": f"f{n + 22:06d}" for n in range(1, 14)}
    assert result.id_map.transitions == ["t000001", "t000002", "t000003", "t000004"]
    records = {
        r.id: r for name in type(after.records).model_fields for r in getattr(after.records, name)
    }
    assert records["f000027"].payload.entity_id == "c005"  # forward reference resolved
    assert records["f000033"].payload.participant_ids == ["c005", "c001"]
    assert records["f000034"].payload.related_entity_ids == ["c006"]
    assert all(r.learned_in_section_id == "section-003" for r in after.records.names[6:])
    assert display_names(after)[0]["c005"] == "Mara Quill"
    assert check_history(base[0], after) == []
    assert result.counts["evidence_items"] == result.counts["evidence_matched"] == 17


def test_old_facts_stay_and_absent_characters_are_kept(base, ch2, ch2_delta: Delta) -> None:
    before = copy.deepcopy(base[0])
    after = merge(base, ch2, ch2_delta).after
    assert after is not None

    assert base[0] == before  # the base model is not modified
    active = _active(after)
    # Tomas does not appear in Chapter 2: his name, (wrong) age, and sibling link remain.
    assert {"f000003", "f000011", "f000014"} <= active
    assert "f000009" in active  # Ilse's affiliation is untouched by the rank change
    assert "f000008" not in active and "f000026" in active
    assert "f000008" in _active(base[0])
    for name in type(after.records).model_fields:
        old = getattr(base[0].records, name)
        assert getattr(after.records, name)[: len(old)] == old


def test_relationship_dimension_is_superseded_but_history_keeps_it(base, ch2, ch2_delta) -> None:
    after = merge(base, ch2, ch2_delta).after
    assert after is not None

    def statuses(model: CumulativeStoryModel) -> list[str]:
        return [
            r.payload.description
            for r in model.records.relationships
            if r.id in _active(model) and r.payload.label == "relationship_status"
        ]

    assert statuses(after) == ["Ilse and the Grey Fox are now allies."]
    assert statuses(base[0]) == ["Ilse and the Grey Fox are sworn enemies."]
    assert "f000014" in _active(after)  # sibling_of is another dimension
    # A different label is not a supersede: the old one is retracted, the new one added.
    retract = after.transitions[2]
    assert (retract.action, retract.target_record_id, retract.replacement_record_id) == (
        "retract",
        "f000015",
        None,
    )
    assert "f000015" not in _active(after) and "f000030" in _active(after)


def test_flashback_is_added_without_replacing_the_current_state(base, ch2, ch2_delta) -> None:
    flashback = copy.deepcopy(ch2_delta["new_records"]["relationships"][1])
    flashback["payload"].update(target_id="c002", label="relationship_status")
    delta = {
        "new_entities": [],
        "new_records": {
            **{name: [] for name in ch2_delta["new_records"]},
            "relationships": [flashback],
        },
        "transitions": [],
    }
    result = merge(base, ch2, delta)
    assert result.passed, result.errors
    assert {"f000013", "f000023"} <= _active(result.after)

    delta["transitions"] = [
        {
            "target_record_id": "f000013",
            "action": "supersede",
            "replacement_local_id": flashback["local_id"],
            "resolution": None,
            "reason": "Misreads the flashback as the present.",
            "evidence": flashback["evidence"],
        }
    ]
    assert "temporal_mismatch" in _codes(merge(base, ch2, delta))


def test_identity_reveal_groups_current_state_only(base, ch2, ch2_delta: Delta) -> None:
    after = merge(base, ch2, ch2_delta).after
    assert after is not None
    assert after.current.identity_groups == [
        IdentityGroup(canonical_id="c002", member_ids=["c002", "c004"], link_record_ids=["f000035"])
    ]
    assert base[0].current.identity_groups == []
    # Both entities keep their own IDs and records.
    assert {"f000002", "f000004", "f000012"} <= _active(after)
    assert "＝" in render_story_markdown(after) and "＝" not in render_story_markdown(base[0])

    inferred = copy.deepcopy(ch2_delta)
    inferred["new_records"]["identity_links"][0]["payload"]["assertion"] = "inferred"
    result = merge(base, ch2, inferred)
    assert result.passed and result.after.current.identity_groups == []
    assert "未合并" in render_story_markdown(result.after)

    mixed = copy.deepcopy(ch2_delta)
    mixed["new_records"]["identity_links"][0]["payload"]["right_entity_id"] = "l001"
    assert "identity_kind_mismatch" in _codes(merge(base, ch2, mixed))


def test_answer_resolves_only_the_new_state(base, ch2, ch2_delta: Delta) -> None:
    after = merge(base, ch2, ch2_delta).after
    assert after is not None
    assert after.current.resolved_uncertainty_ids == ["f000021"]
    assert "f000021" not in _active(after) and "f000022" in _active(after)
    assert base[0].current.resolved_uncertainty_ids == []
    assert "f000021" in _active(base[0])


def test_empty_delta_is_valid_but_flagged(base, ch2, ch2_delta: Delta) -> None:
    empty = {
        "new_entities": [],
        "new_records": {name: [] for name in ch2_delta["new_records"]},
        "transitions": [],
    }
    result = merge(base, ch2, empty)
    assert result.passed
    assert "empty_delta" in {w.code for w in result.warnings}
    assert [s.section_id for s in result.after.processed_sections] == ["section-002", "section-003"]


def test_event_supersede_is_flagged_for_review(base, ch2, ch2_delta: Delta) -> None:
    ch2_delta["transitions"].append(
        {
            "target_record_id": "f000020",
            "action": "supersede",
            "replacement_local_id": "new_record_010",
            "resolution": None,
            "reason": "The night crossing was the Grey Fox's run.",
            "evidence": [
                {"section_id": "section-003", "paragraph_id": "p0004", "quote": "he was Petr Lask"}
            ],
        }
    )
    result = merge(base, ch2, ch2_delta)
    assert result.passed
    assert "semantic_supersede_review" in {w.code for w in result.warnings}


def _set(path: str, value: Any) -> Callable[[Delta], None]:
    def apply(delta: Delta) -> None:
        *parents, last = path.split(".")
        target: Any = delta
        for part in parents:
            target = target[int(part)] if part.isdigit() else target[part]
        target[int(last) if last.isdigit() else last] = value

    return apply


def _evidence(section: str, paragraph: str, quote: str) -> list[dict[str, str]]:
    return [{"section_id": section, "paragraph_id": paragraph, "quote": quote}]


def _duplicate_target(delta: Delta) -> None:
    delta["transitions"].append(
        {**delta["transitions"][0], "replacement_local_id": "new_record_003"}
    )


@pytest.mark.parametrize(
    ("mutate", "code", "path"),
    [
        (
            _set(
                "new_records.names.0.evidence",
                _evidence("section-002", "p0002", "Lieutenant Ilse Varga"),
            ),
            "evidence_outside_section",
            "new_records.names[0].evidence[0]",
        ),
        (
            _set(
                "new_records.names.0.evidence",
                _evidence("section-003", "p0006", "Mara Quill the engineer"),
            ),
            "quote_not_found",
            "new_records.names[0].evidence[0]",
        ),
        (
            _set("new_records.events.0.evidence", _evidence("section-003", "p0001", "THE SIGNAL")),
            "quote_not_found",
            "new_records.events[0].evidence[0]",
        ),
        (
            _set("new_records.events.0.evidence", []),
            "missing_evidence",
            "new_records.events[0].evidence",
        ),
        (
            _set("transitions.0.target_record_id", "f999999"),
            "dangling_reference",
            "transitions[0].target_record_id",
        ),
        (
            _set("transitions.0.target_record_id", "new_record_001"),
            "target_is_new",
            "transitions[0].target_record_id",
        ),
        (_duplicate_target, "target_already_transitioned", "transitions[4].target_record_id"),
        (
            _set("transitions.0.replacement_local_id", "new_record_006"),
            "supersede_kind_mismatch",
            "transitions[0]",
        ),
        (
            _set("transitions.0.replacement_local_id", "new_record_005"),
            "supersede_subject_mismatch",
            "transitions[0]",
        ),
        (
            _set("transitions.0.replacement_local_id", "new_record_099"),
            "unknown_replacement",
            "transitions[0].replacement_local_id",
        ),
        (
            _set("transitions.3.target_record_id", "f000009"),
            "resolve_non_uncertainty",
            "transitions[3].target_record_id",
        ),
        (_set("transitions.3.resolution", " "), "missing_resolution", "transitions[3].resolution"),
        (_set("transitions.2.evidence", []), "missing_evidence", "transitions[2].evidence"),
        (
            _set("new_records.aliases.0.local_id", "new_record_001"),
            "duplicate_local_id",
            "new_records.aliases[0].local_id",
        ),
        (_set("new_entities.0.local_id", "c099"), "local_id_format", "new_entities[0].local_id"),
        (
            _set("new_records.attributes.1.payload.entity_id", "new_entity_009"),
            "dangling_reference",
            "new_records.attributes[1].payload.entity_id",
        ),
        (
            _set("new_records.events.0.payload.location_id", "c001"),
            "wrong_reference_kind",
            "new_records.events[0].payload.location_id",
        ),
        (
            _set("new_records.events.1.payload.narrative_order", 1),
            "narrative_order",
            "new_records.events[1].payload.narrative_order",
        ),
        (lambda d: d["new_records"]["names"].pop(1), "entity_without_name", "new_entities[1]"),
    ],
    ids=[
        "old-section-evidence",
        "fabricated-quote",
        "other-section-p0001",
        "no-evidence",
        "unknown-target",
        "new-record-target",
        "target-twice",
        "replacement-other-kind",
        "replacement-other-label",
        "unknown-replacement",
        "resolve-attribute",
        "resolve-without-answer",
        "transition-without-evidence",
        "duplicate-local-id",
        "local-id-format",
        "dangling-local-entity",
        "wrong-kind",
        "narrative-order",
        "entity-without-name",
    ],
)
def test_invalid_deltas_are_refused_with_delta_paths(
    base, ch2, ch2_delta: Delta, mutate: Callable[[Delta], None], code: str, path: str
) -> None:
    mutate(ch2_delta)
    result = merge(base, ch2, ch2_delta)

    assert not result.passed
    matching = [issue for issue in result.errors if issue.code == code]
    assert matching, result.errors
    assert path in {issue.path for issue in matching}


def test_quote_from_the_other_chapters_p0001_points_there(base, ch2, ch2_delta: Delta) -> None:
    _set("new_records.events.0.evidence", _evidence("section-003", "p0001", "THE SIGNAL"))(
        ch2_delta
    )
    error = next(i for i in merge(base, ch2, ch2_delta).errors if i.code == "quote_not_found")
    assert "occurs verbatim in section-002:p0001 (not accepted)" in error.message

    _set("new_records.events.0.evidence", _evidence("section-003", "p0001", "CHAPTER 2"))(ch2_delta)
    assert merge(base, ch2, ch2_delta).passed


def test_merge_is_deterministic(base, ch2, ch2_delta: Delta) -> None:
    first = merge(base, ch2, copy.deepcopy(ch2_delta))
    second = merge(base, ch2, copy.deepcopy(ch2_delta))
    other_revision = merge(base, ch2, copy.deepcopy(ch2_delta), revision_id="different")

    assert first.after == second.after
    assert first.id_map == second.id_map == other_revision.id_map
    assert knowledge_view(first.after) == knowledge_view(other_revision.after)
    assert first.after.revision.id != other_revision.after.revision.id


def test_tampered_history_and_index_are_detected(base, ch2, ch2_delta: Delta) -> None:
    after = merge(base, ch2, ch2_delta).after
    assert after is not None
    inputs = {**base[1], ch2.section_id: ch2}

    edited = after.model_copy(deep=True)
    edited.records.attributes[0].payload.value = "Major"
    assert {i.code for i in check_history(base[0], edited)} == {"history_changed"}

    dropped = after.model_copy(deep=True)
    dropped.records.events.pop(0)
    assert "history_changed" in {i.code for i in check_history(base[0], dropped)}

    index = after.model_copy(deep=True)
    index.current.active_record_ids.append("f000008")
    assert "current_mismatch" in {i.code for i in validate_cumulative(index, inputs).errors}

    missing = validate_cumulative(after, base[1])
    assert "missing_input" in {i.code for i in missing.errors}
