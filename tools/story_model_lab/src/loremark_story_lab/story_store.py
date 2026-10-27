"""A cumulative story store on disk: latest model, immutable snapshots, inputs, provenance.

    <store>/story_model.json          latest revision; replacing it is the only commit point
    <store>/.lock                     fcntl.flock lock held while committing
    <store>/revisions/NNNNNN-<id>.json  full snapshot of every committed revision
    <store>/inputs/<section>-<hash>.json  normalized text of every processed section
    <store>/provenance/...            where each revision's knowledge came from

A commit writes the inputs, provenance, and snapshot first, then atomically replaces the
latest file under the lock, after re-checking that the latest file is still the one the
update started from. A failure before the replace leaves the previous revision in place;
leftover files are never reachable from the latest revision's parent chain.
"""

from __future__ import annotations

import fcntl
import os
import secrets
import time
from collections.abc import Iterator, Mapping
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

from pydantic import ValidationError

from .artifacts import json_bytes, read_json, sha256_bytes
from .cumulative_schemas import CumulativeStoryModel, RevisionInfo, SectionSource
from .cumulative_validation import validate_cumulative
from .schemas import ChapterInput

LATEST_FILE = "story_model.json"
LOCK_FILE = ".lock"
MANIFEST_FILE = "manifest.json"
INITIAL_PROVENANCE_DIR = "provenance/initial"
LOCK_TIMEOUT_SECONDS = 30.0


class StoreError(Exception):
    """The store is missing, damaged, or cannot be written (exit code 2)."""


class StaleBaseError(Exception):
    """The store was changed by another update after this one read it (exit code 5)."""


# --- layout -----------------------------------------------------------------------------


def snapshot_relpath(revision: RevisionInfo) -> str:
    return f"revisions/{revision.number:06d}-{revision.id}.json"


def input_relpath(chapter: ChapterInput) -> str:
    return f"inputs/{chapter.section_id}-{chapter.text_sha256[:16]}.json"


def section_source(
    chapter: ChapterInput, *, section_order: int, revision: int
) -> tuple[SectionSource, str, bytes]:
    """The SectionSource of a processed section, with its input file path and bytes."""
    relpath = input_relpath(chapter)
    data = json_bytes(chapter.model_dump(mode="json"))
    source = SectionSource(
        section_id=chapter.section_id,
        section_order=section_order,
        chapter_number=chapter.chapter_number,
        title=chapter.title,
        href=chapter.source_href,
        fragment=chapter.source_fragment,
        text_sha256=chapter.text_sha256,
        extraction_version=chapter.extraction_version,
        paragraph_count=len(chapter.paragraphs),
        input_relative_path=relpath,
        input_file_sha256=sha256_bytes(data),
        introduced_revision=revision,
    )
    return source, relpath, data


def store_path(root: Path, relpath: str) -> Path:
    """Resolve a store-relative path, refusing anything that would leave the store."""
    parts = relpath.split("/")
    if (
        not relpath
        or relpath.startswith("/")
        or "\\" in relpath
        or any(part in ("", ".", "..") for part in parts)
    ):
        raise StoreError(f"Refusing path outside the store: {relpath!r}")
    root = root.resolve()
    path = (root / relpath).resolve()
    if root not in path.parents:
        raise StoreError(f"Refusing path outside the store: {relpath!r}")
    return path


def model_bytes(model: CumulativeStoryModel) -> bytes:
    return json_bytes(model.model_dump(mode="json"))


# --- reading ------------------------------------------------------------------------------


@dataclass
class StoreState:
    root: Path
    model: CumulativeStoryModel
    latest_bytes: bytes
    latest_sha256: str
    snapshot_path: str
    inputs: dict[str, ChapterInput]
    input_files: dict[str, bytes]
    # (revision number, snapshot path, SHA-256), newest first; only these are committed.
    chain: list[tuple[int, str, str]]


def _read(root: Path, relpath: str, what: str) -> bytes:
    path = store_path(root, relpath)
    try:
        return path.read_bytes()
    except OSError as exc:
        raise StoreError(f"Cannot read {what} {relpath}: {exc}") from exc


def _parse_model(data: bytes, where: str) -> CumulativeStoryModel:
    try:
        return CumulativeStoryModel.model_validate_json(data)
    except ValidationError as exc:
        first = exc.errors(include_url=False)[0]
        raise StoreError(f"{where} is not a valid cumulative story model: {first['msg']}") from exc


def load_store(root: Path) -> StoreState:
    """Read and verify the latest revision; never trusts saved pass/fail flags.

    Checks the snapshot copy, every saved input and its hashes, provenance manifests, the
    parent chain, and the full model (references, quotes, history index).
    """
    root = root.resolve()
    latest_path = root / LATEST_FILE
    if not latest_path.is_file():
        raise StoreError(f"{root} is not a story store (no {LATEST_FILE}); run `story-model init`")
    latest = latest_path.read_bytes()
    model = _parse_model(latest, str(latest_path))
    latest_sha = sha256_bytes(latest)
    snapshot = snapshot_relpath(model.revision)
    if _read(root, snapshot, "snapshot") != latest:
        raise StoreError(f"{LATEST_FILE} differs from its snapshot {snapshot}")

    inputs: dict[str, ChapterInput] = {}
    input_files: dict[str, bytes] = {}
    for section in model.processed_sections:
        data = _read(root, section.input_relative_path, "input")
        if sha256_bytes(data) != section.input_file_sha256:
            raise StoreError(f"Input {section.input_relative_path} does not match its SHA-256")
        try:
            inputs[section.section_id] = ChapterInput.model_validate_json(data)
        except ValidationError as exc:
            raise StoreError(f"Input {section.input_relative_path} is not valid: {exc}") from exc
        input_files[section.input_relative_path] = data

    _verify_manifests(root)
    report = validate_cumulative(model, inputs)
    if report.errors:
        details = "; ".join(f"{i.code} at {i.path}: {i.message}" for i in report.errors[:5])
        raise StoreError(f"Revision {model.revision.number} fails validation: {details}")

    return StoreState(
        root=root,
        model=model,
        latest_bytes=latest,
        latest_sha256=latest_sha,
        snapshot_path=snapshot,
        inputs=inputs,
        input_files=input_files,
        chain=_parent_chain(root, model, snapshot, latest_sha),
    )


def _parent_chain(
    root: Path, model: CumulativeStoryModel, snapshot: str, sha: str
) -> list[tuple[int, str, str]]:
    chain = [(model.revision.number, snapshot, sha)]
    current = model
    while current.revision.parent_snapshot_path is not None:
        relpath = current.revision.parent_snapshot_path
        data = _read(root, relpath, "parent snapshot")
        sha = sha256_bytes(data)
        if sha != current.revision.parent_sha256:
            raise StoreError(f"Parent snapshot {relpath} does not match the recorded SHA-256")
        parent = _parse_model(data, relpath)
        if (
            parent.revision.number != current.revision.number - 1
            or snapshot_relpath(parent.revision) != relpath
        ):
            raise StoreError(
                f"Parent snapshot {relpath} is not revision {current.revision.number - 1}"
            )
        chain.append((parent.revision.number, relpath, sha))
        current = parent
    if current.revision.number != 1:
        raise StoreError(f"The parent chain stops at revision {current.revision.number}")
    return chain


def _verify_manifests(root: Path) -> None:
    """Every provenance directory lists the SHA-256 of the files it holds."""
    if not (root / INITIAL_PROVENANCE_DIR / MANIFEST_FILE).is_file():
        raise StoreError(f"Missing {INITIAL_PROVENANCE_DIR}/{MANIFEST_FILE}")
    for manifest_path in sorted((root / "provenance").glob(f"*/{MANIFEST_FILE}")):
        directory = manifest_path.parent.relative_to(root).as_posix()
        try:
            files = read_json(manifest_path)["files"]
        except (ValueError, KeyError, TypeError) as exc:
            raise StoreError(f"{directory}/{MANIFEST_FILE} is not a valid manifest") from exc
        for name, expected in files.items():
            data = _read(root, f"{directory}/{name}", "provenance file")
            if sha256_bytes(data) != expected:
                raise StoreError(f"Provenance file {directory}/{name} does not match its SHA-256")


def load_revision(state: StoreState, number: int) -> CumulativeStoryModel:
    """A committed revision, reached through the latest revision's parent chain."""
    for revision, relpath, sha in state.chain:
        if revision != number:
            continue
        if revision == state.model.revision.number:
            return state.model
        data = _read(state.root, relpath, "snapshot")
        if sha256_bytes(data) != sha:
            raise StoreError(f"Snapshot {relpath} changed after it was committed")
        model = _parse_model(data, relpath)
        latest_sections = state.model.processed_sections
        if model.processed_sections != latest_sections[: len(model.processed_sections)]:
            raise StoreError(f"Snapshot {relpath} disagrees with the latest processed sections")
        inputs = {s.section_id: state.inputs[s.section_id] for s in model.processed_sections}
        report = validate_cumulative(model, inputs)
        if report.errors:
            raise StoreError(f"Snapshot {relpath} fails validation: {report.errors[0].message}")
        return model
    available = ", ".join(str(revision) for revision, _, _ in reversed(state.chain))
    raise StoreError(f"Revision {number} is not in the committed history (available: {available})")


# --- writing ------------------------------------------------------------------------------


def ensure_new_store(root: Path) -> None:
    if root.exists() and (not root.is_dir() or any(root.iterdir())):
        raise StoreError(f"{root} exists and is not an empty directory; refusing to initialize")


def manifest_bytes(files: Mapping[str, bytes], **info: object) -> bytes:
    """manifest.json of a provenance directory: the SHA-256 of each file in it."""
    return json_bytes(
        {**info, "files": {name: sha256_bytes(data) for name, data in sorted(files.items())}}
    )


def commit_revision(
    root: Path,
    model: CumulativeStoryModel,
    files: Mapping[str, bytes],
    *,
    expected_base_sha256: str | None,
    lock_timeout: float = LOCK_TIMEOUT_SECONDS,
) -> str:
    """Write `files` and the snapshot, then make `model` the latest revision.

    `expected_base_sha256` is the latest file's hash when the update started (None for a
    new store). Returns the snapshot path. Raises StaleBaseError when the store moved on.
    """
    data = model_bytes(model)
    snapshot = snapshot_relpath(model.revision)
    root.mkdir(parents=True, exist_ok=True)
    with _locked(root, lock_timeout):
        latest = root / LATEST_FILE
        current = sha256_bytes(latest.read_bytes()) if latest.exists() else None
        if current != expected_base_sha256:
            raise StaleBaseError(
                f"{latest} changed since this update read it "
                f"(expected {expected_base_sha256 or 'no file'}, found {current or 'no file'}); "
                "nothing was committed"
            )
        for relpath, content in files.items():
            path = store_path(root, relpath)
            if path.exists():
                if path.read_bytes() != content:
                    raise StoreError(f"{relpath} already exists with different content")
                continue
            _write_file(path, content)
        snapshot_path = store_path(root, snapshot)
        if snapshot_path.exists():
            raise StoreError(f"Snapshot {snapshot} already exists")
        _write_file(snapshot_path, data)
        _write_file(latest, data)  # os.replace inside: the commit point
    return snapshot


def _write_file(path: Path, data: bytes) -> None:
    """Write via a temporary file in the same directory, fsync, then rename into place."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{secrets.token_hex(4)}.tmp")
    try:
        with temporary.open("xb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)
    _fsync_directory(path.parent)


def _fsync_directory(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


@contextmanager
def _locked(root: Path, timeout: float) -> Iterator[None]:
    """An exclusive flock on <store>/.lock; the file existing alone means nothing."""
    fd = os.open(root / LOCK_FILE, os.O_RDWR | os.O_CREAT, 0o644)
    try:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise StoreError(f"{root} is locked by another story-model process") from None
                time.sleep(0.05)
        try:
            yield
        finally:
            fcntl.flock(fd, fcntl.LOCK_UN)
    finally:
        os.close(fd)
