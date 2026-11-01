"""Live API smoke tests. Skipped unless explicitly enabled; they only check the wiring.

RUN_LIVE_OPENAI=1   + OPENAI_API_KEY   + OPENAI_MODEL
RUN_LIVE_DEEPSEEK=1 + DEEPSEEK_API_KEY + DEEPSEEK_MODEL
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest
from conftest import build_epub, xhtml

from loremark_story_lab.config import GenerateConfig, resolve_generate_config
from loremark_story_lab.cumulative_schemas import CumulativeStoryModel, RevisionInfo, StoryDelta
from loremark_story_lab.cumulative_validation import UpdateValidation, validate_update
from loremark_story_lab.epub import EpubBook, open_epub
from loremark_story_lab.incremental_pipeline import empty_model, plan_first_section, plan_update
from loremark_story_lab.openai_client import ResponsesClient, make_sdk_client
from loremark_story_lab.prompting import build_update_context, build_update_params, load_prompt
from loremark_story_lab.schemas import ChapterInput
from loremark_story_lab.story_store import section_source

pytestmark = pytest.mark.live

PROVIDERS = {
    "openai": ("RUN_LIVE_OPENAI", "OPENAI_API_KEY", "OPENAI_MODEL"),
    "deepseek": ("RUN_LIVE_DEEPSEEK", "DEEPSEEK_API_KEY", "DEEPSEEK_MODEL"),
}


def _tiny_book(tmp_path: Path) -> EpubBook:
    docs = {
        "ch1.xhtml": xhtml("<h1>Chapter 1</h1><p>The courier called Wren left the city.</p>"),
        "ch2.xhtml": xhtml(
            "<h1>Chapter 2</h1><p>Wren, whose real name was Ada Fenn, reached the coast.</p>"
        ),
    }
    nav = [("ch1.xhtml", "Chapter 1"), ("ch2.xhtml", "Chapter 2")]
    return open_epub(build_epub(tmp_path / "smoke.epub", docs, nav=nav, title="Live Smoke"))


def _update(
    client: ResponsesClient,
    config: GenerateConfig,
    base: CumulativeStoryModel,
    base_inputs: dict[str, ChapterInput],
    chapter: ChapterInput,
    order: int,
) -> UpdateValidation:
    prompt, _ = load_prompt(None)
    context = build_update_context(base, chapter, section_order=order)
    result = client.generate(build_update_params(context, prompt, config))
    assert result.status == "completed", result.error
    assert isinstance(result.parsed, StoryDelta)
    number = base.revision.number + 1
    section, _, _ = section_source(chapter, section_order=order, revision=number)
    validation = validate_update(
        base,
        result.candidate,
        chapter=chapter,
        base_inputs=base_inputs,
        section=section,
        revision=RevisionInfo(
            number=number,
            id=f"live{number}",
            created_at="now",
            source_run_id="live",
            parent_snapshot_path=None if number == 1 else "revisions/000001-live1.json",
            parent_sha256=None if number == 1 else "0" * 64,
        ),
    )
    print(f"\n{result.response_model} revision {number}: {validation.counts}; {validation.issues}")
    return validation


@pytest.mark.parametrize("provider", sorted(PROVIDERS))
def test_live_story_from_an_empty_model(provider: str, tmp_path: Path) -> None:
    flag, key_env, model_env = PROVIDERS[provider]
    if os.environ.get(flag) != "1" or not os.environ.get(key_env) or not os.environ.get(model_env):
        pytest.skip(f"set {flag}=1, {key_env} and {model_env} to run")

    config = resolve_generate_config(
        provider=provider, model=None, max_output_tokens=None, timeout=None, dry_run=False
    )
    client = ResponsesClient(make_sdk_client(config, config.api_key()))
    book = _tiny_book(tmp_path)
    plan = plan_first_section(book, chapter=1, section_id=None)
    first = _update(client, config, empty_model(book, plan), {}, plan.chapter, plan.section.order)
    assert first.structure_valid
    if not first.passed or first.after is None:
        pytest.skip("the first section did not pass validation; the second is not attempted")
    following = plan_update(first.after, book, chapter=None, section_id=None)
    inputs = {plan.chapter.section_id: plan.chapter}
    second = _update(
        client, config, first.after, inputs, following.chapter, following.section.order
    )
    assert second.structure_valid
