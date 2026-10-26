"""Read an EPUB in memory: container/OPF/nav/NCX, reading-order sections, chapter text."""

from __future__ import annotations

import hashlib
import io
import posixpath
import re
import unicodedata
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal
from urllib.parse import unquote, urlsplit
from xml.etree import ElementTree

from bs4 import BeautifulSoup, NavigableString, Tag
from bs4.element import PreformattedString

from .schemas import ChapterInput, Paragraph

EXTRACTION_VERSION = "1.0"

MAX_MEMBER_BYTES = 64 * 1024 * 1024
XHTML_MEDIA_TYPES = {"application/xhtml+xml", "text/html"}
OPS_NS = "http://www.idpf.org/2007/ops"

# Leaf text is grouped into one paragraph per block element; nested blocks split it.
BLOCK_TAGS = {
    "address", "article", "aside", "blockquote", "body", "caption", "dd", "div", "dl", "dt",
    "figcaption", "figure", "footer", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "li",
    "main", "ol", "p", "pre", "section", "table", "tbody", "td", "tfoot", "th", "thead", "tr",
    "ul",
}  # fmt: skip
SKIP_TAGS = {"head", "math", "nav", "noscript", "script", "style", "svg", "template"}
IMAGE_TAGS = {"img", "image"}

_CHAPTER_TITLE = re.compile(r"^\s*chapter\s+(\d+|[ivxlcdm]+)\b", re.IGNORECASE)
_ROMAN = re.compile(r"^M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$")
_ROMAN_VALUES = {"I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000}

TocSource = Literal["nav", "ncx", "spine"]


class EpubError(Exception):
    """The EPUB cannot be read, or the requested section cannot be located reliably."""


@dataclass
class Section:
    section_id: str
    order: int
    title: str
    chapter_number: int | None
    href: str
    fragment: str | None
    spine_index: int
    in_toc: bool
    problem: str | None = None
    notes: list[str] = field(default_factory=list)


@dataclass
class EpubBook:
    path: Path
    sha256: str
    title: str
    language: str | None
    opf_path: str
    toc_source: TocSource
    sections: list[Section]
    warnings: list[str]
    _archive: zipfile.ZipFile = field(repr=False)
    _soups: dict[str, BeautifulSoup] = field(default_factory=dict, repr=False)

    def soup(self, href: str) -> BeautifulSoup:
        if href not in self._soups:
            self._soups[href] = BeautifulSoup(_read_member(self._archive, href), "html.parser")
        return self._soups[href]


@dataclass
class _TocEntry:
    title: str
    href: str
    fragment: str | None


def normalize_text(text: str) -> str:
    """NFC-normalize and collapse every run of whitespace to one space."""
    return " ".join(unicodedata.normalize("NFC", text).split())


def text_sha256(paragraphs: list[Paragraph]) -> str:
    """Hash of the normalized paragraph texts joined by newlines (IDs excluded)."""
    joined = "\n".join(p.text for p in paragraphs)
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()


def parse_chapter_number(title: str) -> int | None:
    match = _CHAPTER_TITLE.match(title)
    if not match:
        return None
    token = match.group(1)
    if token.isdigit():
        return int(token)
    roman = token.upper()
    if not _ROMAN.match(roman):
        return None
    total = 0
    for char, next_char in zip(roman, roman[1:] + " ", strict=True):
        value = _ROMAN_VALUES[char]
        total += -value if value < _ROMAN_VALUES.get(next_char, 0) else value
    return total


def open_epub(path: Path) -> EpubBook:
    try:
        data = path.read_bytes()
    except OSError as exc:
        raise EpubError(f"Cannot read EPUB file {path}: {exc}") from exc
    try:
        archive = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile as exc:
        raise EpubError(f"{path} is not a valid ZIP/EPUB archive") from exc

    opf_path = _find_opf(archive)
    opf = _parse_xml(archive, opf_path)
    title, language = _read_metadata(opf)
    manifest = _read_manifest(opf, opf_path)
    warnings: list[str] = []
    spine, ncx_id = _read_spine(opf, manifest, warnings)
    if not spine:
        raise EpubError("The OPF spine contains no XHTML documents")

    toc_source, entries = _read_toc(archive, opf, manifest, ncx_id, warnings)
    book = EpubBook(
        path=path.resolve(),
        sha256=hashlib.sha256(data).hexdigest(),
        title=title,
        language=language,
        opf_path=opf_path,
        toc_source=toc_source,
        sections=[],
        warnings=warnings,
        _archive=archive,
    )
    book.sections = _build_sections(book, spine, entries)
    return book


def select_section(book: EpubBook, *, chapter: int | None, section_id: str | None) -> Section:
    if (chapter is None) == (section_id is None):
        raise EpubError("Choose exactly one of --chapter or --section")
    if section_id is not None:
        matches = [s for s in book.sections if s.section_id == section_id]
        if not matches:
            raise EpubError(
                f"Unknown section ID {section_id!r}; run `story-model chapters` to list IDs"
            )
    else:
        matches = [s for s in book.sections if s.chapter_number == chapter]
        if not matches:
            raise EpubError(
                f"No section title is recognized as Chapter {chapter}; "
                "run `story-model chapters` and pick one with --section"
            )
        if len(matches) > 1:
            ids = ", ".join(s.section_id for s in matches)
            raise EpubError(
                f"Chapter {chapter} matches several sections ({ids}); choose one with --section"
            )
    section = matches[0]
    if section.problem:
        raise EpubError(f"{section.section_id} cannot be extracted reliably: {section.problem}")
    return section


def extract_section(book: EpubBook, section: Section) -> ChapterInput:
    if section.problem:
        raise EpubError(f"{section.section_id} cannot be extracted reliably: {section.problem}")
    soup = book.soup(section.href)
    start = _anchor_element(soup, section.fragment)
    end = None
    next_section = _next_in_same_document(book, section)
    if next_section is not None:
        end = _anchor_element(soup, next_section.fragment)

    collector = _RangeCollector(start=start, end=end)
    collector.walk(soup.body or soup)
    collector.flush()
    if not collector.paragraphs:
        raise EpubError(f"{section.section_id} ({section.title!r}) contains no body text")

    width = max(4, len(str(len(collector.paragraphs))))
    paragraphs = [
        Paragraph(id=f"p{index:0{width}d}", text=text)
        for index, text in enumerate(collector.paragraphs, start=1)
    ]
    return ChapterInput(
        book_sha256=book.sha256,
        book_title=book.title,
        section_id=section.section_id,
        chapter_number=section.chapter_number,
        title=section.title,
        source_href=section.href,
        source_fragment=section.fragment,
        paragraphs=paragraphs,
        text_sha256=text_sha256(paragraphs),
        extraction_version=EXTRACTION_VERSION,
        omitted_image_count=collector.images,
        extraction_notes=list(section.notes),
    )


def render_chapter_text(chapter: ChapterInput) -> str:
    return "".join(f"[{p.id}] {p.text}\n" for p in chapter.paragraphs)


# --- archive and XML helpers -------------------------------------------------


def _local(tag: object) -> str:
    return tag.rsplit("}", 1)[-1] if isinstance(tag, str) else ""


def _check_member_path(path: str) -> str:
    if (
        not path
        or path.startswith("/")
        or path == ".."
        or path.startswith("../")
        or "\\" in path
        or re.match(r"^[A-Za-z]:", path)
    ):
        raise EpubError(f"Refusing path outside the EPUB container: {path!r}")
    return path


def _resolve_href(base: str, href: str) -> tuple[str, str | None]:
    parts = urlsplit(href)
    if parts.scheme or parts.netloc:
        raise EpubError(f"External reference is not supported: {href!r}")
    fragment = unquote(parts.fragment) or None
    if not parts.path:
        return base, fragment
    target = posixpath.normpath(posixpath.join(posixpath.dirname(base), unquote(parts.path)))
    return _check_member_path(target), fragment


def _read_member(archive: zipfile.ZipFile, name: str) -> bytes:
    _check_member_path(name)
    try:
        info = archive.getinfo(name)
    except KeyError as exc:
        raise EpubError(f"Missing file inside EPUB: {name}") from exc
    if info.file_size > MAX_MEMBER_BYTES:
        raise EpubError(f"{name} is larger than {MAX_MEMBER_BYTES} bytes; refusing to read it")
    return archive.read(info)


def _parse_xml(archive: zipfile.ZipFile, name: str) -> ElementTree.Element:
    try:
        return ElementTree.fromstring(_read_member(archive, name))
    except ElementTree.ParseError as exc:
        raise EpubError(f"Cannot parse XML in {name}: {exc}") from exc


def _find_opf(archive: zipfile.ZipFile) -> str:
    container = _parse_xml(archive, "META-INF/container.xml")
    for element in container.iter():
        if _local(element.tag) == "rootfile" and element.get("full-path"):
            return _check_member_path(unquote(element.get("full-path", "")))
    raise EpubError("META-INF/container.xml does not name an OPF package file")


def _read_metadata(opf: ElementTree.Element) -> tuple[str, str | None]:
    title = language = None
    for element in opf.iter():
        name = _local(element.tag)
        if name == "title" and title is None:
            title = normalize_text("".join(element.itertext())) or None
        elif name == "language" and language is None:
            language = normalize_text("".join(element.itertext())) or None
    return title or "(untitled)", language


@dataclass
class _ManifestItem:
    href: str
    media_type: str
    properties: set[str]


def _read_manifest(opf: ElementTree.Element, opf_path: str) -> dict[str, _ManifestItem]:
    manifest: dict[str, _ManifestItem] = {}
    for element in opf.iter():
        if _local(element.tag) != "item":
            continue
        item_id, href = element.get("id"), element.get("href")
        if not item_id or not href:
            continue
        path, _ = _resolve_href(opf_path, href)
        manifest[item_id] = _ManifestItem(
            href=path,
            media_type=element.get("media-type", ""),
            properties=set(element.get("properties", "").split()),
        )
    return manifest


def _read_spine(
    opf: ElementTree.Element, manifest: dict[str, _ManifestItem], warnings: list[str]
) -> tuple[list[str], str | None]:
    spine: list[str] = []
    ncx_id = None
    for element in opf.iter():
        name = _local(element.tag)
        if name == "spine":
            ncx_id = element.get("toc")
        elif name == "itemref":
            item = manifest.get(element.get("idref", ""))
            if item is None:
                warnings.append(f"Spine references unknown manifest item {element.get('idref')!r}")
            elif item.media_type not in XHTML_MEDIA_TYPES:
                warnings.append(f"Skipping non-XHTML spine item {item.href} ({item.media_type})")
            elif item.href not in spine:
                spine.append(item.href)
    return spine, ncx_id


def _read_toc(
    archive: zipfile.ZipFile,
    opf: ElementTree.Element,
    manifest: dict[str, _ManifestItem],
    ncx_id: str | None,
    warnings: list[str],
) -> tuple[TocSource, list[_TocEntry]]:
    nav_item = next((i for i in manifest.values() if "nav" in i.properties), None)
    if nav_item is not None:
        try:
            entries = _read_nav(archive, nav_item.href)
        except EpubError as exc:
            warnings.append(f"EPUB 3 nav unusable, trying NCX: {exc}")
        else:
            if entries:
                return "nav", entries
            warnings.append("EPUB 3 nav has no TOC links, trying NCX")

    ncx_item = manifest.get(ncx_id or "") or next(
        (i for i in manifest.values() if i.media_type == "application/x-dtbncx+xml"), None
    )
    if ncx_item is not None:
        try:
            entries = _read_ncx(archive, ncx_item.href)
        except EpubError as exc:
            warnings.append(f"NCX unusable: {exc}")
        else:
            if entries:
                return "ncx", entries
            warnings.append("NCX has no navPoints")

    warnings.append("No usable table of contents; listing spine documents instead (fallback)")
    return "spine", []


def _read_nav(archive: zipfile.ZipFile, nav_href: str) -> list[_TocEntry]:
    root = _parse_xml(archive, nav_href)
    toc_nav = None
    for element in root.iter():
        if _local(element.tag) != "nav":
            continue
        types = (element.get(f"{{{OPS_NS}}}type") or "").split()
        if "toc" in types or element.get("role") == "doc-toc":
            toc_nav = element
            break
    if toc_nav is None:
        return []
    entries = []
    for element in toc_nav.iter():
        if _local(element.tag) == "a" and element.get("href"):
            href, fragment = _resolve_href(nav_href, element.get("href", ""))
            title = normalize_text("".join(element.itertext()))
            entries.append(_TocEntry(title=title, href=href, fragment=fragment))
    return entries


def _read_ncx(archive: zipfile.ZipFile, ncx_href: str) -> list[_TocEntry]:
    root = _parse_xml(archive, ncx_href)
    entries = []
    for point in root.iter():
        if _local(point.tag) != "navPoint":
            continue
        title, src = "", None
        for child in point:
            if _local(child.tag) == "navLabel":
                title = normalize_text("".join(child.itertext()))
            elif _local(child.tag) == "content":
                src = child.get("src")
        if src:
            href, fragment = _resolve_href(ncx_href, src)
            entries.append(_TocEntry(title=title, href=href, fragment=fragment))
    return entries


# --- section boundaries ------------------------------------------------------


def _anchor_element(soup: BeautifulSoup, fragment: str | None) -> Tag | None:
    """The element a section starts at, or None for the start of the document."""
    if fragment is None:
        return None
    element = soup.find(id=fragment)
    if element is None or element.name in {"html", "body"}:
        return None
    return element


def _element_ordinals(soup: BeautifulSoup) -> dict[int, int]:
    root = soup.body or soup
    return {id(node): index for index, node in enumerate(root.descendants) if isinstance(node, Tag)}


def _document_title(soup: BeautifulSoup, href: str) -> str:
    for name in ("title", "h1", "h2", "h3"):
        element = soup.find(name)
        if element is not None:
            text = normalize_text(element.get_text(" "))
            if text:
                return text
    return posixpath.basename(href)


def _build_sections(book: EpubBook, spine: list[str], entries: list[_TocEntry]) -> list[Section]:
    spine_index = {href: index for index, href in enumerate(spine, start=1)}
    positioned: list[tuple[tuple[int, int, int], Section]] = []
    toc_docs: set[str] = set()

    for toc_index, entry in enumerate(entries):
        if entry.href not in spine_index:
            book.warnings.append(
                f"TOC entry {entry.title!r} points to {entry.href}, which is not an XHTML "
                "document in the spine; it is not listed"
            )
            continue
        toc_docs.add(entry.href)
        soup = book.soup(entry.href)
        problem = None
        ordinal = -1
        if entry.fragment is not None:
            element = soup.find(id=entry.fragment)
            if element is None:
                problem = f"anchor #{entry.fragment} was not found in {entry.href}"
            elif element.name not in {"html", "body"}:
                ordinal = _element_ordinals(soup)[id(element)]
        section = Section(
            section_id="",
            order=0,
            title=entry.title or _document_title(soup, entry.href),
            chapter_number=None,
            href=entry.href,
            fragment=entry.fragment,
            spine_index=spine_index[entry.href],
            in_toc=True,
            problem=problem,
        )
        positioned.append(((section.spine_index, ordinal, toc_index), section))

    # Spine documents the TOC never starts in are listed on their own, never silently merged.
    for href, index in spine_index.items():
        if href in toc_docs:
            continue
        soup = book.soup(href)
        section = Section(
            section_id="",
            order=0,
            title=_document_title(soup, href),
            chapter_number=None,
            href=href,
            fragment=None,
            spine_index=index,
            in_toc=False,
        )
        if book.toc_source != "spine":
            section.notes.append("Spine document not referenced by the table of contents")
        positioned.append(((index, -1, len(entries) + index), section))

    positioned.sort(key=lambda item: item[0])
    sections = [section for _, section in positioned]
    for order, section in enumerate(sections, start=1):
        section.order = order
        section.section_id = f"section-{order:03d}"
        section.chapter_number = parse_chapter_number(section.title)

    for current, following in zip(sections, sections[1:], strict=False):
        if current.in_toc and not following.in_toc and book.toc_source != "spine":
            current.notes.append(
                f"Followed by {following.href}, which is not in the TOC; "
                f"that text is listed separately as {following.section_id} and not included here"
            )
    return sections


def _next_in_same_document(book: EpubBook, section: Section) -> Section | None:
    index = book.sections.index(section)
    for candidate in book.sections[index + 1 :]:
        if candidate.href != section.href:
            return None
        if candidate.problem is None:
            return candidate
    return None


class _RangeCollector:
    """Collect paragraph texts between a start element and an end element, in document order."""

    def __init__(self, start: Tag | None, end: Tag | None) -> None:
        self.start = start
        self.end = end
        self.active = start is None
        self.done = False
        self.suppressed = 0
        self.buffer: list[str] = []
        self.paragraphs: list[str] = []
        self.images = 0

    def walk(self, node: Tag | BeautifulSoup) -> None:
        for child in node.children:
            if self.done:
                return
            if isinstance(child, Tag):
                self._visit(child)
            elif self._collects(child):
                self.buffer.append(str(child))

    def _collects(self, node: object) -> bool:
        """Visible text: skips comments, CDATA, processing instructions, and suppressed nodes."""
        is_text = isinstance(node, NavigableString) and not isinstance(node, PreformattedString)
        return is_text and self.active and not self.suppressed

    def flush(self) -> None:
        text = normalize_text("".join(self.buffer))
        self.buffer.clear()
        if text:
            self.paragraphs.append(text)

    def _visit(self, tag: Tag) -> None:
        if tag is self.end:
            self.flush()
            self.done = True
            return
        if tag is self.start:
            self.flush()
            self.active = True
        name = (tag.name or "").lower()
        if name in IMAGE_TAGS and self.active:
            self.images += 1
        if name == "br":
            if self.active and not self.suppressed:
                self.buffer.append(" ")
            return
        skipped = name in SKIP_TAGS or _is_page_break(tag)
        block = name in BLOCK_TAGS
        if block:
            self.flush()
        self.suppressed += skipped
        self.walk(tag)
        self.suppressed -= skipped
        if block:
            self.flush()


def _is_page_break(tag: Tag) -> bool:
    epub_type = tag.get("epub:type") or ""
    if isinstance(epub_type, list):
        epub_type = " ".join(epub_type)
    return "pagebreak" in epub_type.split() or tag.get("role") == "doc-pagebreak"
