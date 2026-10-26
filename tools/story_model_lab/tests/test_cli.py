from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

from loremark_story_lab.artifacts import read_json
from loremark_story_lab.cli import main

pytestmark = pytest.mark.usefixtures("clean_env", "no_network")


def test_chapters_lists_sections(synthetic_epub: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["chapters", "--epub", str(synthetic_epub)]) == 0
    out = capsys.readouterr().out
    assert "TOC source: nav; 3 sections" in out
    assert "section-002" in out and "Chapter 3: The Lantern Ferry" in out
    assert "OEBPS/chapter3.xhtml" in out


def test_extract_writes_chapter_input_only(
    tmp_path: Path, synthetic_epub: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    out = tmp_path / "input"
    assert (
        main(["extract", "--epub", str(synthetic_epub), "--chapter", "3", "--out", str(out)]) == 0
    )
    assert {p.name for p in out.iterdir()} == {"chapter.json", "chapter.txt"}
    chapter = read_json(out / "chapter.json")
    assert chapter["section_id"] == "section-002" and len(chapter["paragraphs"]) == 8
    stdout = capsys.readouterr().out
    assert "Selected section-002" in stdout and str(out.resolve()) in stdout


def test_extract_by_section_id(tmp_path: Path, synthetic_epub: Path) -> None:
    out = tmp_path / "prologue"
    assert (
        main(
            [
                "extract",
                "--epub",
                str(synthetic_epub),
                "--section",
                "section-001",
                "--out",
                str(out),
            ]
        )
        == 0
    )
    assert read_json(out / "chapter.json")["chapter_number"] is None


def test_dry_run_needs_no_key(tmp_path: Path, synthetic_epub: Path) -> None:
    out = tmp_path / "dry"
    code = main(
        [
            "generate",
            "--epub",
            str(synthetic_epub),
            "--chapter",
            "3",
            "--dry-run",
            "--out",
            str(out),
        ]
    )
    assert code == 0
    assert {p.name for p in out.iterdir()} == {
        "chapter.json",
        "chapter.txt",
        "prompt.txt",
        "schema.json",
        "request.json",
        "run.json",
    }
    run = read_json(out / "run.json")
    assert run["status"] == "dry_run"
    assert run["response"] is None and run["request"]["model"] is None


def test_generate_without_key_fails_early(
    tmp_path: Path, synthetic_epub: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    out = tmp_path / "live"
    code = main(
        [
            "generate",
            "--epub",
            str(synthetic_epub),
            "--chapter",
            "3",
            "--model",
            "m",
            "--out",
            str(out),
        ]
    )
    assert code == 2
    assert "OPENAI_API_KEY" in capsys.readouterr().err
    assert not out.exists()


def test_deepseek_without_key_names_its_variable(
    tmp_path: Path, synthetic_epub: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    code = main(
        [
            "generate",
            "--epub",
            str(synthetic_epub),
            "--chapter",
            "3",
            "--provider",
            "deepseek",
            "--model",
            "deepseek-flash",
        ]
    )
    assert code == 2
    assert "DEEPSEEK_API_KEY" in capsys.readouterr().err


def test_existing_output_is_not_overwritten(
    tmp_path: Path, synthetic_epub: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    out = tmp_path / "used"
    out.mkdir()
    (out / "keep.txt").write_text("earlier result")
    code = main(["extract", "--epub", str(synthetic_epub), "--chapter", "3", "--out", str(out)])
    assert code == 2
    assert "not empty" in capsys.readouterr().err
    assert (out / "keep.txt").read_text() == "earlier result"


def test_input_errors_exit_2(tmp_path: Path, synthetic_epub: Path) -> None:
    assert main(["extract", "--epub", str(synthetic_epub), "--chapter", "9"]) == 2
    assert main(["chapters", "--epub", str(tmp_path / "missing.epub")]) == 2
    assert main(["validate", "--run", str(tmp_path)]) == 2
    with pytest.raises(SystemExit) as excinfo:
        main(["extract", "--epub", str(synthetic_epub), "--chapter", "3", "--section", "x"])
    assert excinfo.value.code == 2


def test_module_entrypoint() -> None:
    result = subprocess.run(
        [sys.executable, "-m", "loremark_story_lab", "--help"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0
    assert "chapters" in result.stdout and "generate" in result.stdout
