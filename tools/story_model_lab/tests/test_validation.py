from __future__ import annotations

from typing import Any

from loremark_story_lab.schemas import ChapterInput
from loremark_story_lab.validation import find_spans, validate_candidate


def _codes(report) -> set[str]:
    return {issue.code for issue in report.errors}


def test_synthetic_model_passes(synthetic_chapter: ChapterInput, synthetic_model) -> None:
    report = validate_candidate(synthetic_model, synthetic_chapter)

    assert report.passed, report.issues
    assert report.warnings == []
    assert report.counts["characters"] == 4
    assert report.counts["events"] == 5
    assert report.counts["evidence_items"] == report.counts["evidence_matched"]
    check = report.evidence_by_path()["characters[0].name.evidence[0]"]
    text = synthetic_chapter.paragraphs[1].text
    start, end = check.spans[0]
    assert text[start:end] == "Captain Mira Okonkwo"


def test_reported_claim_and_flashback_are_valid(
    synthetic_chapter: ChapterInput, synthetic_model
) -> None:
    events = synthetic_model["events"]
    assert events[1]["assertion"] == "reported" and events[1]["attributed_to_id"] == "g001"
    assert events[2]["temporal_context"] == "past"
    assert validate_candidate(synthetic_model, synthetic_chapter).passed


def test_fabricated_quote_is_an_error(synthetic_chapter: ChapterInput, synthetic_model) -> None:
    synthetic_model["events"][0]["evidence"][0]["quote"] = "Mira sailed the ferry"
    report = validate_candidate(synthetic_model, synthetic_chapter)

    assert not report.passed
    assert _codes(report) == {"quote_not_found"}
    assert report.errors[0].path == "events[0].evidence[0]"
    assert report.errors[0].record_id == "e001"


def test_quote_from_another_paragraph_is_not_accepted(
    synthetic_chapter: ChapterInput, synthetic_model
) -> None:
    synthetic_model["characters"][2]["name"]["evidence"][0]["paragraph_id"] = "p0002"
    report = validate_candidate(synthetic_model, synthetic_chapter)
    assert _codes(report) == {"quote_not_found"}
    assert "occurs verbatim in p0004" in report.errors[0].message


def test_straightened_quote_marks_are_not_fuzzy_matched(
    synthetic_chapter: ChapterInput, synthetic_model
) -> None:
    synthetic_model["events"][1]["evidence"][0]["quote"] = '"The Harbor Guild says'
    report = validate_candidate(synthetic_model, synthetic_chapter)
    assert _codes(report) == {"quote_not_found"}
    assert "folding" in report.errors[0].message


def test_unknown_paragraph(synthetic_chapter: ChapterInput, synthetic_model) -> None:
    synthetic_model["uncertainties"][0]["evidence"][0]["paragraph_id"] = "p9999"
    assert _codes(validate_candidate(synthetic_model, synthetic_chapter)) == {"unknown_paragraph"}


def test_duplicate_id(synthetic_chapter: ChapterInput, synthetic_model) -> None:
    synthetic_model["locations"][1]["id"] = "c001"
    report = validate_candidate(synthetic_model, synthetic_chapter)
    assert "duplicate_id" in _codes(report)
    # e004 still points at l002, which no longer exists.
    assert "dangling_reference" in _codes(report)


def test_broken_and_wrongly_typed_links(synthetic_chapter: ChapterInput, synthetic_model) -> None:
    synthetic_model["relationships"][0]["target_id"] = "c999"
    synthetic_model["events"][0]["location_id"] = "c001"
    synthetic_model["events"][0]["participant_ids"] = ["l001"]
    synthetic_model["events"][1]["attributed_to_id"] = "l002"
    report = validate_candidate(synthetic_model, synthetic_chapter)

    paths = {(i.code, i.path) for i in report.errors}
    assert ("dangling_reference", "relationships[0].target_id") in paths
    assert ("wrong_reference_kind", "events[0].location_id") in paths
    assert ("wrong_reference_kind", "events[0].participant_ids[0]") in paths
    assert ("wrong_reference_kind", "events[1].attributed_to_id") in paths


def test_empty_model_is_valid_but_flagged(synthetic_chapter: ChapterInput) -> None:
    empty: dict[str, Any] = {
        "characters": [],
        "locations": [],
        "organizations": [],
        "relationships": [],
        "events": [],
        "uncertainties": [],
    }
    report = validate_candidate(empty, synthetic_chapter)
    assert report.passed
    assert {w.code for w in report.warnings} == {"empty_characters", "empty_events"}


def test_missing_evidence_and_empty_text(synthetic_chapter: ChapterInput, synthetic_model) -> None:
    synthetic_model["characters"][0]["attributes"][0]["evidence"] = []
    synthetic_model["relationships"][1]["description"] = "  "
    synthetic_model["events"][2]["evidence"][0]["quote"] = ""
    report = validate_candidate(synthetic_model, synthetic_chapter)
    assert _codes(report) == {"missing_evidence", "empty_text", "empty_quote"}


def test_quote_length_limit(synthetic_chapter: ChapterInput, synthetic_model) -> None:
    synthetic_model["events"][0]["evidence"][0]["quote"] = "x" * 301
    assert _codes(validate_candidate(synthetic_model, synthetic_chapter)) == {"quote_too_long"}


def test_narrative_order_rules(synthetic_chapter: ChapterInput, synthetic_model) -> None:
    events = synthetic_model["events"]
    events[1]["narrative_order"] = 1
    report = validate_candidate(synthetic_model, synthetic_chapter)
    assert any(i.code == "narrative_order" and "repeated" in i.message for i in report.errors)

    events[1]["narrative_order"] = 2
    events[4]["narrative_order"] = 7
    report = validate_candidate(synthetic_model, synthetic_chapter)
    assert report.passed
    assert {w.code for w in report.warnings} == {"narrative_order_gap"}

    events[4]["narrative_order"] = 0
    assert "narrative_order" in _codes(validate_candidate(synthetic_model, synthetic_chapter))


def test_evidence_out_of_narrative_order_is_a_warning(
    synthetic_chapter: ChapterInput, synthetic_model
) -> None:
    events = synthetic_model["events"]
    events[3]["evidence"] = [{"paragraph_id": "p0002", "quote": "Captain Mira Okonkwo"}]
    report = validate_candidate(synthetic_model, synthetic_chapter)
    assert report.passed
    assert "narrative_order_vs_evidence" in {w.code for w in report.warnings}


def test_schema_violations_are_structure_errors(
    synthetic_chapter: ChapterInput, synthetic_model
) -> None:
    synthetic_model["characters"][0]["confidence"] = 0.9
    del synthetic_model["events"][0]["story_time"]
    synthetic_model["events"][1]["assertion"] = "certain"
    report = validate_candidate(synthetic_model, synthetic_chapter)

    assert not report.structure_valid and not report.passed
    paths = {i.path for i in report.errors}
    assert "characters[0].confidence" in paths
    assert "events[0].story_time" in paths
    assert "events[1].assertion" in paths


def test_attribution_without_reported_assertion_warns(
    synthetic_chapter: ChapterInput, synthetic_model
) -> None:
    synthetic_model["relationships"][0]["attributed_to_id"] = "c002"
    report = validate_candidate(synthetic_model, synthetic_chapter)
    assert report.passed
    assert {w.code for w in report.warnings} == {"attribution_without_report"}


def test_find_spans_reports_every_occurrence() -> None:
    assert find_spans("aaa", "aa") == [[0, 2], [1, 3]]
    assert find_spans("“quoted” and “quoted”", "“quoted”") == [[0, 8], [13, 21]]
    assert find_spans("abc", "d") == []
