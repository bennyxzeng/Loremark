"""Regenerates what the Dart port of the story model lab is checked against.

The lab lives on the `story-model` branch. Unpack it anywhere and run this with its
virtual environment; nothing here calls an API:

    git archive story-model tools/story_model_lab | tar -x -C /tmp/lab
    PYTHONPATH=/tmp/lab/tools/story_model_lab/src \
      tools/story_model_lab/.venv/bin/python tool/story_update/gen_goldens.py \
      --lab /tmp/lab/tools/story_model_lab

Writes assets/story_update/ (the prompt and schema the app sends) and
test/fixtures/story_update/ (synthetic EPUBs, and what the lab makes of them). Only synthetic
text is written, plus section titles and hashes of the sample book when it is present.
"""

from __future__ import annotations

import argparse
import copy
import gzip
import hashlib
import json
import shutil
import sys
import tempfile
from collections.abc import Callable
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]
ASSETS = REPO / "assets" / "story_update"
FIXTURES = REPO / "test" / "fixtures" / "story_update"
SAMPLE = REPO / "sample_epub" / "86v1_chapters.epub"
Delta = dict[str, Any]


def write_json(path: Path, data: Any) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha_json(value: Any) -> str:
    text = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lab", type=Path, required=True, help="tools/story_model_lab folder")
    args = parser.parse_args()
    sys.path.insert(0, str(args.lab / "tests"))

    FIXTURES.mkdir(parents=True, exist_ok=True)
    ASSETS.mkdir(parents=True, exist_ok=True)
    write_assets(args.lab)
    write_extraction_golden()
    write_validation_golden()
    write_request_golden()
    if SAMPLE.is_file():
        write_sample_golden()


def write_assets(lab: Path) -> None:
    from loremark_story_lab.prompting import UPDATE_PROMPT, text_format

    prompt = lab / "src" / "loremark_story_lab" / "prompts" / UPDATE_PROMPT
    shutil.copyfile(prompt, ASSETS / UPDATE_PROMPT)
    write_json(ASSETS / "story_delta.schema.json", text_format()["schema"])


# --- extraction -------------------------------------------------------------------------------


def extraction_books() -> dict[str, dict[str, Any]]:
    """Name -> build_epub arguments, one per way a book can be laid out."""
    from conftest import xhtml

    return {
        "nav_order": {
            "docs": {
                "cover.xhtml": xhtml("<p>Cover words.</p>", "Cover"),
                "intro.xhtml": xhtml("<h1>Prologue</h1><p>It began.</p>", "Intro"),
                "one.xhtml": xhtml("<h1>Chapter One</h1><p>First.</p>"),
                "two.xhtml": xhtml("<h1>II</h1><p>Second.</p>"),
            },
            "nav": [
                ("intro.xhtml", "Prologue"),
                ("one.xhtml", "Chapter 1: Arrival"),
                ("two.xhtml", "CHAPTER IV: Departure"),
            ],
        },
        "ncx_only": {
            "docs": {
                "one.xhtml": xhtml('<h1 id="a">A</h1><p>Alpha.</p><h1 id="b">B</h1><p>Beta.</p>'),
                "two.xhtml": xhtml("<p>Gamma.</p>"),
            },
            "ncx": [
                ("one.xhtml#a", "Chapter 1"),
                ("one.xhtml#b", "Chapter 2"),
                ("two.xhtml", "Chapter 3"),
            ],
        },
        "malformed_nav_uses_ncx": {
            "docs": {"one.xhtml": xhtml("<p>Alpha.</p>")},
            "nav_text": "<html><body><nav",
            "ncx": [("one.xhtml", "Chapter 1")],
        },
        "no_toc": {
            "docs": {
                "one.xhtml": xhtml("<h1>Opening</h1><p>Alpha.</p>", "Title from head"),
                "two.xhtml": xhtml("<p>Beta.</p>", ""),
            },
        },
        "text_rules": {
            "docs": {
                "one.xhtml": xhtml(
                    "<h1>Heading<br/>with a break</h1>"
                    "<p>Plain   text\n with\tspaces&#160;and &#8212; dash &amp; more.</p>"
                    "<p>Café in decomposed form, and “curly” ‘quotes’.</p>"
                    '<p>Before<span epub:type="pagebreak">99</span> after.</p>'
                    '<p>Before<span role="doc-pagebreak">98</span> after two.</p>'
                    "<div>Loose <em>inline</em> words<p>Nested block.</p>tail words</div>"
                    "<blockquote><p>Quoted.</p></blockquote>"
                    "<ul><li>One</li><li>Two <b>bold</b></li></ul>"
                    "<table><tr><td>Cell A</td><td>Cell B</td></tr></table>"
                    '<p><img src="a.png" alt="ignored"/>Picture words.</p>'
                    '<svg xmlns="http://www.w3.org/2000/svg"><text>svg words</text>'
                    '<image href="b.png"/></svg>'
                    "<script>var script = 1;</script><style>p {}</style>"
                    "<!-- a comment --><p>After comment.<![CDATA[cdata words]]></p>"
                    "<noscript>noscript words</noscript><template>template words</template>"
                    "<p>   </p><p>Last.</p>"
                ),
            },
            "nav": [("one.xhtml", "Chapter 1")],
        },
        "anchors": {
            "docs": {
                "one.xhtml": xhtml(
                    '<p>Before the first anchor.</p><h1 id="a">A</h1><p>Alpha.</p>'
                    '<div><h1 id="b">B</h1><p>Beta.</p></div><p>Beta tail.</p>'
                    '<h1 id="c">C</h1><p>Gamma.</p>'
                ),
                "untoc.xhtml": xhtml("<h1>Not listed</h1><p>Unlisted words.</p>", "Unlisted"),
                "two.xhtml": xhtml("<p>Delta.</p>"),
            },
            "nav": [
                ("one.xhtml#a", "Chapter 1"),
                ("one.xhtml#b", "Chapter 2"),
                ("one.xhtml#c", "Chapter 3"),
                ("two.xhtml", "Chapter 4"),
            ],
        },
        "bad_anchors": {
            "docs": {
                "missing.xhtml": xhtml('<h1 id="a">A</h1><p>Alpha.</p><p>Beta.</p>'),
                "repeated.xhtml": xhtml('<h1 id="d">D</h1><p>Delta.</p><h1 id="d">D</h1><p>E.</p>'),
                "head.xhtml": xhtml('<h1 id="ok">OK</h1><p>Okay.</p><style id="s">p {}</style>'),
                "same.xhtml": xhtml('<p id="x">Same.</p>'),
                "good.xhtml": xhtml("<p>Good words.</p>"),
            },
            "nav": [
                ("missing.xhtml#a", "Chapter 1"),
                ("missing.xhtml#gone", "Chapter 2"),
                ("repeated.xhtml#d", "Chapter 3"),
                ("head.xhtml#ok", "Chapter 4"),
                ("head.xhtml#s", "Chapter 5"),
                ("same.xhtml", "Chapter 6"),
                ("same.xhtml#x", "Chapter 7"),
                ("good.xhtml", "Chapter 8"),
            ],
        },
        "toc_oddities": {
            "docs": {
                "one.xhtml": xhtml("<p>Alpha.</p>"),
                "empty.xhtml": xhtml('<img src="plate.png"/>'),
                "two.xhtml": xhtml("<p>Beta.</p>"),
            },
            "nav": [
                ("one.xhtml", "Chapter 1"),
                ("one.xhtml", "Chapter 1"),
                ("nowhere.xhtml", "Not in the spine"),
                ("empty.xhtml", "Plate"),
                ("two.xhtml", ""),
            ],
        },
        "blocked_later": {
            "docs": {
                "good.xhtml": xhtml("<p>Good words.</p>"),
                "bad.xhtml": xhtml("<p>Words the anchor never finds.</p>"),
            },
            "nav": [("good.xhtml", "Chapter 1"), ("bad.xhtml#gone", "Chapter 2")],
        },
        "spine_order": {
            "docs": {
                "first.xhtml": xhtml("<p>Second in the spine.</p>"),
                "second.xhtml": xhtml("<p>First in the spine.</p>"),
            },
            "nav": [("first.xhtml", "Chapter 2"), ("second.xhtml", "Chapter 1")],
            "spine": ["second.xhtml", "first.xhtml", "second.xhtml"],
        },
    }


def describe_book(path: Path) -> dict[str, Any]:
    from loremark_story_lab.epub import EpubError, extract_section, open_epub

    book = open_epub(path)
    sections = []
    for section in book.sections:
        item: dict[str, Any] = {
            "section_id": section.section_id,
            "order": section.order,
            "title": section.title,
            "chapter_number": section.chapter_number,
            "href": section.href,
            "fragment": section.fragment,
            "spine_index": section.spine_index,
            "in_toc": section.in_toc,
            "has_problem": section.problem is not None,
            "notes": section.notes,
        }
        try:
            item["input"] = extract_section(book, section).model_dump(mode="json")
        except EpubError:
            item["input"] = None
        sections.append(item)
    return {
        "title": book.title,
        "sha256": book.sha256,
        "toc_source": book.toc_source,
        "warnings": book.warnings,
        "sections": sections,
    }


def write_extraction_golden() -> None:
    from conftest import build_epub, xhtml

    golden = {}
    for name, arguments in extraction_books().items():
        path = FIXTURES / f"{name}.epub"
        build_epub(path, title=f"Book {name}", **arguments)
        golden[name] = describe_book(path)
    write_json(FIXTURES / "extraction_golden.json", golden)
    # Not in the golden file: BeautifulSoup guesses at this document, and the port flags it.
    build_epub(
        FIXTURES / "malformed_document.epub",
        {
            "good.xhtml": xhtml("<p>Good words.</p>"),
            "broken.xhtml": "<html><body><p>Never closed</body></html>",
        },
        nav=[("good.xhtml", "Chapter 1"), ("broken.xhtml", "Chapter 2")],
        title="Book malformed_document",
    )


def write_sample_golden() -> None:
    from loremark_story_lab.epub import EpubError, extract_section, open_epub

    book = open_epub(SAMPLE)
    sections = []
    for section in book.sections:
        item: dict[str, Any] = {
            "section_id": section.section_id,
            "title": section.title,
            "chapter_number": section.chapter_number,
            "href": section.href,
            "fragment": section.fragment,
        }
        try:
            chapter = extract_section(book, section)
        except EpubError:
            item["text_sha256"] = None
        else:
            item["text_sha256"] = chapter.text_sha256
            item["paragraph_count"] = len(chapter.paragraphs)
        sections.append(item)
    write_json(FIXTURES / "sample_book_golden.json", {"sha256": book.sha256, "sections": sections})


# --- validation -------------------------------------------------------------------------------


def _record(delta: Delta, collection: str, index: int = 0) -> dict[str, Any]:
    return delta["new_records"][collection][index]


def _copy_record(delta: Delta, collection: str, local_id: str, **payload: Any) -> dict[str, Any]:
    """A new record copied from the collection's first, with payload fields replaced."""
    record = copy.deepcopy(_record(delta, collection))
    record["local_id"] = local_id
    record["payload"].update(payload)
    delta["new_records"][collection].append(record)
    return record


def _set(mutate: Callable[[Delta], Any]) -> Callable[[Delta], Delta]:
    def apply(delta: Delta) -> Delta:
        mutate(delta)
        return delta

    return apply


def _no_identity_or_resolve(delta: Delta) -> None:
    delta["new_records"]["identity_links"].clear()


def validation_cases(base_payloads: dict[str, Any]) -> dict[str, Callable[[Delta], Any]]:
    """Name -> a change to the Chapter 2 delta that a check must notice."""
    next_record = "f000023"  # base has 22 records, so this is the first new stable ID

    def _evidence(delta: Delta) -> dict[str, Any]:
        return _record(delta, "names")["evidence"][0]

    return {
        "clean": lambda d: d,
        # structure
        "not_an_object": lambda d: ["not", "a", "delta"],
        "missing_top_level": _set(lambda d: d.pop("transitions")),
        "missing_field": _set(lambda d: d["new_entities"][0].pop("kind")),
        "extra_field": _set(lambda d: d["new_entities"][0].update(extra=1)),
        "bad_enum": _set(lambda d: _record(d, "attributes")["payload"].update(assertion="maybe")),
        "bad_kind": _set(lambda d: d["new_entities"][0].update(kind="vehicle")),
        "not_an_integer": _set(lambda d: _record(d, "events")["payload"].update(narrative_order="x")),
        "null_string": _set(lambda d: _record(d, "names")["payload"].update(text=None)),
        "not_a_list": _set(lambda d: d.update(new_entities={})),
        # local IDs and references
        "duplicate_local_entity": _set(lambda d: d["new_entities"].append(dict(d["new_entities"][0]))),
        "duplicate_local_record": _set(
            lambda d: _record(d, "names", 1).update(local_id=_record(d, "names")["local_id"])
        ),
        "bad_local_entity_id": _set(lambda d: d["new_entities"].append({"local_id": "x", "kind": "location"})),
        "stable_id_as_local": _set(lambda d: d["new_entities"].append({"local_id": "c001", "kind": "character"})),
        "bad_local_record_id": _set(lambda d: _record(d, "names").update(local_id="rec1")),
        "unknown_entity": _set(lambda d: _record(d, "names")["payload"].update(entity_id="c999")),
        "target_is_new": _set(lambda d: d["transitions"][0].update(target_record_id="new_record_001")),
        "unknown_replacement": _set(lambda d: d["transitions"][0].update(replacement_local_id="new_record_999")),
        # evidence
        "quote_not_found": _set(lambda d: _evidence(d).update(quote="Words that are not there")),
        "quote_folds_only": _set(lambda d: _evidence(d).update(quote="the engineer mara quill")),
        "quote_in_other_paragraph": _set(lambda d: _evidence(d).update(paragraph_id="p0002")),
        "unknown_paragraph": _set(lambda d: _evidence(d).update(paragraph_id="p9999")),
        "evidence_other_section": _set(lambda d: _evidence(d).update(section_id="section-002")),
        "empty_quote": _set(lambda d: _evidence(d).update(quote="   ")),
        "long_quote": _set(lambda d: _evidence(d).update(quote="x" * 301)),
        "no_evidence": _set(lambda d: _record(d, "names").update(evidence=[])),
        "transition_no_evidence": _set(lambda d: d["transitions"][0].update(evidence=[])),
        # payloads
        "empty_name": _set(lambda d: _record(d, "names")["payload"].update(text=" ")),
        "empty_attribute": _set(lambda d: _record(d, "attributes")["payload"].update(label="", value=" ")),
        "empty_relationship": _set(lambda d: _record(d, "relationships")["payload"].update(label="", description="")),
        "empty_event": _set(lambda d: _record(d, "events")["payload"].update(description=" ")),
        "empty_question": _set(lambda d: _record(d, "uncertainties")["payload"].update(question="")),
        "empty_explanation": _set(lambda d: _record(d, "identity_links")["payload"].update(explanation="")),
        "self_relationship": _set(lambda d: _record(d, "relationships")["payload"].update(target_id="c001")),
        "wrong_participant_kind": _set(lambda d: _record(d, "events")["payload"].update(participant_ids=["l001"])),
        "repeated_participant": _set(lambda d: _record(d, "events")["payload"].update(participant_ids=["c001", "c001"])),
        "wrong_location_kind": _set(lambda d: _record(d, "events")["payload"].update(location_id="c001")),
        "attribution_not_reported": _set(lambda d: _record(d, "attributes")["payload"].update(attributed_to_id="c001")),
        "wrong_speaker_kind": _set(
            lambda d: _record(d, "attributes")["payload"].update(assertion="reported", attributed_to_id="l001")
        ),
        "self_identity": _set(lambda d: _record(d, "identity_links")["payload"].update(right_entity_id="c002")),
        "identity_kinds_differ": _set(lambda d: _record(d, "identity_links")["payload"].update(right_entity_id="l001")),
        "identity_conflict": _set(
            lambda d: (
                _copy_record(d, "attributes", "new_record_020", entity_id="c002", label="Rank", value="Sailor"),
                _copy_record(d, "attributes", "new_record_021", entity_id="c004", label="rank", value="Tinker"),
            )
        ),
        # events
        "event_order_zero": _set(lambda d: _record(d, "events")["payload"].update(narrative_order=0)),
        "event_order_repeated": _set(lambda d: _record(d, "events", 1)["payload"].update(narrative_order=1)),
        "event_order_backwards": _set(
            lambda d: (
                _record(d, "events", 0)["payload"].update(narrative_order=2),
                _record(d, "events", 1)["payload"].update(narrative_order=1),
            )
        ),
        "event_order_gap": _set(lambda d: _record(d, "events", 1)["payload"].update(narrative_order=5)),
        # duplicates
        "duplicate_claim": _set(lambda d: _record(d, "aliases")["payload"].update(base_payloads["alias"])),
        # transitions
        "dangling_target": _set(lambda d: d["transitions"][0].update(target_record_id="f999999")),
        "target_not_prior": _set(lambda d: d["transitions"][0].update(target_record_id=next_record)),
        "target_twice": _set(lambda d: d["transitions"][1].update(target_record_id=d["transitions"][0]["target_record_id"])),
        "supersede_no_replacement": _set(lambda d: d["transitions"][0].update(replacement_local_id=None)),
        "supersede_with_resolution": _set(lambda d: d["transitions"][0].update(resolution="An answer")),
        "replacement_reused": _set(
            lambda d: d["transitions"][1].update(replacement_local_id=d["transitions"][0]["replacement_local_id"])
        ),
        "supersede_other_collection": _set(lambda d: d["transitions"][0].update(replacement_local_id="new_record_001")),
        "supersede_other_label": _set(lambda d: _record(d, "attributes")["payload"].update(label="grade")),
        "supersede_other_direction": _set(
            lambda d: _record(d, "relationships")["payload"].update(source_id="c002", target_id="c001")
        ),
        "supersede_other_time": _set(lambda d: _record(d, "relationships")["payload"].update(temporal_context="past")),
        "supersede_name_other_entity": _set(
            lambda d: (
                d["transitions"][0].update(target_record_id="f000001", replacement_local_id="new_record_001"),
            )
        ),
        "supersede_event_is_flagged": _set(
            lambda d: d["transitions"][0].update(target_record_id=base_payloads["event_id"], replacement_local_id="new_record_009")
        ),
        "retract_with_replacement": _set(lambda d: d["transitions"][2].update(replacement_local_id="new_record_001")),
        "retract_with_resolution": _set(lambda d: d["transitions"][2].update(resolution="An answer")),
        "resolve_with_replacement": _set(lambda d: d["transitions"][3].update(replacement_local_id="new_record_012")),
        "resolve_no_answer": _set(lambda d: d["transitions"][3].update(resolution=" ")),
        "resolve_not_uncertainty": _set(lambda d: d["transitions"][3].update(target_record_id="f000001")),
        "empty_reason": _set(lambda d: d["transitions"][0].update(reason="")),
        "bad_action": _set(lambda d: d["transitions"][0].update(action="delete")),
        # names
        "entity_without_name": _set(lambda d: d["new_records"]["names"].pop(0)),
        "second_active_name": _set(
            lambda d: _copy_record(d, "names", "new_record_020", entity_id="c001", text="Another Name")
        ),
        "name_retracted": _set(
            lambda d: d["transitions"].append(
                {
                    "target_record_id": "f000001",
                    "action": "retract",
                    "replacement_local_id": None,
                    "resolution": None,
                    "reason": "No longer the name.",
                    "evidence": copy.deepcopy(d["transitions"][0]["evidence"]),
                }
            )
        ),
        # a delta with nothing in it
        "empty_delta": lambda d: {
            "new_entities": [],
            "new_records": {name: [] for name in d["new_records"]},
            "transitions": [],
        },
    }


def _issues(issues: list[Any]) -> list[dict[str, str]]:
    return [{"severity": i.severity, "code": i.code, "path": i.path} for i in issues]


def write_validation_golden() -> None:
    from conftest import build_story_epub, story_chapter, story_delta
    from loremark_story_lab.cumulative_schemas import RevisionInfo
    from loremark_story_lab.cumulative_validation import validate_cumulative, validate_update
    from loremark_story_lab.epub import open_epub
    from loremark_story_lab.incremental_pipeline import UpdatePlan, empty_model
    from loremark_story_lab.story_store import section_source

    epub = FIXTURES / "story.epub"
    build_story_epub(epub)
    book = open_epub(epub)
    chapter1 = story_chapter(epub, "section-002")
    chapter2 = story_chapter(epub, "section-003")
    start = next(s for s in book.sections if s.section_id == "section-002")
    empty = empty_model(book, UpdatePlan(start, chapter1, already_processed=False))

    def revision(number: int, parent: str | None, sha: str | None) -> RevisionInfo:
        return RevisionInfo(
            number=number,
            id=f"rev{number}",
            created_at="2026-01-01T00:00:00Z",
            source_run_id=f"run{number}",
            parent_snapshot_path=parent,
            parent_sha256=sha,
        )

    section1, _, _ = section_source(chapter1, section_order=2, revision=1)
    first = validate_update(
        empty,
        story_delta("chapter1_delta.json"),
        chapter=chapter1,
        base_inputs={},
        section=section1,
        revision=revision(1, None, None),
    )
    assert first.passed, first.errors
    base = first.after
    assert base is not None
    base_inputs = {"section-002": chapter1}

    base_payloads = {
        "alias": base.records.aliases[0].payload.model_dump(mode="json"),
        "event_id": base.records.events[0].id,
    }
    rev2 = revision(2, "revisions/000001-rev1.json", "0" * 64)
    cases = []
    for name, mutate in validation_cases(base_payloads).items():
        for check_quotes in (True, False):
            candidate = mutate(copy.deepcopy(story_delta()))
            section, _, _ = section_source(
                chapter2, section_order=3, revision=2, quotes_checked=check_quotes
            )
            result = validate_update(
                base,
                candidate,
                chapter=chapter2,
                base_inputs=base_inputs,
                section=section,
                revision=rev2,
            )
            case: dict[str, Any] = {
                "name": name,
                "check_quotes": check_quotes,
                "candidate": candidate,
                "structure_valid": result.structure_valid,
                "passed": result.passed,
                "issues": _issues(result.issues),
            }
            if result.after is not None:
                case["after_sha"] = sha_json(result.after.model_dump(mode="json"))
                case["id_map"] = result.id_map.to_json() if result.id_map else None
            cases.append(case)

    after = None
    clean = validate_update(
        base,
        story_delta(),
        chapter=chapter2,
        base_inputs=base_inputs,
        section=section_source(chapter2, section_order=3, revision=2)[0],
        revision=rev2,
    )
    assert clean.passed, clean.errors
    after = clean.after
    assert after is not None
    inputs = {**base_inputs, "section-003": chapter2}

    def tampered(mutate: Callable[[dict[str, Any]], Any]) -> dict[str, Any]:
        data = after.model_dump(mode="json")
        mutate(data)
        return data

    whole_model = {
        "untouched": lambda m: None,
        "current_active": lambda m: m["current"]["active_record_ids"].pop(),
        "current_resolved": lambda m: m["current"]["resolved_uncertainty_ids"].clear(),
        "current_groups": lambda m: m["current"]["identity_groups"].clear(),
        "section_count": lambda m: m["processed_sections"].pop(),
        "section_order": lambda m: m["processed_sections"][1].update(section_order=1),
        "section_duplicate": lambda m: m["processed_sections"][1].update(section_id="section-002"),
        "input_mismatch_hash": lambda m: m["processed_sections"][0].update(text_sha256="0" * 64),
        "input_mismatch_book": lambda m: m["book"].update(epub_sha256="0" * 64),
        "coverage_start": lambda m: m["coverage"].update(start_section_id="section-009"),
        "coverage_overlap": lambda m: m["coverage"]["omitted_prefix_section_ids"].append("section-002"),
        "revision_zero": lambda m: m["revision"].update(number=0),
        "revision_no_id": lambda m: m["revision"].update(id=" "),
        "revision_no_parent": lambda m: m["revision"].update(parent_snapshot_path=None),
        "revision_one_with_parent": lambda m: (
            m["revision"].update(number=1),
            m["processed_sections"].pop(),
        ),
        "entity_duplicate": lambda m: m["entities"].append(dict(m["entities"][0])),
        "entity_id_format": lambda m: m["entities"][0].update(id="person1"),
        "entity_revision": lambda m: m["entities"][0].update(introduced_revision=9),
        "record_duplicate": lambda m: m["records"]["names"].append(copy.deepcopy(m["records"]["names"][0])),
        "record_id_format": lambda m: m["records"]["names"][0].update(id="n1"),
        "record_revision": lambda m: m["records"]["names"][0].update(introduced_revision=9),
        "record_section": lambda m: m["records"]["names"][0].update(learned_in_section_id="section-099"),
        "record_section_revision": lambda m: m["records"]["names"][0].update(learned_in_section_id="section-003"),
        "reference_from_future": lambda m: m["records"]["aliases"][0]["payload"].update(
            entity_id=next(e["id"] for e in m["entities"] if e["introduced_revision"] == 2)
        ),
        "transition_duplicate": lambda m: m["transitions"].append(copy.deepcopy(m["transitions"][0])),
        "transition_id_format": lambda m: m["transitions"][0].update(id="x1"),
        "replacement_old_revision": lambda m: m["transitions"][0].update(replacement_record_id="f000002"),
        "replacement_missing": lambda m: m["transitions"][0].update(replacement_record_id="f999999"),
    }
    whole = []
    for name, mutate in whole_model.items():
        model = tampered(mutate)
        from loremark_story_lab.cumulative_schemas import CumulativeStoryModel

        report = validate_cumulative(CumulativeStoryModel.model_validate(model), inputs)
        whole.append({"name": name, "model": model, "issues": _issues(report.issues)})

    # Many near-identical whole models, so it is kept compressed (mtime 0: stable bytes).
    golden = json.dumps(
        {
            "empty": empty.model_dump(mode="json"),
            "first": {
                "candidate": story_delta("chapter1_delta.json"),
                "chapter": chapter1.model_dump(mode="json"),
                "section": section1.model_dump(mode="json"),
                "revision": revision(1, None, None).model_dump(mode="json"),
                "after": base.model_dump(mode="json"),
                "id_map": first.id_map.to_json() if first.id_map else None,
                "issues": _issues(first.issues),
            },
            "chapter": chapter2.model_dump(mode="json"),
            "section_order": 3,
            "revision": rev2.model_dump(mode="json"),
            "cases": cases,
            "whole_model": whole,
        },
        ensure_ascii=False,
    )
    with (FIXTURES / "validation_golden.json.gz").open("wb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="wb", mtime=0) as compressed:
            compressed.write(golden.encode("utf-8"))


# --- requests ---------------------------------------------------------------------------------


def write_request_golden() -> None:
    """The real SDK's request bodies, through a mock transport, with long parts hashed."""
    from conftest import (
        DEEPSEEK_ENV,
        build_story_epub,
        delta_api,
        story_delta,
        update_store,
    )

    openai_env = {"OPENAI_API_KEY": "sk-test-secret", "OPENAI_MODEL": "gpt-6.1-terra"}
    golden = []
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        epub = build_story_epub(root / "story.epub")
        for provider, env, effort in (
            ("deepseek", DEEPSEEK_ENV, "high"),
            ("deepseek", DEEPSEEK_ENV, None),
            ("openai", openai_env, "low"),
        ):
            store = root / f"{provider}-{effort}"
            first = delta_api(story_delta("chapter1_delta.json"))
            outcome = update_store(
                store,
                epub,
                first,
                root / "runs" / f"{provider}-{effort}-1",
                section="section-002",
                provider=provider,
                env=env,
                reasoning_effort=effort,
            )
            assert outcome.status == "committed", outcome.status
            golden.append(_request_case(provider, env, effort, "section-002", 0, first.body()))

            second = delta_api(story_delta())
            outcome = update_store(
                store,
                epub,
                second,
                root / "runs" / f"{provider}-{effort}-2",
                provider=provider,
                env=env,
                reasoning_effort=effort,
            )
            assert outcome.status == "committed", outcome.status
            golden.append(_request_case(provider, env, effort, "section-003", 1, second.body()))
    write_json(FIXTURES / "request_golden.json", golden)


def _request_case(
    provider: str, env: dict[str, str], effort: str | None, section: str, base: int, body: Any
) -> dict[str, Any]:
    body["input"][0]["content"] = hashlib.sha256(body["input"][0]["content"].encode()).hexdigest()
    body["text"]["format"]["schema"] = sha_json(body["text"]["format"]["schema"])
    model = env["OPENAI_MODEL"] if provider == "openai" else env["DEEPSEEK_MODEL"]
    return {
        "provider": provider,
        "model": model,
        "effort": effort,
        "section_id": section,
        "base_revision": base,
        "body": body,
    }


if __name__ == "__main__":
    main()
