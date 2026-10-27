"""Cumulative flows behind `init`, `update`, `show`, and `validate` of update runs.

`update` reads and verifies the store, checks that the requested section is the next one in
reading order of the same EPUB, sends the prior model and that section, validates the
returned delta, merges it in memory, and commits a new revision. Every check that can fail
without the model runs before the API call; nothing reaches the store unless the whole
candidate revision passes, and a commit refuses to overwrite a store another update changed.
"""

from __future__ import annotations

import copy
import json
import re
import secrets
import time
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from pydantic import ValidationError

from .artifacts import (
    environment_versions,
    json_bytes,
    prepare_output_dir,
    read_json,
    sha256_bytes,
    utc_now,
    write_json,
    write_text,
)
from .config import GenerateConfig
from .cumulative_schemas import CumulativeStoryModel, RevisionInfo, StoryDelta
from .cumulative_validation import (
    VALIDATOR_VERSION,
    UpdateValidation,
    validate_cumulative,
    validate_update,
)
from .epub import EpubBook, EpubError, Section, extract_section, find_section, open_epub
from .incremental_reporting import render_diff, render_story_markdown, render_update_review
from .migration import import_v1_run
from .pipeline import (
    EXIT_API,
    EXIT_INPUT,
    EXIT_OK,
    EXIT_STALE_BASE,
    EXIT_VALIDATION,
    ClientFactory,
    Echo,
    Outcome,
    RunInputError,
    default_client_factory,
    describe_selection,
    failure_record,
    new_run_record,
    response_summary,
    write_chapter_files,
)
from .prompting import (
    UPDATE_PROMPT,
    build_update_context,
    build_update_params,
    load_prompt,
    request_record,
    sha256_json,
    text_format,
)
from .schemas import ChapterInput
from .story_store import (
    StaleBaseError,
    StoreError,
    StoreState,
    commit_revision,
    ensure_new_store,
    load_revision,
    load_store,
    manifest_bytes,
    model_bytes,
    section_source,
)

# Run status -> exit code for every terminal state of `update`.
UPDATE_EXIT_CODES = {
    "dry_run": EXIT_OK,
    "committed": EXIT_OK,
    "committed_report_failed": EXIT_OK,
    "validation_failed": EXIT_VALIDATION,
    "schema_invalid": EXIT_VALIDATION,
    "api_error": EXIT_API,
    "refusal": EXIT_API,
    "incomplete": EXIT_API,
    "failed": EXIT_API,
    "empty_output": EXIT_API,
    "stale_base": EXIT_STALE_BASE,
    "commit_failed": EXIT_INPUT,
}
BASE_INPUTS_DIR = "base_inputs"
CORRECTIONS_FILE = "manual_corrections.json"
# A correction may only move evidence to where its text really is, never change a fact.
_CORRECTABLE_PATH = re.compile(
    r"^(new_records\.\w+\[\d+\]|transitions\[\d+\])\.evidence\[\d+\]\.(paragraph_id|quote)$"
)
_CORRECTION_FIELDS = ("path", "from", "to", "reason", "corrected_by", "corrected_at")


class UpdateInputError(Exception):
    """The requested section cannot be processed next (exit code 2)."""


def new_revision_id() -> str:
    return secrets.token_hex(6)


# --- init / show ----------------------------------------------------------------------------


def run_init(*, from_run: Path, store_root: Path, epub_path: Path | None, echo: Echo) -> Outcome:
    store_root = store_root.resolve()
    ensure_new_store(store_root)
    imported = import_v1_run(
        from_run, epub_override=epub_path, revision_id=new_revision_id(), created_at=utc_now()
    )
    commit_revision(store_root, imported.model, imported.files, expected_base_sha256=None)
    state = load_store(store_root)
    model = state.model
    echo(f"Imported {from_run.resolve()} ({model.provenance.initial_run_id}) as revision 1")
    echo(f"Book: {model.book.title} (SHA-256 {model.book.epub_sha256})")
    section = model.processed_sections[0]
    echo(f"Section: {section.section_id} {section.title!r} [{section.paragraph_count} paragraphs]")
    omitted = model.coverage.omitted_prefix_section_ids
    if omitted:
        echo(f"Not covered (before the start): {', '.join(omitted)}")
    echo(
        f"Entities: {len(model.entities)}; records: {len(model.current.active_record_ids)}; "
        f"manual corrections carried over: {len(model.provenance.imported_manual_corrections)}"
    )
    echo(f"Store: {state.root}")
    echo("Status: initialized")
    return Outcome(EXIT_OK, "initialized", state.root)


def run_show(*, store_root: Path, revision: int | None, as_json: bool, echo: Echo) -> Outcome:
    """Print one committed revision; reads only, never calls the API."""
    state = load_store(store_root)
    model = state.model if revision is None else load_revision(state, revision)
    if as_json:
        echo(json.dumps(model.model_dump(mode="json"), ensure_ascii=False, indent=2))
    else:
        echo(render_story_markdown(model).rstrip("\n"))
    return Outcome(EXIT_OK, "shown", state.root)


# --- update -----------------------------------------------------------------------------------


@dataclass
class UpdatePlan:
    section: Section
    chapter: ChapterInput
    already_processed: bool


def plan_update(
    state: StoreState, book: EpubBook, *, chapter: int | None, section_id: str | None
) -> UpdatePlan:
    """Check that the selection is the next section of the same book; nothing is sent."""
    model = state.model
    if book.sha256 != model.book.epub_sha256:
        raise UpdateInputError(
            f"{book.path} has SHA-256 {book.sha256}, but the store was built from "
            f"{model.book.epub_sha256}; a book with the same title is not necessarily the same file"
        )
    by_id = {section.section_id: section for section in book.sections}
    for source in model.processed_sections:
        current = by_id.get(source.section_id)
        if current is None or (current.order, current.href, current.fragment, current.title) != (
            source.section_order,
            source.href,
            source.fragment,
            source.title,
        ):
            raise UpdateInputError(
                f"{source.section_id} no longer maps to the same place in the book "
                "(the section list changed); this store cannot be continued with it"
            )

    selected = find_section(book, chapter=chapter, section_id=section_id)
    processed = {source.section_id: source for source in model.processed_sections}
    if selected.section_id in processed:
        source = processed[selected.section_id]
        fresh = extract_section(book, selected)
        if fresh.text_sha256 != source.text_sha256:
            raise UpdateInputError(
                f"{selected.section_id} was processed in revision {source.introduced_revision} "
                f"with text SHA-256 {source.text_sha256}, but extracting it now gives "
                f"{fresh.text_sha256}; re-processing a section is not supported"
            )
        return UpdatePlan(selected, fresh, already_processed=True)

    last = model.processed_sections[-1]
    following = [s for s in book.sections if s.order > last.section_order]
    if not following:
        raise UpdateInputError(f"Every section after {last.section_id} is already processed")
    expected = following[0]
    if selected.order < expected.order:
        raise UpdateInputError(
            f"{selected.section_id} ({selected.title!r}) comes before {last.section_id}, the last "
            "processed section; adding earlier sections is not supported"
        )
    if selected.order > expected.order:
        raise UpdateInputError(
            f"{selected.section_id} ({selected.title!r}) would skip {expected.section_id} "
            f"({expected.title!r}), which has not been processed. Sections are processed one at "
            f"a time in reading order; the next one is {expected.section_id} "
            f"(`--section {expected.section_id}`)"
        )
    if selected.problem:
        raise EpubError(
            f"{selected.section_id}, the next section, cannot be extracted reliably "
            f"({selected.problem}); it cannot be skipped, so updating stops here for now"
        )
    try:
        chapter_input = extract_section(book, selected)
    except EpubError as exc:
        raise EpubError(
            f"{exc}; {selected.section_id} is the next section and cannot be skipped, "
            "so updating stops here for now"
        ) from exc
    return UpdatePlan(selected, chapter_input, already_processed=False)


def run_update(
    *,
    store_root: Path,
    epub_path: Path,
    chapter: int | None,
    section_id: str | None,
    config: GenerateConfig,
    out: Path | None,
    prompt_file: Path | None,
    echo: Echo,
    client_factory: ClientFactory = default_client_factory,
    env: Mapping[str, str] | None = None,
) -> Outcome:
    started_clock = time.monotonic()
    state = load_store(store_root)
    book = open_epub(epub_path)
    plan = plan_update(state, book, chapter=chapter, section_id=section_id)
    chapter_input = plan.chapter
    echo(describe_selection(chapter_input))
    if plan.already_processed:
        echo(f"Store: {state.root} (revision {state.model.revision.number}, unchanged)")
        echo(
            f"Status: already_processed ({chapter_input.section_id} with this text is in the store)"
        )
        return Outcome(EXIT_OK, "already_processed", state.root)

    prompt_text, prompt_source = load_prompt(prompt_file, builtin=UPDATE_PROMPT)
    api_key = "" if config.dry_run else config.api_key(env)
    base = state.model
    number = base.revision.number + 1
    section, input_relpath, input_data = section_source(
        chapter_input, section_order=plan.section.order, revision=number
    )

    run_dir = prepare_output_dir(out)
    context = build_update_context(base, chapter_input, section_order=plan.section.order)
    params = build_update_params(context, prompt_text, config)
    fmt = text_format(StoryDelta)
    write_chapter_files(run_dir, chapter_input)
    write_text(run_dir / "prompt.txt", prompt_text)
    write_json(run_dir / "schema.json", fmt["schema"])
    write_json(run_dir / "request.json", request_record(params, config, StoryDelta))
    write_json(run_dir / "context.json", context)
    (run_dir / "base_story_model.json").write_bytes(state.latest_bytes)
    for relpath, data in state.input_files.items():
        target = run_dir / BASE_INPUTS_DIR / Path(relpath).name
        target.parent.mkdir(exist_ok=True)
        target.write_bytes(data)

    run = new_run_record(
        run_dir, book, chapter_input, config, params, prompt_text, prompt_source, command="update"
    )
    run["source"]["section_order"] = plan.section.order
    run["hashes"].update(
        schema_sha256=sha256_json(fmt["schema"]),
        context_sha256=sha256_json(context),
        base_sha256=state.latest_sha256,
    )
    run.update(
        store={"path": str(state.root)},
        base_revision={
            "number": base.revision.number,
            "id": base.revision.id,
            "sha256": state.latest_sha256,
            "snapshot_path": state.snapshot_path,
        },
        candidate_revision=None,
        committed_revision=None,
        commit_status="not_attempted",
        report_status=None,
    )
    warnings = [*book.warnings, *chapter_input.extraction_notes]

    if config.dry_run:
        _finish(run, "dry_run", started_clock)
        write_json(run_dir / "run.json", run)
        echo(f"Output: {run_dir}")
        echo(f"Context: prior revision {base.revision.number} + {chapter_input.section_id}")
        echo("Status: dry_run (no request sent, store unchanged)")
        return Outcome(EXIT_OK, "dry_run", run_dir, warnings)

    write_json(run_dir / "run.json", run)
    echo(f"Output: {run_dir}")
    update_run = _UpdateRun(run_dir, run, state, chapter_input, started_clock, echo, warnings)

    limit = "no timeout" if config.timeout is None else f"timeout {config.timeout:g}s"
    echo(f"Calling {config.provider.name} model {config.model!r} ({limit})...")
    try:
        result = client_factory(config, api_key).generate(params, output_type=StoryDelta)
    except Exception as exc:
        run["error"] = {
            "category": "internal_error",
            "type": type(exc).__name__,
            "message": str(exc),
        }
        _finish(run, "internal_error", started_clock)
        write_json(run_dir / "run.json", run)
        write_json(run_dir / "failure.json", {"status": "internal_error", "error": run["error"]})
        raise

    run["response"] = response_summary(result)
    if result.response_body is not None:
        write_json(run_dir / "response.json", result.response_body)
    validation = None
    if result.candidate is not None:
        write_json(run_dir / "delta.candidate.json", result.candidate)
        revision = RevisionInfo(
            number=number,
            id=new_revision_id(),
            created_at=utc_now(),
            source_run_id=run_dir.name,
            parent_snapshot_path=state.snapshot_path,
            parent_sha256=state.latest_sha256,
        )
        validation = validate_update(
            base,
            result.candidate,
            chapter=chapter_input,
            base_inputs=state.inputs,
            section=section,
            revision=revision,
        )
        _save_validation(run_dir, run, base, validation)

    if result.status != "completed" or validation is None or not validation.passed:
        status = _failure_status(result.status, validation)
        failure = failure_record(result, status)
        if result.status == "completed" and validation is not None:
            failure["error"] = {
                "category": "validation",
                "message": f"{len(validation.errors)} errors; see validation.json",
            }
        return update_run.stop(status, failure, validation)
    return update_run.commit(validation, input_relpath, input_data)


@dataclass
class _UpdateRun:
    """An update run that has a run directory; ends by committing or by stopping."""

    run_dir: Path
    run: dict[str, Any]
    state: StoreState
    chapter: ChapterInput
    started_clock: float
    echo: Echo
    warnings: list[str]

    def stop(
        self, status: str, failure: dict[str, Any], validation: UpdateValidation | None
    ) -> Outcome:
        """End without changing the store, keeping every diagnostic file."""
        base = self.state.model
        _finish(self.run, status, self.started_clock)
        write_json(self.run_dir / "failure.json", failure)
        write_json(self.run_dir / "run.json", self.run)
        review = render_update_review(self.chapter, self.run, base, validation, failure)
        write_text(self.run_dir / "review.md", review)
        self.echo(f"Status: {status} (store unchanged at revision {base.revision.number})")
        return Outcome(UPDATE_EXIT_CODES[status], status, self.run_dir, self.warnings)

    def commit(
        self, validation: UpdateValidation, input_relpath: str, input_data: bytes
    ) -> Outcome:
        run, run_dir, state, echo = self.run, self.run_dir, self.state, self.echo
        base, chapter_input, warnings = state.model, self.chapter, self.warnings
        stop, started_clock = self.stop, self.started_clock
        after = validation.after
        assert after is not None and validation.delta is not None and validation.id_map is not None
        run["candidate_revision"] = {"number": after.revision.number, "id": after.revision.id}
        files = {input_relpath: input_data, **_provenance_files(run_dir, run, after, validation)}
        try:
            commit_revision(state.root, after, files, expected_base_sha256=state.latest_sha256)
        except StaleBaseError as exc:
            run["commit_status"] = "stale_base"
            failure = {
                "status": "stale_base",
                "error": {"category": "stale_base", "message": str(exc)},
            }
            return stop("stale_base", failure, validation)
        except (OSError, StoreError) as exc:
            run["commit_status"] = "failed"
            failure = {
                "status": "commit_failed",
                "error": {
                    "category": "commit_failed",
                    "type": type(exc).__name__,
                    "message": f"{exc}; the store still holds revision {base.revision.number}",
                },
            }
            return stop("commit_failed", failure, validation)

        # The latest file has been replaced: the update is committed. Report problems from here
        # on are recorded as such, never as a failed update.
        run["commit_status"] = "committed"
        run["committed_revision"] = {"number": after.revision.number, "id": after.revision.id}
        try:
            _finish(run, "committed", started_clock)
            write_json(run_dir / "run.json", run)
            write_text(
                run_dir / "review.md",
                render_update_review(chapter_input, run, base, validation, None),
            )
            run["report_status"] = "complete"
            write_json(run_dir / "run.json", run)
        except Exception as exc:
            message = (
                f"revision {after.revision.number} was committed, but the run report is incomplete "
                f"({type(exc).__name__}: {exc}); do not re-apply this delta"
            )
            try:
                run["report_status"] = "failed"
                run["report_error"] = message
                _finish(run, "committed_report_failed", started_clock)
                write_json(run_dir / "run.json", run)
            except Exception:  # the state is committed; report what we can
                pass
            echo(f"Output: {run_dir}")
            echo(f"Status: committed_report_failed (revision {after.revision.number})")
            return Outcome(EXIT_OK, "committed_report_failed", run_dir, [*warnings, message])
        echo(f"Store: {state.root} (revision {base.revision.number} → {after.revision.number})")
        echo(f"Status: committed ({len(validation.warnings)} warnings; see {run_dir}/review.md)")
        return Outcome(EXIT_OK, "committed", run_dir, warnings)


def _failure_status(call_status: str, validation: UpdateValidation | None) -> str:
    if call_status == "parse_error":
        return "schema_invalid"
    if call_status != "completed":
        return call_status
    if validation is None:
        return "empty_output"
    return "validation_failed" if validation.structure_valid else "schema_invalid"


def _save_validation(
    run_dir: Path,
    run: dict[str, Any],
    base: CumulativeStoryModel,
    validation: UpdateValidation,
    name: str = "validation.json",
) -> None:
    write_json(run_dir / name, validation.to_json())
    run["validation"] = {
        "passed": validation.passed,
        "structure_valid": validation.structure_valid,
        "merged": validation.after is not None,
        "error_count": len(validation.errors),
        "warning_count": len(validation.warnings),
        "validator_version": VALIDATOR_VERSION,
        "validated_at": utc_now(),
    }
    if not validation.passed:
        return
    assert validation.after is not None and validation.delta is not None
    assert validation.id_map is not None
    write_json(run_dir / "delta.json", validation.delta.model_dump(mode="json"))
    write_json(run_dir / "id_map.json", validation.id_map.to_json())
    (run_dir / "story_model.after.json").write_bytes(model_bytes(validation.after))
    write_text(run_dir / "diff.md", render_diff(base, validation.after, validation.id_map))


def _provenance_files(
    run_dir: Path, run: dict[str, Any], after: CumulativeStoryModel, validation: UpdateValidation
) -> dict[str, bytes]:
    """What the store keeps about this update: the delta, ID map, and base it was applied to."""
    assert validation.delta is not None and validation.id_map is not None
    response = run.get("response") or {}
    files = {
        "delta.candidate.json": (run_dir / "delta.candidate.json").read_bytes(),
        "delta.json": json_bytes(validation.delta.model_dump(mode="json")),
        "id_map.json": json_bytes(validation.id_map.to_json()),
        "commit.json": json_bytes(
            {
                "run_id": run["run_id"],
                "base_revision": run["base_revision"],
                "revision": {"number": after.revision.number, "id": after.revision.id},
                "section_id": after.processed_sections[-1].section_id,
                "input_relative_path": after.processed_sections[-1].input_relative_path,
                "provider": run["request"]["provider"],
                "model": run["request"]["model"],
                "response_model": response.get("model"),
                "response_id": response.get("response_id"),
                "usage": response.get("usage"),
                "prompt_source": run["prompt_source"],
                "hashes": run["hashes"],
                "manual_corrections": run.get("manual_corrections") or [],
            }
        ),
    }
    if run.get("manual_corrections"):
        for name in (CORRECTIONS_FILE, "delta.corrected.json", "validation.json"):
            files[name] = (run_dir / name).read_bytes()
    directory = f"provenance/{run_dir.name}"
    paths = {f"{directory}/{name}": data for name, data in files.items()}
    paths[f"{directory}/manifest.json"] = manifest_bytes(files, source_run_id=run_dir.name)
    return paths


def _finish(run: dict[str, Any], status: str, started_clock: float) -> None:
    run["status"] = status
    run["exit_code"] = UPDATE_EXIT_CODES.get(status)
    run["finished_at"] = utc_now()
    run["elapsed_seconds"] = round(time.monotonic() - started_clock, 3)


# --- commit a manually corrected update run ---------------------------------------------------


def apply_corrections(candidate: Any, corrections: Any) -> tuple[Any, list[dict[str, Any]]]:
    """Apply evidence-location corrections to a copy of the model's raw delta.

    Each item names a path in the delta, the value the model returned (`from`), and the new
    value (`to`). Anything else (facts, IDs, a stale `from`) is refused.
    """
    if not isinstance(corrections, list) or not corrections:
        raise RunInputError(f"{CORRECTIONS_FILE} must be a non-empty JSON list")
    corrected = copy.deepcopy(candidate)
    records: list[dict[str, Any]] = []
    seen: set[str] = set()
    for index, item in enumerate(corrections):
        where = f"{CORRECTIONS_FILE}[{index}]"
        if not isinstance(item, dict) or set(item) != set(_CORRECTION_FIELDS):
            raise RunInputError(
                f"{where} needs exactly these keys: {', '.join(_CORRECTION_FIELDS)}"
            )
        path = item["path"]
        if not isinstance(path, str) or not _CORRECTABLE_PATH.match(path):
            raise RunInputError(
                f"{where}: {path!r} is not an evidence paragraph_id or quote; only evidence "
                "locations can be corrected, never facts"
            )
        if path in seen:
            raise RunInputError(f"{where}: {path} is corrected twice")
        seen.add(path)
        parent, key = _resolve_delta_path(corrected, path, where)
        if parent[key] != item["from"]:
            raise RunInputError(
                f"{where}: {path} is {parent[key]!r} in the model output, not {item['from']!r}"
            )
        if not isinstance(item["to"], str) or not item["to"].strip():
            raise RunInputError(f"{where}: the corrected value must be non-empty text")
        parent[key] = item["to"]
        records.append(
            {
                "path": path,
                "original": item["from"],
                "corrected": item["to"],
                "reason": str(item["reason"]),
                "corrected_by": str(item["corrected_by"]),
                "corrected_at": str(item["corrected_at"]),
            }
        )
    return corrected, records


def _resolve_delta_path(data: Any, path: str, where: str) -> tuple[Any, str]:
    parts = re.findall(r"[^.\[\]]+", path)
    target = data
    try:
        for part in parts[:-1]:
            target = target[int(part)] if part.isdigit() else target[part]
        if parts[-1] not in target:
            raise KeyError(parts[-1])
    except (KeyError, IndexError, TypeError) as exc:
        raise RunInputError(f"{where}: {path} does not exist in the model output") from exc
    return target, parts[-1]


def run_commit_corrected(*, run_dir: Path, epub_path: Path, echo: Echo) -> Outcome:
    """Commit an update run whose delta failed validation, after recorded manual corrections.

    The model's raw delta stays in delta.candidate.json; the corrections, the corrected delta,
    and the original validation go to the store's provenance, and every correction is listed
    in the model's `provenance.update_manual_corrections`. Nothing is sent to any model.
    """
    started_clock = time.monotonic()
    run_dir = run_dir.resolve()
    run_path = run_dir / "run.json"
    if not run_path.is_file() or read_json(run_path).get("command") != "update":
        raise RunInputError(f"{run_dir} is not an update run directory")
    run = read_json(run_path)
    if run.get("commit_status") == "committed":
        raise RunInputError(
            f"{run_dir} was already committed as revision "
            f"{(run.get('committed_revision') or {}).get('number')}"
        )
    for name in ("delta.candidate.json", CORRECTIONS_FILE, "chapter.json"):
        if not (run_dir / name).is_file():
            raise RunInputError(f"{run_dir / name} not found")
    corrected, corrections = apply_corrections(
        read_json(run_dir / "delta.candidate.json"), read_json(run_dir / CORRECTIONS_FILE)
    )

    state = load_store(Path(run["store"]["path"]))
    base_sha = run["base_revision"]["sha256"]
    if state.latest_sha256 != base_sha:
        raise StaleBaseError(
            f"The store moved on since this run (expected {base_sha}, found "
            f"{state.latest_sha256}); its delta no longer applies. Nothing was committed."
        )
    book = open_epub(epub_path)
    plan = plan_update(state, book, chapter=None, section_id=run["source"]["section_id"])
    saved = ChapterInput.model_validate(read_json(run_dir / "chapter.json"))
    if plan.already_processed or plan.chapter != saved:
        raise RunInputError(
            f"{run_dir}/chapter.json is not the next section of this store as the EPUB gives it"
        )

    write_json(run_dir / "delta.corrected.json", corrected)
    base = state.model
    number = base.revision.number + 1
    section, input_relpath, input_data = section_source(
        saved, section_order=plan.section.order, revision=number
    )
    revision = RevisionInfo(
        number=number,
        id=new_revision_id(),
        created_at=utc_now(),
        source_run_id=run_dir.name,
        parent_snapshot_path=state.snapshot_path,
        parent_sha256=state.latest_sha256,
    )
    validation = validate_update(
        base,
        corrected,
        chapter=saved,
        base_inputs=state.inputs,
        section=section,
        revision=revision,
        corrections=corrections,
    )
    echo(describe_selection(saved))
    echo(f"Applied {len(corrections)} manual corrections to delta.candidate.json")
    if not validation.passed:
        write_json(run_dir / "validation.corrected.json", validation.to_json())
        echo(
            f"Status: still failing ({len(validation.errors)} errors; see "
            f"{run_dir / 'validation.corrected.json'}); nothing was committed"
        )
        return Outcome(EXIT_VALIDATION, "validation_failed", run_dir)

    original_validation = run.get("validation")
    _save_validation(run_dir, run, base, validation, name="validation.corrected.json")
    run.update(
        original_status=run.get("status"),
        original_finished_at=run.get("finished_at"),
        manual_corrections=corrections,
        corrected_validation=run["validation"],
        validation=original_validation,
    )
    write_json(run_path, run)
    update_run = _UpdateRun(run_dir, run, state, saved, started_clock, echo, [])
    return update_run.commit(validation, input_relpath, input_data)


# --- validate an update run -----------------------------------------------------------------


def validate_update_run(run_dir: Path, echo: Echo) -> Outcome:
    """Re-check an update run's base, delta, and merged result offline.

    The store is not read or written, and the run's own artifacts are left as they are; the
    result goes to validation.recheck.json.
    """
    run = read_json(run_dir / "run.json")
    required = ("base_story_model.json", "chapter.json")
    for name in required:
        if not (run_dir / name).is_file():
            raise RunInputError(f"{run_dir / name} not found; is this an update run directory?")
    candidate_path = run_dir / "delta.candidate.json"
    if not candidate_path.is_file():
        raise RunInputError(
            f"{candidate_path} not found; the run produced no parseable delta to validate"
        )
    try:
        base = CumulativeStoryModel.model_validate_json(
            (run_dir / "base_story_model.json").read_bytes()
        )
        chapter = ChapterInput.model_validate(read_json(run_dir / "chapter.json"))
    except ValidationError as exc:
        raise RunInputError(f"{run_dir} holds an invalid base model or chapter: {exc}") from exc

    base_inputs: dict[str, ChapterInput] = {}
    for source in base.processed_sections:
        path = run_dir / BASE_INPUTS_DIR / Path(source.input_relative_path).name
        if not path.is_file() or sha256_bytes(path.read_bytes()) != source.input_file_sha256:
            raise RunInputError(f"{path} is missing or does not match the base model's hash")
        base_inputs[source.section_id] = ChapterInput.model_validate_json(path.read_bytes())

    base_report = validate_cumulative(base, base_inputs)
    after_path = run_dir / "story_model.after.json"
    saved_after = (
        CumulativeStoryModel.model_validate_json(after_path.read_bytes())
        if after_path.is_file()
        else None
    )
    number = base.revision.number + 1
    revision = (
        saved_after.revision
        if saved_after is not None
        else RevisionInfo(
            number=number,
            id=(run.get("candidate_revision") or {}).get("id") or "recheck",
            created_at=utc_now(),
            source_run_id=run_dir.name,
            parent_snapshot_path=(run.get("base_revision") or {}).get("snapshot_path"),
            parent_sha256=(run.get("base_revision") or {}).get("sha256"),
        )
    )
    section, _, _ = section_source(
        chapter, section_order=run["source"]["section_order"], revision=number
    )
    validation = validate_update(
        base,
        read_json(candidate_path),
        chapter=chapter,
        base_inputs=base_inputs,
        section=section,
        revision=revision,
    )
    problems = [f"base: {i.code} at {i.path}: {i.message}" for i in base_report.errors]
    if (
        saved_after is not None
        and validation.after is not None
        and validation.after.model_dump() != saved_after.model_dump()
    ):
        problems.append("story_model.after.json differs from base + delta merged again")
    passed = validation.passed and not problems
    write_json(
        run_dir / "validation.recheck.json",
        {
            **validation.to_json(),
            "passed": passed,
            "base_errors": problems,
            "checked_at": utc_now(),
            "note": "Offline re-check of base, delta, and merged result; the store was not "
            "read or changed.",
            "versions": environment_versions(),
        },
    )
    status = "passed" if passed else "failed"
    echo(describe_selection(chapter))
    echo(f"Output: {run_dir / 'validation.recheck.json'}")
    echo(
        f"Status: {status} ({len(validation.errors) + len(problems)} errors, "
        f"{len(validation.warnings)} warnings; commit status was {run.get('commit_status')})"
    )
    return Outcome(EXIT_OK if passed else EXIT_VALIDATION, status, run_dir)
