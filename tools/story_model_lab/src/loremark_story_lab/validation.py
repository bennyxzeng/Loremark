"""Deterministic checks of a candidate story model against the chapter input.

A matched quote only proves the text exists in the cited paragraph, not that it supports
the claim. Nothing here edits or drops records; every problem is reported.
"""

from __future__ import annotations

import re
from dataclasses import asdict, dataclass, field
from typing import Any, Literal

from pydantic import ValidationError

from .schemas import ChapterInput, ChapterStoryModel, Entity, Evidence

VALIDATOR_VERSION = "1.0"
MAX_QUOTE_CHARS = 300

Kind = Literal["character", "location", "organization", "relationship", "event"]
ENTITY_KINDS: set[Kind] = {"character", "location", "organization"}
SPEAKER_KINDS: set[Kind] = {"character", "organization"}
ID_PATTERNS: dict[Kind, re.Pattern[str]] = {
    "character": re.compile(r"^c\d{3,}$"),
    "location": re.compile(r"^l\d{3,}$"),
    "organization": re.compile(r"^g\d{3,}$"),
    "relationship": re.compile(r"^r\d{3,}$"),
    "event": re.compile(r"^e\d{3,}$"),
}
_QUOTE_FOLD = str.maketrans({"“": '"', "”": '"', "‘": "'", "’": "'", "—": "-", "–": "-"})


@dataclass
class Issue:
    severity: Literal["error", "warning"]
    code: str
    path: str
    message: str
    record_id: str | None = None


@dataclass
class EvidenceCheck:
    path: str
    record_id: str | None
    paragraph_id: str
    quote: str
    matched: bool
    spans: list[list[int]] = field(default_factory=list)


@dataclass
class ValidationReport:
    structure_valid: bool
    issues: list[Issue]
    evidence: list[EvidenceCheck]
    counts: dict[str, int]
    model: ChapterStoryModel | None = None

    @property
    def errors(self) -> list[Issue]:
        return [i for i in self.issues if i.severity == "error"]

    @property
    def warnings(self) -> list[Issue]:
        return [i for i in self.issues if i.severity == "warning"]

    @property
    def passed(self) -> bool:
        return self.structure_valid and not self.errors

    def evidence_by_path(self) -> dict[str, EvidenceCheck]:
        return {check.path: check for check in self.evidence}

    def to_json(self) -> dict[str, Any]:
        return {
            "validator_version": VALIDATOR_VERSION,
            "passed": self.passed,
            "structure_valid": self.structure_valid,
            "error_count": len(self.errors),
            "warning_count": len(self.warnings),
            "counts": self.counts,
            "issues": [asdict(i) for i in self.issues],
            "evidence": [asdict(e) for e in self.evidence],
            "note": "A matched quote only shows the text exists in that paragraph; "
            "it does not show that the quote supports the claim.",
        }


def find_spans(text: str, quote: str) -> list[list[int]]:
    """All [start, end) code-point ranges where quote occurs in text, overlaps included."""
    spans = []
    start = text.find(quote)
    while start != -1:
        spans.append([start, start + len(quote)])
        start = text.find(quote, start + 1)
    return spans


def validate_candidate(candidate: Any, chapter: ChapterInput) -> ValidationReport:
    try:
        model = ChapterStoryModel.model_validate(candidate)
    except ValidationError as exc:
        issues = [
            Issue("error", "schema", error_path(err["loc"]), err["msg"])
            for err in exc.errors(include_url=False)
        ]
        return ValidationReport(structure_valid=False, issues=issues, evidence=[], counts={})
    return _Checker(model, chapter).run()


def error_path(loc: tuple[Any, ...]) -> str:
    path = ""
    for part in loc:
        path += f"[{part}]" if isinstance(part, int) else (f".{part}" if path else str(part))
    return path or "(root)"


class _Checker:
    def __init__(self, model: ChapterStoryModel, chapter: ChapterInput) -> None:
        self.model = model
        self.paragraphs = {p.id: p.text for p in chapter.paragraphs}
        self.paragraph_index = {p.id: i for i, p in enumerate(chapter.paragraphs)}
        self.issues: list[Issue] = []
        self.evidence: list[EvidenceCheck] = []
        self.kinds: dict[str, Kind] = {}

    def run(self) -> ValidationReport:
        self._register_ids()
        groups: list[tuple[str, Kind, list[Entity]]] = [
            ("characters", "character", self.model.characters),
            ("locations", "location", self.model.locations),
            ("organizations", "organization", self.model.organizations),
        ]
        for list_name, _, entities in groups:
            for index, entity in enumerate(entities):
                self._check_entity(f"{list_name}[{index}]", entity)
        self._check_relationships()
        self._check_events()
        self._check_uncertainties()
        if not self.model.characters:
            self._warn("empty_characters", "characters", "No characters extracted; check manually")
        if not self.model.events:
            self._warn("empty_events", "events", "No events extracted; check manually")

        matched = sum(1 for check in self.evidence if check.matched)
        counts = {
            "characters": len(self.model.characters),
            "locations": len(self.model.locations),
            "organizations": len(self.model.organizations),
            "relationships": len(self.model.relationships),
            "events": len(self.model.events),
            "uncertainties": len(self.model.uncertainties),
            "attributes": sum(len(e.attributes) for _, _, es in groups for e in es),
            "aliases": sum(len(e.aliases) for _, _, es in groups for e in es),
            "evidence_items": len(self.evidence),
            "evidence_matched": matched,
        }
        return ValidationReport(
            structure_valid=True,
            issues=self.issues,
            evidence=self.evidence,
            counts=counts,
            model=self.model,
        )

    # --- helpers --------------------------------------------------------------

    def _error(self, code: str, path: str, message: str, record_id: str | None = None) -> None:
        self.issues.append(Issue("error", code, path, message, record_id))

    def _warn(self, code: str, path: str, message: str, record_id: str | None = None) -> None:
        self.issues.append(Issue("warning", code, path, message, record_id))

    def _register_ids(self) -> None:
        records: list[tuple[str, Kind, list[Any]]] = [
            ("characters", "character", self.model.characters),
            ("locations", "location", self.model.locations),
            ("organizations", "organization", self.model.organizations),
            ("relationships", "relationship", self.model.relationships),
            ("events", "event", self.model.events),
        ]
        for list_name, kind, items in records:
            for index, item in enumerate(items):
                path = f"{list_name}[{index}].id"
                if not item.id.strip():
                    self._error("empty_id", path, "ID is empty")
                    continue
                if item.id in self.kinds:
                    self._error("duplicate_id", path, f"Duplicate ID {item.id!r}", item.id)
                    continue
                self.kinds[item.id] = kind
                if not ID_PATTERNS[kind].match(item.id):
                    self._warn(
                        "id_format",
                        path,
                        f"{item.id!r} does not follow the {kind} ID pattern "
                        f"{ID_PATTERNS[kind].pattern}",
                        item.id,
                    )

    def _check_reference(
        self, path: str, ref: str, allowed: set[Kind], record_id: str | None
    ) -> None:
        kind = self.kinds.get(ref)
        if kind is None:
            self._error("dangling_reference", path, f"{ref!r} does not exist", record_id)
        elif kind not in allowed:
            expected = " or ".join(sorted(allowed))
            self._error(
                "wrong_reference_kind",
                path,
                f"{ref!r} is a {kind}, expected {expected}",
                record_id,
            )

    def _check_nonempty(self, path: str, value: str, record_id: str | None) -> None:
        if not value.strip():
            self._error("empty_text", path, "Text is empty", record_id)

    def _check_assertion(
        self, path: str, assertion: str, attributed_to_id: str | None, record_id: str | None
    ) -> None:
        if attributed_to_id is None:
            return
        self._check_reference(
            f"{path}.attributed_to_id", attributed_to_id, SPEAKER_KINDS, record_id
        )
        if assertion != "reported":
            self._warn(
                "attribution_without_report",
                f"{path}.attributed_to_id",
                f"attributed_to_id is set but assertion is {assertion!r}",
                record_id,
            )

    def _check_evidence(self, path: str, items: list[Evidence], record_id: str | None) -> None:
        if not items:
            self._error("missing_evidence", f"{path}.evidence", "Evidence list is empty", record_id)
            return
        for index, item in enumerate(items):
            item_path = f"{path}.evidence[{index}]"
            text = self.paragraphs.get(item.paragraph_id)
            spans: list[list[int]] = []
            if text is None:
                self._error(
                    "unknown_paragraph",
                    item_path,
                    f"Paragraph {item.paragraph_id!r} is not part of this chapter input",
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
                    self._error(
                        "quote_not_found",
                        item_path,
                        self._not_found_message(item),
                        record_id,
                    )
            self.evidence.append(
                EvidenceCheck(
                    path=item_path,
                    record_id=record_id,
                    paragraph_id=item.paragraph_id,
                    quote=item.quote,
                    matched=bool(spans),
                    spans=spans,
                )
            )

    def _not_found_message(self, item: Evidence) -> str:
        message = f"Quote is not an exact substring of {item.paragraph_id}"
        elsewhere = [pid for pid, text in self.paragraphs.items() if item.quote in text]
        if elsewhere:
            return f"{message}; it occurs verbatim in {', '.join(elsewhere[:5])} (not accepted)"
        folded = fold_text(item.quote)
        if folded and folded in fold_text(self.paragraphs[item.paragraph_id]):
            return f"{message}; it matches only after folding quotes/dashes/case/spaces"
        return message

    def _check_supported_text(self, path: str, value: Any, record_id: str | None) -> None:
        self._check_nonempty(f"{path}.text", value.text, record_id)
        self._check_evidence(path, value.evidence, record_id)

    # --- record checks ----------------------------------------------------------

    def _check_entity(self, path: str, entity: Entity) -> None:
        rid = entity.id
        self._check_supported_text(f"{path}.name", entity.name, rid)
        for index, alias in enumerate(entity.aliases):
            alias_path = f"{path}.aliases[{index}]"
            self._check_supported_text(alias_path, alias, rid)
            if alias.text.strip() == entity.name.text.strip():
                self._warn("alias_repeats_name", alias_path, "Alias repeats the name", rid)
        for index, attribute in enumerate(entity.attributes):
            attr_path = f"{path}.attributes[{index}]"
            self._check_nonempty(f"{attr_path}.label", attribute.label, rid)
            self._check_nonempty(f"{attr_path}.value", attribute.value, rid)
            self._check_assertion(attr_path, attribute.assertion, attribute.attributed_to_id, rid)
            self._check_evidence(attr_path, attribute.evidence, rid)

    def _check_relationships(self) -> None:
        for index, rel in enumerate(self.model.relationships):
            path = f"relationships[{index}]"
            self._check_reference(f"{path}.source_id", rel.source_id, ENTITY_KINDS, rel.id)
            self._check_reference(f"{path}.target_id", rel.target_id, ENTITY_KINDS, rel.id)
            if rel.source_id == rel.target_id:
                self._warn("self_relationship", path, "Source and target are the same", rel.id)
            self._check_nonempty(f"{path}.label", rel.label, rel.id)
            self._check_nonempty(f"{path}.description", rel.description, rel.id)
            self._check_assertion(path, rel.assertion, rel.attributed_to_id, rel.id)
            self._check_evidence(path, rel.evidence, rel.id)

    def _check_events(self) -> None:
        previous_order = 0
        previous_first_paragraph: int | None = None
        seen_orders: set[int] = set()
        for index, event in enumerate(self.model.events):
            path = f"events[{index}]"
            self._check_nonempty(f"{path}.description", event.description, event.id)
            for p_index, participant in enumerate(event.participant_ids):
                self._check_reference(
                    f"{path}.participant_ids[{p_index}]", participant, SPEAKER_KINDS, event.id
                )
            if len(set(event.participant_ids)) != len(event.participant_ids):
                self._warn("duplicate_participant", path, "A participant is listed twice", event.id)
            if event.location_id is not None:
                self._check_reference(
                    f"{path}.location_id", event.location_id, {"location"}, event.id
                )
            self._check_assertion(path, event.assertion, event.attributed_to_id, event.id)
            self._check_evidence(path, event.evidence, event.id)

            order_path = f"{path}.narrative_order"
            order = event.narrative_order
            if order < 1:
                self._error("narrative_order", order_path, f"{order} is not positive", event.id)
            elif order in seen_orders:
                self._error("narrative_order", order_path, f"{order} is repeated", event.id)
            elif order < previous_order:
                self._error(
                    "narrative_order",
                    order_path,
                    f"{order} comes after {previous_order}; events must be listed in order",
                    event.id,
                )
            elif order != previous_order + 1:
                self._warn(
                    "narrative_order_gap",
                    order_path,
                    f"Expected {previous_order + 1}, got {order}",
                    event.id,
                )
            seen_orders.add(order)
            previous_order = max(previous_order, order)

            positions = [
                self.paragraph_index[e.paragraph_id]
                for e in event.evidence
                if e.paragraph_id in self.paragraph_index
            ]
            if positions:
                first = min(positions)
                if previous_first_paragraph is not None and first < previous_first_paragraph:
                    self._warn(
                        "narrative_order_vs_evidence",
                        path,
                        "Earliest evidence comes before the previous event's; "
                        "check the narrative order manually",
                        event.id,
                    )
                previous_first_paragraph = first

    def _check_uncertainties(self) -> None:
        for index, item in enumerate(self.model.uncertainties):
            path = f"uncertainties[{index}]"
            self._check_nonempty(f"{path}.question", item.question, None)
            for r_index, ref in enumerate(item.related_entity_ids):
                self._check_reference(
                    f"{path}.related_entity_ids[{r_index}]", ref, ENTITY_KINDS, None
                )
            self._check_evidence(path, item.evidence, None)


def fold_text(text: str) -> str:
    return " ".join(text.translate(_QUOTE_FOLD).casefold().split())
