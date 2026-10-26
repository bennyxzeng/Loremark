from __future__ import annotations

import copy
import html
import json
import re
import socket
import zipfile
from pathlib import Path
from typing import Any

import pytest

from loremark_story_lab.epub import text_sha256
from loremark_story_lab.schemas import ChapterInput, Paragraph

FIXTURES = Path(__file__).parent / "fixtures"
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
