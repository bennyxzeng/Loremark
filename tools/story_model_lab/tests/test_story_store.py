"""The on-disk store: atomic commits, stale bases, fault injection, and refusing damage."""

from __future__ import annotations

import fcntl
import json
import os
from pathlib import Path

import pytest
from conftest import story_chapter, story_delta

from loremark_story_lab import story_store
from loremark_story_lab.artifacts import sha256_bytes
from loremark_story_lab.cumulative_schemas import CumulativeStoryModel, RevisionInfo
from loremark_story_lab.cumulative_validation import validate_update
from loremark_story_lab.incremental_pipeline import run_init
from loremark_story_lab.story_store import (
    StaleBaseError,
    StoreError,
    StoreState,
    commit_revision,
    load_revision,
    load_store,
    section_source,
)

pytestmark = pytest.mark.usefixtures("no_network")


@pytest.fixture
def store(tmp_path: Path, v1_run: Path) -> Path:
    root = tmp_path / "store"
    run_init(from_run=v1_run, store_root=root, epub_path=None, echo=lambda _: None)
    return root


def candidate(state: StoreState, epub: Path, revision_id: str) -> tuple[CumulativeStoryModel, dict]:
    """Revision 2 built from the store's latest revision, plus the files a commit writes."""
    chapter = story_chapter(epub, "section-003")
    section, relpath, data = section_source(chapter, section_order=3, revision=2)
    result = validate_update(
        state.model,
        story_delta(),
        chapter=chapter,
        base_inputs=state.inputs,
        section=section,
        revision=RevisionInfo(
            number=2,
            id=revision_id,
            created_at="2026-10-26T01:00:00Z",
            source_run_id=f"run-{revision_id}",
            parent_snapshot_path=state.snapshot_path,
            parent_sha256=state.latest_sha256,
        ),
    )
    assert result.passed, result.errors
    return result.after, {relpath: data}


def test_initialized_store_is_verified_on_load(store: Path) -> None:
    state = load_store(store)
    assert state.model.revision.number == 1
    assert (store / state.snapshot_path).read_bytes() == (store / "story_model.json").read_bytes()
    assert state.chain == [(1, state.snapshot_path, state.latest_sha256)]
    assert list(state.inputs) == ["section-002"]
    assert (store / ".lock").is_file()


def test_commit_appends_a_revision_and_keeps_the_old_snapshot(
    store: Path, story_epub: Path
) -> None:
    state = load_store(store)
    first_snapshot = (store / state.snapshot_path).read_bytes()
    after, files = candidate(state, story_epub, "aaaa")
    snapshot = commit_revision(store, after, files, expected_base_sha256=state.latest_sha256)

    latest = load_store(store)
    assert latest.model.revision.number == 2
    assert (store / snapshot).read_bytes() == (store / "story_model.json").read_bytes()
    assert latest.model.revision.parent_snapshot_path == state.snapshot_path
    assert latest.model.revision.parent_sha256 == sha256_bytes(first_snapshot)
    assert (store / state.snapshot_path).read_bytes() == first_snapshot
    assert load_revision(latest, 1) == state.model
    assert [n for n, _, _ in latest.chain] == [2, 1]


def test_second_update_from_the_same_base_is_stale(store: Path, story_epub: Path) -> None:
    state = load_store(store)
    first, files = candidate(state, story_epub, "first")
    second, _ = candidate(state, story_epub, "second")
    commit_revision(store, first, files, expected_base_sha256=state.latest_sha256)
    committed = (store / "story_model.json").read_bytes()

    with pytest.raises(StaleBaseError, match="changed since this update read it"):
        commit_revision(store, second, files, expected_base_sha256=state.latest_sha256)
    assert (store / "story_model.json").read_bytes() == committed
    assert load_store(store).model.revision.id == "first"


def test_failed_snapshot_write_leaves_the_store_unchanged(
    store: Path, story_epub: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    state = load_store(store)
    after, files = candidate(state, story_epub, "broken")
    real_write = story_store._write_file

    def write(path: Path, data: bytes) -> None:
        if path.parent.name == "revisions":
            raise OSError("disk full (injected)")
        real_write(path, data)

    monkeypatch.setattr(story_store, "_write_file", write)
    with pytest.raises(OSError, match="injected"):
        commit_revision(store, after, files, expected_base_sha256=state.latest_sha256)
    assert (store / "story_model.json").read_bytes() == state.latest_bytes
    assert load_store(store).model.revision.number == 1


def test_failure_before_replace_leaves_an_unreachable_snapshot(
    store: Path, story_epub: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    state = load_store(store)
    after, files = candidate(state, story_epub, "orphan")
    real_replace = os.replace

    def replace(src: os.PathLike[str], dst: os.PathLike[str]) -> None:
        if Path(dst).name == "story_model.json":
            raise OSError("power loss (injected)")
        real_replace(src, dst)

    monkeypatch.setattr(story_store.os, "replace", replace)
    with pytest.raises(OSError, match="injected"):
        commit_revision(store, after, files, expected_base_sha256=state.latest_sha256)
    monkeypatch.undo()

    assert (store / "revisions" / "000002-orphan.json").is_file()
    assert not list(store.glob(".story_model.json.*.tmp"))
    reloaded = load_store(store)
    assert reloaded.model.revision.number == 1
    with pytest.raises(StoreError, match="not in the committed history"):
        load_revision(reloaded, 2)

    # The leftover file does not block a retry with a new revision ID.
    retry, files = candidate(reloaded, story_epub, "retry")
    commit_revision(store, retry, files, expected_base_sha256=reloaded.latest_sha256)
    assert load_store(store).model.revision.id == "retry"


def _rewrite_latest(store: Path, edit) -> None:
    """Change the latest file and its snapshot together, so only deeper checks can notice."""
    data = json.loads((store / "story_model.json").read_text(encoding="utf-8"))
    edit(data)
    model = CumulativeStoryModel.model_validate(data)
    content = story_store.model_bytes(model)
    (store / "story_model.json").write_bytes(content)
    (store / story_store.snapshot_relpath(model.revision)).write_bytes(content)


@pytest.mark.parametrize(
    ("damage", "message"),
    [
        (lambda s: next((s / "inputs").iterdir()).unlink(), "Cannot read input"),
        (
            lambda s: next((s / "inputs").iterdir()).write_text("{}", encoding="utf-8"),
            "does not match its SHA-256",
        ),
        (
            lambda s: (s / "story_model.json").write_text(
                (s / "story_model.json").read_text(encoding="utf-8").replace("Lieutenant", "Major"),
                encoding="utf-8",
            ),
            "differs from its snapshot",
        ),
        (
            lambda s: _rewrite_latest(s, lambda d: d["current"]["active_record_ids"].pop()),
            "current_mismatch",
        ),
        (
            lambda s: _rewrite_latest(
                s,
                lambda d: d["processed_sections"][0].update(input_relative_path="../outside.json"),
            ),
            "outside the store",
        ),
        (
            lambda s: (s / "provenance" / "initial" / "candidate.original.json").write_text("{}"),
            "Provenance file",
        ),
        (lambda s: (s / "story_model.json").unlink(), "not a story store"),
    ],
    ids=[
        "missing-input",
        "input-hash",
        "latest-vs-snapshot",
        "current",
        "path",
        "provenance",
        "empty",
    ],
)
def test_damaged_stores_are_refused(store: Path, damage, message: str) -> None:
    damage(store)
    with pytest.raises(StoreError, match=message):
        load_store(store)


def test_commit_waits_for_a_real_lock_not_for_the_lock_file(store: Path, story_epub: Path) -> None:
    state = load_store(store)
    after, files = candidate(state, story_epub, "locked")
    holder = os.open(store / ".lock", os.O_RDWR)
    try:
        fcntl.flock(holder, fcntl.LOCK_EX)
        with pytest.raises(StoreError, match="locked by another"):
            commit_revision(
                store, after, files, expected_base_sha256=state.latest_sha256, lock_timeout=0.2
            )
    finally:
        fcntl.flock(holder, fcntl.LOCK_UN)
        os.close(holder)
    assert (store / ".lock").exists()  # a leftover lock file alone does not block
    commit_revision(store, after, files, expected_base_sha256=state.latest_sha256)
    assert load_store(store).model.revision.id == "locked"
