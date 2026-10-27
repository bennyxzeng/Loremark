"""Live API smoke tests. Skipped unless explicitly enabled; they only check the wiring.

RUN_LIVE_OPENAI=1   + OPENAI_API_KEY   + OPENAI_MODEL
RUN_LIVE_DEEPSEEK=1 + DEEPSEEK_API_KEY + DEEPSEEK_MODEL
"""

from __future__ import annotations

import os

import pytest

from loremark_story_lab.config import resolve_generate_config
from loremark_story_lab.cumulative_schemas import RevisionInfo, StoryDelta
from loremark_story_lab.cumulative_validation import validate_update
from loremark_story_lab.epub import text_sha256
from loremark_story_lab.migration import migrate_model
from loremark_story_lab.openai_client import ResponsesClient, make_sdk_client
from loremark_story_lab.prompting import (
    UPDATE_PROMPT,
    build_request_params,
    build_update_context,
    build_update_params,
    load_prompt,
)
from loremark_story_lab.schemas import (
    ChapterInput,
    ChapterStoryModel,
    Paragraph,
    StoryModelEnvelope,
)
from loremark_story_lab.story_store import section_source
from loremark_story_lab.validation import validate_candidate

pytestmark = pytest.mark.live

PROVIDERS = {
    "openai": ("RUN_LIVE_OPENAI", "OPENAI_API_KEY", "OPENAI_MODEL"),
    "deepseek": ("RUN_LIVE_DEEPSEEK", "DEEPSEEK_API_KEY", "DEEPSEEK_MODEL"),
}


def _tiny_chapter() -> ChapterInput:
    texts = [
        "CHAPTER 1 THE BELL",
        "Ada Fenn rang the harbor bell at dawn.",
        "Her cousin Bram, a lighthouse keeper, waved from the cliff.",
    ]
    paragraphs = [Paragraph(id=f"p{i:04d}", text=t) for i, t in enumerate(texts, start=1)]
    return ChapterInput(
        book_sha256="0" * 64,
        book_title="Live Smoke",
        section_id="section-001",
        chapter_number=1,
        title="Chapter 1: The Bell",
        source_href="smoke.xhtml",
        source_fragment=None,
        paragraphs=paragraphs,
        text_sha256="0" * 64,
        extraction_version="1.0",
        omitted_image_count=0,
    )


@pytest.mark.parametrize("provider", sorted(PROVIDERS))
def test_live_structured_output(provider: str) -> None:
    flag, key_env, model_env = PROVIDERS[provider]
    if os.environ.get(flag) != "1" or not os.environ.get(key_env) or not os.environ.get(model_env):
        pytest.skip(f"set {flag}=1, {key_env} and {model_env} to run")

    config = resolve_generate_config(
        provider=provider,
        model=None,
        max_output_tokens=None,
        timeout=None,
        dry_run=False,
    )
    chapter = _tiny_chapter()
    prompt, _ = load_prompt(None)
    client = ResponsesClient(make_sdk_client(config, config.api_key()))
    result = client.generate(build_request_params(chapter, prompt, config))

    assert result.status == "completed", result.error
    assert result.parsed is not None
    assert result.usage is not None
    report = validate_candidate(result.candidate, chapter)
    assert report.structure_valid
    print(f"\n{provider} {result.response_model}: {report.counts}; issues={report.issues}")


def _chapter(section_id: str, number: int, texts: list[str]) -> ChapterInput:
    paragraphs = [Paragraph(id=f"p{i:04d}", text=t) for i, t in enumerate(texts, start=1)]
    return ChapterInput(
        book_sha256="0" * 64,
        book_title="Live Smoke",
        section_id=section_id,
        chapter_number=number,
        title=f"Chapter {number}",
        source_href=f"smoke{number}.xhtml",
        source_fragment=None,
        paragraphs=paragraphs,
        text_sha256=text_sha256(paragraphs),
        extraction_version="1.0",
        omitted_image_count=0,
    )


@pytest.mark.parametrize("provider", sorted(PROVIDERS))
def test_live_story_delta(provider: str) -> None:
    flag, key_env, model_env = PROVIDERS[provider]
    if os.environ.get(flag) != "1" or not os.environ.get(key_env) or not os.environ.get(model_env):
        pytest.skip(f"set {flag}=1, {key_env} and {model_env} to run")

    config = resolve_generate_config(
        provider=provider, model=None, max_output_tokens=None, timeout=None, dry_run=False
    )
    first = _chapter("section-001", 1, ["CHAPTER 1", "The courier called Wren left the city."])
    v1 = ChapterStoryModel.model_validate(
        {
            "characters": [
                {
                    "id": "c001",
                    "name": {
                        "text": "Wren",
                        "evidence": [{"paragraph_id": "p0002", "quote": "The courier called Wren"}],
                    },
                    "aliases": [],
                    "attributes": [],
                }
            ],
            "locations": [],
            "organizations": [],
            "relationships": [],
            "events": [],
            "uncertainties": [],
        }
    )
    source, _, _ = section_source(first, section_order=1, revision=1)
    base, _ = migrate_model(
        StoryModelEnvelope.build(first, v1),
        first,
        revision=RevisionInfo(
            number=1,
            id="live",
            created_at="now",
            source_run_id="live",
            parent_snapshot_path=None,
            parent_sha256=None,
        ),
        source=source,
        omitted_prefix=[],
        corrections=[],
    )
    second = _chapter(
        "section-002", 2, ["CHAPTER 2", "Wren, whose real name was Ada Fenn, reached the coast."]
    )
    prompt, _ = load_prompt(None, builtin=UPDATE_PROMPT)
    params = build_update_params(
        build_update_context(base, second, section_order=2), prompt, config
    )
    client = ResponsesClient(make_sdk_client(config, config.api_key()))
    result = client.generate(params, output_type=StoryDelta)

    assert result.status == "completed", result.error
    assert isinstance(result.parsed, StoryDelta)
    section, _, _ = section_source(second, section_order=2, revision=2)
    validation = validate_update(
        base,
        result.candidate,
        chapter=second,
        base_inputs={"section-001": first},
        section=section,
        revision=RevisionInfo(
            number=2,
            id="live2",
            created_at="now",
            source_run_id="live",
            parent_snapshot_path="revisions/000001-live.json",
            parent_sha256="0" * 64,
        ),
    )
    assert validation.structure_valid
    print(f"\n{provider} {result.response_model}: {validation.counts}; issues={validation.issues}")
