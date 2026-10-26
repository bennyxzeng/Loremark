"""Prompt loading, chapter serialization, the Structured Outputs schema, and request params."""

from __future__ import annotations

import hashlib
import json
from importlib import resources
from pathlib import Path
from typing import Any

from openai.lib._parsing._responses import type_to_text_format_param

from .config import ConfigError, GenerateConfig
from .schemas import ChapterInput, ChapterStoryModel

BUILTIN_PROMPT = "extract_story_v1.txt"


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_json(value: Any) -> str:
    canonical = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return sha256_text(canonical)


def load_prompt(prompt_file: Path | None) -> tuple[str, str]:
    """Return (prompt text, source label)."""
    if prompt_file is None:
        text = resources.files("loremark_story_lab").joinpath("prompts", BUILTIN_PROMPT)
        return text.read_text(encoding="utf-8"), f"builtin:{BUILTIN_PROMPT}"
    try:
        text = prompt_file.read_text(encoding="utf-8")
    except OSError as exc:
        raise ConfigError(f"Cannot read prompt file {prompt_file}: {exc}") from exc
    if not text.strip():
        raise ConfigError(f"Prompt file {prompt_file} is empty")
    return text, str(prompt_file.resolve())


def serialize_chapter(chapter: ChapterInput) -> str:
    """The user message: identifiers of the selected section and its paragraphs only."""
    header = (
        f"Chapter section ID: {chapter.section_id}\n"
        f"Chapter title: {chapter.title}\n"
        f"Paragraph count: {len(chapter.paragraphs)}\n\n"
    )
    return header + "\n".join(f"[{p.id}] {p.text}" for p in chapter.paragraphs) + "\n"


def text_format() -> dict[str, Any]:
    """The exact `text.format` object the SDK sends for ChapterStoryModel."""
    return dict(type_to_text_format_param(ChapterStoryModel))


def build_request_params(
    chapter: ChapterInput, prompt_text: str, config: GenerateConfig
) -> dict[str, Any]:
    """Keyword arguments for `responses.parse`, except `text_format`."""
    params: dict[str, Any] = {
        "model": config.model,
        "input": [
            {"role": "system", "content": prompt_text},
            {"role": "user", "content": serialize_chapter(chapter)},
        ],
    }
    if config.max_output_tokens is not None:
        params["max_output_tokens"] = config.max_output_tokens
    if config.reasoning_effort is not None:
        params["reasoning"] = {"effort": config.reasoning_effort}
    if config.provider.sends_store_and_truncation:
        params["store"] = False
        params["truncation"] = "disabled"
    return params


def request_record(params: dict[str, Any], config: GenerateConfig) -> dict[str, Any]:
    """What request.json stores: semantic parameters and text, never credentials."""
    fmt = text_format()
    return {
        "endpoint": "POST /responses (client.responses.parse)",
        "provider": config.provider.name,
        "base_url": config.base_url,
        **params,
        "text": {
            "format": {
                "type": fmt["type"],
                "name": fmt["name"],
                "strict": fmt["strict"],
                "schema_file": "schema.json",
                "schema_sha256": sha256_json(fmt["schema"]),
            }
        },
        "client_options": {"timeout_seconds": config.timeout, "max_retries": config.max_retries},
    }
