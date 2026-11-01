from __future__ import annotations

from loremark_story_lab.cumulative_validation import find_spans


def test_find_spans_reports_every_occurrence() -> None:
    assert find_spans("aaa", "aa") == [[0, 2], [1, 3]]
    assert find_spans("“quoted” and “quoted”", "“quoted”") == [[0, 8], [13, 21]]
    assert find_spans("abc", "d") == []
