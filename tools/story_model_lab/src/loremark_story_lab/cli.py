"""Command line entry point: chapters / extract / generate / validate."""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from pathlib import Path

from .artifacts import OutputDirError
from .config import PROVIDERS, ConfigError, resolve_generate_config
from .epub import EpubError, extract_section, open_epub
from .pipeline import EXIT_INPUT, EXIT_OK, RunInputError, run_extract, run_generate, run_validate


def _echo(message: str) -> None:
    print(message, flush=True)


def _warn(message: str) -> None:
    print(f"warning: {message}", file=sys.stderr, flush=True)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="story-model",
        description="Extract a single-chapter story model from an EPUB with the Responses API.",
    )
    commands = parser.add_subparsers(dest="command", required=True)

    chapters = commands.add_parser("chapters", help="list sections in reading order")
    chapters.add_argument("--epub", type=Path, required=True)

    extract = commands.add_parser("extract", help="write the chapter input only (offline)")
    _add_selection(extract)

    generate = commands.add_parser("generate", help="run one chapter through the model")
    _add_selection(generate)
    generate.add_argument(
        "--provider",
        choices=sorted(PROVIDERS),
        default="openai",
        help="openai (default) or deepseek; picks the key/model/base-URL environment variables",
    )
    generate.add_argument("--model", help="overrides OPENAI_MODEL / DEEPSEEK_MODEL")
    generate.add_argument("--prompt-file", type=Path, help="system prompt file (default: v1)")
    generate.add_argument(
        "--max-output-tokens",
        type=int,
        metavar="N",
        help="optional output cap; by default none is sent and the provider's limit applies",
    )
    generate.add_argument(
        "--timeout",
        type=float,
        metavar="SECONDS",
        help="optional per-request timeout; by default the client waits indefinitely",
    )
    generate.add_argument(
        "--reasoning-effort",
        metavar="LEVEL",
        help="optional reasoning.effort, e.g. low/high/max for DeepSeek; "
        "by default none is sent and the model's default applies",
    )
    generate.add_argument(
        "--dry-run", action="store_true", help="write the request files without calling the API"
    )

    validate = commands.add_parser("validate", help="re-check a saved run offline")
    validate.add_argument("--run", type=Path, required=True, help="run directory")
    return parser


def _add_selection(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--epub", type=Path, required=True)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--chapter", type=int, help="chapter number recognized from its title")
    group.add_argument("--section", help="section ID shown by `story-model chapters`")
    parser.add_argument("--out", type=Path, help="output directory (must be new or empty)")


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
        if args.command == "extract":
            outcome = run_extract(args.epub, args.chapter, args.section, args.out, _echo)
        elif args.command == "generate":
            config = resolve_generate_config(
                provider=args.provider,
                model=args.model,
                max_output_tokens=args.max_output_tokens,
                timeout=args.timeout,
                dry_run=args.dry_run,
                reasoning_effort=args.reasoning_effort,
            )
            outcome = run_generate(
                epub_path=args.epub,
                chapter=args.chapter,
                section_id=args.section,
                config=config,
                out=args.out,
                prompt_file=args.prompt_file,
                echo=_echo,
            )
        else:
            outcome = run_validate(args.run, _echo)
    except (EpubError, ConfigError, OutputDirError, RunInputError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return EXIT_INPUT
    for warning in outcome.warnings:
        _warn(warning)
    if outcome.exit_code != EXIT_OK:
        print(
            f"error: run finished with status {outcome.status}; see {outcome.run_dir}/review.md",
            file=sys.stderr,
        )
    return outcome.exit_code


if __name__ == "__main__":
    sys.exit(main())
