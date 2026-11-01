"""Run plumbing shared by the commands: exit codes, outcomes, the API client factory, and
the files and records every update run writes. The flows themselves are in
incremental_pipeline.py.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .artifacts import environment_versions, utc_now, write_json, write_text
from .config import GenerateConfig
from .epub import EpubBook, render_chapter_text
from .openai_client import CallResult, ResponsesClient, StoryModelClient, make_sdk_client
from .prompting import sha256_text
from .schemas import ChapterInput

EXIT_OK = 0
EXIT_INPUT = 2
EXIT_API = 3
EXIT_VALIDATION = 4
EXIT_STALE_BASE = 5

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


def describe_selection(chapter: ChapterInput) -> str:
    number = f"Chapter {chapter.chapter_number}" if chapter.chapter_number is not None else "—"
    return (
        f"Selected {chapter.section_id} ({number}): {chapter.title!r} "
        f"[{chapter.source_href}, {len(chapter.paragraphs)} paragraphs]"
    )


def write_chapter_files(run_dir: Path, chapter: ChapterInput) -> None:
    write_json(run_dir / "chapter.json", chapter.model_dump(mode="json"))
    write_text(run_dir / "chapter.txt", render_chapter_text(chapter))


def new_run_record(
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
        "command": "update",
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


def response_summary(result: CallResult) -> dict[str, Any]:
    return {
        "status": result.status,
        "api_status": (result.response_body or {}).get("status"),
        "response_id": result.response_id,
        "request_id": result.request_id,
        "model": result.response_model,
        "usage": result.usage,
        "api_elapsed_seconds": result.elapsed_seconds,
        "retries_taken": result.retries_taken,
    }


def failure_record(result: CallResult, status: str) -> dict[str, Any]:
    return {
        "status": status,
        "error": result.error,
        "response_id": result.response_id,
        "request_id": result.request_id,
        "usage": result.usage,
        "output_text": result.output_text if result.candidate is None else None,
    }
