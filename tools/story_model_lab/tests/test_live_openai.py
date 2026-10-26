"""Live API smoke tests. Skipped unless explicitly enabled; they only check the wiring.

RUN_LIVE_OPENAI=1   + OPENAI_API_KEY   + OPENAI_MODEL
RUN_LIVE_DEEPSEEK=1 + DEEPSEEK_API_KEY + DEEPSEEK_MODEL
"""

from __future__ import annotations

import os

import pytest

from loremark_story_lab.config import resolve_generate_config
from loremark_story_lab.openai_client import ResponsesClient, make_sdk_client
from loremark_story_lab.prompting import build_request_params, load_prompt
from loremark_story_lab.schemas import ChapterInput, Paragraph
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
