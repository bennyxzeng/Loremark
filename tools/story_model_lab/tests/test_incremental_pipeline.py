"""`update` end to end against the real OpenAI SDK, with HTTP served by httpx2.MockTransport."""

from __future__ import annotations

import copy
import json
from pathlib import Path
from typing import Any

import httpx2
import pytest
from conftest import (
    STORY,
    FakeApi,
    build_epub,
    build_story_epub,
    chapter_xhtml,
    json_response,
    response_body,
    story_chapter,
    tree_hashes,
    write_v1_run,
    xhtml,
)

from loremark_story_lab import incremental_pipeline, story_store
from loremark_story_lab.artifacts import read_json, write_json
from loremark_story_lab.config import resolve_generate_config
from loremark_story_lab.cumulative_schemas import StoryDelta
from loremark_story_lab.epub import EpubError
from loremark_story_lab.incremental_pipeline import (
    UpdateInputError,
    run_commit_corrected,
    run_init,
    run_show,
    run_update,
)
from loremark_story_lab.pipeline import Outcome, RunInputError, run_validate
from loremark_story_lab.prompting import text_format
from loremark_story_lab.story_store import StaleBaseError, StoreError, load_store

pytestmark = pytest.mark.usefixtures("clean_env", "no_network")

DEEPSEEK_ENV = {"DEEPSEEK_API_KEY": "ds-test-secret", "DEEPSEEK_MODEL": "deepseek-flash"}
COMMITTED_FILES = {
    "chapter.json",
    "chapter.txt",
    "prompt.txt",
    "schema.json",
    "request.json",
    "context.json",
    "base_story_model.json",
    "base_inputs",
    "run.json",
    "response.json",
    "delta.candidate.json",
    "validation.json",
    "delta.json",
    "id_map.json",
    "story_model.after.json",
    "diff.md",
    "review.md",
}


@pytest.fixture
def store(tmp_path: Path, v1_run: Path) -> Path:
    root = tmp_path / "store"
    run_init(from_run=v1_run, store_root=root, epub_path=None, echo=lambda _: None)
    return root


def delta_api(delta: dict[str, Any]) -> FakeApi:
    return FakeApi(json_response(response_body(json.dumps(delta))))


def update(
    store: Path,
    epub: Path,
    api: FakeApi,
    out: Path | None,
    *,
    chapter: int | None = 2,
    section: str | None = None,
    dry_run: bool = False,
) -> Outcome:
    config = resolve_generate_config(
        provider="deepseek",
        model=None,
        max_output_tokens=None,
        timeout=None,
        dry_run=dry_run,
        env=DEEPSEEK_ENV,
    )
    return run_update(
        store_root=store,
        epub_path=epub,
        chapter=None if section else chapter,
        section_id=section,
        config=config,
        out=out,
        prompt_file=None,
        echo=lambda _: None,
        client_factory=api,
        env=DEEPSEEK_ENV,
    )


def show(store: Path, revision: int | None = None) -> str:
    lines: list[str] = []
    run_show(store_root=store, revision=revision, as_json=False, echo=lines.append)
    return "\n".join(lines)


def test_dry_run_writes_the_request_and_leaves_the_store(
    tmp_path: Path, store: Path, story_epub: Path, ch2_delta
) -> None:
    before = tree_hashes(store)
    api = delta_api(ch2_delta)
    outcome = update(store, story_epub, api, tmp_path / "dry", dry_run=True)

    assert outcome.exit_code == 0 and outcome.status == "dry_run"
    assert {p.name for p in outcome.run_dir.iterdir()} == {
        "chapter.json",
        "chapter.txt",
        "prompt.txt",
        "schema.json",
        "request.json",
        "context.json",
        "base_story_model.json",
        "base_inputs",
        "run.json",
    }
    assert api.requests == []
    assert tree_hashes(store) == before
    run = read_json(outcome.run_dir / "run.json")
    assert (run["status"], run["commit_status"], run["candidate_revision"]) == (
        "dry_run",
        "not_attempted",
        None,
    )
    assert read_json(outcome.run_dir / "schema.json") == text_format(StoryDelta)["schema"]
    assert read_json(outcome.run_dir / "request.json")["text"]["format"]["name"] == "StoryDelta"


def test_update_sends_prior_model_and_new_section_and_commits(
    tmp_path: Path, store: Path, story_epub: Path, ch2_delta
) -> None:
    revision_one = show(store, 1)
    first_snapshot = load_store(store).snapshot_path
    snapshot_bytes = (store / first_snapshot).read_bytes()
    api = delta_api(ch2_delta)
    outcome = update(store, story_epub, api, tmp_path / "run")

    assert outcome.exit_code == 0 and outcome.status == "committed"
    run_dir = outcome.run_dir
    assert {p.name for p in run_dir.iterdir()} == COMMITTED_FILES

    raw = api.requests[0].content.decode("utf-8")
    sent = api.body()
    system, user = sent["input"]
    assert system["role"] == "system" and "PRIOR_STORY_MODEL" in system["content"]
    assert '"id":"f000013"' in user["content"]
    assert "Ilse and the Grey Fox were sworn enemies." in user["content"]
    assert "[p0004] The Grey Fox pulled back his hood" in user["content"]
    for absent in (
        "CHAPTER-THREE-SENTINEL",
        "INTERLUDE-SENTINEL",
        "PROLOGUE-SENTINEL",
        "humming an old song",  # Chapter 1 text that no record quotes
        "Synthetic Story",
    ):
        assert absent not in raw
    assert sent["text"]["format"]["name"] == "StoryDelta"
    assert sent["text"]["format"]["schema"] == read_json(run_dir / "schema.json")
    assert read_json(run_dir / "context.json")["NEW_SECTION"]["section_id"] == "section-003"

    run = read_json(run_dir / "run.json")
    assert run["base_revision"]["number"] == 1
    assert run["candidate_revision"]["number"] == run["committed_revision"]["number"] == 2
    assert (run["commit_status"], run["report_status"]) == ("committed", "complete")
    assert run["response"]["response_id"] == "resp_test123"

    state = load_store(store)
    assert state.model.revision.number == 2
    assert (store / "story_model.json").read_bytes() == (
        run_dir / "story_model.after.json"
    ).read_bytes()
    assert (store / first_snapshot).read_bytes() == snapshot_bytes
    provenance = store / "provenance" / run_dir.name
    assert {p.name for p in provenance.iterdir()} == {
        "delta.candidate.json",
        "delta.json",
        "id_map.json",
        "commit.json",
        "manifest.json",
    }
    assert (
        read_json(provenance / "commit.json")["base_revision"]["sha256"]
        == run["hashes"]["base_sha256"]
    )

    latest = show(store)
    assert "Mara Quill" in latest and "Captain" in latest and "已合并" in latest
    assert "The Grey Fox is Petr Lask." in latest
    # Revision 1 is shown exactly as before the update, with nothing from Chapter 2.
    assert show(store, 1) == revision_one
    for later in ("Mara Quill", "Captain Ilse Varga", "已合并", "The Grey Fox is Petr Lask."):
        assert later not in revision_one
    review = (run_dir / "review.md").read_text(encoding="utf-8")
    assert "已提交为 revision 2" in review and "t000001" in review
    diff = (run_dir / "diff.md").read_text(encoding="utf-8")
    assert "Lieutenant" in diff and "Captain" in diff


def _network_error(request: httpx2.Request) -> httpx2.Response:
    raise httpx2.ConnectError("connection refused", request=request)


def _bad_target(delta: dict[str, Any]) -> dict[str, Any]:
    delta["transitions"][0]["target_record_id"] = "f999999"
    return delta


@pytest.mark.parametrize(
    ("handler", "status", "exit_code"),
    [
        (json_response(response_body(refusal="I can't help with that.")), "refusal", 3),
        (
            json_response(
                response_body(
                    '{"new_entities": [', status="incomplete", incomplete_reason="max_output_tokens"
                )
            ),
            "incomplete",
            3,
        ),
        (json_response(response_body("not json")), "schema_invalid", 4),
        (
            json_response(response_body(json.dumps({"new_entities": [], "extra": 1}))),
            "schema_invalid",
            4,
        ),
        ("bad_target", "validation_failed", 4),
        (_network_error, "api_error", 3),
    ],
    ids=["refusal", "incomplete", "invalid-json", "schema-mismatch", "reference", "network"],
)
def test_failures_keep_diagnostics_and_never_touch_the_store(
    tmp_path: Path, store: Path, story_epub: Path, ch2_delta, handler, status: str, exit_code: int
) -> None:
    if handler == "bad_target":
        handler = json_response(response_body(json.dumps(_bad_target(ch2_delta))))
    before = tree_hashes(store)
    outcome = update(store, story_epub, FakeApi(handler), tmp_path / "run")

    assert (outcome.status, outcome.exit_code) == (status, exit_code)
    assert tree_hashes(store) == before
    run = read_json(outcome.run_dir / "run.json")
    assert run["commit_status"] == "not_attempted" and run["committed_revision"] is None
    assert (outcome.run_dir / "failure.json").is_file()
    assert (outcome.run_dir / "review.md").is_file()
    assert not (outcome.run_dir / "story_model.after.json").exists()
    if status == "validation_failed":
        assert read_json(outcome.run_dir / "delta.candidate.json") == ch2_delta
        assert read_json(outcome.run_dir / "validation.json")["passed"] is False


def test_same_section_again_is_already_processed_without_a_request(
    tmp_path: Path, store: Path, story_epub: Path, ch2_delta
) -> None:
    update(store, story_epub, delta_api(ch2_delta), tmp_path / "run")
    before = tree_hashes(store)
    api = delta_api(ch2_delta)
    outcome = update(store, story_epub, api, tmp_path / "again")

    assert (outcome.status, outcome.exit_code) == ("already_processed", 0)
    assert api.requests == []
    assert tree_hashes(store) == before
    assert not (tmp_path / "again").exists()


def test_order_and_book_are_checked_before_any_request(
    tmp_path: Path, store: Path, story_epub: Path, ch2_delta, monkeypatch: pytest.MonkeyPatch
) -> None:
    api = delta_api(ch2_delta)
    other = build_story_epub(
        tmp_path / "other.epub", chapter2=xhtml("<h1>CHAPTER 2</h1><p>Other.</p>")
    )
    with pytest.raises(UpdateInputError, match="SHA-256"):
        update(store, other, api, tmp_path / "x")
    with pytest.raises(UpdateInputError, match="would skip section-003"):
        update(store, story_epub, api, tmp_path / "x", chapter=3)
    with pytest.raises(UpdateInputError, match="comes before section-002"):
        update(store, story_epub, api, tmp_path / "x", section="section-001")

    real_extract = incremental_pipeline.extract_section

    def changed_text(book, section):
        chapter = real_extract(book, section)
        return chapter.model_copy(update={"text_sha256": "f" * 64})

    monkeypatch.setattr(incremental_pipeline, "extract_section", changed_text)
    with pytest.raises(UpdateInputError, match="re-processing a section is not supported"):
        update(store, story_epub, api, tmp_path / "x", section="section-002")
    monkeypatch.undo()

    update(store, story_epub, api, tmp_path / "ch2")
    # The interlude after Chapter 2 cannot be skipped by asking for Chapter 3.
    with pytest.raises(UpdateInputError, match=r"would skip section-004 \('Interlude: The Lamp'\)"):
        update(store, story_epub, api, tmp_path / "x", chapter=3)
    assert len(api.requests) == 1
    assert not (tmp_path / "x").exists()


def test_unreliable_next_section_is_rejected_before_any_request(tmp_path: Path) -> None:
    rest = chapter_xhtml(STORY / "chapter2.txt").replace("<h1>", '<h1 id="c2">', 1)
    rest = rest.replace("</body>", "<h1>Interlude</h1><p>INTERLUDE-SENTINEL</p></body>")
    epub = build_epub(
        tmp_path / "broken.epub",
        {
            "prologue.xhtml": xhtml("<h1>Prologue</h1><p>PROLOGUE-SENTINEL</p>"),
            "ch1.xhtml": chapter_xhtml(STORY / "chapter1.txt"),
            "rest.xhtml": rest,
        },
        nav=[
            ("prologue.xhtml", "Prologue"),
            ("ch1.xhtml", "Chapter 1: The Signal"),
            ("rest.xhtml#c2", "Chapter 2: The Storm"),
            ("rest.xhtml#missing", "Interlude: The Lamp"),
        ],
    )
    store = tmp_path / "store"
    run_init(
        from_run=write_v1_run(tmp_path / "run", epub), store_root=store, epub_path=None, echo=print
    )
    api = delta_api({})
    with pytest.raises(EpubError, match="cannot be extracted reliably"):
        update(store, epub, api, tmp_path / "x")
    assert api.requests == []


def test_concurrent_update_from_the_same_base_is_stale(
    tmp_path: Path, store: Path, story_epub: Path, ch2_delta
) -> None:
    other = delta_api(ch2_delta)
    winner: list[Outcome] = []

    def slow_response(request: httpx2.Request) -> httpx2.Response:
        # While this request is "in flight", another update of the same base commits first.
        winner.append(update(store, story_epub, other, tmp_path / "winner"))
        return json_response(response_body(json.dumps(ch2_delta)))(request)

    outcome = update(store, story_epub, FakeApi(slow_response), tmp_path / "loser")

    assert winner[0].status == "committed"
    assert (outcome.status, outcome.exit_code) == ("stale_base", 5)
    run = read_json(outcome.run_dir / "run.json")
    assert run["commit_status"] == "stale_base" and run["committed_revision"] is None
    state = load_store(store)
    assert state.model.revision.source_run_id == "winner"
    assert (
        state.model.revision.id
        == read_json(winner[0].run_dir / "run.json")["committed_revision"]["id"]
    )


@pytest.mark.parametrize("where", ["snapshot", "replace"])
def test_commit_failures_report_the_store_unchanged(
    tmp_path: Path,
    store: Path,
    story_epub: Path,
    ch2_delta,
    monkeypatch: pytest.MonkeyPatch,
    where: str,
) -> None:
    before = tree_hashes(store)
    if where == "snapshot":
        real_write = story_store._write_file

        def write(path: Path, data: bytes) -> None:
            if path.parent.name == "revisions":
                raise OSError("injected")
            real_write(path, data)

        monkeypatch.setattr(story_store, "_write_file", write)
    else:
        real_replace = story_store.os.replace

        def replace(src, dst) -> None:
            if Path(dst).name == "story_model.json":
                raise OSError("injected")
            real_replace(src, dst)

        monkeypatch.setattr(story_store.os, "replace", replace)
    outcome = update(store, story_epub, delta_api(ch2_delta), tmp_path / "run")
    monkeypatch.undo()

    assert (outcome.status, outcome.exit_code) == ("commit_failed", 2)
    assert read_json(outcome.run_dir / "run.json")["commit_status"] == "failed"
    assert (store / "story_model.json").read_bytes() == load_store(store).latest_bytes
    assert load_store(store).model.revision.number == 1
    assert {k: v for k, v in tree_hashes(store).items() if k in before} == before


def test_report_failure_after_commit_is_not_reported_as_a_failed_update(
    tmp_path: Path, store: Path, story_epub: Path, ch2_delta, monkeypatch: pytest.MonkeyPatch
) -> None:
    def broken(*args: object) -> str:
        raise RuntimeError("report renderer crashed (injected)")

    monkeypatch.setattr(incremental_pipeline, "render_update_review", broken)
    outcome = update(store, story_epub, delta_api(ch2_delta), tmp_path / "run")
    monkeypatch.undo()

    assert (outcome.status, outcome.exit_code) == ("committed_report_failed", 0)
    assert any("was committed" in w for w in outcome.warnings)
    run = read_json(outcome.run_dir / "run.json")
    assert (run["commit_status"], run["report_status"]) == ("committed", "failed")
    assert load_store(store).model.revision.number == 2

    api = delta_api(ch2_delta)
    again = update(store, story_epub, api, tmp_path / "again")
    assert again.status == "already_processed" and api.requests == []
    assert load_store(store).model.revision.number == 2


def test_validate_rechecks_an_update_run_without_touching_the_store(
    tmp_path: Path, store: Path, story_epub: Path, ch2_delta
) -> None:
    run_dir = update(store, story_epub, delta_api(ch2_delta), tmp_path / "run").run_dir
    before_store = tree_hashes(store)
    before_run = tree_hashes(run_dir)

    outcome = run_validate(run_dir, lambda _: None)
    assert (outcome.status, outcome.exit_code) == ("passed", 0)
    assert tree_hashes(store) == before_store
    assert {k: v for k, v in tree_hashes(run_dir).items() if k in before_run} == before_run
    assert read_json(run_dir / "validation.recheck.json")["passed"] is True

    ch2_delta["new_records"]["names"][0]["evidence"][0]["quote"] = "invented"
    (run_dir / "delta.candidate.json").write_text(json.dumps(ch2_delta), encoding="utf-8")
    outcome = run_validate(run_dir, lambda _: None)
    assert (outcome.status, outcome.exit_code) == ("failed", 4)
    assert tree_hashes(store) == before_store
    assert load_store(store).model.revision.number == 2


def test_show_reads_only_committed_revisions(
    tmp_path: Path, store: Path, story_epub: Path, ch2_delta
) -> None:
    update(store, story_epub, delta_api(ch2_delta), tmp_path / "run")
    before = tree_hashes(store)
    lines: list[str] = []
    run_show(store_root=store, revision=1, as_json=True, echo=lines.append)
    data = json.loads(lines[0])
    assert data["schema_version"] == "2.0" and data["revision"]["number"] == 1
    assert data["current"]["resolved_uncertainty_ids"] == []
    with pytest.raises(StoreError, match="not in the committed history"):
        show(store, 3)
    assert tree_hashes(store) == before


def test_chapter_two_input_matches_the_fixture(story_epub: Path) -> None:
    chapter = story_chapter(story_epub, "section-003")
    expected = (STORY / "chapter2.txt").read_text(encoding="utf-8").splitlines()
    assert [f"[{p.id}] {p.text}" for p in chapter.paragraphs] == expected


# --- committing a manually corrected run ----------------------------------------------------

CORRECTIONS = [
    {
        "path": "new_records.names[0].evidence[0].paragraph_id",
        "from": "p0007",
        "to": "p0006",
        "reason": "The quote occurs verbatim in p0006",
        "corrected_by": "test",
        "corrected_at": "2026-10-26T00:00:00Z",
    },
    {
        "path": "new_records.events[0].evidence[0].quote",
        "from": "the storm wrecked harbor",
        "to": "the storm wrecked the harbor",
        "reason": "The model dropped a word",
        "corrected_by": "test",
        "corrected_at": "2026-10-26T00:00:00Z",
    },
]


def failed_run(tmp_path: Path, store: Path, epub: Path, delta: dict[str, Any]) -> Path:
    bad = copy.deepcopy(delta)
    bad["new_records"]["names"][0]["evidence"][0]["paragraph_id"] = "p0007"
    bad["new_records"]["events"][0]["evidence"][0]["quote"] = "the storm wrecked harbor"
    outcome = update(store, epub, delta_api(bad), tmp_path / "failed")
    assert outcome.status == "validation_failed"
    return outcome.run_dir


def commit(run_dir: Path, epub: Path) -> Outcome:
    return run_commit_corrected(run_dir=run_dir, epub_path=epub, echo=lambda _: None)


def test_corrected_run_commits_and_records_every_correction(
    tmp_path: Path, store: Path, story_epub: Path, ch2_delta
) -> None:
    run_dir = failed_run(tmp_path, store, story_epub, ch2_delta)
    raw = (run_dir / "delta.candidate.json").read_bytes()
    original_validation = (run_dir / "validation.json").read_bytes()
    write_json(run_dir / "manual_corrections.json", CORRECTIONS)

    outcome = commit(run_dir, story_epub)

    assert (outcome.status, outcome.exit_code) == ("committed", 0)
    assert (run_dir / "delta.candidate.json").read_bytes() == raw
    assert (run_dir / "validation.json").read_bytes() == original_validation
    run = read_json(run_dir / "run.json")
    assert (run["commit_status"], run["original_status"]) == ("committed", "validation_failed")
    assert run["validation"]["passed"] is False and run["corrected_validation"]["passed"] is True
    assert len(run["manual_corrections"]) == 2

    state = load_store(store)
    assert state.model.revision.number == 2
    recorded = state.model.provenance.update_manual_corrections
    assert [(c.revision, c.record_id, c.original, c.corrected) for c in recorded] == [
        (2, "f000023", "p0007", "p0006"),
        (2, "f000031", "the storm wrecked harbor", "the storm wrecked the harbor"),
    ]
    provenance = store / "provenance" / run_dir.name
    for name in ("manual_corrections.json", "delta.corrected.json", "validation.json"):
        assert (provenance / name).is_file()
    assert read_json(provenance / "delta.candidate.json") == read_json(
        run_dir / "delta.candidate.json"
    )
    assert "revision 2 的增量含 2 处人工修正" in show(store)
    assert "的增量含" not in show(store, 1)
    assert "不是模型原样输出" in (run_dir / "review.md").read_text(encoding="utf-8")

    with pytest.raises(RunInputError, match="already committed"):
        commit(run_dir, story_epub)
    again = update(store, story_epub, delta_api(ch2_delta), tmp_path / "again")
    assert again.status == "already_processed"


@pytest.mark.parametrize(
    ("edit", "message"),
    [
        (lambda c: c[0].update(path="new_records.names[0].payload.text"), "never facts"),
        (lambda c: c[0].update(**{"from": "p0005"}), "not 'p0005'"),
        (
            lambda c: c[0].update(path="new_records.names[9].evidence[0].paragraph_id"),
            "does not exist",
        ),
        (lambda c: c[0].pop("reason"), "needs exactly these keys"),
        (lambda c: c.append(dict(c[0])), "corrected twice"),
    ],
    ids=["fact", "stale-from", "missing-path", "missing-key", "twice"],
)
def test_unacceptable_corrections_are_refused(
    tmp_path: Path, store: Path, story_epub: Path, ch2_delta, edit, message: str
) -> None:
    run_dir = failed_run(tmp_path, store, story_epub, ch2_delta)
    corrections = copy.deepcopy(CORRECTIONS)
    edit(corrections)
    write_json(run_dir / "manual_corrections.json", corrections)
    before = tree_hashes(store)
    with pytest.raises(RunInputError, match=message):
        commit(run_dir, story_epub)
    assert tree_hashes(store) == before


def test_incomplete_corrections_are_not_committed(
    tmp_path: Path, store: Path, story_epub: Path, ch2_delta
) -> None:
    run_dir = failed_run(tmp_path, store, story_epub, ch2_delta)
    write_json(run_dir / "manual_corrections.json", CORRECTIONS[:1])
    before = tree_hashes(store)
    outcome = commit(run_dir, story_epub)
    assert (outcome.status, outcome.exit_code) == ("validation_failed", 4)
    assert (run_dir / "validation.corrected.json").is_file()
    assert tree_hashes(store) == before
    assert read_json(run_dir / "run.json")["commit_status"] == "not_attempted"


def test_corrections_do_not_apply_after_the_store_moved(
    tmp_path: Path, store: Path, story_epub: Path, ch2_delta
) -> None:
    run_dir = failed_run(tmp_path, store, story_epub, ch2_delta)
    write_json(run_dir / "manual_corrections.json", CORRECTIONS)
    assert update(store, story_epub, delta_api(ch2_delta), tmp_path / "other").status == "committed"
    with pytest.raises(StaleBaseError, match="moved on"):
        commit(run_dir, story_epub)
