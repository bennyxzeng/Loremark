"""Run directories, UTF-8 JSON files, and environment metadata."""

from __future__ import annotations

import json
import platform
import secrets
from datetime import UTC, datetime
from importlib import metadata
from pathlib import Path
from typing import Any

_TOOL_ROOT = Path(__file__).resolve().parents[2]


class OutputDirError(Exception):
    """The output directory cannot be used (exit code 2)."""


def utc_now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds").replace("+00:00", "Z")


def default_runs_root() -> Path:
    """tools/story_model_lab/runs when running from the source tree, else ./runs."""
    if (_TOOL_ROOT / "pyproject.toml").is_file():
        return _TOOL_ROOT / "runs"
    return Path.cwd() / "runs"


def new_run_id() -> str:
    return f"{datetime.now(UTC):%Y%m%dT%H%M%SZ}-{secrets.token_hex(3)}"


def prepare_output_dir(out: Path | None) -> Path:
    """Create the run directory; an explicit existing directory must be empty."""
    path = (out if out is not None else default_runs_root() / new_run_id()).resolve()
    if path.exists():
        if not path.is_dir():
            raise OutputDirError(f"{path} exists and is not a directory")
        if any(path.iterdir()):
            raise OutputDirError(f"{path} is not empty; refusing to overwrite earlier results")
    try:
        path.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise OutputDirError(f"Cannot create output directory {path}: {exc}") from exc
    return path


def write_json(path: Path, data: Any) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_text(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def environment_versions() -> dict[str, str | None]:
    def version(dist: str) -> str | None:
        try:
            return metadata.version(dist)
        except metadata.PackageNotFoundError:
            return None

    return {
        "python": platform.python_version(),
        "loremark-story-lab": version("loremark-story-lab"),
        "openai": version("openai"),
        "pydantic": version("pydantic"),
        "beautifulsoup4": version("beautifulsoup4"),
    }
