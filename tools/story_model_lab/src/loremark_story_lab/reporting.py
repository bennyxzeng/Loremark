"""Render review.md from saved structured data (no LLM involved)."""

from __future__ import annotations

import html
import re
from typing import Any

from .schemas import Attribute, ChapterInput, ChapterStoryModel, Entity, Evidence
from .validation import EvidenceCheck, ValidationReport

_MD_SPECIAL = re.compile(r"([\\`*_\[\]|])")

SUPPORT_NOTE = (
    "引用匹配通过只表示该短引用逐字出现在所标段落中，**不代表引用支持对应结论**。"
    "每条主张仍需人工阅读原文判断。"
)


def md(text: str) -> str:
    """Escape model or novel text for inline Markdown."""
    return _MD_SPECIAL.sub(r"\\\1", html.escape(text, quote=False))


def inline_code(value: object) -> str:
    return "—" if value is None else f"`{value}`"


def render_review(
    chapter: ChapterInput,
    run: dict[str, Any],
    report: ValidationReport | None,
    failure: dict[str, Any] | None,
) -> str:
    lines: list[str] = [f"# Story model 审阅报告：{md(chapter.title)}", ""]
    lines += _status_block(run, report, failure)
    lines += _metadata(chapter, run)
    lines += [
        "## 阅读须知",
        "",
        f"- {SUPPORT_NOTE}",
        "- 只输入了本章原文；前文才能确定的身份、指代和原因应出现在“疑点”中，而不是被猜测补全。",
        f"- 本实验只处理文字：本章省略了 {chapter.omitted_image_count} 张图片，图片内容未被读取。",
        "",
    ]
    if failure is not None:
        lines += _failure_section(failure)
    if report is not None:
        lines += _validation_section(report)
        if report.model is not None:
            lines += _model_sections(report.model, report.evidence_by_path())
    lines += _appendix(chapter)
    return "\n".join(lines).rstrip() + "\n"


def _status_block(
    run: dict[str, Any], report: ValidationReport | None, failure: dict[str, Any] | None
) -> list[str]:
    status = run.get("status")
    if failure is not None and report is None:
        headline = f"运行失败（{status}），没有可审阅的模型输出"
    elif report is None:
        headline = f"没有候选输出（{status}）"
    elif report.passed:
        headline = "通过自动校验（结构、ID、引用存在性）；内容是否正确仍需人工审阅"
    elif not report.structure_valid:
        headline = "未通过：候选 JSON 不符合 schema"
    else:
        headline = f"未通过自动校验：{len(report.errors)} 个错误"
    marker = "✅" if report is not None and report.passed and failure is None else "❌"
    lines = [f"> {marker} **状态：{headline}**", ""]
    corrections = run.get("manual_corrections") or []
    if corrections:
        lines += [
            f"> ⚠️ **本结果包含 {len(corrections)} 处人工修正，不是模型原样输出。**"
            "原始输出见 `candidate.original.json`。",
            "",
            "## 人工修正",
            "",
        ]
        for item in corrections:
            lines.append(
                f"- `{item.get('path')}`：{md(str(item.get('from')))} → {md(str(item.get('to')))}"
                f"（{md(str(item.get('reason')))}；{item.get('corrected_by')}，"
                f"{item.get('corrected_at')}）"
            )
        lines.append("")
    return lines


def _metadata(chapter: ChapterInput, run: dict[str, Any]) -> list[str]:
    request = run.get("request") or {}
    response = run.get("response") or {}
    hashes = run.get("hashes") or {}
    lines = [
        "## 运行信息",
        "",
        f"- 运行 ID：{inline_code(run.get('run_id'))}；状态：{inline_code(run.get('status'))}",
        f"- Provider：{inline_code(request.get('provider'))}；"
        f"请求模型：{inline_code(request.get('model'))}；"
        f"响应模型：{inline_code(response.get('model'))}",
        f"- Response ID：{inline_code(response.get('response_id'))}；"
        f"Request ID：{inline_code(response.get('request_id'))}",
        f"- 书籍：{md(chapter.book_title)}；节：`{chapter.section_id}`"
        f"（Chapter {chapter.chapter_number if chapter.chapter_number is not None else '—'}）；"
        f"资源：`{chapter.source_href}`；段落数：{len(chapter.paragraphs)}",
        f"- 文本 SHA-256：`{chapter.text_sha256}`",
        f"- Prompt SHA-256：{inline_code(hashes.get('prompt_sha256'))}；"
        f"Schema SHA-256：{inline_code(hashes.get('schema_sha256'))}",
    ]
    usage = response.get("usage")
    if usage:
        lines.append(
            f"- Usage：input {usage.get('input_tokens')}，output {usage.get('output_tokens')}，"
            f"total {usage.get('total_tokens')}"
        )
    return [*lines, ""]


def _failure_section(failure: dict[str, Any]) -> list[str]:
    error = failure.get("error") or {}
    lines = [
        "## 失败信息",
        "",
        f"- 阶段：`{failure.get('status')}`；类别：`{error.get('category')}`",
    ]
    if error.get("status_code") is not None:
        lines.append(f"- HTTP 状态：`{error.get('status_code')}`")
    message = error.get("message") or error.get("detail")
    if message:
        lines.append(f"- 详情：{md(str(message))[:2000]}")
    lines += ["- 完整诊断见 `failure.json`（以及可获得时的 `response.json`）。", ""]
    return lines


def _validation_section(report: ValidationReport) -> list[str]:
    lines = ["## 自动校验", ""]
    if report.counts:
        counts = report.counts
        lines += [
            f"- 人物 {counts['characters']}，地点 {counts['locations']}，"
            f"组织 {counts['organizations']}，关系 {counts['relationships']}，"
            f"事件 {counts['events']}，疑点 {counts['uncertainties']}",
            f"- 证据 {counts['evidence_items']} 条，其中逐字匹配 {counts['evidence_matched']} 条",
        ]
    lines.append(f"- 错误 {len(report.errors)} 个，警告 {len(report.warnings)} 个")
    lines.append("")
    for title, issues in (("错误", report.errors), ("警告", report.warnings)):
        if not issues:
            continue
        lines += [f"### {title}", ""]
        for issue in issues:
            rid = f" `{issue.record_id}`" if issue.record_id else ""
            lines.append(f"- `{issue.code}`{rid} `{issue.path}`：{md(issue.message)}")
        lines.append("")
    return lines


class _Renderer:
    def __init__(self, model: ChapterStoryModel, checks: dict[str, EvidenceCheck]) -> None:
        self.checks = checks
        self.names = {
            entity.id: entity.name.text
            for entity in (*model.characters, *model.locations, *model.organizations)
        }

    def ref(self, entity_id: str | None) -> str:
        if entity_id is None:
            return "—"
        name = self.names.get(entity_id)
        return f"`{entity_id}` {md(name)}" if name is not None else f"`{entity_id}`（未找到）"

    def evidence(self, path: str, items: list[Evidence], indent: str) -> list[str]:
        if not items:
            return [f"{indent}- 证据：（无）"]
        lines = []
        for index, item in enumerate(items):
            check = self.checks.get(f"{path}.evidence[{index}]")
            if check is not None and check.matched:
                spans = ", ".join(f"{s}–{e}" for s, e in check.spans)
                status = f"✓ 匹配 [{spans}]"
            else:
                status = "✗ 未匹配"
            lines.append(
                f"{indent}- [{md(item.paragraph_id)}](#{item.paragraph_id}) "
                f"“{md(item.quote)}” — {status}"
            )
        return lines

    def tags(
        self, assertion: str, attributed_to_id: str | None, temporal: str | None = None
    ) -> str:
        parts = [assertion]
        if temporal is not None:
            parts.append(temporal)
        text = " · ".join(f"`{p}`" for p in parts)
        if attributed_to_id is not None:
            text += f" · 来源 {self.ref(attributed_to_id)}"
        return text

    def attribute(self, path: str, attribute: Attribute) -> list[str]:
        head = (
            f"  - **{md(attribute.label)}**：{md(attribute.value)} · "
            f"{self.tags(attribute.assertion, attribute.attributed_to_id)}"
        )
        return [head, *self.evidence(path, attribute.evidence, "    ")]

    def entity(self, path: str, entity: Entity) -> list[str]:
        lines = [f"### `{entity.id}` {md(entity.name.text)}", ""]
        lines.append("- 名称证据：")
        lines += self.evidence(f"{path}.name", entity.name.evidence, "  ")
        if entity.aliases:
            lines.append("- 别名：")
            for index, alias in enumerate(entity.aliases):
                alias_path = f"{path}.aliases[{index}]"
                lines.append(f"  - {md(alias.text)}")
                lines += self.evidence(alias_path, alias.evidence, "    ")
        if entity.attributes:
            lines.append("- 属性：")
            for index, attribute in enumerate(entity.attributes):
                lines += self.attribute(f"{path}.attributes[{index}]", attribute)
        return [*lines, ""]


def _model_sections(model: ChapterStoryModel, checks: dict[str, EvidenceCheck]) -> list[str]:
    r = _Renderer(model, checks)
    lines: list[str] = []
    for title, list_name, entities in (
        ("人物", "characters", model.characters),
        ("地点", "locations", model.locations),
        ("组织", "organizations", model.organizations),
    ):
        lines += [f"## {title}（{len(entities)}）", ""]
        if not entities:
            lines += ["（空）需要人工确认本章是否确实没有此类信息。", ""]
        for index, entity in enumerate(entities):
            lines += r.entity(f"{list_name}[{index}]", entity)

    lines += [f"## 关系（{len(model.relationships)}）", ""]
    for index, rel in enumerate(model.relationships):
        path = f"relationships[{index}]"
        lines.append(
            f"- **`{rel.id}`** {r.ref(rel.source_id)} —{md(rel.label)}→ {r.ref(rel.target_id)} · "
            f"{r.tags(rel.assertion, rel.attributed_to_id, rel.temporal_context)}"
        )
        lines.append(f"  - {md(rel.description)}")
        lines += r.evidence(path, rel.evidence, "  ")
    lines.append("")

    lines += [f"## 事件（{len(model.events)}，按本章叙述顺序）", ""]
    if not model.events:
        lines += ["（空）需要人工确认。", ""]
    for index, event in enumerate(model.events):
        path = f"events[{index}]"
        participants = "，".join(r.ref(pid) for pid in event.participant_ids) or "—"
        lines.append(
            f"{event.narrative_order}. **`{event.id}`** {md(event.description)} · "
            f"{r.tags(event.assertion, event.attributed_to_id, event.temporal_context)}"
        )
        lines.append(
            f"   - 参与者：{participants}；地点：{r.ref(event.location_id)}；"
            f"时间：{md(event.story_time) if event.story_time else '—'}"
        )
        lines += r.evidence(path, event.evidence, "   ")
    lines.append("")

    lines += [f"## 疑点（{len(model.uncertainties)}）", ""]
    for index, item in enumerate(model.uncertainties):
        path = f"uncertainties[{index}]"
        related = "，".join(r.ref(eid) for eid in item.related_entity_ids) or "—"
        lines.append(f"- {md(item.question)}（相关：{related}）")
        lines += r.evidence(path, item.evidence, "  ")
    lines.append("")
    return lines


def _appendix(chapter: ChapterInput) -> list[str]:
    lines = ["## 附录：本章原文段落", ""]
    for paragraph in chapter.paragraphs:
        lines += [f'<a id="{paragraph.id}"></a>**[{paragraph.id}]** {md(paragraph.text)}', ""]
    return lines
