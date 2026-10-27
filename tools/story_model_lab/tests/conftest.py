from __future__ import annotations

import copy
import hashlib
import html
import json
import re
import socket
import zipfile
from collections.abc import Callable
from dataclasses import replace
from pathlib import Path
from typing import Any

import httpx2
import pytest

from loremark_story_lab.artifacts import write_json
from loremark_story_lab.config import GenerateConfig
from loremark_story_lab.epub import extract_section, open_epub, select_section, text_sha256
from loremark_story_lab.openai_client import ResponsesClient, make_sdk_client
from loremark_story_lab.schemas import (
    ChapterInput,
    ChapterStoryModel,
    Paragraph,
    StoryModelEnvelope,
)

FIXTURES = Path(__file__).parent / "fixtures"
STORY = FIXTURES / "story"
REPO_ROOT = Path(__file__).resolve().parents[3]
SAMPLE_EPUB = REPO_ROOT / "sample_epub" / "86v1_chapters.epub"
PROVIDER_ENV_VARS = [
    "OPENAI_API_KEY",
    "OPENAI_MODEL",
    "OPENAI_BASE_URL",
    "OPENAI_ORG_ID",
    "OPENAI_PROJECT_ID",
    "DEEPSEEK_API_KEY",
    "DEEPSEEK_MODEL",
    "DEEPSEEK_BASE_URL",
]


def xhtml(body: str, title: str = "Document") -> str:
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
        f"<head><title>{title}</title><style>p {{ color: red; }}</style></head>"
        f"<body>{body}</body></html>"
    )


def build_epub(
    path: Path,
    docs: dict[str, str],
    *,
    nav: list[tuple[str, str]] | None = None,
    nav_text: str | None = None,
    ncx: list[tuple[str, str]] | None = None,
    spine: list[str] | None = None,
    title: str = "Synthetic Book",
) -> Path:
    """Write a minimal EPUB. `nav`/`ncx` are (href relative to OEBPS/, label) pairs."""
    spine = list(docs) if spine is None else spine
    ids = {name: f"doc{index}" for index, name in enumerate(docs, start=1)}
    manifest = [
        f'<item id="{ids[name]}" href="{name}" media-type="application/xhtml+xml"/>'
        for name in docs
    ]
    files: dict[str, str] = {f"OEBPS/{name}": content for name, content in docs.items()}
    if nav is not None or nav_text is not None:
        if nav_text is None:
            links = "".join(f'<li><a href="{h}">{html.escape(t)}</a></li>' for h, t in nav or [])
            nav_text = xhtml(f'<nav epub:type="toc" id="toc"><ol>{links}</ol></nav>', "TOC")
        files["OEBPS/nav.xhtml"] = nav_text
        manifest.append(
            '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
        )
    spine_attr = ""
    if ncx is not None:
        points = "".join(
            f'<navPoint id="n{i}" playOrder="{i}"><navLabel><text>{html.escape(label)}</text>'
            f'</navLabel><content src="{src}"/></navPoint>'
            for i, (src, label) in enumerate(ncx, start=1)
        )
        files["OEBPS/toc.ncx"] = (
            '<?xml version="1.0" encoding="utf-8"?>'
            '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
            f"<navMap>{points}</navMap></ncx>"
        )
        manifest.append('<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>')
        spine_attr = ' toc="ncx"'
    itemrefs = "".join(f'<itemref idref="{ids[name]}"/>' for name in spine)
    files["OEBPS/content.opf"] = (
        '<?xml version="1.0" encoding="utf-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        f"<dc:title>{html.escape(title)}</dc:title><dc:language>en</dc:language></metadata>"
        f"<manifest>{''.join(manifest)}</manifest><spine{spine_attr}>{itemrefs}</spine></package>"
    )
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("mimetype", "application/epub+zip")
        archive.writestr(
            "META-INF/container.xml",
            '<?xml version="1.0"?><container version="1.0" '
            'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
            '<rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'
            "</rootfiles></container>",
        )
        for name, content in files.items():
            archive.writestr(name, content)
    return path


def read_synthetic_paragraphs() -> list[Paragraph]:
    paragraphs = []
    for line in (FIXTURES / "synthetic_chapter.txt").read_text(encoding="utf-8").splitlines():
        match = re.match(r"^\[(p\d+)\] (.*)$", line)
        assert match, line
        paragraphs.append(Paragraph(id=match.group(1), text=match.group(2)))
    return paragraphs


@pytest.fixture
def synthetic_chapter() -> ChapterInput:
    paragraphs = read_synthetic_paragraphs()
    return ChapterInput(
        book_sha256="0" * 64,
        book_title="Synthetic Book",
        section_id="section-002",
        chapter_number=3,
        title="Chapter 3: The Lantern Ferry",
        source_href="OEBPS/chapter3.xhtml",
        source_fragment=None,
        paragraphs=paragraphs,
        text_sha256=text_sha256(paragraphs),
        extraction_version="1.0",
        omitted_image_count=0,
    )


@pytest.fixture
def synthetic_model() -> dict[str, Any]:
    return copy.deepcopy(json.loads((FIXTURES / "synthetic_model.json").read_text("utf-8")))


@pytest.fixture
def synthetic_epub(tmp_path: Path) -> Path:
    """Prologue, the synthetic Chapter 3, and a Chapter 4, each with sentinel text."""
    body = "<h1>CHAPTER 3<br/>THE LANTERN FERRY</h1>" + "".join(
        f"<p>{html.escape(p.text, quote=False)}</p>" for p in read_synthetic_paragraphs()[1:]
    )
    docs = {
        "prologue.xhtml": xhtml("<h1>Prologue</h1><p>PREVIOUS-SENTINEL The fog stayed.</p>"),
        "chapter3.xhtml": xhtml(body),
        "chapter4.xhtml": xhtml("<h1>Chapter 4</h1><p>NEXT-SENTINEL The dam broke.</p>"),
    }
    nav = [
        ("prologue.xhtml", "Prologue"),
        ("chapter3.xhtml", "Chapter 3: The Lantern Ferry"),
        ("chapter4.xhtml", "Chapter 4: Dawn"),
    ]
    return build_epub(tmp_path / "synthetic.epub", docs, nav=nav)


@pytest.fixture
def clean_env(monkeypatch: pytest.MonkeyPatch) -> None:
    for name in PROVIDER_ENV_VARS:
        monkeypatch.delenv(name, raising=False)


@pytest.fixture
def no_network(monkeypatch: pytest.MonkeyPatch) -> None:
    def refuse(*args: object, **kwargs: object) -> None:
        raise AssertionError("network access attempted in an offline test")

    monkeypatch.setattr(socket.socket, "connect", refuse)
    monkeypatch.setattr(socket, "create_connection", refuse)


# --- mock Responses API -----------------------------------------------------------------

Handler = Callable[[httpx2.Request], httpx2.Response]


def response_body(
    output_text: str | None = None,
    *,
    status: str = "completed",
    refusal: str | None = None,
    incomplete_reason: str | None = None,
) -> dict[str, Any]:
    content: list[dict[str, Any]] = []
    if output_text is not None:
        content.append({"type": "output_text", "text": output_text, "annotations": []})
    if refusal is not None:
        content.append({"type": "refusal", "refusal": refusal})
    return {
        "id": "resp_test123",
        "object": "response",
        "created_at": 1761450000,
        "status": status,
        "model": "test-model-2026-10-01",
        "output": [
            {
                "type": "message",
                "id": "msg_1",
                "status": status,
                "role": "assistant",
                "content": content,
            }
        ],
        "error": None,
        "incomplete_details": {"reason": incomplete_reason} if incomplete_reason else None,
        "instructions": None,
        "metadata": {},
        "parallel_tool_calls": True,
        "tool_choice": "auto",
        "tools": [],
        "usage": {
            "input_tokens": 1200,
            "input_tokens_details": {"cached_tokens": 0},
            "output_tokens": 800,
            "output_tokens_details": {"reasoning_tokens": 120},
            "total_tokens": 2000,
        },
    }


def json_response(body: Any, status_code: int = 200) -> Handler:
    def handler(request: httpx2.Request) -> httpx2.Response:
        return httpx2.Response(status_code, json=body, headers={"x-request-id": "req_abc"})

    return handler


class FakeApi:
    """Client factory that wires the real SDK to a mock transport and records requests."""

    def __init__(self, handler: Handler) -> None:
        self.handler = handler
        self.requests: list[httpx2.Request] = []

    def __call__(self, config: GenerateConfig, api_key: str) -> ResponsesClient:
        def record(request: httpx2.Request) -> httpx2.Response:
            self.requests.append(request)
            return self.handler(request)

        http_client = httpx2.Client(transport=httpx2.MockTransport(record))
        sdk = make_sdk_client(replace(config, max_retries=0), api_key, http_client=http_client)
        return ResponsesClient(sdk)

    def body(self, index: int = 0) -> dict[str, Any]:
        return json.loads(self.requests[index].content)


# --- synthetic two-chapter story --------------------------------------------------------


def read_paragraphs(path: Path) -> list[Paragraph]:
    paragraphs = []
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^\[(p\d+)\] (.*)$", line)
        assert match, line
        paragraphs.append(Paragraph(id=match.group(1), text=match.group(2)))
    return paragraphs


def chapter_xhtml(path: Path) -> str:
    """The first paragraph becomes the <h1> heading, the rest <p> elements."""
    heading, *rest = read_paragraphs(path)
    body = f"<h1>{html.escape(heading.text, quote=False)}</h1>" + "".join(
        f"<p>{html.escape(p.text, quote=False)}</p>" for p in rest
    )
    return xhtml(body)


def build_story_epub(path: Path, chapter2: str | None = None) -> Path:
    """Prologue, Chapter 1, Chapter 2, an interlude, and Chapter 3 (sentinels outside 1-2)."""
    docs = {
        "prologue.xhtml": xhtml("<h1>Prologue</h1><p>PROLOGUE-SENTINEL The river was quiet.</p>"),
        "ch1.xhtml": chapter_xhtml(STORY / "chapter1.txt"),
        "ch2.xhtml": chapter2 or chapter_xhtml(STORY / "chapter2.txt"),
        "interlude.xhtml": xhtml("<h1>Interlude</h1><p>INTERLUDE-SENTINEL The lamp burned.</p>"),
        "ch3.xhtml": xhtml("<h1>Chapter 3</h1><p>CHAPTER-THREE-SENTINEL The town rebuilt.</p>"),
    }
    nav = [
        ("prologue.xhtml", "Prologue"),
        ("ch1.xhtml", "Chapter 1: The Signal"),
        ("ch2.xhtml", "Chapter 2: The Storm"),
        ("interlude.xhtml", "Interlude: The Lamp"),
        ("ch3.xhtml", "Chapter 3: Aftermath"),
    ]
    return build_epub(path, docs, nav=nav, title="Synthetic Story")


def story_chapter(epub: Path, section_id: str) -> ChapterInput:
    book = open_epub(epub)
    return extract_section(book, select_section(book, chapter=None, section_id=section_id))


def write_v1_run(run_dir: Path, epub: Path, *, corrected: bool = True) -> Path:
    """A finished `generate` run of Chapter 1, as the v1 pipeline would leave it.

    With `corrected`, the run records one manual correction like the real Chapter 1 run.
    """
    chapter = story_chapter(epub, "section-002")
    model = json.loads((STORY / "chapter1_model.json").read_text(encoding="utf-8"))
    run_dir.mkdir(parents=True)
    write_json(run_dir / "chapter.json", chapter.model_dump(mode="json"))
    envelope = StoryModelEnvelope.build(chapter, ChapterStoryModel.model_validate(model))
    write_json(run_dir / "story_model.json", envelope.model_dump(mode="json"))
    write_json(run_dir / "candidate.json", model)
    run: dict[str, Any] = {
        "run_id": "20261026T000000Z-test01",
        "command": "generate",
        "status": "succeeded",
        "source": {
            "epub_path": str(epub.resolve()),
            "book_sha256": chapter.book_sha256,
            "section_id": chapter.section_id,
        },
        "hashes": {"text_sha256": chapter.text_sha256},
        "request": {"provider": "deepseek", "model": "deepseek-flash"},
    }
    if corrected:
        original = copy.deepcopy(model)
        original["characters"][0]["aliases"][0]["evidence"][0]["paragraph_id"] = "p0003"
        write_json(run_dir / "candidate.original.json", original)
        run["manual_corrections"] = [
            {
                "path": "characters[0].aliases[0].evidence[0].paragraph_id",
                "from": "p0003",
                "to": "p0004",
                "reason": "Quote occurs verbatim in p0004, not p0003",
                "corrected_by": "test",
                "corrected_at": "2026-10-26T00:00:00Z",
                "original_candidate": "candidate.original.json",
            }
        ]
    write_json(run_dir / "run.json", run)
    return run_dir


def tree_hashes(root: Path) -> dict[str, str]:
    return {
        path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def story_delta() -> dict[str, Any]:
    return json.loads((STORY / "chapter2_delta.json").read_text(encoding="utf-8"))


@pytest.fixture
def story_epub(tmp_path: Path) -> Path:
    return build_story_epub(tmp_path / "story.epub")


@pytest.fixture
def v1_run(tmp_path: Path, story_epub: Path) -> Path:
    return write_v1_run(tmp_path / "runs" / "chapter1", story_epub)


@pytest.fixture
def ch2_delta() -> dict[str, Any]:
    return story_delta()
