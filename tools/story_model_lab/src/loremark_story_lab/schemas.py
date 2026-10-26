"""Pydantic models: chapter input (built locally), LLM output, and the saved envelope.

The LLM output models only describe structure. Semantic rules (non-empty evidence, exact
quotes, ID references) live in validation.py so that a structurally valid but semantically
wrong candidate is still saved for analysis.
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict

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


# --- LLM output ----------------------------------------------------------------


class Evidence(_Strict):
    paragraph_id: str
    quote: str


class SupportedText(_Strict):
    text: str
    evidence: list[Evidence]


class Attribute(_Strict):
    label: str
    value: str
    assertion: Assertion
    attributed_to_id: str | None
    evidence: list[Evidence]


class Entity(_Strict):
    id: str
    name: SupportedText
    aliases: list[SupportedText]
    attributes: list[Attribute]


class Relationship(_Strict):
    id: str
    source_id: str
    target_id: str
    label: str
    description: str
    assertion: Assertion
    attributed_to_id: str | None
    temporal_context: TemporalContext
    evidence: list[Evidence]


class StoryEvent(_Strict):
    id: str
    description: str
    participant_ids: list[str]
    location_id: str | None
    narrative_order: int
    temporal_context: TemporalContext
    story_time: str | None
    assertion: Assertion
    attributed_to_id: str | None
    evidence: list[Evidence]


class Uncertainty(_Strict):
    question: str
    related_entity_ids: list[str]
    evidence: list[Evidence]


class ChapterStoryModel(_Strict):
    characters: list[Entity]
    locations: list[Entity]
    organizations: list[Entity]
    relationships: list[Relationship]
    events: list[StoryEvent]
    uncertainties: list[Uncertainty]


# --- saved envelope --------------------------------------------------------------


class StoryModelSource(_Strict):
    book_title: str
    book_sha256: str
    section_id: str
    chapter_number: int | None
    title: str
    source_href: str
    source_fragment: str | None
    text_sha256: str
    paragraph_count: int


class StoryModelEnvelope(_Strict):
    schema_version: Literal["1.0"] = SCHEMA_VERSION
    scope: Literal["single_chapter"] = "single_chapter"
    source: StoryModelSource
    model: ChapterStoryModel

    @classmethod
    def build(cls, chapter: ChapterInput, model: ChapterStoryModel) -> StoryModelEnvelope:
        return cls(
            source=StoryModelSource(
                book_title=chapter.book_title,
                book_sha256=chapter.book_sha256,
                section_id=chapter.section_id,
                chapter_number=chapter.chapter_number,
                title=chapter.title,
                source_href=chapter.source_href,
                source_fragment=chapter.source_fragment,
                text_sha256=chapter.text_sha256,
                paragraph_count=len(chapter.paragraphs),
            ),
            model=model,
        )
