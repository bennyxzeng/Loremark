"""Markdown views of a cumulative model and update reports, from saved data (no LLM).

Every view is built from one revision only: a historical snapshot never borrows names,
aliases, identity merges, or answers from a later revision.
"""

from __future__ import annotations

from typing import Any

from .cumulative_schemas import (
    AttributePayload,
    CumulativeStoryModel,
    EntityTextPayload,
    EventPayload,
    EvidenceV2,
    IdentityLinkPayload,
    Record,
    RecordTransition,
    RelationshipPayload,
    UncertaintyPayload,
)
from .cumulative_validation import UpdateValidation
from .merge import IdMap, record_index
from .reporting import SUPPORT_NOTE, inline_code, md
from .schemas import ChapterInput

KIND_TITLES = {"character": "人物", "location": "地点", "organization": "组织"}
COLLECTION_TITLES = {
    "names": "名称",
    "aliases": "别名",
    "attributes": "属性",
    "relationships": "关系",
    "events": "事件",
    "uncertainties": "疑点",
    "identity_links": "身份链接",
}
ACTION_TITLES = {"supersede": "替代", "retract": "撤回", "resolve": "解答"}
REVIEW_FOCUS_CODES = {
    "semantic_supersede_review",
    "name_conflict",
    "no_active_name",
    "identity_attribute_conflict",
    "duplicate_claim",
    "empty_delta",
    "replacement_reused",
}


def display_names(model: CumulativeStoryModel) -> tuple[dict[str, str], dict[str, list[str]]]:
    """Display name of every entity in this revision, and entities with several active names.

    The newest active name record wins (then the lowest record ID); without one, the ID.
    """
    active = set(model.current.active_record_ids)
    by_entity: dict[str, list[Record[Any]]] = {}
    for record in model.records.names:
        if record.id in active:
            by_entity.setdefault(record.payload.entity_id, []).append(record)
    names: dict[str, str] = {}
    conflicts: dict[str, list[str]] = {}
    for entity in model.entities:
        candidates = sorted(
            by_entity.get(entity.id, []), key=lambda r: (-r.introduced_revision, r.id)
        )
        names[entity.id] = candidates[0].payload.text if candidates else entity.id
        if len(candidates) > 1:
            conflicts[entity.id] = [r.payload.text for r in candidates]
    return names, conflicts


class _View:
    def __init__(self, model: CumulativeStoryModel) -> None:
        self.model = model
        self.index = record_index(model)
        self.active = set(model.current.active_record_ids)
        self.names, self.conflicts = display_names(model)
        self.transitions = {t.target_record_id: t for t in model.transitions}
        self.groups = {
            member: group for group in model.current.identity_groups for member in group.member_ids
        }

    def ref(self, entity_id: str | None) -> str:
        if entity_id is None:
            return "—"
        if entity_id not in self.names:
            return f"`{entity_id}`（未找到）"
        name = self.names[entity_id]
        return f"`{entity_id}`" if name == entity_id else f"`{entity_id}` {md(name)}"

    def evidence(self, items: list[EvidenceV2]) -> str:
        return "；".join(
            f"[{item.section_id}:{item.paragraph_id}] “{md(item.quote)}”" for item in items
        )

    def tags(self, assertion: str, attributed_to: str | None, temporal: str | None = None) -> str:
        parts = [assertion] + ([temporal] if temporal else [])
        text = " · ".join(f"`{p}`" for p in parts)
        if attributed_to is not None:
            text += f" · 来源 {self.ref(attributed_to)}"
        return text

    def payload_tags(self, payload: RelationshipPayload | EventPayload) -> str:
        return self.tags(payload.assertion, payload.attributed_to_id, payload.temporal_context)

    def claim(self, record_id: str) -> str:
        """One line describing a record's payload."""
        found = self.index.get(record_id)
        if found is None:
            return f"`{record_id}`（未找到）"
        collection, record = found
        payload = record.payload
        if isinstance(payload, EntityTextPayload):
            title = COLLECTION_TITLES[collection]
            text = f"{title} “{md(payload.text)}”（{self.ref(payload.entity_id)}）"
        elif isinstance(payload, AttributePayload):
            text = (
                f"{self.ref(payload.entity_id)} **{md(payload.label)}**：{md(payload.value)} · "
                f"{self.tags(payload.assertion, payload.attributed_to_id)}"
            )
        elif isinstance(payload, RelationshipPayload):
            text = (
                f"{self.ref(payload.source_id)} —{md(payload.label)}→ {self.ref(payload.target_id)}"
                f"：{md(payload.description)} · {self.payload_tags(payload)}"
            )
        elif isinstance(payload, EventPayload):
            text = f"事件：{md(payload.description)} · {self.payload_tags(payload)}"
        elif isinstance(payload, UncertaintyPayload):
            text = f"疑点：{md(payload.question)}"
        else:
            text = self.identity(payload)
        return f"`{record_id}` {text}"

    def identity(self, payload: IdentityLinkPayload) -> str:
        return (
            f"{self.ref(payload.left_entity_id)} ＝ {self.ref(payload.right_entity_id)} · "
            f"`{payload.assertion}`：{md(payload.explanation)}"
        )

    def transition(self, item: RecordTransition, indent: str = "") -> list[str]:
        head = (
            f"{indent}- `{item.id}` revision {item.introduced_revision} · "
            f"`{item.learned_in_section_id}` · **{item.action}**（{ACTION_TITLES[item.action]}）"
        )
        lines = [head, f"{indent}  - 旧：{self.claim(item.target_record_id)}"]
        if item.replacement_record_id is not None:
            lines.append(f"{indent}  - 新：{self.claim(item.replacement_record_id)}")
            replacement = self.index.get(item.replacement_record_id)
            if replacement is not None:
                lines.append(f"{indent}    - 新记录证据：{self.evidence(replacement[1].evidence)}")
        if item.resolution is not None:
            lines.append(f"{indent}  - 答案：{md(item.resolution)}")
        lines.append(f"{indent}  - 理由：{md(item.reason)}")
        lines.append(f"{indent}  - 本节证据：{self.evidence(item.evidence)}")
        return lines


# --- `show` ------------------------------------------------------------------------------------


def render_story_markdown(model: CumulativeStoryModel) -> str:
    view = _View(model)
    revision = model.revision
    lines = [
        f"# Story model：{md(model.book.title)} · revision {revision.number}",
        "",
        f"> {SUPPORT_NOTE}这是逐节自动抽取并累计的结果，不是事实真相。",
        "",
    ]
    lines += _coverage(model, view)
    lines += _identities(view)
    for kind in ("character", "location", "organization"):
        lines += _entities(view, kind)
    lines += _relationships(view)
    lines += _events(view)
    lines += _uncertainties(view)
    lines += [f"## 修订历史（{len(model.transitions)} 条状态转换）", ""]
    if not model.transitions:
        lines += ["（无）", ""]
    for item in model.transitions:
        lines += view.transition(item)
    return "\n".join(lines).rstrip() + "\n"


def _coverage(model: CumulativeStoryModel, view: _View) -> list[str]:
    revision = model.revision
    counts = {kind: 0 for kind in KIND_TITLES}
    for entity in model.entities:
        counts[entity.kind] += 1
    total_records = len(view.index)
    lines = [
        "## 覆盖范围",
        "",
        f"- 修订 {revision.number}（`{revision.id}`），创建于 {revision.created_at}，"
        f"来源运行 `{revision.source_run_id}`",
        f"- 已处理 {len(model.processed_sections)} 节（按阅读顺序）：",
    ]
    for section in model.processed_sections:
        number = section.chapter_number if section.chapter_number is not None else "—"
        lines.append(
            f"  - `{section.section_id}`（Chapter {number}）{md(section.title)} · "
            f"revision {section.introduced_revision} · {section.paragraph_count} 段"
        )
    omitted = model.coverage.omitted_prefix_section_ids
    start = f"- 起点：`{model.coverage.start_section_id}`。"
    if omitted:
        start += (
            f"之前未处理的节：{'、'.join(f'`{sid}`' for sid in omitted)}。"
            "本模型不包含这些节的信息，不代表“全书开头到当前”的完整状态。"
        )
    lines.append(start)
    corrections = model.provenance.imported_manual_corrections
    if corrections:
        lines.append(
            f"- ⚠️ 导入的初始模型含 {len(corrections)} 处人工修正，不是模型原样输出"
            f"（初始运行 `{model.provenance.initial_run_id}`）："
        )
        for item in corrections:
            change = f"{md(item.original)} → {md(item.corrected)}"
            lines.append(f"  - `{item.path}`：{change}（{md(item.reason)}）")
    updates = model.provenance.update_manual_corrections
    if updates:
        revisions = sorted({item.revision for item in updates})
        lines.append(
            f"- ⚠️ revision {'、'.join(map(str, revisions))} 的增量含 {len(updates)} 处人工修正"
            "（只改证据位置），不是模型原样输出："
        )
        for item in updates:
            change = f"{md(item.original)} → {md(item.corrected)}"
            target = f"`{item.record_id}` " if item.record_id else ""
            lines.append(
                f"  - revision {item.revision} {target}`{item.path}`：{change}（{md(item.reason)}）"
            )
    lines += [
        f"- 统计：实体 {len(model.entities)}（人物 {counts['character']}、地点 "
        f"{counts['location']}、组织 {counts['organization']}）；有效记录 {len(view.active)} / "
        f"共 {total_records}；状态转换 {len(model.transitions)}",
        "",
    ]
    return lines


def _identities(view: _View) -> list[str]:
    groups = view.model.current.identity_groups
    others = [
        r
        for r in view.model.records.identity_links
        if r.id in view.active and r.payload.assertion != "explicit"
    ]
    if not groups and not others:
        return []
    lines = ["## 身份", ""]
    if groups:
        lines += ["### 已合并（explicit 身份链接）", ""]
        for group in groups:
            members = " ＝ ".join(view.ref(member) for member in group.member_ids)
            links = "、".join(f"`{rid}`" for rid in group.link_record_ids)
            lines.append(f"- {members}（显示用 `{group.canonical_id}`；链接 {links}）")
        lines.append("")
    if others:
        lines += ["### 推断或转述的身份链接（未合并）", ""]
        for record in others:
            lines.append(f"- `{record.id}` {view.identity(record.payload)}")
            lines.append(f"  - 证据：{view.evidence(record.evidence)}")
        lines.append("")
    return lines


def _active(view: _View, collection: str) -> list[Record[Any]]:
    return [r for r in getattr(view.model.records, collection) if r.id in view.active]


def _entities(view: _View, kind: str) -> list[str]:
    entities = [e for e in view.model.entities if e.kind == kind]
    lines = [f"## {KIND_TITLES[kind]}（{len(entities)}）", ""]
    by_entity: dict[str, dict[str, list[Record[Any]]]] = {}
    for collection in ("names", "aliases", "attributes"):
        for record in _active(view, collection):
            by_entity.setdefault(record.payload.entity_id, {}).setdefault(collection, []).append(
                record
            )
    for entity in entities:
        records = by_entity.get(entity.id, {})
        lines += [f"### {view.ref(entity.id)}", ""]
        if entity.introduced_revision > 1:
            lines.append(f"- 首次出现于 revision {entity.introduced_revision}")
        group = view.groups.get(entity.id)
        if group is not None:
            others = [view.ref(m) for m in group.member_ids if m != entity.id]
            lines.append(f"- 与 {'、'.join(others)} 为同一身份（explicit）")
        if entity.id in view.conflicts:
            listed = "、".join(f"“{md(n)}”" for n in view.conflicts[entity.id])
            lines.append(f"- ⚠️ 多个有效名称：{listed}（按最新修订显示第一个）")
        if not records.get("names"):
            lines.append("- ⚠️ 没有有效名称，显示为 ID")
        for record in records.get("names", []):
            lines.append(f"- 名称：{md(record.payload.text)} — {view.evidence(record.evidence)}")
        if records.get("aliases"):
            lines.append("- 别名：")
            for record in records["aliases"]:
                lines.append(f"  - {md(record.payload.text)} — {view.evidence(record.evidence)}")
        if records.get("attributes"):
            lines.append("- 属性：")
            for record in records["attributes"]:
                payload = record.payload
                lines.append(
                    f"  - **{md(payload.label)}**：{md(payload.value)} · "
                    f"{view.tags(payload.assertion, payload.attributed_to_id)} — "
                    f"{view.evidence(record.evidence)}"
                )
        lines.append("")
    return lines


def _relationships(view: _View) -> list[str]:
    records = _active(view, "relationships")
    lines = [f"## 关系（有效 {len(records)}）", ""]
    for record in records:
        payload = record.payload
        lines.append(
            f"- `{record.id}` {view.ref(payload.source_id)} —{md(payload.label)}→ "
            f"{view.ref(payload.target_id)} · "
            f"{view.tags(payload.assertion, payload.attributed_to_id, payload.temporal_context)}"
        )
        lines.append(f"  - {md(payload.description)} — {view.evidence(record.evidence)}")
    return [*lines, ""]


def _events(view: _View) -> list[str]:
    records = _active(view, "events")
    lines = [f"## 事件（有效 {len(records)}，按章节顺序，再按章内叙述顺序）", ""]
    for section in view.model.processed_sections:
        events = sorted(
            (r for r in records if r.learned_in_section_id == section.section_id),
            key=lambda r: r.payload.narrative_order,
        )
        if not events:
            continue
        lines += [f"### `{section.section_id}` {md(section.title)}", ""]
        for record in events:
            payload = record.payload
            participants = "，".join(view.ref(pid) for pid in payload.participant_ids) or "—"
            lines.append(
                f"{payload.narrative_order}. `{record.id}` {md(payload.description)} · "
                f"{view.payload_tags(payload)}"
            )
            lines.append(
                f"   - 参与者：{participants}；地点：{view.ref(payload.location_id)}；"
                f"时间：{md(payload.story_time) if payload.story_time else '—'}"
            )
            lines.append(f"   - 证据：{view.evidence(record.evidence)}")
        lines.append("")
    return lines


def _uncertainties(view: _View) -> list[str]:
    records = view.model.records.uncertainties
    open_items = [r for r in records if r.id in view.active]
    resolved = [
        (r, view.transitions[r.id])
        for r in records
        if r.id in view.transitions and view.transitions[r.id].action == "resolve"
    ]
    lines = ["## 疑点", "", f"### 未解答（{len(open_items)}）", ""]
    for record in open_items:
        related = "，".join(view.ref(eid) for eid in record.payload.related_entity_ids) or "—"
        lines.append(f"- `{record.id}` {md(record.payload.question)}（相关：{related}）")
        lines.append(f"  - 证据：{view.evidence(record.evidence)}")
    lines += ["", f"### 已解答（{len(resolved)}）", ""]
    for record, item in resolved:
        lines.append(
            f"- `{record.id}` {md(record.payload.question)} → **{md(item.resolution or '')}**"
            f"（`{item.id}`，`{item.learned_in_section_id}`）"
        )
        lines.append(f"  - 证据：{view.evidence(item.evidence)}")
    return [*lines, ""]


# --- update run reports ------------------------------------------------------------------------


def render_diff(base: CumulativeStoryModel, after: CumulativeStoryModel, id_map: IdMap) -> str:
    view = _View(after)
    section = after.processed_sections[-1]
    local_of = {stable: local for local, stable in {**id_map.entities, **id_map.records}.items()}
    lines = [
        f"# 增量变化：revision {base.revision.number} → {after.revision.number}（候选）",
        "",
        f"- 新节：`{section.section_id}` {md(section.title)}（{section.paragraph_count} 段）",
        "- 本文件描述合并后的候选修订；是否已提交以 `run.json` 的 `commit_status` 为准。",
        f"- {SUPPORT_NOTE}",
        "",
    ]
    new_entities = after.entities[len(base.entities) :]
    new_transitions = after.transitions[len(base.transitions) :]
    new_records = {
        collection: getattr(after.records, collection)[len(getattr(base.records, collection)) :]
        for collection in COLLECTION_TITLES
    }
    if not new_entities and not new_transitions and not any(new_records.values()):
        lines += ["> ⚠️ 本节没有新增或修改任何记录。请人工检查是否遗漏。", ""]

    lines += [f"## 新实体（{len(new_entities)}）", ""]
    for entity in new_entities:
        lines.append(
            f"- {view.ref(entity.id)}（{local_of.get(entity.id, '—')}）· {KIND_TITLES[entity.kind]}"
        )
    lines.append("")
    for collection, records in new_records.items():
        lines += [f"## 新{COLLECTION_TITLES[collection]}（{len(records)}）", ""]
        for record in records:
            lines.append(f"- {view.claim(record.id)}（{local_of.get(record.id, '—')}）")
            lines.append(f"  - 证据：{view.evidence(record.evidence)}")
        lines.append("")
    for action in ("supersede", "retract", "resolve"):
        items = [t for t in new_transitions if t.action == action]
        lines += [f"## {ACTION_TITLES[action]}（{action}，{len(items)}）", ""]
        for item in items:
            collection = view.index.get(item.target_record_id, ("", None))[0]
            if action == "supersede" and collection in ("events", "uncertainties"):
                lines.append("- ⚠️ 重点人工审阅：代码无法判断新旧描述是否指同一件事")
            lines += view.transition(item)
        lines.append("")
    unchanged = sum(
        1
        for collection in COLLECTION_TITLES
        for record in getattr(base.records, collection)
        if record.id in view.active
    )
    lines += [
        "## 未在本节改变的旧记录",
        "",
        f"- 仍有效 {unchanged} 条。新节未提及不等于被推翻，旧记录默认保持有效。",
        "",
    ]
    return "\n".join(lines).rstrip() + "\n"


def render_update_review(
    chapter: ChapterInput,
    run: dict[str, Any],
    base: CumulativeStoryModel,
    validation: UpdateValidation | None,
    failure: dict[str, Any] | None,
) -> str:
    after = validation.after if validation is not None and validation.passed else None
    lines = [f"# 累计更新审阅报告：{md(chapter.title)}", ""]
    lines += _update_status(run, validation, failure)
    lines += _update_metadata(chapter, run)
    lines += [
        "## 阅读须知",
        "",
        f"- {SUPPORT_NOTE}",
        "- 输入只有上一版完整的结构化模型和本节原文；此前各章原文与后续章节均未发送。"
        "上一版模型是可被新证据修订的抽取结果，不是绝对真理。",
        "- 新记录和状态转换的证据只能来自本节；旧记录不会被改写或删除，只能通过新的转换失效。",
    ]
    omitted = base.coverage.omitted_prefix_section_ids
    if omitted:
        lines.append(
            f"- 起点为 `{base.coverage.start_section_id}`，之前的 "
            f"{'、'.join(f'`{s}`' for s in omitted)} 未处理。"
        )
    if base.provenance.imported_manual_corrections:
        lines.append(
            f"- 初始模型含 {len(base.provenance.imported_manual_corrections)} 处人工修正，"
            "不是模型原样输出。"
        )
    lines += [f"- 本节省略了 {chapter.omitted_image_count} 张图片，图片内容未被读取。", ""]

    if failure is not None:
        lines += _failure(failure)
    if validation is not None:
        lines += _update_validation(validation)
    if after is not None:
        view = _View(after)
        new_transitions = after.transitions[len(base.transitions) :]
        new_links = after.records.identity_links[len(base.records.identity_links) :]
        new_names = [
            r
            for r in after.records.names[len(base.records.names) :]
            if r.payload.entity_id in {e.id for e in base.entities}
        ]
        lines += ["## 重要变化（需人工审阅）", ""]
        if not (new_transitions or new_links or new_names):
            lines += ["- 本节没有修订旧记录、揭示身份或为已有实体添加新名称。", ""]
        for item in new_transitions:
            lines += view.transition(item)
        for record in new_links:
            lines.append(f"- 身份链接 {view.claim(record.id)}")
            lines.append(f"  - 证据：{view.evidence(record.evidence)}")
        for record in new_names:
            lines.append(f"- 已有实体的新名称 {view.claim(record.id)}")
            lines.append(f"  - 证据：{view.evidence(record.evidence)}")
        lines += ["", "完整的逐条新增内容见 `diff.md`。", ""]
        lines += [
            "## 当前状态（候选修订）",
            "",
            f"- 实体 {len(after.entities)}（新增 {len(after.entities) - len(base.entities)}）；"
            f"有效记录 {len(view.active)} / 共 {len(view.index)}；"
            f"状态转换 {len(after.transitions)}；身份组 {len(after.current.identity_groups)}；"
            f"已解答疑点 {len(after.current.resolved_uncertainty_ids)}",
            "- 完整视图：`story-model show --store <store>`（提交后）或打开 "
            "`story_model.after.json`。",
            "",
        ]
    lines += [
        "## 待人工判断",
        "",
        "- 抽查本节重要信息点是否被遗漏；检查错误关联、重复人物、旧事实误删、倒叙误判为当前状态。",
    ]
    if validation is not None:
        for issue in validation.warnings:
            if issue.code in REVIEW_FOCUS_CODES:
                lines.append(f"- `{issue.code}` `{issue.path}`：{md(issue.message)}")
    lines.append("")
    lines += ["## 附录：本节原文段落", ""]
    for paragraph in chapter.paragraphs:
        lines += [
            f'<a id="{paragraph.id}"></a>**[{chapter.section_id}:{paragraph.id}]** '
            f"{md(paragraph.text)}",
            "",
        ]
    return "\n".join(lines).rstrip() + "\n"


def _update_status(
    run: dict[str, Any], validation: UpdateValidation | None, failure: dict[str, Any] | None
) -> list[str]:
    commit = run.get("commit_status")
    status = run.get("status")
    committed = run.get("committed_revision") or {}
    if commit == "committed":
        headline = (
            f"已提交为 revision {committed.get('number')}；通过自动校验（结构、ID、引用存在性、"
            "历史不变量），内容是否正确仍需人工审阅"
        )
    elif status == "stale_base":
        headline = "未提交：store 已被其他更新改变（stale_base），本次增量没有写入"
    elif validation is not None and validation.passed:
        headline = f"候选通过自动校验，但未提交（{status}，commit_status={commit}）"
    elif validation is not None and not validation.structure_valid:
        headline = "未提交：增量 JSON 不符合 schema"
    elif validation is not None:
        headline = f"未提交：未通过自动校验，{len(validation.errors)} 个错误"
    elif failure is not None:
        headline = f"未提交：运行失败（{status}），没有可合并的增量"
    else:
        headline = f"未提交（{status}）"
    marker = "✅" if commit == "committed" else "❌"
    lines = [f"> {marker} **状态：{headline}**", ""]
    corrections = run.get("manual_corrections") or []
    if corrections:
        lines += [
            f"> ⚠️ **本修订的增量包含 {len(corrections)} 处人工修正，不是模型原样输出；模型原始输出"
            f"未通过校验（{run.get('original_status')}）。** 原始输出见 `delta.candidate.json`，"
            "修正后的增量见 `delta.corrected.json`，原始校验见 `validation.json`。",
            "",
            "## 人工修正（只修正证据位置）",
            "",
        ]
        for item in corrections:
            lines.append(
                f"- `{item['path']}`：{md(str(item['original']))} → {md(str(item['corrected']))}"
                f"（{md(str(item['reason']))}；{item['corrected_by']}，{item['corrected_at']}）"
            )
        lines.append("")
    return lines


def _update_metadata(chapter: ChapterInput, run: dict[str, Any]) -> list[str]:
    request = run.get("request") or {}
    response = run.get("response") or {}
    hashes = run.get("hashes") or {}
    base = run.get("base_revision") or {}
    candidate = run.get("candidate_revision") or {}
    committed = run.get("committed_revision") or {}
    lines = [
        "## 运行信息",
        "",
        f"- 运行 ID：{inline_code(run.get('run_id'))}；状态：{inline_code(run.get('status'))}；"
        f"commit_status：{inline_code(run.get('commit_status'))}",
        f"- Base revision：{inline_code(base.get('number'))}（{inline_code(base.get('id'))}，"
        f"SHA-256 {inline_code(base.get('sha256'))}）",
        f"- 候选 revision：{inline_code(candidate.get('number'))}；"
        f"已提交 revision：{inline_code(committed.get('number'))}",
        f"- Provider：{inline_code(request.get('provider'))}；请求模型："
        f"{inline_code(request.get('model'))}；响应模型：{inline_code(response.get('model'))}",
        f"- Response ID：{inline_code(response.get('response_id'))}；"
        f"Request ID：{inline_code(response.get('request_id'))}",
        f"- 新节：`{chapter.section_id}`（Chapter "
        f"{chapter.chapter_number if chapter.chapter_number is not None else '—'}）；"
        f"资源：`{chapter.source_href}`；段落数：{len(chapter.paragraphs)}",
        f"- 文本 SHA-256：`{chapter.text_sha256}`；Prompt SHA-256："
        f"{inline_code(hashes.get('prompt_sha256'))}；Schema SHA-256："
        f"{inline_code(hashes.get('schema_sha256'))}",
    ]
    usage = response.get("usage")
    if usage:
        lines.append(
            f"- Usage：input {usage.get('input_tokens')}，output {usage.get('output_tokens')}，"
            f"total {usage.get('total_tokens')}"
        )
    return [*lines, ""]


def _failure(failure: dict[str, Any]) -> list[str]:
    error = failure.get("error") or {}
    lines = [
        "## 失败信息",
        "",
        f"- 阶段：`{failure.get('status')}`；类别：`{error.get('category')}`",
    ]
    message = error.get("message") or error.get("detail")
    if message:
        lines.append(f"- 详情：{md(str(message))[:2000]}")
    lines += ["- 完整诊断见 `failure.json`（以及可获得时的 `response.json`）。", ""]
    return lines


def _update_validation(validation: UpdateValidation) -> list[str]:
    counts = validation.counts
    lines = ["## 自动校验", ""]
    if counts:
        records = "，".join(
            f"{title} {counts.get(f'new_{name}', 0)}" for name, title in COLLECTION_TITLES.items()
        )
        lines.append(f"- 新实体 {counts.get('new_entities', 0)}；新记录：{records}")
        lines.append(
            f"- 转换：替代 {counts.get('transitions_supersede', 0)}，撤回 "
            f"{counts.get('transitions_retract', 0)}，解答 {counts.get('transitions_resolve', 0)}"
        )
        if "evidence_items" in counts:
            lines.append(
                f"- 新证据 {counts['evidence_items']} 条，"
                f"其中逐字匹配 {counts['evidence_matched']} 条"
            )
    lines += [f"- 错误 {len(validation.errors)} 个，警告 {len(validation.warnings)} 个", ""]
    for title, issues in (("错误", validation.errors), ("警告", validation.warnings)):
        if not issues:
            continue
        lines += [f"### {title}", ""]
        for issue in issues:
            rid = f" `{issue.record_id}`" if issue.record_id else ""
            lines.append(f"- `{issue.code}`{rid} `{issue.path}`：{md(issue.message)}")
        lines.append("")
    return lines
