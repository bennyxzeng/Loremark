"""Offline import of a single-chapter (v1) run as revision 1 of a cumulative model.

Nothing is taken on trust: the v1 model is re-validated against its chapter input, the
input is compared with a fresh extraction from the same EPUB (by SHA-256), and the import
is refused when anything does not match. Facts are carried over exactly as they were,
including known errors and omissions; no model is called and nothing is filled in.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from pydantic import ValidationError

from .artifacts import json_bytes, read_json
from .cumulative_schemas import (
    COLLECTIONS,
    AttributePayload,
    BookRef,
    Coverage,
    CumulativeStoryModel,
    CurrentIndex,
    EntityTextPayload,
    EventPayload,
    ImportedCorrection,
    Provenance,
    RecordCollections,
    RelationshipPayload,
    RevisionInfo,
    SectionSource,
    StableEntity,
    UncertaintyPayload,
)
from .cumulative_validation import validate_cumulative
from .epub import EpubError, extract_section, open_epub, text_sha256
from .merge import format_record_id, project_current
from .schemas import ChapterInput, Evidence, StoryModelEnvelope, _Strict
from .story_store import INITIAL_PROVENANCE_DIR, manifest_bytes, section_source
from .validation import validate_candidate

MIGRATION_VERSION = "1.0"
# Copied byte for byte into provenance/initial/ when present in the v1 run directory.
PROVENANCE_FILES = (
    "run.json",
    "chapter.json",
    "story_model.json",
    "candidate.json",
    "candidate.original.json",
    "validation.json",
    "request.json",
    "response.json",
    "prompt.txt",
    "schema.json",
)


class MigrationError(Exception):
    """A v1 run cannot be imported as it is (exit code 2)."""


@dataclass
class InitialImport:
    model: CumulativeStoryModel
    chapter: ChapterInput
    epub_path: Path
    files: dict[str, bytes]  # store-relative path -> bytes, written before the commit
    migration_map: dict[str, Any]


def import_v1_run(
    run_dir: Path, *, epub_override: Path | None, revision_id: str, created_at: str
) -> InitialImport:
    run_dir = run_dir.resolve()
    for name in ("story_model.json", "chapter.json", "run.json"):
        if not (run_dir / name).is_file():
            raise MigrationError(f"{run_dir / name} not found; the source of the model is unknown")
    try:
        run = read_json(run_dir / "run.json")
        envelope = StoryModelEnvelope.model_validate(read_json(run_dir / "story_model.json"))
        chapter = ChapterInput.model_validate(read_json(run_dir / "chapter.json"))
    except (ValueError, ValidationError) as exc:
        raise MigrationError(f"{run_dir} does not hold a valid v1 model and input: {exc}") from exc
    _check_v1_consistency(run_dir, envelope, chapter, run)
    corrections = _manual_corrections(run_dir, run)

    epub_path, book_sections, section_order = _verify_against_epub(run, chapter, epub_override)
    omitted = [sid for sid, order in book_sections if order < section_order]
    source, input_path, input_data = section_source(
        chapter, section_order=section_order, revision=1
    )

    model, migration_map = migrate_model(
        envelope,
        chapter,
        revision=RevisionInfo(
            number=1,
            id=revision_id,
            created_at=created_at,
            source_run_id=str(run.get("run_id") or run_dir.name),
            parent_snapshot_path=None,
            parent_sha256=None,
        ),
        source=source,
        omitted_prefix=omitted,
        corrections=corrections,
    )
    report = validate_cumulative(model, {chapter.section_id: chapter})
    if report.errors:
        first = report.errors[0]
        raise MigrationError(f"Imported model fails validation: {first.code} at {first.path}")

    copied = {
        name: (run_dir / name).read_bytes()
        for name in PROVENANCE_FILES
        if (run_dir / name).is_file()
    }
    copied["migration_map.json"] = json_bytes(migration_map)
    files = {input_path: input_data}
    files.update({f"{INITIAL_PROVENANCE_DIR}/{name}": data for name, data in copied.items()})
    files[f"{INITIAL_PROVENANCE_DIR}/manifest.json"] = manifest_bytes(
        copied,
        source_run_id=model.provenance.initial_run_id,
        source_run_dir=str(run_dir),
        migration_version=MIGRATION_VERSION,
        note="Byte-for-byte copies of the imported v1 run; story_model.json is the model "
        "that was imported (after the manual corrections listed in run.json).",
    )
    return InitialImport(model, chapter, epub_path, files, migration_map)


def _check_v1_consistency(
    run_dir: Path, envelope: StoryModelEnvelope, chapter: ChapterInput, run: dict[str, Any]
) -> None:
    if text_sha256(chapter.paragraphs) != chapter.text_sha256:
        raise MigrationError("chapter.json paragraphs do not match its text_sha256")
    source = envelope.source
    expected = {
        "book_title": chapter.book_title,
        "book_sha256": chapter.book_sha256,
        "section_id": chapter.section_id,
        "chapter_number": chapter.chapter_number,
        "title": chapter.title,
        "source_href": chapter.source_href,
        "source_fragment": chapter.source_fragment,
        "text_sha256": chapter.text_sha256,
        "paragraph_count": len(chapter.paragraphs),
    }
    mismatched = [name for name, value in expected.items() if getattr(source, name) != value]
    if mismatched:
        raise MigrationError(
            f"story_model.json source does not match chapter.json: {', '.join(mismatched)}"
        )
    run_source, hashes = run.get("source") or {}, run.get("hashes") or {}
    if (
        run.get("command") != "generate"
        or run_source.get("book_sha256") != chapter.book_sha256
        or run_source.get("section_id") != chapter.section_id
        or hashes.get("text_sha256") != chapter.text_sha256
    ):
        raise MigrationError("run.json does not describe a generate run of this chapter input")

    report = validate_candidate(envelope.model.model_dump(mode="json"), chapter)
    if not report.passed:
        details = "; ".join(f"{i.code} at {i.path}" for i in report.errors[:5])
        raise MigrationError(f"The v1 model fails validation again: {details}")
    candidate_path = run_dir / "candidate.json"
    if candidate_path.is_file() and read_json(candidate_path) != envelope.model.model_dump(
        mode="json"
    ):
        raise MigrationError("candidate.json differs from the model in story_model.json")


def _manual_corrections(run_dir: Path, run: dict[str, Any]) -> list[ImportedCorrection]:
    items = run.get("manual_corrections") or []
    corrections = []
    for item in items:
        try:
            corrections.append(
                ImportedCorrection(
                    path=item["path"],
                    original=str(item["from"]),
                    corrected=str(item["to"]),
                    reason=item["reason"],
                    corrected_by=item["corrected_by"],
                    corrected_at=item["corrected_at"],
                )
            )
        except (KeyError, TypeError) as exc:
            raise MigrationError(f"run.json has an incomplete manual correction: {item}") from exc
        original = item.get("original_candidate") or "candidate.original.json"
        if not (run_dir / original).is_file():
            raise MigrationError(
                f"run.json records a manual correction, but the original output {original} is "
                "missing; the correction's source cannot be kept"
            )
    return corrections


def _verify_against_epub(
    run: dict[str, Any], chapter: ChapterInput, epub_override: Path | None
) -> tuple[Path, list[tuple[str, int]], int]:
    """Re-extract the chapter from the same EPUB with the current extractor."""
    recorded = (run.get("source") or {}).get("epub_path")
    epub_path = epub_override or (Path(recorded) if recorded else None)
    if epub_path is None or not epub_path.is_file():
        raise MigrationError(
            f"The EPUB is not available ({epub_path or 'no path recorded'}); pass --epub with "
            f"the same file (SHA-256 {chapter.book_sha256}). Section order is never guessed."
        )
    book = open_epub(epub_path)
    if book.sha256 != chapter.book_sha256:
        raise MigrationError(
            f"{epub_path} has SHA-256 {book.sha256}, but the run used {chapter.book_sha256}; "
            "a book with the same title is not necessarily the same file"
        )
    section = next((s for s in book.sections if s.section_id == chapter.section_id), None)
    if section is None or (section.href, section.fragment, section.title) != (
        chapter.source_href,
        chapter.source_fragment,
        chapter.title,
    ):
        raise MigrationError(
            f"{chapter.section_id} no longer maps to {chapter.source_href} ({chapter.title!r}) "
            "with the current extractor"
        )
    try:
        fresh = extract_section(book, section)
    except EpubError as exc:
        raise MigrationError(f"The current extractor rejects {section.section_id}: {exc}") from exc
    if fresh.paragraphs != chapter.paragraphs or fresh.text_sha256 != chapter.text_sha256:
        raise MigrationError(
            f"Re-extracting {section.section_id} gives different text (SHA-256 "
            f"{fresh.text_sha256}, saved input {chapter.text_sha256}); the saved input may mix "
            "in another section. Refusing to import it."
        )
    return epub_path.resolve(), [(s.section_id, s.order) for s in book.sections], section.order


def migrate_model(
    envelope: StoryModelEnvelope,
    chapter: ChapterInput,
    *,
    revision: RevisionInfo,
    source: SectionSource,
    omitted_prefix: list[str],
    corrections: list[ImportedCorrection],
) -> tuple[CumulativeStoryModel, dict[str, Any]]:
    """Convert v1 records to v2 one for one; entity IDs are kept, records get f-IDs."""
    v1 = envelope.model
    section_id = chapter.section_id
    groups = (
        ("characters", "character", v1.characters),
        ("locations", "location", v1.locations),
        ("organizations", "organization", v1.organizations),
    )
    entities = [
        StableEntity(id=entity.id, kind=kind, introduced_revision=1)
        for _, kind, items in groups
        for entity in items
    ]
    records: dict[str, list[dict[str, Any]]] = {name: [] for name in COLLECTIONS}
    paths: dict[str, str] = {}
    legacy: dict[str, str] = {}

    def add(
        collection: str,
        v1_path: str,
        payload: _Strict,
        evidence: list[Evidence],
        legacy_id: str | None = None,
    ) -> None:
        record_id = format_record_id(sum(len(items) for items in records.values()) + 1)
        records[collection].append(
            {
                "id": record_id,
                "introduced_revision": 1,
                "learned_in_section_id": section_id,
                "legacy_id": legacy_id,
                "payload": payload.model_dump(),
                "evidence": [
                    {"section_id": section_id, "paragraph_id": e.paragraph_id, "quote": e.quote}
                    for e in evidence
                ],
            }
        )
        paths[v1_path] = record_id
        if legacy_id is not None:
            legacy[legacy_id] = record_id

    for list_name, _, items in groups:
        for i, entity in enumerate(items):
            payload = EntityTextPayload(entity_id=entity.id, text=entity.name.text)
            add("names", f"{list_name}[{i}].name", payload, entity.name.evidence)
    for list_name, _, items in groups:
        for i, entity in enumerate(items):
            for j, alias in enumerate(entity.aliases):
                payload = EntityTextPayload(entity_id=entity.id, text=alias.text)
                add("aliases", f"{list_name}[{i}].aliases[{j}]", payload, alias.evidence)
    for list_name, _, items in groups:
        for i, entity in enumerate(items):
            for j, attribute in enumerate(entity.attributes):
                payload = AttributePayload(
                    entity_id=entity.id,
                    label=attribute.label,
                    value=attribute.value,
                    assertion=attribute.assertion,
                    attributed_to_id=attribute.attributed_to_id,
                )
                add("attributes", f"{list_name}[{i}].attributes[{j}]", payload, attribute.evidence)
    for i, rel in enumerate(v1.relationships):
        payload = RelationshipPayload(**rel.model_dump(exclude={"id", "evidence"}))
        add("relationships", f"relationships[{i}]", payload, rel.evidence, rel.id)
    for i, event in enumerate(v1.events):
        payload = EventPayload(**event.model_dump(exclude={"id", "evidence"}))
        add("events", f"events[{i}]", payload, event.evidence, event.id)
    for i, item in enumerate(v1.uncertainties):
        payload = UncertaintyPayload(**item.model_dump(exclude={"evidence"}))
        add("uncertainties", f"uncertainties[{i}]", payload, item.evidence)

    model = CumulativeStoryModel(
        book=BookRef(title=chapter.book_title, epub_sha256=chapter.book_sha256),
        revision=revision,
        processed_sections=[source],
        coverage=Coverage(start_section_id=section_id, omitted_prefix_section_ids=omitted_prefix),
        entities=entities,
        records=RecordCollections.model_validate(records),
        transitions=[],
        current=CurrentIndex(active_record_ids=[], resolved_uncertainty_ids=[], identity_groups=[]),
        provenance=Provenance(
            initial_run_id=revision.source_run_id,
            imported_manual_corrections=corrections,
            migration_version=MIGRATION_VERSION,
        ),
    )
    model.current = project_current(model)
    migration_map = {
        "migration_version": MIGRATION_VERSION,
        "source_run_id": revision.source_run_id,
        "section_id": section_id,
        "entity_ids_kept": [entity.id for entity in entities],
        "records": paths,
        "legacy_ids": legacy,
        "manual_corrections": [
            {"path": c.path, "record_id": _record_for_path(paths, c.path)} for c in corrections
        ],
    }
    return model, migration_map


def _record_for_path(paths: dict[str, str], v1_path: str) -> str | None:
    """The record a v1 field path (e.g. `characters[1].attributes[6].evidence[0]`) is in."""
    matches = [p for p in paths if v1_path == p or v1_path.startswith((f"{p}.", f"{p}["))]
    return paths[max(matches, key=len)] if matches else None
