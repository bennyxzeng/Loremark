from __future__ import annotations

import zipfile
from pathlib import Path

import pytest
from conftest import FIXTURES, SAMPLE_EPUB, build_epub, xhtml

from loremark_story_lab.epub import (
    EpubError,
    extract_section,
    open_epub,
    parse_chapter_number,
    render_chapter_text,
    select_section,
)


def _texts(book, section_id: str) -> list[str]:
    section = select_section(book, chapter=None, section_id=section_id)
    return [p.text for p in extract_section(book, section).paragraphs]


def test_reading_order_and_chapter_numbers_differ_from_spine_position(tmp_path: Path) -> None:
    docs = {
        "prologue.xhtml": xhtml("<p>Before everything.</p>"),
        "one.xhtml": xhtml("<p>First chapter text.</p>"),
        "interlude.xhtml": xhtml("<p>An interlude.</p>"),
        "two.xhtml": xhtml("<p>Second chapter text.</p>"),
    }
    nav = [
        ("prologue.xhtml", "Prologue"),
        ("one.xhtml", "Chapter 1: Start"),
        ("interlude.xhtml", "Interlude"),
        ("two.xhtml", "Chapter 2: Middle"),
    ]
    book = open_epub(build_epub(tmp_path / "b.epub", docs, nav=nav))

    assert book.toc_source == "nav"
    assert [s.section_id for s in book.sections] == [f"section-00{i}" for i in range(1, 5)]
    assert [s.chapter_number for s in book.sections] == [None, 1, None, 2]
    chapter_one = select_section(book, chapter=1, section_id=None)
    assert chapter_one.href == "OEBPS/one.xhtml"
    assert chapter_one.spine_index == 2
    assert [p.text for p in extract_section(book, chapter_one).paragraphs] == [
        "First chapter text."
    ]
    assert _texts(book, "section-003") == ["An interlude."]


def test_ncx_is_used_when_there_is_no_nav(tmp_path: Path) -> None:
    docs = {"a.xhtml": xhtml("<p>Alpha.</p>"), "b.xhtml": xhtml("<p>Beta.</p>")}
    ncx = [("a.xhtml", "Chapter 1"), ("b.xhtml", "Chapter 2")]
    book = open_epub(build_epub(tmp_path / "b.epub", docs, ncx=ncx))

    assert book.toc_source == "ncx"
    assert [s.title for s in book.sections] == ["Chapter 1", "Chapter 2"]
    assert _texts(book, "section-002") == ["Beta."]


def test_malformed_nav_falls_back_to_ncx(tmp_path: Path) -> None:
    docs = {"a.xhtml": xhtml("<p>Alpha.</p>")}
    book = open_epub(
        build_epub(
            tmp_path / "b.epub",
            docs,
            nav_text="<html><body><nav>&nbsp;broken",
            ncx=[("a.xhtml", "Chapter 1")],
        )
    )
    assert book.toc_source == "ncx"
    assert any("nav unusable" in w for w in book.warnings)


def test_spine_fallback_without_any_toc(tmp_path: Path) -> None:
    docs = {
        "a.xhtml": xhtml("<p>Alpha.</p>", title="Chapter 1: Alpha"),
        "b.xhtml": xhtml("<p>Beta.</p>", title="Chapter 2: Beta"),
    }
    book = open_epub(build_epub(tmp_path / "b.epub", docs))
    assert book.toc_source == "spine"
    assert [s.chapter_number for s in book.sections] == [1, 2]
    assert any("fallback" in w for w in book.warnings)


def test_multiple_anchors_in_one_document_are_cut_at_toc_boundaries(tmp_path: Path) -> None:
    body = (
        '<h2 id="c1">Chapter 1</h2><p>One A.</p><div><p>One B.</p></div>'
        '<h2 id="c2">Chapter 2</h2><p>Two A. <a id="c3"></a>Three starts mid-paragraph.</p>'
        "<p>Three B.</p>"
    )
    nav = [
        ("all.xhtml#c1", "Chapter 1"),
        ("all.xhtml#c2", "Chapter 2"),
        ("all.xhtml#c3", "Chapter 3"),
    ]
    book = open_epub(build_epub(tmp_path / "b.epub", {"all.xhtml": xhtml(body)}, nav=nav))

    assert _texts(book, "section-001") == ["Chapter 1", "One A.", "One B."]
    assert _texts(book, "section-002") == ["Chapter 2", "Two A."]
    assert _texts(book, "section-003") == ["Three starts mid-paragraph.", "Three B."]


def test_text_extraction_keeps_characters_and_skips_non_text(tmp_path: Path) -> None:
    body = (
        "<h1>CHAPTER 1<br/>A  TITLE</h1>"
        "<p>Café &amp; “quotes” — dash&#160;and nbsp, Liberté et Égalité.</p>"
        "<p>&lt;System Start&gt;</p>"
        '<div><p>Nested once.</p><img src="x.png" alt="ALT TEXT"/></div>'
        '<p>Page <span epub:type="pagebreak" id="pg12">12</span>break.</p>'
        "<script>var hidden = 1;</script><style>p {}</style>"
        "<p>   </p>"
        "<div>Loose <em>inline</em> text<p>Inner block.</p>tail</div>"
    )
    book = open_epub(
        build_epub(tmp_path / "b.epub", {"c.xhtml": xhtml(body)}, nav=[("c.xhtml", "Chapter 1")])
    )
    chapter = extract_section(book, book.sections[0])

    assert [p.text for p in chapter.paragraphs] == [
        "CHAPTER 1 A TITLE",
        "Café & “quotes” — dash and nbsp, Liberté et Égalité.",
        "<System Start>",
        "Nested once.",
        "Page break.",
        "Loose inline text",
        "Inner block.",
        "tail",
    ]
    assert [p.id for p in chapter.paragraphs][:2] == ["p0001", "p0002"]
    assert chapter.omitted_image_count == 1
    assert "ALT TEXT" not in render_chapter_text(chapter)


def test_section_without_body_text_is_rejected(tmp_path: Path) -> None:
    docs = {"a.xhtml": xhtml('<img src="cover.jpg"/>'), "b.xhtml": xhtml("<p>Text.</p>")}
    book = open_epub(
        build_epub(tmp_path / "b.epub", docs, nav=[("a.xhtml", "Cover"), ("b.xhtml", "Ch")])
    )
    with pytest.raises(EpubError, match="no body text"):
        extract_section(book, book.sections[0])


def test_spine_document_missing_from_toc_is_listed_and_flagged(tmp_path: Path) -> None:
    docs = {
        "one.xhtml": xhtml("<p>Chapter one.</p>"),
        "one-part2.xhtml": xhtml("<p>Continuation.</p>"),
        "two.xhtml": xhtml("<p>Chapter two.</p>"),
    }
    nav = [("one.xhtml", "Chapter 1"), ("two.xhtml", "Chapter 2")]
    book = open_epub(build_epub(tmp_path / "b.epub", docs, nav=nav))

    assert [s.href for s in book.sections] == [
        "OEBPS/one.xhtml",
        "OEBPS/one-part2.xhtml",
        "OEBPS/two.xhtml",
    ]
    assert not book.sections[1].in_toc
    assert "section-002" in book.sections[0].notes[0]
    chapter = extract_section(book, select_section(book, chapter=1, section_id=None))
    assert [p.text for p in chapter.paragraphs] == ["Chapter one."]
    assert chapter.extraction_notes


def test_missing_anchor_is_reported_not_guessed(tmp_path: Path) -> None:
    nav = [("a.xhtml#nowhere", "Chapter 1")]
    book = open_epub(build_epub(tmp_path / "b.epub", {"a.xhtml": xhtml("<p>A.</p>")}, nav=nav))
    with pytest.raises(EpubError, match="anchor #nowhere"):
        select_section(book, chapter=1, section_id=None)


def test_chapter_selection_errors(tmp_path: Path) -> None:
    docs = {"a.xhtml": xhtml("<p>A.</p>"), "b.xhtml": xhtml("<p>B.</p>")}
    nav = [("a.xhtml", "Chapter 1: A"), ("b.xhtml", "Chapter 1: Again")]
    book = open_epub(build_epub(tmp_path / "b.epub", docs, nav=nav))
    with pytest.raises(EpubError, match="--section"):
        select_section(book, chapter=1, section_id=None)
    with pytest.raises(EpubError, match="No section title"):
        select_section(book, chapter=9, section_id=None)
    with pytest.raises(EpubError, match="Unknown section"):
        select_section(book, chapter=None, section_id="section-999")
    with pytest.raises(EpubError, match="exactly one"):
        select_section(book, chapter=1, section_id="section-001")


def test_href_outside_container_is_refused(tmp_path: Path) -> None:
    docs = {"../../evil.xhtml": xhtml("<p>A.</p>")}
    with pytest.raises(EpubError, match="outside the EPUB"):
        open_epub(build_epub(tmp_path / "manifest.epub", docs))

    nav = [("../../etc/passwd", "Chapter 1")]
    book = open_epub(build_epub(tmp_path / "nav.epub", {"a.xhtml": xhtml("<p>A.</p>")}, nav=nav))
    assert any("outside the EPUB" in w for w in book.warnings)
    assert book.toc_source == "spine"


def test_unreadable_epubs_are_refused(tmp_path: Path) -> None:
    not_zip = tmp_path / "plain.epub"
    not_zip.write_text("hello")
    with pytest.raises(EpubError, match="not a valid ZIP"):
        open_epub(not_zip)

    no_container = tmp_path / "empty.epub"
    with zipfile.ZipFile(no_container, "w") as archive:
        archive.writestr("mimetype", "application/epub+zip")
    with pytest.raises(EpubError, match="container.xml"):
        open_epub(no_container)

    with pytest.raises(EpubError, match="Cannot read"):
        open_epub(tmp_path / "missing.epub")


def test_original_epub_is_not_modified(synthetic_epub: Path) -> None:
    before = synthetic_epub.read_bytes()
    book = open_epub(synthetic_epub)
    extract_section(book, book.sections[1])
    assert synthetic_epub.read_bytes() == before


def test_synthetic_epub_chapter_matches_fixture_text(synthetic_epub: Path) -> None:
    book = open_epub(synthetic_epub)
    chapter = extract_section(book, select_section(book, chapter=3, section_id=None))
    expected = (FIXTURES / "synthetic_chapter.txt").read_text(encoding="utf-8")
    assert render_chapter_text(chapter) == expected


@pytest.mark.parametrize(
    ("title", "number"),
    [
        ("Chapter 1: A Battlefield", 1),
        ("CHAPTER 12", 12),
        ("Chapter IV - Roman", 4),
        ("Chapter Civil War", None),
        ("Interlude: The Headless Knight II", None),
        ("Epilogue II: Reboot", None),
    ],
)
def test_parse_chapter_number(title: str, number: int | None) -> None:
    assert parse_chapter_number(title) == number


@pytest.mark.skipif(not SAMPLE_EPUB.is_file(), reason="user sample EPUB not present")
def test_user_sample_chapter_mapping() -> None:
    book = open_epub(SAMPLE_EPUB)
    assert book.title == "86—EIGHTY-SIX, Vol. 1"
    assert [s.section_id for s in book.sections] == [f"section-{i:03d}" for i in range(1, 19)]
    expected = {1: 4, 2: 5, 3: 6, 4: 8, 5: 10, 6: 12, 7: 14}
    for chapter_number, spine_index in expected.items():
        section = select_section(book, chapter=chapter_number, section_id=None)
        assert section.spine_index == spine_index
        assert section.href == f"EPUB/section-{spine_index:03d}.xhtml"

    chapter = extract_section(book, select_section(book, chapter=1, section_id=None))
    assert chapter.source_href == "EPUB/section-004.xhtml"
    assert chapter.paragraphs[0].text.startswith("CHAPTER 1")
    assert chapter.paragraphs[1].text == "There were no casualties on that battlefield."
    previous = extract_section(book, select_section(book, chapter=None, section_id="section-003"))
    following = extract_section(book, select_section(book, chapter=2, section_id=None))

    # Short dialogue lines such as "“…”" legitimately repeat across chapters.
    def long_texts(chapter_input):
        return {p.text for p in chapter_input.paragraphs if len(p.text) > 20}

    assert not long_texts(chapter) & long_texts(previous)
    assert not long_texts(chapter) & long_texts(following)
    assert following.paragraphs[0].text.startswith("CHAPTER 2")
