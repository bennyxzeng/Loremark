"""v1 -> v2 import: offline, faithful, and refused whenever its source cannot be verified."""

from __future__ import annotations

import json
import shutil
from collections.abc import Callable
from pathlib import Path

import pytest
from conftest import STORY, build_epub, build_story_epub, chapter_xhtml, tree_hashes, write_v1_run

from loremark_story_lab.artifacts import read_json, sha256_bytes, write_json
from loremark_story_lab.epub import text_sha256
from loremark_story_lab.incremental_pipeline import run_init
from loremark_story_lab.migration import MigrationError, import_v1_run
from loremark_story_lab.schemas import ChapterInput, Paragraph
from loremark_story_lab.story_store import StoreError, load_store

pytestmark = pytest.mark.usefixtures("no_network")


def _import(run_dir: Path, epub: Path | None = None):
    return import_v1_run(
        run_dir, epub_override=epub, revision_id="rev1", created_at="2026-10-26T00:00:00Z"
    )


def test_import_keeps_entity_ids_and_facts(v1_run: Path) -> None:
    imported = _import(v1_run)
    model = imported.model
    v1 = json.loads((STORY / "chapter1_model.json").read_text(encoding="utf-8"))

    assert [e.id for e in model.entities] == ["c001", "c002", "c003", "c004", "l001", "g001"]
    assert all(e.introduced_revision == 1 for e in model.entities)
    counts = {name: len(getattr(model.records, name)) for name in type(model.records).model_fields}
    assert counts == {
        "names": 6,
        "aliases": 1,
        "attributes": 5,
        "relationships": 4,
        "events": 4,
        "uncertainties": 2,
        "identity_links": 0,
    }
    ids = [r.id for name in counts for r in getattr(model.records, name)]
    assert ids == [f"f{n:06d}" for n in range(1, 23)]

    # Payloads are the v1 facts one for one; only the evidence gains the section ID.
    rank = model.records.attributes[0]
    assert rank.payload.model_dump() == {
        "entity_id": "c001",
        **{k: v1["characters"][0]["attributes"][0][k] for k in ("label", "value", "assertion")},
        "attributed_to_id": None,
    }
    for relationship, record in zip(v1["relationships"], model.records.relationships, strict=True):
        assert record.legacy_id == relationship["id"]
        assert record.payload.description == relationship["description"]
        assert [e.model_dump() for e in record.evidence] == [
            {"section_id": "section-002", **e} for e in relationship["evidence"]
        ]
    assert [r.legacy_id for r in model.records.events] == ["e001", "e002", "e003", "e004"]
    assert all(r.learned_in_section_id == "section-002" for r in model.records.names)

    assert model.transitions == [] and model.records.identity_links == []
    assert model.current.active_record_ids == ids
    assert model.current.resolved_uncertainty_ids == []
    assert model.current.identity_groups == []
    assert model.coverage.start_section_id == "section-002"
    assert model.coverage.omitted_prefix_section_ids == ["section-001"]
    assert model.processed_sections[0].section_order == 2
    assert imported.migration_map["records"]["characters[0].attributes[0]"] == "f000008"
    assert imported.migration_map["legacy_ids"]["r001"] == "f000013"


def test_known_errors_and_omissions_are_carried_over_unchanged(v1_run: Path) -> None:
    model = _import(v1_run).model
    tomas_age = model.records.attributes[3].payload
    assert tomas_age.entity_id == "c003"
    assert "KNOWN-WRONG" in tomas_age.value and tomas_age.assertion == "inferred"
    dump = json.dumps(model.model_dump(mode="json"), ensure_ascii=False)
    assert "humming" not in dump  # an omission in the v1 model stays an omission


def test_init_copies_provenance_and_leaves_the_run_untouched(tmp_path: Path, v1_run: Path) -> None:
    before = tree_hashes(v1_run)
    run_init(from_run=v1_run, store_root=tmp_path / "store", epub_path=None, echo=lambda _: None)

    assert tree_hashes(v1_run) == before
    state = load_store(tmp_path / "store")
    corrections = state.model.provenance.imported_manual_corrections
    assert [(c.path, c.original, c.corrected) for c in corrections] == [
        ("characters[0].aliases[0].evidence[0].paragraph_id", "p0003", "p0004")
    ]
    initial = tmp_path / "store" / "provenance" / "initial"
    for name in ("run.json", "candidate.original.json", "story_model.json", "migration_map.json"):
        assert (initial / name).is_file()
    assert (initial / "candidate.original.json").read_bytes() == (
        v1_run / "candidate.original.json"
    ).read_bytes()
    manifest = read_json(initial / "manifest.json")
    for name, digest in manifest["files"].items():
        assert sha256_bytes((initial / name).read_bytes()) == digest
    migration_map = read_json(initial / "migration_map.json")
    assert migration_map["manual_corrections"] == [
        {"path": "characters[0].aliases[0].evidence[0].paragraph_id", "record_id": "f000007"}
    ]

    shutil.rmtree(v1_run)  # the store no longer needs the run directory
    assert load_store(tmp_path / "store").model.revision.number == 1


def _break_candidate(run: Path) -> None:
    data = read_json(run / "candidate.json")
    data["events"][0]["description"] = "Changed after validation."
    write_json(run / "candidate.json", data)


def _break_chapter_text(run: Path) -> None:
    data = read_json(run / "chapter.json")
    data["paragraphs"][3]["text"] = "Ilse and the Grey Fox were old friends."
    write_json(run / "chapter.json", data)


def _break_quote(run: Path) -> None:
    for name in ("story_model.json", "candidate.json"):
        data = read_json(run / name)
        model = data["model"] if name == "story_model.json" else data
        model["events"][0]["evidence"][0]["quote"] = "kept watch from the lighthouse"
        write_json(run / name, data)


@pytest.mark.parametrize(
    ("breakage", "message"),
    [
        (lambda run: (run / "chapter.json").unlink(), "chapter.json not found"),
        (lambda run: (run / "run.json").unlink(), "run.json not found"),
        (_break_candidate, "candidate.json differs"),
        (_break_chapter_text, "do not match its text_sha256"),
        (_break_quote, "fails validation again"),
        (lambda run: (run / "candidate.original.json").unlink(), "original output"),
    ],
    ids=["no-chapter", "no-run", "candidate", "text-hash", "quote", "no-original"],
)
def test_init_refuses_unverifiable_runs(
    tmp_path: Path, v1_run: Path, breakage: Callable[[Path], None], message: str
) -> None:
    breakage(v1_run)
    with pytest.raises(MigrationError, match=message):
        run_init(from_run=v1_run, store_root=tmp_path / "store", epub_path=None, echo=print)
    assert not (tmp_path / "store").exists() or not any((tmp_path / "store").iterdir())


def test_epub_must_be_available_and_identical(tmp_path: Path, story_epub: Path) -> None:
    run = write_v1_run(tmp_path / "run", story_epub)
    moved = tmp_path / "moved.epub"
    shutil.move(story_epub, moved)
    with pytest.raises(MigrationError, match="not available"):
        _import(run)

    other = build_story_epub(
        tmp_path / "other.epub", chapter2=chapter_xhtml(STORY / "chapter1.txt")
    )
    with pytest.raises(MigrationError, match="SHA-256"):
        _import(run, other)

    imported = _import(run, moved)
    assert imported.epub_path == moved.resolve()


def test_input_that_mixes_in_the_next_chapter_is_refused(tmp_path: Path, story_epub: Path) -> None:
    run = write_v1_run(tmp_path / "run", story_epub)
    chapter = ChapterInput.model_validate(read_json(run / "chapter.json"))
    mixed = [*chapter.paragraphs, Paragraph(id="p0010", text="CHAPTER 2 THE STORM")]
    chapter = chapter.model_copy(update={"paragraphs": mixed, "text_sha256": text_sha256(mixed)})
    write_json(run / "chapter.json", chapter.model_dump(mode="json"))
    story = read_json(run / "story_model.json")
    story["source"].update(text_sha256=chapter.text_sha256, paragraph_count=len(mixed))
    write_json(run / "story_model.json", story)
    run_json = read_json(run / "run.json")
    run_json["hashes"]["text_sha256"] = chapter.text_sha256
    write_json(run / "run.json", run_json)

    with pytest.raises(MigrationError, match="gives different text"):
        _import(run)


def test_input_whose_boundary_is_now_unreliable_is_refused(tmp_path: Path) -> None:
    body = chapter_xhtml(STORY / "chapter1.txt").replace("<h1>", '<h1 id="c1">', 1)
    body = body.replace("</body>", "<h1>CHAPTER 2</h1><p>NEXT-SENTINEL</p></body>")
    epub = build_epub(
        tmp_path / "broken.epub",
        {"prologue.xhtml": "<html><body><p>Prologue.</p></body></html>", "all.xhtml": body},
        nav=[
            ("prologue.xhtml", "Prologue"),
            ("all.xhtml#c1", "Chapter 1: The Signal"),
            ("all.xhtml#missing", "Chapter 2: The Storm"),
        ],
    )
    # A run made by the old extractor, before the boundary fix.
    good = write_v1_run(tmp_path / "good", build_story_epub(tmp_path / "story.epub"))
    chapter = read_json(good / "chapter.json")
    chapter.update(
        book_sha256=sha256_bytes(epub.read_bytes()),
        source_href="OEBPS/all.xhtml",
        source_fragment="c1",
    )
    write_json(good / "chapter.json", chapter)
    story = read_json(good / "story_model.json")
    story["source"].update(
        book_sha256=chapter["book_sha256"], source_href="OEBPS/all.xhtml", source_fragment="c1"
    )
    write_json(good / "story_model.json", story)
    run_json = read_json(good / "run.json")
    run_json["source"].update(book_sha256=chapter["book_sha256"], epub_path=str(epub))
    write_json(good / "run.json", run_json)

    with pytest.raises(MigrationError, match="rejects section-002"):
        _import(good)


def test_init_needs_a_new_or_empty_store(tmp_path: Path, v1_run: Path) -> None:
    store = tmp_path / "store"
    store.mkdir()
    (store / "notes.txt").write_text("keep")
    with pytest.raises(StoreError, match="not an empty directory"):
        run_init(from_run=v1_run, store_root=store, epub_path=None, echo=print)
    assert (store / "notes.txt").read_text() == "keep"
