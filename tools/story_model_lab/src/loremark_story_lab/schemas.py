"""Pydantic models shared by the story model: the chapter input (built locally) and the
literal types its payloads use.

The story model itself and the StoryDelta the LLM returns are in cumulative_schemas.py.
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict

# Version of the chapter input format (inputs/*.json, chapter.json), not of the story model.
SCHEMA_VERSION = "1.0"

Assertion = Literal["explicit", "reported", "inferred"]
TemporalContext = Literal["current", "past", "future", "hypothetical", "unknown"]


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


# --- chapter input (code-generated, never filled by the model) ---------------


class Paragraph(_Strict):
    id: str
    text: str


class ChapterInput(_Strict):
    schema_version: Literal["1.0"] = SCHEMA_VERSION
    book_sha256: str
    book_title: str
    section_id: str
    chapter_number: int | None
    title: str
    source_href: str
    source_fragment: str | None
    paragraphs: list[Paragraph]
    text_sha256: str
    extraction_version: str
    omitted_image_count: int
    extraction_notes: list[str] = []
