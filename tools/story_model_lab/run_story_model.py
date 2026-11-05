"""Run story-model with the settings below instead of typing command-line flags.

Edit the settings, then run this file with the lab's virtual environment:

tools/story_model_lab/.venv/bin/python tools/story_model_lab/run_story_model.py
tools/story_model_lab/.venv/bin/python tools/story_model_lab/run_story_model.py > story_model_latest.md

API keys come from tools/story_model_lab/.env (copy .env.example); variables already exported
in the shell take precedence.
"""

from __future__ import annotations

import os
import shlex
import sys
from enum import StrEnum
from pathlib import Path


class Command(StrEnum):
    CHAPTERS = "chapters"  # list sections in reading order
    UPDATE = "update"  # add the next section through the model; creates a missing store
    COMMIT = "commit"  # commit an update run after manual evidence corrections (offline)
    SHOW = "show"  # print a committed revision of a store (offline)
    VALIDATE = "validate"  # re-check a saved update run (offline)


class Model(StrEnum):
    GPT_6_1_TERRA = "gpt-6.1-terra"
    DEEPSEEK_FLASH = "deepseek-flash"


# The provider, and so which API key in .env is used, follows from the model.
PROVIDERS = {
    Model.GPT_6_1_TERRA: "openai",
    Model.DEEPSEEK_FLASH: "deepseek",
}


class Effort(StrEnum):
    """reasoning.effort: gpt-6.1-terra accepts all of these; DeepSeek accepts none/low/high/max
    and treats medium and xhigh as high."""

    NONE = "none"
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    XHIGH = "xhigh"
    MAX = "max"


# ---- Settings --------------------------------------------------------------------------------
# Relative paths are from the repository root. None or False leaves an option out.

COMMAND = Command.SHOW

# chapters, update, commit
EPUB = "sample_epub/86v1_chapters.epub"
# update, show; a missing or empty directory is created by the first update
STORE = "tools/story_model_lab/stores/86v1"

# update: CHAPTER and SECTION both None = the next section of the store. A new store needs
# one of them: its starting section (earlier sections are never covered).
CHAPTER: int | None = None  # chapter number recognized from its title
SECTION: str | None = None  # section ID shown by Command.CHAPTERS, e.g. "section-007"
OUT: str | None = None  # new or empty directory; None = tools/story_model_lab/runs/<time>-<id>

# update
MODEL = Model.GPT_6_1_TERRA
EFFORT: Effort | None = Effort.HIGH  # None = not sent; the model's default applies
MAX_OUTPUT_TOKENS: int | None = None  # None = no cap; the provider's limit applies
TIMEOUT: float | None = None  # seconds per request; None = wait indefinitely
PROMPT_FILE: str | None = None  # None = built-in prompt
DRY_RUN = False  # True = write the request files without calling the API
CHECK_QUOTES = False  # False = a quote not found in its paragraph is a warning, not a failure

# commit, validate: an update run directory
RUN: str | None = None

# show
REVISION: int | None = None  # None = latest
SHOW_JSON = False  # True = full JSON instead of Markdown
# ----------------------------------------------------------------------------------------------

LAB_DIR = Path(__file__).resolve().parent
REPO_ROOT = LAB_DIR.parents[1]


def load_env_file(path: Path) -> None:
    """Set the KEY=value lines of path as environment variables, keeping non-empty ones."""
    if not path.is_file():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.removeprefix("export ").strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
            value = value[1:-1]
        if value and not os.environ.get(key):
            os.environ[key] = value


def _update_options() -> dict[str, object]:
    return {
        "--store": STORE,
        "--epub": EPUB,
        "--chapter": CHAPTER,
        "--section": SECTION,
        "--out": OUT,
        "--provider": PROVIDERS[MODEL],
        "--model": MODEL,
        "--prompt-file": PROMPT_FILE,
        "--max-output-tokens": MAX_OUTPUT_TOKENS,
        "--timeout": TIMEOUT,
        "--reasoning-effort": EFFORT,
        "--dry-run": DRY_RUN,
        "--no-quote-check": not CHECK_QUOTES,
    }


def build_argv() -> list[str]:
    """Translate the settings into story-model arguments for COMMAND."""
    match COMMAND:
        case Command.CHAPTERS:
            options = {"--epub": EPUB}
        case Command.UPDATE:
            options = _update_options()
        case Command.VALIDATE:
            options = {"--run": RUN}
        case Command.COMMIT:
            options = {"--run": RUN, "--epub": EPUB}
        case Command.SHOW:
            options = {"--store": STORE, "--revision": REVISION, "--json": SHOW_JSON}
        case _:
            raise ValueError(f"unknown COMMAND {COMMAND!r}")
    argv = [str(COMMAND)]
    for flag, value in options.items():
        if value is True:
            argv.append(flag)
        elif value is not None and value is not False:
            argv += [flag, str(value)]
    return argv


def main() -> int:
    load_env_file(LAB_DIR / ".env")
    try:
        from loremark_story_lab.cli import main as story_model
    except ImportError:
        print(
            "error: loremark_story_lab is not installed for this Python; run this file with "
            "tools/story_model_lab/.venv/bin/python",
            file=sys.stderr,
        )
        return 2
    os.chdir(REPO_ROOT)
    argv = build_argv()
    # On stderr, so `> file` with Command.SHOW captures only the model.
    print(f"$ {shlex.join(['story-model', *argv])}", file=sys.stderr, flush=True)
    return story_model(argv)


if __name__ == "__main__":
    sys.exit(main())
