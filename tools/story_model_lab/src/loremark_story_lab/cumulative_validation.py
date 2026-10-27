"""Deterministic checks of a cumulative (v2) model, of one update, and of history.

As in validation.py, a matched quote only proves the text exists in that paragraph, and
nothing here edits or drops records. Code cannot tell whether two events or questions mean
the same thing, so such replacements are flagged for manual review instead of judged.
"""

from __future__ import annotations

import re
from collections.abc import Mapping
from dataclasses import asdict, dataclass, field
from typing import Any

from pydantic import ValidationError

from .cumulative_schemas import (
    COLLECTIONS,
    AttributePayload,
    CumulativeStoryModel,
    EntityTextPayload,
    EventPayload,
    EvidenceV2,
    IdentityLinkPayload,
    Record,
    RelationshipPayload,
    RevisionInfo,
    SectionSource,
    StoryDelta,
    UncertaintyPayload,
)
from .epub import text_sha256
from .merge import IdMap, apply_delta, iter_records, project_current
from .schemas import ChapterInput
from .validation import MAX_QUOTE_CHARS, Issue, error_path, find_spans, fold_text

VALIDATOR_VERSION = "2.0"

ALL_KINDS = {"character", "location", "organization"}
SPEAKER_KINDS = {"character", "organization"}
ENTITY_ID_PATTERNS = {
    "character": re.compile(r"^c\d{3,}$"),
    "location": re.compile(r"^l\d{3,}$"),
    "organization": re.compile(r"^g\d{3,}$"),
}
RECORD_ID_PATTERN = re.compile(r"^f\d{6,}$")
TRANSITION_ID_PATTERN = re.compile(r"^t\d{6,}$")
LOCAL_ENTITY_PATTERN = re.compile(r"^new_entity_\d{3,}$")
LOCAL_RECORD_PATTERN = re.compile(r"^new_record_\d{3,}$")

SUPPORT_NOTE = (
    "A matched quote only shows the text exists in that paragraph; "
    "it does not show that the quote supports the claim."
)


@dataclass
class EvidenceCheckV2:
    path: str
    record_id: str | None
    section_id: str
    paragraph_id: str
    quote: str
    matched: bool
    spans: list[list[int]] = field(default_factory=list)


@dataclass
class CumulativeReport:
    issues: list[Issue]
    evidence: list[EvidenceCheckV2]
    counts: dict[str, int]

    @property
    def errors(self) -> list[Issue]:
        return [i for i in self.issues if i.severity == "error"]

    @property
    def warnings(self) -> list[Issue]:
        return [i for i in self.issues if i.severity == "warning"]

    @property
    def passed(self) -> bool:
        return not self.errors


def validate_cumulative(
    model: CumulativeStoryModel,
    inputs: Mapping[str, ChapterInput],
    *,
    paths: Mapping[str, str] | None = None,
    focus_revision: int | None = None,
) -> CumulativeReport:
    """Check a whole cumulative model against the inputs of its processed sections.

    `paths` renames items in messages (an update reports `new_records.names[0]` instead of
    `records.names[57]`). With `focus_revision`, per-record warnings are only reported for
    items of that revision; errors are always reported.
    """
    return _Checker(model, inputs, paths or {}, focus_revision).run()


# --- whole-model checks ------------------------------------------------------------------


class _Checker:
    def __init__(
        self,
        model: CumulativeStoryModel,
        inputs: Mapping[str, ChapterInput],
        paths: Mapping[str, str],
        focus: int | None,
    ) -> None:
        self.model = model
        self.inputs = inputs
        self.paths = paths
        self.focus = focus
        self.revision = model.revision.number
        self.issues: list[Issue] = []
        self.evidence: list[EvidenceCheckV2] = []
        self.paragraphs: dict[str, dict[str, str]] = {}
        self.section_revisions: dict[str, int] = {}
        self.entities = {}
        self.records: dict[str, tuple[str, Record[Any]]] = {}
        self.active: set[str] = set()

    def run(self) -> CumulativeReport:
        self._check_revision()
        self._check_sections()
        self._check_entities()
        self._check_records()
        self._check_transitions()
        expected = project_current(self.model)
        self.active = set(expected.active_record_ids)
        self._check_current(expected)
        self._check_names()
        self._check_identity_conflicts(expected)
        return CumulativeReport(self.issues, self.evidence, self._counts())

    # --- helpers ----------------------------------------------------------------------

    def _error(self, code: str, path: str, message: str, record_id: str | None = None) -> None:
        self.issues.append(Issue("error", code, path, message, record_id))

    def _warn(
        self,
        code: str,
        path: str,
        message: str,
        record_id: str | None = None,
        revision: int | None = None,
    ) -> None:
        """A warning; per-record ones (with `revision`) only for the focused revision."""
        if revision is None or self.focus is None or revision == self.focus:
            self.issues.append(Issue("warning", code, path, message, record_id))

    def _nonempty(self, path: str, value: str, record_id: str | None) -> None:
        if not value.strip():
            self._error("empty_text", path, "Text is empty", record_id)

    def _check_origin(self, path: str, item_id: str, revision: int, section_id: str) -> None:
        if not 1 <= revision <= self.revision:
            self._error(
                "revision_range",
                f"{path}.introduced_revision",
                f"{revision} is outside 1..{self.revision}",
                item_id,
            )
        section_revision = self.section_revisions.get(section_id)
        if section_revision is None:
            self._error(
                "unknown_section",
                f"{path}.learned_in_section_id",
                f"{section_id!r} is not a processed section",
                item_id,
            )
        elif section_revision != revision:
            self._error(
                "section_revision_mismatch",
                f"{path}.learned_in_section_id",
                f"{section_id} was processed in revision {section_revision}, not {revision}",
                item_id,
            )

    def _check_ref(
        self, path: str, ref: str, allowed: set[str], record_id: str, revision: int
    ) -> None:
        entity = self.entities.get(ref)
        if entity is None:
            self._error("dangling_reference", path, f"{ref!r} does not exist", record_id)
        elif entity.kind not in allowed:
            expected = " or ".join(sorted(allowed))
            self._error(
                "wrong_reference_kind",
                path,
                f"{ref!r} is a {entity.kind}, expected {expected}",
                record_id,
            )
        elif entity.introduced_revision > revision:
            self._error(
                "reference_from_future",
                path,
                f"{ref!r} is introduced in revision {entity.introduced_revision}, "
                f"after this item (revision {revision})",
                record_id,
            )

    def _check_assertion(
        self,
        path: str,
        assertion: str,
        attributed_to_id: str | None,
        record_id: str,
        revision: int,
    ) -> None:
        if attributed_to_id is None:
            return
        self._check_ref(
            f"{path}.attributed_to_id", attributed_to_id, SPEAKER_KINDS, record_id, revision
        )
        if assertion != "reported":
            self._warn(
                "attribution_without_report",
                f"{path}.attributed_to_id",
                f"attributed_to_id is set but assertion is {assertion!r}",
                record_id,
                revision,
            )

    def _check_evidence(
        self,
        path: str,
        items: list[EvidenceV2],
        record_id: str,
        section_id: str,
    ) -> None:
        if not items:
            self._error("missing_evidence", f"{path}.evidence", "Evidence list is empty", record_id)
            return
        for index, item in enumerate(items):
            item_path = f"{path}.evidence[{index}]"
            paragraphs = self.paragraphs.get(item.section_id)
            text = paragraphs.get(item.paragraph_id) if paragraphs is not None else None
            spans: list[list[int]] = []
            if item.section_id != section_id:
                self._error(
                    "evidence_outside_section",
                    item_path,
                    f"Evidence cites {item.section_id!r}; it must come from {section_id}, "
                    "the section this item was learned in",
                    record_id,
                )
            elif paragraphs is None:
                self._error(
                    "unknown_section",
                    item_path,
                    f"No input is available for {item.section_id!r}",
                    record_id,
                )
            elif text is None:
                self._error(
                    "unknown_paragraph",
                    item_path,
                    f"Paragraph {item.paragraph_id!r} is not part of {item.section_id}",
                    record_id,
                )
            elif not item.quote.strip():
                self._error("empty_quote", item_path, "Quote is empty", record_id)
            elif len(item.quote) > MAX_QUOTE_CHARS:
                self._error(
                    "quote_too_long",
                    item_path,
                    f"Quote has {len(item.quote)} characters (limit {MAX_QUOTE_CHARS})",
                    record_id,
                )
            else:
                spans = find_spans(text, item.quote)
                if not spans:
                    self._error("quote_not_found", item_path, self._not_found(item), record_id)
            self.evidence.append(
                EvidenceCheckV2(
                    path=item_path,
                    record_id=record_id,
                    section_id=item.section_id,
                    paragraph_id=item.paragraph_id,
                    quote=item.quote,
                    matched=bool(spans),
                    spans=spans,
                )
            )

    def _not_found(self, item: EvidenceV2) -> str:
        message = f"Quote is not an exact substring of {item.section_id}:{item.paragraph_id}"
        elsewhere = [
            f"{sid}:{pid}"
            for sid, paragraphs in self.paragraphs.items()
            for pid, text in paragraphs.items()
            if item.quote in text
        ]
        if elsewhere:
            return f"{message}; it occurs verbatim in {', '.join(elsewhere[:5])} (not accepted)"
        folded = fold_text(item.quote)
        if folded and folded in fold_text(self.paragraphs[item.section_id][item.paragraph_id]):
            return f"{message}; it matches only after folding quotes/dashes/case/spaces"
        return message

    # --- sections, entities, records ------------------------------------------------------

    def _check_revision(self) -> None:
        revision = self.model.revision
        if revision.number < 1:
            self._error("revision_range", "revision.number", f"{revision.number} is not positive")
        if not revision.id.strip():
            self._error("empty_id", "revision.id", "Revision ID is empty")
        has_parent = bool(revision.parent_snapshot_path) or bool(revision.parent_sha256)
        if revision.number == 1 and has_parent:
            self._error("revision_parent", "revision", "Revision 1 must not have a parent")
        if revision.number > 1 and not (revision.parent_snapshot_path and revision.parent_sha256):
            self._error(
                "revision_parent",
                "revision",
                f"Revision {revision.number} needs a parent snapshot path and hash",
            )

    def _check_sections(self) -> None:
        sections = self.model.processed_sections
        if len(sections) != self.revision:
            self._error(
                "section_count",
                "processed_sections",
                f"Revision {self.revision} must have exactly {self.revision} processed sections "
                f"(one per revision), found {len(sections)}",
            )
        previous_order = 0
        for index, section in enumerate(sections):
            path = f"processed_sections[{index}]"
            if section.section_id in self.section_revisions:
                self._error("duplicate_section", path, f"{section.section_id} is listed twice")
            self.section_revisions[section.section_id] = section.introduced_revision
            if section.introduced_revision != index + 1:
                self._error(
                    "section_revision_mismatch",
                    f"{path}.introduced_revision",
                    f"Section {index + 1} must be introduced in revision {index + 1}",
                )
            if section.section_order <= previous_order:
                self._error(
                    "section_order",
                    f"{path}.section_order",
                    "Processed sections must be in increasing reading order",
                )
            previous_order = section.section_order
            self._check_input(path, section)

        coverage = self.model.coverage
        if sections and coverage.start_section_id != sections[0].section_id:
            self._error(
                "coverage",
                "coverage.start_section_id",
                f"{coverage.start_section_id!r} is not the first processed section",
            )
        overlap = set(coverage.omitted_prefix_section_ids) & set(self.section_revisions)
        if overlap:
            self._error(
                "coverage",
                "coverage.omitted_prefix_section_ids",
                f"{', '.join(sorted(overlap))} are listed as omitted but were processed",
            )

    def _check_input(self, path: str, section: SectionSource) -> None:
        chapter = self.inputs.get(section.section_id)
        if chapter is None:
            self._error(
                "missing_input", path, f"No saved input for {section.section_id}; cannot verify"
            )
            return
        expected = {
            "section_id": section.section_id,
            "book_sha256": self.model.book.epub_sha256,
            "text_sha256": section.text_sha256,
            "paragraph_count": section.paragraph_count,
            "extraction_version": section.extraction_version,
            "source_href": section.href,
            "source_fragment": section.fragment,
            "title": section.title,
            "chapter_number": section.chapter_number,
        }
        actual = chapter.model_dump()
        actual["paragraph_count"] = len(chapter.paragraphs)
        mismatched = [name for name, value in expected.items() if actual[name] != value]
        if text_sha256(chapter.paragraphs) != section.text_sha256:
            mismatched.append("paragraph text")
        if mismatched:
            self._error(
                "input_mismatch",
                path,
                f"Saved input of {section.section_id} does not match: {', '.join(mismatched)}",
            )
            return
        self.paragraphs[section.section_id] = {p.id: p.text for p in chapter.paragraphs}

    def _check_entities(self) -> None:
        for index, entity in enumerate(self.model.entities):
            path = self.paths.get(entity.id) or f"entities[{index}]"
            if entity.id in self.entities:
                self._error("duplicate_id", path, f"Duplicate entity ID {entity.id!r}", entity.id)
                continue
            self.entities[entity.id] = entity
            if not ENTITY_ID_PATTERNS[entity.kind].match(entity.id):
                self._warn(
                    "id_format",
                    path,
                    f"{entity.id!r} does not follow the {entity.kind} ID pattern",
                    entity.id,
                    entity.introduced_revision,
                )
            if not 1 <= entity.introduced_revision <= self.revision:
                self._error(
                    "revision_range",
                    f"{path}.introduced_revision",
                    f"{entity.introduced_revision} is outside 1..{self.revision}",
                    entity.id,
                )

    def _check_records(self) -> None:
        events_by_section: dict[str, list[tuple[str, Record[Any]]]] = {}
        for collection, index, record in iter_records(self.model):
            path = self.paths.get(record.id) or f"records.{collection}[{index}]"
            if record.id in self.records:
                self._error("duplicate_id", path, f"Duplicate record ID {record.id!r}", record.id)
                continue
            self.records[record.id] = (collection, record)
            if not RECORD_ID_PATTERN.match(record.id):
                self._error("id_format", path, f"{record.id!r} is not a record ID", record.id)
            self._check_origin(
                path, record.id, record.introduced_revision, record.learned_in_section_id
            )
            self._check_payload(f"{path}.payload", record)
            self._check_evidence(path, record.evidence, record.id, record.learned_in_section_id)
            if collection == "events":
                events_by_section.setdefault(record.learned_in_section_id, []).append(
                    (path, record)
                )
        for events in events_by_section.values():
            self._check_event_order(events)
        if self.focus is not None:
            self._check_duplicate_claims()

    def _check_payload(self, path: str, record: Record[Any]) -> None:
        rid, rev, payload = record.id, record.introduced_revision, record.payload
        if isinstance(payload, EntityTextPayload):
            self._check_ref(f"{path}.entity_id", payload.entity_id, ALL_KINDS, rid, rev)
            self._nonempty(f"{path}.text", payload.text, rid)
        elif isinstance(payload, AttributePayload):
            self._check_ref(f"{path}.entity_id", payload.entity_id, ALL_KINDS, rid, rev)
            self._nonempty(f"{path}.label", payload.label, rid)
            self._nonempty(f"{path}.value", payload.value, rid)
            self._check_assertion(path, payload.assertion, payload.attributed_to_id, rid, rev)
        elif isinstance(payload, RelationshipPayload):
            self._check_ref(f"{path}.source_id", payload.source_id, ALL_KINDS, rid, rev)
            self._check_ref(f"{path}.target_id", payload.target_id, ALL_KINDS, rid, rev)
            if payload.source_id == payload.target_id:
                self._warn("self_relationship", path, "Source and target are the same", rid, rev)
            self._nonempty(f"{path}.label", payload.label, rid)
            self._nonempty(f"{path}.description", payload.description, rid)
            self._check_assertion(path, payload.assertion, payload.attributed_to_id, rid, rev)
        elif isinstance(payload, EventPayload):
            self._nonempty(f"{path}.description", payload.description, rid)
            for index, participant in enumerate(payload.participant_ids):
                self._check_ref(
                    f"{path}.participant_ids[{index}]", participant, SPEAKER_KINDS, rid, rev
                )
            if len(set(payload.participant_ids)) != len(payload.participant_ids):
                self._warn("duplicate_participant", path, "A participant is listed twice", rid, rev)
            if payload.location_id is not None:
                self._check_ref(f"{path}.location_id", payload.location_id, {"location"}, rid, rev)
            self._check_assertion(path, payload.assertion, payload.attributed_to_id, rid, rev)
        elif isinstance(payload, UncertaintyPayload):
            self._nonempty(f"{path}.question", payload.question, rid)
            for index, ref in enumerate(payload.related_entity_ids):
                self._check_ref(f"{path}.related_entity_ids[{index}]", ref, ALL_KINDS, rid, rev)
        elif isinstance(payload, IdentityLinkPayload):
            left, right = payload.left_entity_id, payload.right_entity_id
            self._check_ref(f"{path}.left_entity_id", left, ALL_KINDS, rid, rev)
            self._check_ref(f"{path}.right_entity_id", right, ALL_KINDS, rid, rev)
            self._nonempty(f"{path}.explanation", payload.explanation, rid)
            if left == right:
                self._error("self_identity", path, "An entity cannot be linked to itself", rid)
            elif left in self.entities and right in self.entities:
                kinds = (self.entities[left].kind, self.entities[right].kind)
                if kinds[0] != kinds[1]:
                    self._error(
                        "identity_kind_mismatch",
                        path,
                        f"Cannot link a {kinds[0]} ({left}) and a {kinds[1]} ({right})",
                        rid,
                    )

    def _check_event_order(self, events: list[tuple[str, Record[Any]]]) -> None:
        """narrative_order counts within the section the event was learned in: 1, 2, 3, ..."""
        previous = 0
        seen: set[int] = set()
        for path, record in events:
            order = record.payload.narrative_order
            order_path = f"{path}.payload.narrative_order"
            if order < 1:
                self._error("narrative_order", order_path, f"{order} is not positive", record.id)
            elif order in seen:
                self._error("narrative_order", order_path, f"{order} is repeated", record.id)
            elif order < previous:
                self._error(
                    "narrative_order",
                    order_path,
                    f"{order} comes after {previous}; events must be listed in order",
                    record.id,
                )
            elif order != previous + 1:
                self._warn(
                    "narrative_order_gap",
                    order_path,
                    f"Expected {previous + 1}, got {order}",
                    record.id,
                    record.introduced_revision,
                )
            seen.add(order)
            previous = max(previous, order)

    def _check_duplicate_claims(self) -> None:
        """Flag (never merge) new records whose payload repeats an earlier record exactly."""
        earlier: dict[tuple[str, str], str] = {}
        for collection, _, record in iter_records(self.model):
            key = (collection, record.payload.model_dump_json())
            if record.introduced_revision != self.focus:
                earlier.setdefault(key, record.id)
            elif key in earlier:
                self._warn(
                    "duplicate_claim",
                    self.paths.get(record.id) or record.id,
                    f"Repeats {earlier[key]} exactly; kept as a separate record",
                    record.id,
                    record.introduced_revision,
                )

    # --- transitions and the derived index ------------------------------------------------

    def _check_transitions(self) -> None:
        targets: dict[str, str] = {}
        replacements: set[str] = set()
        seen_ids: set[str] = set()
        for index, item in enumerate(self.model.transitions):
            path = self.paths.get(item.id) or f"transitions[{index}]"
            tid = item.id
            if tid in seen_ids or tid in self.records:
                self._error("duplicate_id", path, f"Duplicate transition ID {tid!r}", tid)
            seen_ids.add(tid)
            if not TRANSITION_ID_PATTERN.match(tid):
                self._error("id_format", path, f"{tid!r} is not a transition ID", tid)
            self._check_origin(path, tid, item.introduced_revision, item.learned_in_section_id)
            self._nonempty(f"{path}.reason", item.reason, tid)

            target = self.records.get(item.target_record_id)
            target_path = f"{path}.target_record_id"
            if target is None:
                self._error(
                    "dangling_reference",
                    target_path,
                    f"Target {item.target_record_id!r} does not exist",
                    tid,
                )
            else:
                if target[1].introduced_revision >= item.introduced_revision:
                    self._error(
                        "target_not_prior",
                        target_path,
                        f"{item.target_record_id} is from revision "
                        f"{target[1].introduced_revision}; only records of earlier revisions "
                        "can be changed",
                        tid,
                    )
                if item.target_record_id in targets:
                    self._error(
                        "target_already_transitioned",
                        target_path,
                        f"{item.target_record_id} is no longer active: "
                        f"{targets[item.target_record_id]} already changed it",
                        tid,
                    )
                targets[item.target_record_id] = tid

            if item.action == "supersede":
                self._check_supersede(path, item.replacement_record_id, target, item, replacements)
                if item.resolution is not None:
                    self._error(
                        "transition_fields",
                        f"{path}.resolution",
                        "supersede has no resolution",
                        tid,
                    )
            elif item.action == "retract":
                if item.replacement_record_id is not None or item.resolution is not None:
                    self._error(
                        "transition_fields",
                        path,
                        "retract has neither a replacement nor a resolution",
                        tid,
                    )
            else:
                if target is not None and target[0] != "uncertainties":
                    self._error(
                        "resolve_non_uncertainty",
                        target_path,
                        f"resolve only applies to uncertainties, not {target[0]}",
                        tid,
                    )
                if item.replacement_record_id is not None:
                    self._error(
                        "transition_fields",
                        f"{path}.replacement_record_id",
                        "resolve has no replacement; add any new fact as its own record",
                        tid,
                    )
                if not (item.resolution or "").strip():
                    self._error(
                        "missing_resolution", f"{path}.resolution", "resolve needs an answer", tid
                    )
            self._check_evidence(path, item.evidence, tid, item.learned_in_section_id)

    def _check_supersede(
        self,
        path: str,
        replacement_id: str | None,
        target: tuple[str, Record[Any]] | None,
        item: Any,
        replacements: set[str],
    ) -> None:
        tid = item.id
        if replacement_id is None:
            self._error(
                "missing_replacement",
                f"{path}.replacement_record_id",
                "supersede needs a replacement record",
                tid,
            )
            return
        replacement = self.records.get(replacement_id)
        if replacement is None:
            self._error(
                "dangling_reference",
                f"{path}.replacement_record_id",
                f"Replacement {replacement_id!r} does not exist",
                tid,
            )
            return
        if replacement[1].introduced_revision != item.introduced_revision:
            self._error(
                "replacement_not_new",
                f"{path}.replacement_record_id",
                f"{replacement_id} must be a record added in the same revision",
                tid,
            )
        if replacement_id in replacements:
            self._warn(
                "replacement_reused",
                path,
                f"{replacement_id} replaces more than one record; check manually",
                tid,
                item.introduced_revision,
            )
        replacements.add(replacement_id)
        if target is None:
            return
        collection, old = target
        if replacement[0] != collection:
            self._error(
                "supersede_kind_mismatch",
                path,
                f"A {collection} record can only be replaced by another {collection} record, "
                f"not by {replacement[0]}",
                tid,
            )
            return
        self._check_same_subject(path, collection, old, replacement[1], item)

    def _check_same_subject(
        self, path: str, collection: str, old: Record[Any], new: Record[Any], item: Any
    ) -> None:
        before, after = old.payload, new.payload
        problem = None
        if collection in ("names", "aliases") and before.entity_id != after.entity_id:
            problem = f"entity {before.entity_id} → {after.entity_id}"
        elif collection == "attributes" and (before.entity_id, before.label) != (
            after.entity_id,
            after.label,
        ):
            problem = (
                f"{before.entity_id}/{before.label!r} → {after.entity_id}/{after.label!r}; "
                "an attribute is replaced by the same entity's attribute with the same label"
            )
        elif collection == "relationships":
            old_key = (before.source_id, before.target_id, before.label)
            new_key = (after.source_id, after.target_id, after.label)
            if old_key != new_key:
                problem = (
                    f"{'/'.join(old_key)} → {'/'.join(new_key)}; a relationship is replaced only "
                    "by one with the same direction and label (use retract plus a new record "
                    "for a different label)"
                )
            elif before.temporal_context != after.temporal_context:
                self._error(
                    "temporal_mismatch",
                    path,
                    f"Replacing a {before.temporal_context!r} relationship with a "
                    f"{after.temporal_context!r} one; a flashback adds a record, it does not "
                    "replace the current state",
                    item.id,
                )
        elif collection == "identity_links" and {before.left_entity_id, before.right_entity_id} != {
            after.left_entity_id,
            after.right_entity_id,
        }:
            problem = "an identity link is replaced only by a link between the same two entities"
        elif collection in ("events", "uncertainties"):
            self._warn(
                "semantic_supersede_review",
                path,
                f"Replaces {collection[:-1]} {old.id} with {new.id}; code cannot check that "
                "both describe the same thing; review manually",
                item.id,
                item.introduced_revision,
            )
        if problem:
            self._error("supersede_subject_mismatch", path, problem, item.id)

    def _check_current(self, expected: Any) -> None:
        stored = self.model.current
        for name in ("active_record_ids", "resolved_uncertainty_ids", "identity_groups"):
            if getattr(stored, name) != getattr(expected, name):
                self._error(
                    "current_mismatch",
                    f"current.{name}",
                    "Does not match the index computed from records and transitions",
                )

    def _check_names(self) -> None:
        names: dict[str, list[Record[Any]]] = {}
        for record in self.model.records.names:
            names.setdefault(record.payload.entity_id, []).append(record)
        for index, entity in enumerate(self.model.entities):
            path = self.paths.get(entity.id) or f"entities[{index}]"
            records = names.get(entity.id, [])
            if not any(r.introduced_revision == entity.introduced_revision for r in records):
                self._error(
                    "entity_without_name",
                    path,
                    f"{entity.id} has no name record from the revision that introduced it",
                    entity.id,
                )
            active = [r.id for r in records if r.id in self.active]
            if not active:
                self._warn("no_active_name", path, f"{entity.id} has no active name", entity.id)
            elif len(active) > 1:
                self._warn(
                    "name_conflict",
                    path,
                    f"{entity.id} has several active names ({', '.join(active)})",
                    entity.id,
                )

    def _check_identity_conflicts(self, expected: Any) -> None:
        """Merged identities do not reconcile their facts; conflicting values are shown."""
        for group in expected.identity_groups:
            values: dict[str, dict[str, list[str]]] = {}
            for record in self.model.records.attributes:
                payload = record.payload
                if record.id in self.active and payload.entity_id in group.member_ids:
                    label = payload.label.strip().casefold()
                    values.setdefault(label, {}).setdefault(
                        payload.value.strip().casefold(), []
                    ).append(record.id)
            for label, by_value in values.items():
                if len(by_value) > 1:
                    ids = ", ".join(rid for rids in by_value.values() for rid in rids)
                    self._warn(
                        "identity_attribute_conflict",
                        f"current.identity_groups[{group.canonical_id}]",
                        f"Members of {'/'.join(group.member_ids)} have different {label!r} "
                        f"values ({ids})",
                        group.canonical_id,
                    )

    def _counts(self) -> dict[str, int]:
        counts = {f"entities_{kind}": 0 for kind in sorted(ALL_KINDS)}
        for entity in self.model.entities:
            counts[f"entities_{entity.kind}"] += 1
        for collection in COLLECTIONS:
            counts[f"records_{collection}"] = len(getattr(self.model.records, collection))
        counts["records_active"] = len(self.active)
        counts["transitions"] = len(self.model.transitions)
        counts["evidence_items"] = len(self.evidence)
        counts["evidence_matched"] = sum(1 for check in self.evidence if check.matched)
        return counts


# --- history and updates -------------------------------------------------------------------


def check_history(base: CumulativeStoryModel, after: CumulativeStoryModel) -> list[Issue]:
    """Earlier knowledge must be an unchanged prefix of the next revision."""
    issues: list[Issue] = []

    def error(path: str, message: str) -> None:
        issues.append(Issue("error", "history_changed", path, message))

    number = after.revision.number
    if number != base.revision.number + 1:
        error("revision.number", f"Expected {base.revision.number + 1}, got {number}")
    for name in ("book", "coverage"):
        if getattr(after, name) != getattr(base, name):
            error(name, f"{name} changed between revisions")
    exclude = {"update_manual_corrections"}
    if after.provenance.model_dump(exclude=exclude) != base.provenance.model_dump(exclude=exclude):
        error("provenance", "provenance changed between revisions")
    pairs: list[tuple[str, list[Any], list[Any]]] = [
        ("processed_sections", base.processed_sections, after.processed_sections),
        ("entities", base.entities, after.entities),
        ("transitions", base.transitions, after.transitions),
    ]
    pairs += [
        (f"records.{c}", getattr(base.records, c), getattr(after.records, c)) for c in COLLECTIONS
    ]
    pairs.append(
        (
            "provenance.update_manual_corrections",
            base.provenance.update_manual_corrections,
            after.provenance.update_manual_corrections,
        )
    )
    for path, before, now in pairs:
        if now[: len(before)] != before:
            error(path, "Earlier items were changed, removed, or reordered")
        for index, item in enumerate(now[len(before) :], start=len(before)):
            revision = getattr(item, "introduced_revision", None) or getattr(item, "revision", None)
            if revision != number:
                error(f"{path}[{index}]", f"New item is not marked as revision {number}")
    if len(after.processed_sections) != len(base.processed_sections) + 1:
        error("processed_sections", "An update adds exactly one processed section")
    return issues


@dataclass
class UpdateValidation:
    structure_valid: bool
    issues: list[Issue]
    evidence: list[EvidenceCheckV2]
    counts: dict[str, int]
    delta: StoryDelta | None = None
    after: CumulativeStoryModel | None = None
    id_map: IdMap | None = None

    @property
    def errors(self) -> list[Issue]:
        return [i for i in self.issues if i.severity == "error"]

    @property
    def warnings(self) -> list[Issue]:
        return [i for i in self.issues if i.severity == "warning"]

    @property
    def passed(self) -> bool:
        return self.structure_valid and self.after is not None and not self.errors

    def evidence_by_record(self) -> dict[str, list[EvidenceCheckV2]]:
        grouped: dict[str, list[EvidenceCheckV2]] = {}
        for check in self.evidence:
            grouped.setdefault(check.record_id or "", []).append(check)
        return grouped

    def to_json(self) -> dict[str, Any]:
        return {
            "validator_version": VALIDATOR_VERSION,
            "passed": self.passed,
            "structure_valid": self.structure_valid,
            "merged": self.after is not None,
            "error_count": len(self.errors),
            "warning_count": len(self.warnings),
            "counts": self.counts,
            "issues": [asdict(i) for i in self.issues],
            "evidence": [asdict(e) for e in self.evidence],
            "note": SUPPORT_NOTE,
        }


def check_delta_ids(base: CumulativeStoryModel, delta: StoryDelta) -> list[Issue]:
    """Local IDs must be unique and well-formed before any stable ID is assigned."""
    issues: list[Issue] = []
    existing = {e.id for e in base.entities} | {t.id for t in base.transitions}
    existing |= {record.id for _, _, record in iter_records(base)}
    seen: set[str] = set()

    def check(path: str, local_id: str, pattern: re.Pattern[str], example: str) -> None:
        if local_id in seen:
            issues.append(
                Issue("error", "duplicate_local_id", path, f"{local_id!r} is used twice", local_id)
            )
        elif local_id in existing or not pattern.match(local_id):
            issues.append(
                Issue(
                    "error",
                    "local_id_format",
                    path,
                    f"{local_id!r} is not a new local ID like {example!r}",
                    local_id,
                )
            )
        seen.add(local_id)

    for index, entity in enumerate(delta.new_entities):
        check(
            f"new_entities[{index}].local_id",
            entity.local_id,
            LOCAL_ENTITY_PATTERN,
            "new_entity_001",
        )
    record_ids: set[str] = set()
    for collection in COLLECTIONS:
        for index, record in enumerate(getattr(delta.new_records, collection)):
            path = f"new_records.{collection}[{index}].local_id"
            check(path, record.local_id, LOCAL_RECORD_PATTERN, "new_record_001")
            record_ids.add(record.local_id)
    for index, item in enumerate(delta.transitions):
        path = f"transitions[{index}]"
        if item.target_record_id in seen:
            issues.append(
                Issue(
                    "error",
                    "target_is_new",
                    f"{path}.target_record_id",
                    "Transitions can only target records of the prior model",
                )
            )
        if item.replacement_local_id is not None and item.replacement_local_id not in record_ids:
            issues.append(
                Issue(
                    "error",
                    "unknown_replacement",
                    f"{path}.replacement_local_id",
                    f"{item.replacement_local_id!r} is not the local_id of a record in this delta",
                )
            )
    return issues


def delta_counts(delta: StoryDelta) -> dict[str, int]:
    counts = {"new_entities": len(delta.new_entities)}
    for collection in COLLECTIONS:
        counts[f"new_{collection}"] = len(getattr(delta.new_records, collection))
    for action in ("supersede", "retract", "resolve"):
        counts[f"transitions_{action}"] = sum(1 for t in delta.transitions if t.action == action)
    return counts


def delta_is_empty(delta: StoryDelta) -> bool:
    return (
        not delta.new_entities
        and not delta.transitions
        and not any(getattr(delta.new_records, c) for c in COLLECTIONS)
    )


def _delta_paths(delta: StoryDelta, id_map: IdMap) -> dict[str, str]:
    paths = {}
    for index, entity in enumerate(delta.new_entities):
        paths[id_map.entities[entity.local_id]] = f"new_entities[{index}]"
    for collection in COLLECTIONS:
        for index, record in enumerate(getattr(delta.new_records, collection)):
            paths[id_map.records[record.local_id]] = f"new_records.{collection}[{index}]"
    for index, tid in enumerate(id_map.transitions):
        paths[tid] = f"transitions[{index}]"
    return paths


def validate_update(
    base: CumulativeStoryModel,
    candidate: Any,
    *,
    chapter: ChapterInput,
    base_inputs: Mapping[str, ChapterInput],
    section: SectionSource,
    revision: RevisionInfo,
    corrections: list[dict[str, Any]] | None = None,
) -> UpdateValidation:
    """Parse a delta, merge it in memory, and check the result and its history.

    Nothing is written; the store is not touched.
    """
    try:
        delta = StoryDelta.model_validate(candidate)
    except ValidationError as exc:
        issues = [
            Issue("error", "schema", error_path(err["loc"]), err["msg"])
            for err in exc.errors(include_url=False)
        ]
        return UpdateValidation(structure_valid=False, issues=issues, evidence=[], counts={})

    counts = delta_counts(delta)
    issues = check_delta_ids(base, delta)
    if any(issue.severity == "error" for issue in issues):
        return UpdateValidation(True, issues, [], counts, delta=delta)

    after, id_map = apply_delta(
        base, delta, section=section, revision=revision, corrections=corrections
    )
    paths = _delta_paths(delta, id_map)
    report = validate_cumulative(
        after,
        {**base_inputs, section.section_id: chapter},
        paths=paths,
        focus_revision=revision.number,
    )
    issues += report.issues
    issues += check_history(base, after)
    if delta_is_empty(delta):
        issues.append(
            Issue(
                "warning",
                "empty_delta",
                "(root)",
                "The model reported nothing new for this section; check manually for omissions",
            )
        )
    new_ids = set(paths)
    evidence = [check for check in report.evidence if check.record_id in new_ids]
    counts["evidence_items"] = len(evidence)
    counts["evidence_matched"] = sum(1 for check in evidence if check.matched)
    return UpdateValidation(True, issues, evidence, counts, delta, after, id_map)
