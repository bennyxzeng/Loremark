from __future__ import annotations

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

from loremark_story_lab.config import GenerateConfig, resolve_generate_config
from loremark_story_lab.epub import extract_section, open_epub, select_section
from loremark_story_lab.incremental_pipeline import run_update
from loremark_story_lab.openai_client import ResponsesClient, make_sdk_client
from loremark_story_lab.pipeline import Echo, Outcome
from loremark_story_lab.schemas import ChapterInput, Paragraph

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
DEEPSEEK_ENV = {"DEEPSEEK_API_KEY": "ds-test-secret", "DEEPSEEK_MODEL": "deepseek-flash"}


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


def tree_hashes(root: Path) -> dict[str, str]:
    return {
        path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def story_delta(name: str = "chapter2_delta.json") -> dict[str, Any]:
    return json.loads((STORY / name).read_text(encoding="utf-8"))


def delta_api(delta: dict[str, Any]) -> FakeApi:
    return FakeApi(json_response(response_body(json.dumps(delta))))


def update_store(
    store: Path,
    epub: Path,
    api: FakeApi,
    out: Path | None,
    *,
    chapter: int | None = None,
    section: str | None = None,
    provider: str = "deepseek",
    env: dict[str, str] | None = None,
    dry_run: bool = False,
    max_output_tokens: int | None = None,
    reasoning_effort: str | None = None,
    echo: Echo = lambda _: None,
) -> Outcome:
    """`update` through the real SDK and a mock API; without a selection, the next section."""
    env = DEEPSEEK_ENV if env is None else env
    config = resolve_generate_config(
        provider=provider,
        model=None,
        max_output_tokens=max_output_tokens,
        timeout=None,
        dry_run=dry_run,
        reasoning_effort=reasoning_effort,
        env=env,
    )
    return run_update(
        store_root=store,
        epub_path=epub,
        chapter=chapter,
        section_id=section,
        config=config,
        out=out,
        prompt_file=None,
        echo=echo,
        client_factory=api,
        env=env,
    )


def create_store(root: Path, epub: Path, out: Path) -> Path:
    """A store created by `update` from Chapter 1 (section-002); the prologue stays uncovered."""
    outcome = update_store(
        root, epub, delta_api(story_delta("chapter1_delta.json")), out, section="section-002"
    )
    assert outcome.status == "committed", outcome.status
    return root


@pytest.fixture
def story_epub(tmp_path: Path) -> Path:
    return build_story_epub(tmp_path / "story.epub")


@pytest.fixture
def store(tmp_path: Path, story_epub: Path) -> Path:
    return create_store(tmp_path / "store", story_epub, tmp_path / "runs" / "chapter1")


@pytest.fixture
def ch1_delta() -> dict[str, Any]:
    return story_delta("chapter1_delta.json")


@pytest.fixture
def ch2_delta() -> dict[str, Any]:
    return story_delta()
