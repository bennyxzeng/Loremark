from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest
from conftest import build_epub, create_store, xhtml

from loremark_story_lab import cli
from loremark_story_lab.artifacts import read_json
from loremark_story_lab.cli import main
from loremark_story_lab.story_store import StaleBaseError

pytestmark = pytest.mark.usefixtures("clean_env", "no_network")


def test_chapters_lists_sections(synthetic_epub: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["chapters", "--epub", str(synthetic_epub)]) == 0
    out = capsys.readouterr().out
    assert "TOC source: nav; 3 sections" in out
    assert "section-002" in out and "Chapter 3: The Lantern Ferry" in out
    assert "OEBPS/chapter3.xhtml" in out


def update_args(store: Path, epub: Path, *extra: str) -> list[str]:
    return ["update", "--store", str(store), "--epub", str(epub), *extra]


def test_dry_run_of_a_new_store_needs_no_key(
    tmp_path: Path, synthetic_epub: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    store, out = tmp_path / "store", tmp_path / "dry"
    assert (
        main(update_args(store, synthetic_epub, "--chapter", "3", "--dry-run", "--out", str(out)))
        == 0
    )
    assert {p.name for p in out.iterdir()} == {
        "chapter.json",
        "chapter.txt",
        "prompt.txt",
        "schema.json",
        "request.json",
        "context.json",
        "base_story_model.json",
        "run.json",
    }
    run = read_json(out / "run.json")
    assert run["status"] == "dry_run" and run["base_revision"] is None
    assert run["response"] is None and run["request"]["model"] is None
    chapter = read_json(out / "chapter.json")
    assert chapter["section_id"] == "section-002" and len(chapter["paragraphs"]) == 8
    stdout = capsys.readouterr().out
    assert "Selected section-002" in stdout and "Context: new store + section-002" in stdout
    assert "no store created" in stdout
    assert not store.exists()


@pytest.mark.parametrize(
    ("provider", "variable"), [("openai", "OPENAI_API_KEY"), ("deepseek", "DEEPSEEK_API_KEY")]
)
def test_update_without_key_fails_early(
    tmp_path: Path,
    synthetic_epub: Path,
    capsys: pytest.CaptureFixture[str],
    provider: str,
    variable: str,
) -> None:
    out = tmp_path / "live"
    args = ["--chapter", "3", "--provider", provider, "--model", "m", "--out", str(out)]
    assert main(update_args(tmp_path / "store", synthetic_epub, *args)) == 2
    assert variable in capsys.readouterr().err
    assert not out.exists() and not (tmp_path / "store").exists()


def test_existing_output_is_not_overwritten(
    tmp_path: Path, synthetic_epub: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    out = tmp_path / "used"
    out.mkdir()
    (out / "keep.txt").write_text("earlier result")
    args = ["--chapter", "3", "--dry-run", "--out", str(out)]
    assert main(update_args(tmp_path / "store", synthetic_epub, *args)) == 2
    assert "not empty" in capsys.readouterr().err
    assert (out / "keep.txt").read_text() == "earlier result"


def test_input_errors_exit_2(tmp_path: Path, synthetic_epub: Path) -> None:
    store = tmp_path / "store"
    assert main(update_args(store, synthetic_epub, "--chapter", "9", "--dry-run")) == 2
    assert main(update_args(store, synthetic_epub, "--dry-run")) == 2  # no starting section
    assert main(["chapters", "--epub", str(tmp_path / "missing.epub")]) == 2
    assert main(["validate", "--run", str(tmp_path)]) == 2
    assert main(["show", "--store", str(store)]) == 2
    with pytest.raises(SystemExit) as excinfo:
        main(update_args(store, synthetic_epub, "--chapter", "3", "--section", "x"))
    assert excinfo.value.code == 2


def test_module_entrypoint() -> None:
    result = subprocess.run(
        [sys.executable, "-m", "loremark_story_lab", "--help"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0
    for command in ("chapters", "update", "commit", "show", "validate"):
        assert command in result.stdout
    for removed in ("generate", "init", "extract"):
        assert removed not in result.stdout


def test_store_commands(
    tmp_path: Path, story_epub: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    store = create_store(tmp_path / "store", story_epub, tmp_path / "runs" / "chapter1")

    assert main(["show", "--store", str(store)]) == 0
    shown = capsys.readouterr().out
    assert "revision 1" in shown and "之前未处理的节：`section-001`" in shown
    assert main(["show", "--store", str(store), "--revision", "1", "--json"]) == 0
    assert json.loads(capsys.readouterr().out)["scope"] == "cumulative"

    dry = tmp_path / "dry"
    update = [*update_args(store, story_epub), "--provider", "deepseek"]
    assert main([*update, "--dry-run", "--out", str(dry)]) == 0
    assert read_json(dry / "run.json")["source"]["section_id"] == "section-003"
    assert "Context: prior revision 1 + section-003" in capsys.readouterr().out

    live = tmp_path / "live"
    assert main([*update, "--chapter", "2", "--model", "m", "--out", str(live)]) == 2
    assert "DEEPSEEK_API_KEY" in capsys.readouterr().err
    assert not live.exists()
    assert main([*update, "--chapter", "3", "--dry-run"]) == 2
    assert "would skip section-003" in capsys.readouterr().err
    assert main(["show", "--store", str(store), "--revision", "2"]) == 2


def test_bad_boundary_fails_before_any_request(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")
    monkeypatch.setenv("OPENAI_MODEL", "m")
    body = '<h2 id="c1">Chapter 1</h2><p>ONE</p><h2 id="c2">Chapter 2</h2><p>TWO</p>'
    nav = [("all.xhtml#c1", "Chapter 1"), ("all.xhtml#missing", "Chapter 2")]
    epub = build_epub(tmp_path / "b.epub", {"all.xhtml": xhtml(body)}, nav=nav)
    out = tmp_path / "run"

    assert main(update_args(tmp_path / "store", epub, "--chapter", "1", "--out", str(out))) == 2
    assert "cannot be extracted reliably" in capsys.readouterr().err
    assert not out.exists()
    assert main(["chapters", "--epub", str(epub)]) == 0
    assert "unsupported: TOC boundaries" in capsys.readouterr().out


def test_stale_base_exits_5(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    def stale(**kwargs: object) -> None:
        raise StaleBaseError("store changed")

    monkeypatch.setattr(cli, "run_commit_corrected", stale)
    assert main(["commit", "--run", "r", "--epub", "e"]) == 5
    assert "store changed" in capsys.readouterr().err
