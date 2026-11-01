"""Run story-model with the settings below instead of typing command-line flags.

Edit the settings, then run this file with the lab's virtual environment:

    tools/story_model_lab/.venv/bin/python tools/story_model_lab/run_story_model.py

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
    EXTRACT = "extract"  # write the chapter input only (offline)
    GENERATE = "generate"  # run one chapter through the model
    VALIDATE = "validate"  # re-check a saved generate or update run (offline)
    INIT = "init"  # start a cumulative store from a generate run (offline)
    UPDATE = "update"  # add the next section to a cumulative store through the model
    COMMIT = "commit"  # commit an update run after manual evidence corrections (offline)
    SHOW = "show"  # print a committed revision of a store (offline)


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

COMMAND = Command.UPDATE

# chapters, extract, generate, update, init, commit
EPUB = "sample_epub/86v1_chapters.epub"
# init, update, show
STORE = "tools/story_model_lab/stores/86v1"

# extract, generate, update: set one of CHAPTER / SECTION and the other to None
CHAPTER: int | None = 3  # chapter number recognized from its title
SECTION: str | None = None  # section ID shown by Command.CHAPTERS, e.g. "section-007"
OUT: str | None = None  # new or empty directory; None = tools/story_model_lab/runs/<time>-<id>

# generate, update
MODEL = Model.DEEPSEEK_FLASH
EFFORT: Effort | None = None  # None = not sent; the model's default applies
MAX_OUTPUT_TOKENS: int | None = None  # None = no cap; the provider's limit applies
TIMEOUT: float | None = None  # seconds per request; None = wait indefinitely
PROMPT_FILE: str | None = None  # None = built-in prompt
DRY_RUN = False  # True = write the request files without calling the API

# validate, commit: a run directory
RUN: str | None = None
# init: the generate run to start the store from
FROM_RUN: str | None = None

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


def _selection() -> dict[str, object]:
    return {"--epub": EPUB, "--chapter": CHAPTER, "--section": SECTION, "--out": OUT}


def _model_options() -> dict[str, object]:
    return {
        "--provider": PROVIDERS[MODEL],
        "--model": MODEL,
        "--prompt-file": PROMPT_FILE,
        "--max-output-tokens": MAX_OUTPUT_TOKENS,
        "--timeout": TIMEOUT,
        "--reasoning-effort": EFFORT,
        "--dry-run": DRY_RUN,
    }


def build_argv() -> list[str]:
    """Translate the settings into story-model arguments for COMMAND."""
    match COMMAND:
        case Command.CHAPTERS:
            options = {"--epub": EPUB}
        case Command.EXTRACT:
            options = _selection()
        case Command.GENERATE:
            options = _selection() | _model_options()
        case Command.UPDATE:
            options = {"--store": STORE} | _selection() | _model_options()
        case Command.VALIDATE:
            options = {"--run": RUN}
        case Command.INIT:
            options = {"--from-run": FROM_RUN, "--store": STORE, "--epub": EPUB}
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
    print(f"$ {shlex.join(['story-model', *argv])}", flush=True)
    return story_model(argv)


if __name__ == "__main__":
    sys.exit(main())
