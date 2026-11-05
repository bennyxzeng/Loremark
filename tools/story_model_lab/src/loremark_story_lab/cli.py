"""Command line entry point: chapters / update / commit / show / validate."""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from pathlib import Path

from .artifacts import OutputDirError
from .config import PROVIDERS, ConfigError, GenerateConfig, resolve_generate_config
from .epub import EpubError, extract_section, open_epub
from .incremental_pipeline import (
    UpdateInputError,
    run_commit_corrected,
    run_show,
    run_update,
    validate_update_run,
)
from .pipeline import EXIT_INPUT, EXIT_OK, EXIT_STALE_BASE, RunInputError
from .story_store import StaleBaseError, StoreError

INPUT_ERRORS = (
    EpubError,
    ConfigError,
    OutputDirError,
    RunInputError,
    StoreError,
    UpdateInputError,
)


def _echo(message: str) -> None:
    print(message, flush=True)


def _warn(message: str) -> None:
    print(f"warning: {message}", file=sys.stderr, flush=True)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="story-model",
        description="Build a story model of an EPUB with the Responses API, one section at a "
        "time in reading order: the first `update` creates the store, each later one adds the "
        "next section.",
    )
    commands = parser.add_subparsers(dest="command", required=True)

    chapters = commands.add_parser("chapters", help="list sections in reading order")
    chapters.add_argument("--epub", type=Path, required=True)

    update = commands.add_parser(
        "update",
        help="add the next section to a store through the model, creating the store from the "
        "chosen section if it does not exist",
    )
    update.add_argument(
        "--store", type=Path, required=True, help="store directory (missing or empty: created)"
    )
    update.add_argument("--epub", type=Path, required=True)
    group = update.add_mutually_exclusive_group()
    group.add_argument("--chapter", type=int, help="chapter number recognized from its title")
    group.add_argument("--section", help="section ID shown by `story-model chapters`")
    update.add_argument("--out", type=Path, help="run directory (must be new or empty)")
    update.add_argument(
        "--no-quote-check",
        action="store_true",
        help="commit even if a quote is not found in its paragraph (reported as a warning); "
        "the store remembers this for the section",
    )
    _add_model_options(update)

    commit = commands.add_parser(
        "commit",
        help="commit an update run after manual corrections of evidence locations (offline)",
    )
    commit.add_argument("--run", type=Path, required=True, help="update run directory")
    commit.add_argument("--epub", type=Path, required=True, help="the store's EPUB")

    show = commands.add_parser("show", help="print a committed revision of a store (offline)")
    show.add_argument("--store", type=Path, required=True, help="store directory")
    show.add_argument("--revision", type=int, help="revision number (default: latest)")
    show.add_argument("--json", action="store_true", help="full JSON instead of Markdown")

    validate = commands.add_parser("validate", help="re-check a saved update run offline")
    validate.add_argument("--run", type=Path, required=True, help="update run directory")
    return parser


def _add_model_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--provider",
        choices=sorted(PROVIDERS),
        default="openai",
        help="openai (default) or deepseek; picks the key/model/base-URL environment variables",
    )
    parser.add_argument("--model", help="overrides OPENAI_MODEL / DEEPSEEK_MODEL")
    parser.add_argument("--prompt-file", type=Path, help="system prompt file (default: built-in)")
    parser.add_argument(
        "--max-output-tokens",
        type=int,
        metavar="N",
        help="optional output cap; by default none is sent and the provider's limit applies",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        metavar="SECONDS",
        help="optional per-request timeout; by default the client waits indefinitely",
    )
    parser.add_argument(
        "--reasoning-effort",
        metavar="LEVEL",
        help="optional reasoning.effort, e.g. low/high/max for DeepSeek; "
        "by default none is sent and the model's default applies",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="write the request files without calling the API"
    )


def _model_config(args: argparse.Namespace) -> GenerateConfig:
    return resolve_generate_config(
        provider=args.provider,
        model=args.model,
        max_output_tokens=args.max_output_tokens,
        timeout=args.timeout,
        dry_run=args.dry_run,
        reasoning_effort=args.reasoning_effort,
    )


def _list_chapters(epub: Path) -> int:
    book = open_epub(epub)
    _echo(f"Book: {book.title} ({book.language or 'unknown language'})")
    _echo(f"SHA-256: {book.sha256}")
    _echo(f"TOC source: {book.toc_source}; {len(book.sections)} sections in reading order")
    _echo("")
    _echo(f"{'SECTION':<12} {'CH':>3} {'PARAS':>6} {'CHARS':>7} {'IMG':>4}  RESOURCE  TITLE")
    for section in book.sections:
        paragraphs = chars = images = 0
        problem = section.problem
        if problem is None:
            try:
                chapter = extract_section(book, section)
            except EpubError as exc:
                problem = str(exc)
            else:
                paragraphs = len(chapter.paragraphs)
                chars = sum(len(p.text) for p in chapter.paragraphs)
                images = chapter.omitted_image_count
        number = str(section.chapter_number) if section.chapter_number is not None else "-"
        resource = section.href + (f"#{section.fragment}" if section.fragment else "")
        _echo(
            f"{section.section_id:<12} {number:>3} {paragraphs:>6} {chars:>7} {images:>4}  "
            f"{resource}  {section.title}"
        )
        for note in section.notes:
            _echo(f"{'':<12} note: {note}")
        if problem:
            _echo(f"{'':<12} unsupported: {problem}")
    for warning in book.warnings:
        _warn(warning)
    return EXIT_OK


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "chapters":
            return _list_chapters(args.epub)
        if args.command == "update":
            outcome = run_update(
                store_root=args.store,
                epub_path=args.epub,
                chapter=args.chapter,
                section_id=args.section,
                config=_model_config(args),
                out=args.out,
                prompt_file=args.prompt_file,
                echo=_echo,
                check_quotes=not args.no_quote_check,
            )
        elif args.command == "commit":
            outcome = run_commit_corrected(run_dir=args.run, epub_path=args.epub, echo=_echo)
        elif args.command == "show":
            outcome = run_show(
                store_root=args.store, revision=args.revision, as_json=args.json, echo=_echo
            )
        else:
            outcome = validate_update_run(args.run, _echo)
    except INPUT_ERRORS as exc:
        print(f"error: {exc}", file=sys.stderr)
        return EXIT_INPUT
    except StaleBaseError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return EXIT_STALE_BASE
    for warning in outcome.warnings:
        _warn(warning)
    if outcome.exit_code != EXIT_OK:
        report = outcome.run_dir / "review.md"
        detail = f"; see {report}" if report.is_file() else ""
        print(f"error: run finished with status {outcome.status}{detail}", file=sys.stderr)
    return outcome.exit_code


if __name__ == "__main__":
    sys.exit(main())
