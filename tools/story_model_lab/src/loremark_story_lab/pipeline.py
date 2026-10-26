"""Single-chapter experiment flows behind the CLI commands."""

from __future__ import annotations

import time
from collections.abc import Callable, Mapping
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .artifacts import (
    environment_versions,
    prepare_output_dir,
    read_json,
    utc_now,
    write_json,
    write_text,
)
from .config import GenerateConfig
from .epub import EpubBook, Section, extract_section, open_epub, render_chapter_text, select_section
from .openai_client import CallResult, ResponsesClient, StoryModelClient, make_sdk_client
from .prompting import build_request_params, load_prompt, request_record, sha256_json, sha256_text
from .prompting import text_format as build_text_format
from .reporting import render_review
from .schemas import ChapterInput, StoryModelEnvelope
from .validation import VALIDATOR_VERSION, ValidationReport, validate_candidate

EXIT_OK = 0
EXIT_INPUT = 2
EXIT_API = 3
EXIT_VALIDATION = 4

# Run status -> exit code for every terminal state of `generate`.
STATUS_EXIT_CODES = {
    "dry_run": EXIT_OK,
    "succeeded": EXIT_OK,
    "validation_failed": EXIT_VALIDATION,
    "schema_invalid": EXIT_VALIDATION,
    "api_error": EXIT_API,
    "refusal": EXIT_API,
    "incomplete": EXIT_API,
    "failed": EXIT_API,
    "empty_output": EXIT_API,
}
_VALIDATION_STATUSES = {"succeeded", "validation_failed", "schema_invalid"}

ClientFactory = Callable[[GenerateConfig, str], StoryModelClient]
Echo = Callable[[str], None]


class RunInputError(Exception):
    """A saved run directory lacks what a command needs (exit code 2)."""


@dataclass
class Outcome:
    exit_code: int
    status: str
    run_dir: Path
    warnings: list[str] = field(default_factory=list)


def default_client_factory(config: GenerateConfig, api_key: str) -> StoryModelClient:
    return ResponsesClient(make_sdk_client(config, api_key))


def load_section(
    epub_path: Path, chapter: int | None, section_id: str | None
) -> tuple[EpubBook, Section, ChapterInput]:
    book = open_epub(epub_path)
    section = select_section(book, chapter=chapter, section_id=section_id)
    return book, section, extract_section(book, section)


def describe_selection(chapter: ChapterInput) -> str:
    number = f"Chapter {chapter.chapter_number}" if chapter.chapter_number is not None else "—"
    return (
        f"Selected {chapter.section_id} ({number}): {chapter.title!r} "
        f"[{chapter.source_href}, {len(chapter.paragraphs)} paragraphs]"
    )


def write_chapter_files(run_dir: Path, chapter: ChapterInput) -> None:
    write_json(run_dir / "chapter.json", chapter.model_dump(mode="json"))
    write_text(run_dir / "chapter.txt", render_chapter_text(chapter))


def run_extract(
    epub_path: Path, chapter: int | None, section_id: str | None, out: Path | None, echo: Echo
) -> Outcome:
    book, _, chapter_input = load_section(epub_path, chapter, section_id)
    echo(describe_selection(chapter_input))
    run_dir = prepare_output_dir(out)
    write_chapter_files(run_dir, chapter_input)
    echo(f"Output: {run_dir}")
    echo("Status: extracted")
    return Outcome(EXIT_OK, "extracted", run_dir, [*book.warnings, *chapter_input.extraction_notes])


def run_generate(
    *,
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
    book, _, chapter_input = load_section(epub_path, chapter, section_id)
    echo(describe_selection(chapter_input))
    prompt_text, prompt_source = load_prompt(prompt_file)
    api_key = "" if config.dry_run else config.api_key(env)

    run_dir = prepare_output_dir(out)
    params = build_request_params(chapter_input, prompt_text, config)
    text_format = build_text_format()
    write_chapter_files(run_dir, chapter_input)
    write_text(run_dir / "prompt.txt", prompt_text)
    write_json(run_dir / "schema.json", text_format["schema"])
    write_json(run_dir / "request.json", request_record(params, config))

    run = _new_run_record(run_dir, book, chapter_input, config, params, prompt_text, prompt_source)
    run["hashes"]["schema_sha256"] = sha256_json(text_format["schema"])
    warnings = [*book.warnings, *chapter_input.extraction_notes]

    if config.dry_run:
        _finish(run, "dry_run", started_clock)
        write_json(run_dir / "run.json", run)
        echo(f"Output: {run_dir}")
        echo("Status: dry_run (no request sent)")
        return Outcome(EXIT_OK, "dry_run", run_dir, warnings)

    write_json(run_dir / "run.json", run)
    echo(f"Output: {run_dir}")
    limit = "no timeout" if config.timeout is None else f"timeout {config.timeout:g}s"
    echo(f"Calling {config.provider.name} model {config.model!r} ({limit})...")
    try:
        result = client_factory(config, api_key).generate(params)
        status, report = _record_result(run_dir, run, chapter_input, result)
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
    _finish(run, status, started_clock)
    write_json(run_dir / "run.json", run)
    _write_review(run_dir, chapter_input, run, report)
    echo(f"Status: {status}")
    return Outcome(STATUS_EXIT_CODES[status], status, run_dir, warnings)


def run_validate(run_dir: Path, echo: Echo) -> Outcome:
    run_dir = run_dir.resolve()
    chapter_path, candidate_path = run_dir / "chapter.json", run_dir / "candidate.json"
    if not chapter_path.is_file():
        raise RunInputError(f"{chapter_path} not found; is this a run directory?")
    if not candidate_path.is_file():
        raise RunInputError(
            f"{candidate_path} not found; the run produced no parseable model output to validate"
        )
    chapter = ChapterInput.model_validate(read_json(chapter_path))
    run_path = run_dir / "run.json"
    run: dict[str, Any] = read_json(run_path) if run_path.is_file() else {"run_id": run_dir.name}

    report = _validate_and_save(run_dir, chapter, read_json(candidate_path))
    status = _validation_status(report)
    run["validation"] = _validation_summary(report)
    if run.get("status") in _VALIDATION_STATUSES:
        run["status"] = status
        run["exit_code"] = STATUS_EXIT_CODES[status]
    write_json(run_path, run)
    _write_review(run_dir, chapter, run, report)
    echo(describe_selection(chapter))
    echo(f"Output: {run_dir}")
    echo(f"Status: {status} ({len(report.errors)} errors, {len(report.warnings)} warnings)")
    return Outcome(STATUS_EXIT_CODES[status], status, run_dir)


# --- internals -------------------------------------------------------------------


def _new_run_record(
    run_dir: Path,
    book: EpubBook,
    chapter: ChapterInput,
    config: GenerateConfig,
    params: dict[str, Any],
    prompt_text: str,
    prompt_source: str,
) -> dict[str, Any]:
    return {
        "run_id": run_dir.name,
        "command": "generate",
        "status": "running",
        "exit_code": None,
        "started_at": utc_now(),
        "finished_at": None,
        "elapsed_seconds": None,
        "output_dir": str(run_dir),
        "source": {
            "epub_path": str(book.path),
            "book_sha256": book.sha256,
            "book_title": book.title,
            "toc_source": book.toc_source,
            "section_id": chapter.section_id,
            "chapter_number": chapter.chapter_number,
            "title": chapter.title,
            "source_href": chapter.source_href,
            "source_fragment": chapter.source_fragment,
            "paragraph_count": len(chapter.paragraphs),
            "character_count": sum(len(p.text) for p in chapter.paragraphs),
            "omitted_image_count": chapter.omitted_image_count,
            "extraction_version": chapter.extraction_version,
            "extraction_notes": chapter.extraction_notes,
            "epub_warnings": book.warnings,
        },
        "hashes": {
            "text_sha256": chapter.text_sha256,
            "prompt_sha256": sha256_text(prompt_text),
            "schema_sha256": None,
        },
        "prompt_source": prompt_source,
        "request": {
            "provider": config.provider.name,
            "base_url": config.base_url,
            "model": config.model,
            "max_output_tokens": config.max_output_tokens,
            "timeout_seconds": config.timeout,
            "reasoning_effort": config.reasoning_effort,
            "max_retries": config.max_retries,
            "store": params.get("store"),
            "truncation": params.get("truncation"),
            "dry_run": config.dry_run,
        },
        "response": None,
        "validation": None,
        "versions": environment_versions(),
    }


def _finish(run: dict[str, Any], status: str, started_clock: float) -> None:
    run["status"] = status
    run["exit_code"] = STATUS_EXIT_CODES.get(status)
    run["finished_at"] = utc_now()
    run["elapsed_seconds"] = round(time.monotonic() - started_clock, 3)


def _record_result(
    run_dir: Path, run: dict[str, Any], chapter: ChapterInput, result: CallResult
) -> tuple[str, ValidationReport | None]:
    run["response"] = {
        "status": result.status,
        "api_status": (result.response_body or {}).get("status"),
        "response_id": result.response_id,
        "request_id": result.request_id,
        "model": result.response_model,
        "usage": result.usage,
        "api_elapsed_seconds": result.elapsed_seconds,
        "retries_taken": result.retries_taken,
    }
    if result.response_body is not None:
        write_json(run_dir / "response.json", result.response_body)
    if result.candidate is not None:
        write_json(run_dir / "candidate.json", result.candidate)

    report = None
    if result.candidate is not None:
        report = _validate_and_save(run_dir, chapter, result.candidate)
        run["validation"] = _validation_summary(report)
    if result.status == "completed" and report is not None:
        return _validation_status(report), report

    status = "schema_invalid" if result.status == "parse_error" else result.status
    failure = {
        "status": status,
        "error": result.error,
        "response_id": result.response_id,
        "request_id": result.request_id,
        "usage": result.usage,
        "output_text": result.output_text if result.candidate is None else None,
    }
    write_json(run_dir / "failure.json", failure)
    return status, report


def _validate_and_save(run_dir: Path, chapter: ChapterInput, candidate: Any) -> ValidationReport:
    report = validate_candidate(candidate, chapter)
    write_json(run_dir / "validation.json", report.to_json())
    story_model_path = run_dir / "story_model.json"
    if report.passed and report.model is not None:
        envelope = StoryModelEnvelope.build(chapter, report.model)
        write_json(story_model_path, envelope.model_dump(mode="json"))
    elif story_model_path.exists():
        story_model_path.unlink()  # a stale story_model.json would claim a passing result
    return report


def _validation_status(report: ValidationReport) -> str:
    if report.passed:
        return "succeeded"
    return "validation_failed" if report.structure_valid else "schema_invalid"


def _validation_summary(report: ValidationReport) -> dict[str, Any]:
    return {
        "passed": report.passed,
        "structure_valid": report.structure_valid,
        "error_count": len(report.errors),
        "warning_count": len(report.warnings),
        "validator_version": VALIDATOR_VERSION,
        "validated_at": utc_now(),
    }


def _write_review(
    run_dir: Path, chapter: ChapterInput, run: dict[str, Any], report: ValidationReport | None
) -> None:
    failure_path = run_dir / "failure.json"
    failure = read_json(failure_path) if failure_path.is_file() else None
    if report is not None and report.passed:
        failure = None
    write_text(run_dir / "review.md", render_review(chapter, run, report, failure))
