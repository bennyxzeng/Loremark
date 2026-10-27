# Story Model 第二阶段执行文档：章节边界修复与累计更新

日期：2026-10-26。交付对象：下一位负责实现的 agent。

## 1. 用户决定与本轮范围

在现有 Python CLI 上完成两件事，顺序不能颠倒：

1. 修复 EPUB 章节边界错误，避免选中一章却输入下一章内容。
2. 实现持续更新的 Story model：**第一章已有模型 + 第二章正文 → 第二章结束后的累计模型**，之后以相同方式继续。

用户已确认：**保留历史事实，并生成最新累计状态，以后能够回看各章。** 因此旧事实不能被删除，旧章节快照不能被新章节的揭示改写。

本文件替代旧执行文档中“只做单章、不做历史或跨章关联”的范围限制。旧 `generate` 单章实验功能仍保留；新增累计模式，不把原有结果原地转换。

仍然只在本地 terminal 运行，不接 App/Readium，不维护用户阅读进度。这里的“已处理章节”和“模型修订号”只是 CLI 数据处理记录。不要引入数据库、服务端、向量检索、多 agent 系统或全文重跑。

本轮文档作者没有修改实现代码。执行 agent 应完成实际代码、测试、文档和可复核实验，不只搭空文件结构。

## 2. 已有基础与兼容要求

- 当前分支 `story-model`，开始时重新检查 git 状态，沿用当前分支，不擅自提交或推送。
- 工具目录：`tools/story_model_lab/`。
- EPUB：`sample_epub/86v1_chapters.epub`。
- 可作为初始状态的第一章目录：`tools/story_model_lab/runs/20261026T032410Z-2c6f50/`。
- 该目录包含 `story_model.json`、`chapter.json`、`candidate.json`、`candidate.original.json`、`response.json` 和 `run.json`。
- 第一章是 `section-004` / `EPUB/section-004.xhtml`；第二章是 `section-005` / `EPUB/section-005.xhtml`。
- 第一章由 `deepseek-flash` 真实生成；最终结果修正过一处证据段落 ID，`run.json.manual_corrections` 有记录。导入的是修正后的合格模型，必须保留修正来源，不能将它称为未经修改的原始输出。
- 上次验收：63 个离线测试通过。当前自动检查验证的是结构、ID 和引用存在性，不保证事实准确或信息完整。

保留现有 OpenAI/DeepSeek provider、模型配置、可选 timeout/token/reasoning 参数和原始响应保存功能。不要借本次升级改变现有 provider 默认值，也不需要再更换技术栈。OpenAI 官方接口尚无已核实真实运行记录；如未实测，交付时继续注明，不把 DeepSeek 成功等同于 OpenAI 实测成功。

## 3. 先修复章节边界 bug

### 3.1 复现与根因

同一 XHTML：

```html
<h2 id="c1">Chapter 1</h2><p>CHAPTER_ONE_ONLY</p>
<h2 id="c2">Chapter 2</h2><p>CHAPTER_TWO_SENTINEL</p>
```

目录却指向：

```text
all.xhtml#c1       → Chapter 1
all.xhtml#missing  → Chapter 2
```

当前 `epub.py` 的 `_build_sections()` 把无效锚点的 ordinal 留为 -1，排序后可能将 Chapter 2 放到 Chapter 1 前面；`_next_in_same_document()` 又跳过 problem 条目。结果是 Chapter 1 找不到可靠结束位置，却继续读至文件末尾，包含第二章。

只修 `_next_in_same_document()` 不够，因为排序已经丢失了可信边界关系。

### 3.2 修复规则

- 章节边界必须在提取正文前验证，不能遇到坏边界就扩大提取范围。
- 第一版采取保守且容易验证的策略：**一个 XHTML 只要有无法可靠定位的 TOC 边界，就将该文档内相关章节全部标为不可可靠提取**，说明出错 href/fragment；其他独立 XHTML 的正常章节仍可读取。
- 缺失锚点、同一 ID 出现多次、落在 head/被忽略节点中的锚点、不明确的重复起点均应明确处理。同 href+fragment 且同标题的完全重复目录链接可去重；不同章节标题指向同一位置则报歧义，不生成空章节或吞并正文。
- `body`/`html` 起点按原有约定作为文档起始处理，但必须检查它们和其他边界是否重复、是否可排序。
- `_anchor_element()` 不得把“指定 fragment 没找到”作为 `None = 文档开始` 使用。
- 不用无效位置 -1 参与正常正文位置排序；保留目录信息用于诊断。`chapters` 仍可列出问题条目，但 `extract/generate/update` 必须失败，且不调用 API。
- 全部有效时，保持正常 EPUB 的输出、section ID、段落文本和哈希稳定。不要为了修 bug 顺便重写文本规范化规则。
- `_RangeCollector` 对同文件正常多锚点、段落中锚点、最后一个章节的行为不得回退。

### 3.3 必须增加的回归测试

1. 上述最小复现：Chapter 1 必须抛 `EpubError`，不能包含下一章哨兵。
2. 三章同文件，中间锚点无效：不能跳过中间章而截到第三章。
3. 重复 ID、重复边界、head 内锚点分别给出可理解的错误。
4. 一个坏文档不影响另一个独立且边界完整的文档。
5. 正常同文件多章、最后一章、NCX fallback 继续通过。
6. 用户样本的七个主章节映射不变，Chapter 1 的文本哈希仍为 `d1053fa1bbdd5a1609a15112b64f9fa961aa5395f72a2d80bed92ade53f9d549`。
7. CLI 和 mock API 测试确认坏边界在联网前被拒绝。

## 4. 累计更新的整体流程

```text
第一章旧格式运行目录
    ↓ init，离线校验与迁移
store/story_model.json（revision 1，第一章累计状态）
    + 第二章正文
    ↓ update，LLM 只提出增量
StoryDelta（新增人物/事实、旧事实修订、身份揭示、疑点解答）
    ↓ 程序校验、分配稳定 ID、确定性合并
revision 2 快照 + 最新累计 story_model.json
```

关键选择：**LLM 不返回完整改写后的整本模型，而是返回增量。程序负责将增量应用到原文件。** 这样能明确检查它改了什么，避免遗漏第一章人物、重排所有 ID 或悄悄重写历史。

LLM 的输入仍包含上一版完整的结构化知识（含历史与状态）和新章节正文，因此确实是“从第一章文件继续”。不附上此前各章完整正文，也不输入尚未选择的后续章。旧模型是可被新证据修订的抽取结果，不是绝对真理。

## 5. CLI 契约与实际使用方法

保留 `chapters/extract/generate/validate`，新增 `init/update/show`。复用现有 provider 参数组，避免两套 API 配置漂移。

```bash
source tools/story_model_lab/.venv/bin/activate

# 1. 由已有第一章结果初始化累计模型；离线，不重新生成第一章。
story-model init \
  --from-run tools/story_model_lab/runs/20261026T032410Z-2c6f50 \
  --store tools/story_model_lab/stores/86v1

# 2. 查看第二章实际输入与增量 schema；不联网、不修改 store。
story-model update \
  --store tools/story_model_lab/stores/86v1 \
  --epub sample_epub/86v1_chapters.epub --chapter 2 \
  --provider deepseek --dry-run

# 3. 根据第一章模型和第二章正文进行真实更新。
# 模型与 key 从对应 provider 的环境变量读取，或用 --model 指定。
story-model update \
  --store tools/story_model_lab/stores/86v1 \
  --epub sample_epub/86v1_chapters.epub --chapter 2 \
  --provider deepseek

# 4. 展示最新累计模型；也能看某个旧修订，不能修改最新状态。
story-model show --store tools/story_model_lab/stores/86v1
story-model show --store tools/story_model_lab/stores/86v1 --revision 1

# 5. 离线重新验证某次 update 产物；不提交或改变正式 store。
story-model validate --run tools/story_model_lab/runs/<update-run-id>
```

命令行为：

- `init` 要求目标 store 不存在或为空。缺失可信章节输入、模型不合格、哈希不符时拒绝导入。它从原 `run.json.source.epub_path` 读取 EPUB 以核实章节顺序与起始覆盖；支持可选 `--epub` 覆盖已失效的路径，但文件 SHA-256 必须相同。EPUB 不可用时不猜章节顺序。
- `update` 必须显式提供 store 和新章节；`--chapter/--section` 二选一。支持既有 `--model/--provider/--timeout/--max-output-tokens/--reasoning-effort/--prompt-file/--out/--dry-run`。
- 每次成功 `update` 自动提交一个新修订；不另外要求确认。失败则只保存实验产物，旧 store 保持不变。
- `show` 默认输出最新状态的 Markdown（人物、事实、关系、事件、疑点和章节覆盖）；`--json` 输出该修订的完整 v2 JSON，包括历史。不要把它实现为一次 LLM 请求。
- `validate` 对旧单章运行保留现有行为；对 update 运行仅检查该运行的 base/delta/after，不能再次应用 delta 或覆盖 store。
- 保留退出码 0/2/3/4；增加 5 表示提交前发现 base 已被其他更新改变。遇到 5 不自动重试模型。

章节顺序：

- 同一本 EPUB 用 SHA-256 判断，书名相同不等于同一版本。
- `init` 允许从已有第一章起步；本书第一章之前的序章等未被处理，必须在覆盖信息中明确标出，不能称为“全书开头到第一章完整状态”。
- 初始化之后，每次只能处理目录/阅读顺序中的**下一节**，不要用 chapter_number + 1 推断。Chapter 3 后的间章必须先处理，再处理 Chapter 4。
- 索引会包含非正文条目；第一版不自动跳过。遇到不能提取的条目则清楚报错并留作后续支持，不隐式越过。
- 同一 section + 文本哈希已经处理过：联网前返回 `already_processed`，退出 0，修订数与文件字节不变。
- 处理过的 section 内容哈希不同、不同 EPUB、向后插章、跨过未处理节都拒绝；本版不做 rebase、章节重跑替换或历史编辑。

## 6. v2 数据设计：稳定实体、不可变记录与状态转换

v1 的 `c001` 人物 ID 直接沿用，不能在第二章重新从 c001 编起；地点 l、组织 g 同理。第一章属性、别名、关系、事件、疑点都要获得稳定记录 ID，才能明确引用和修订。

采用 `schema_version: "2.0"`、`scope: "cumulative"`。不要把 v2 强行塞进旧 `ChapterStoryModel`。新增独立 Pydantic 模型；旧 v1 仍可加载和验证。

### 6.1 顶层与证据

```text
CumulativeStoryModel
  schema_version: "2.0"
  scope: "cumulative"
  book: {title, epub_sha256}
  revision: {number, id, created_at, source_run_id, parent_snapshot_path?, parent_sha256?}
  processed_sections: SectionSource[]       # 有序；仅实际处理过的节
  coverage: {start_section_id, omitted_prefix_section_ids}
  entities: StableEntity[]
  records: RecordCollections
  transitions: RecordTransition[]
  current: {active_record_ids, resolved_uncertainty_ids, identity_groups}
  provenance: {initial_run_id, imported_manual_corrections, migration_version}

SectionSource
  section_id, section_order, chapter_number?, title, href, fragment?
  text_sha256, extraction_version, paragraph_count
  input_relative_path, input_file_sha256, introduced_revision

EvidenceV2
  section_id: string
  paragraph_id: string
  quote: string

StableEntity
  id: string                    # c001 / l001 / g001
  kind: character | location | organization
  introduced_revision: integer
```

`?` 表示 required-but-nullable，实际 Structured Outputs 使用明确类型，不使用无约束 dict/Any。文件元信息、正式 ID、修订号和 current 全部由程序生成。

证据的唯一定位是 `(book SHA, section_id, paragraph_id)`。两章都存在 p0001 时不再碰撞。原有第一章引用迁移为 `section-004:pXXXX`，不能仅将第二章段落接在第一章数组后重新编号。

### 6.2 不可变知识记录

`RecordCollections` 是以下固定类型数组：`names, aliases, attributes, relationships, events, uncertainties, identity_links`。每条记录外包统一 envelope：

```text
Record<TypedPayload>
  id: string                         # 程序分配 f000001 等全局唯一记录 ID
  introduced_revision: integer
  learned_in_section_id: string
  legacy_id: string | null            # 导入时原 r001/e001 等，便于追溯
  payload: 对应集合的具体 Pydantic 类型
  evidence: EvidenceV2[]              # 非空
```

payload 的字段如下（复用 v1 定义的语义，但 evidence 移至记录外层）：

| 集合 | payload |
| --- | --- |
| names / aliases | `entity_id, text` |
| attributes | `entity_id, label, value, assertion, attributed_to_id` |
| relationships | `source_id, target_id, label, description, assertion, attributed_to_id, temporal_context` |
| events | `description, participant_ids, location_id, narrative_order, temporal_context, story_time, assertion, attributed_to_id` |
| uncertainties | `question, related_entity_ids` |
| identity_links | `left_entity_id, right_entity_id, assertion, explanation` |

沿用 v1 assertion、时间枚举。事件 `narrative_order` 是**其所在章节**的叙述顺序，全书按 section_order 再按 narrative_order 排序，不能要求第二章从第一章最后一个编号继续。

主显示名也作为记录保存：第二章知道真名时新增 name，并明确替代旧 name；旧名称可另外作为 alias 保留。不能直接改 `StableEntity` 的永久 name 字段。

旧记录加入后不原地改字、不追加证据、不删掉。某件事得到新的重要描述或证据时新增记录；完全相同的重复主张可以提示模型不再产生，程序不得用模糊相似度偷偷合并事实。

### 6.3 明确修订、撤回和疑点解答

```text
RecordTransition
  id: string                         # t000001，由代码分配
  introduced_revision: integer
  learned_in_section_id: string
  target_record_id: string            # 必须是 base 中当前有效的旧记录
  action: supersede | retract | resolve
  replacement_record_id: string | null
  resolution: string | null
  reason: string
  evidence: EvidenceV2[]
```

- `supersede`：本次新增的一条记录替代旧记录；replacement 必填，resolution 为 null。例如旧职业、新关系状态、新名称或修订后的事件描述。
- `retract`：新章节明确推翻旧主张，尚无替代内容；replacement/resolution 都为 null。
- `resolve`：只针对 uncertainty；resolution 必填，replacement 为 null。若答案还应成为人物属性/身份关系，需要同时新增相应记录，不能仅在答案里藏结构化知识。
- 每个目标在同一批次最多一个转换，目标必须在 base 中有效，不能针对本批次新建记录做连续转换。
- supersede 限于同类记录；names/aliases/attributes 必须同一实体，attribute 还需相同 label；relationship 必须同一对有向端点、同一 label。关系状态变化应保持 label 为同一维度，例如 `relationship_status: enemies → allies`。兼容导入的旧 label，不自动规范化。
- 不同维度的关系可以并存，如兄妹与盟友。不能因出现一条较新的关系就清除旧的全部关系。
- 对于已导入的 v1 关系，若旧 label=`opposes`、新 label=`allied_with`，不能违反同 label 的 supersede 约束；用有新证据的 `retract` 退役旧关系，并新增新关系。报告将两项并列展示。不要重命名历史 label 来迁就规则。
- events/uncertainties 的替换保留同类约束与 reason/evidence，不能靠纯代码判断语义是否真的相同；报告中列为重点人工审阅。
- 倒叙中新披露的历史关系通常应追加，不应替代当前关系。对 temporal_context 不一致的关系替代直接报错；其余语义矛盾标记供人工评审。
- 未出现于新章不等于已被推翻；默认保留旧记录有效。
- 历史转换本身也不修改或删除。本版不实现撤销一条旧转换；如需要纠错，通过新事实及新的语义修订处理，不能伪造历史。

`current` 是程序从记录和 transitions 计算出的索引，不能接受 LLM 提供的 active 状态，也不能把 inactive 当成不存在。加载时重新计算并核对，避免索引与历史不一致。

显示名称从该修订的有效 name 记录选择；同实体多个有效主名称时列出冲突，显示上按最新 introduced_revision、再按记录 ID 稳定排序，但不删除其余记录。没有有效名称时回退为实体 ID 并警告。不得从最新修订借用名称显示历史快照。

### 6.4 身份揭示

若第一章将两个称谓记为两个实体，第二章揭示是同一个人：新增 `identity_links`，保留原 ID 与引用，不破坏性合并历史数据。

只有 assertion=`explicit` 的有效 identity link 可进入当前展示的同一身份组；推断性的 link 作为推断展示，不自动合并。要求两端实体类型相同，不能人物合并到组织。

显示用 canonical ID 由程序选择该组中最早引入的实体，再按 ID 打破平局。保留原始成员 ID；报告汇总成员的有效事实。实体合并并不自动解决成员间矛盾属性，须展示冲突或用明确 transition 修订。

回看第一章使用第一章快照，因此不能显示第二章才出现的姓名、别名、合并身份或已解答的疑点。

## 7. LLM 返回的 StoryDelta

不要让 LLM 输出任意 JSON Patch、文件路径、程序表达式或完整累计 JSON。使用专门的严格 Pydantic 输出：

```text
StoryDelta
  new_entities: [{local_id, kind}]
  new_records: DeltaRecordCollections
  transitions: DeltaTransition[]
```

`DeltaRecordCollections` 对应第 6 节七个数组，每条结构为 `{local_id, payload, evidence}`。`DeltaTransition` 为 `{target_record_id, action, replacement_local_id?, resolution?, reason, evidence}`。

- LLM 引用旧实体使用现有 c/l/g ID；新实体使用本批次 `new_entity_001`。新记录用 `new_record_001`。local ID 全批次唯一。
- payload 中的实体引用允许现有 ID 或本批次新实体 local ID。先整体收集，再解析引用，允许前向引用。
- replacement_local_id 只能引用本批次新记录。delta 不包含正式记录 ID、修订号、current 或删除命令。
- 程序按固定集合顺序和数组顺序，从已有最大计数之后分配正式 ID。把 local → stable 映射保存到 `id_map.json`。合并相同 base + delta 必须得到相同知识内容与映射（运行时间/修订 UUID 等元信息除外）。
- 每个新实体必须至少有一个本次 name 记录，不能留下只有 ID 的空人物。
- 每条新增记录/transition 至少一条证据来自**本次新章节**，并逐字匹配当前段落。旧记录中的引文可作为模型背景，但不能仅凭旧引文制造一条“新章节确认”的主张。
- 本版 delta 的 evidence 限定为当前章节，禁止伪造新章里没有的句子去支持跨章判断。需要组合前章信息时，通过引用旧实体/目标记录提供上下文，并在 reason 中说明新章如何改变原判断。
- 歧义保留为 uncertainty，不为了整合而硬猜别名。已有模型若有错误，也不能仅凭模型记忆无证据地改正。
- 空 delta 合法：表示本节没有新增可记录信息。仍保存处理覆盖和新修订，报告明确提示人工检查是否遗漏。

请求分为 system 任务指令和 user 数据块：`PRIOR_STORY_MODEL`、`NEW_SECTION`。旧模型及小说文字都是数据，不可作为指令执行。保存实际发送的上下文 `context.json`；可去掉绝对路径、旧 usage 和内部运行日志，但保留所有事实 ID、payload、证据、introduced revision、transition 与 current，不做自动摘要或静默裁剪。

继续使用现有 Responses API adapter，但使输出模型可参数化：默认仍是 `ChapterStoryModel`，累计更新传 `StoryDelta`。同时修改 `CallResult.parsed` 的类型、parse 调用、schema 导出和失败处理；不能只改 prompt 而忘记 `openai_client.py` 与 `prompting.py` 中写死的类型。保存的 schema 必须与真正发送的一致。

上下文过长、输出 incomplete、拒绝或校验失败都不能自动裁剪旧模型、切换 provider 或提交部分更新。本轮先验证前两章可用，不提前实现长书压缩系统。

## 8. 第一章迁移与累计存储

### 8.1 离线 init

1. 读取 v1 `story_model.json`、`chapter.json` 和 `run.json`；重新校验模型、证据、书籍/文本哈希与元信息的一致性。读取匹配哈希的 EPUB，使用修复后的提取器重新提取初始章节并比较文本；据实际目录填 section_order 和 omitted_prefix_section_ids。若修复揭示旧输入混章，拒绝导入而非迁移错误文本。
2. 不只相信旧 `passed=true`。若 `candidate.json` 存在，要求其内容与 story_model.model 一致；缺 run/chapter 或不一致则失败，不猜来源。
3. 人物/地点/组织 ID 原样导入。每条 name、alias、attribute、relationship、event、uncertainty 按固定顺序分配 f ID；关系/事件旧 ID 放在 legacy_id，保存 `migration_map.json`。
4. 不调用 LLM、不补事实、不修正已知遗漏；第一章原有错误或不确定性也忠实带入并说明。否则无法比较累计更新本身的效果。
5. 引用补上 section_id，所有导入记录 introduced_revision=1。无 transitions/identity links；所有导入记录当前有效，疑点均未解答。
6. 复制第一章规范化输入和必要原始/人工修正出处到 store 的 provenance 目录，记录哈希。删除旧 runs 目录不应导致已有累计模型无法验证。
7. 提交 revision 1，原运行目录及其每个文件保持不变。

### 8.2 磁盘结构

```text
tools/story_model_lab/stores/86v1/
  story_model.json                 # 用户日常打开的最新累计模型；唯一提交入口
  .lock                           # 提交阶段的进程锁
  revisions/
    000001-<revision-id>.json      # 完整且不可变的历史快照
    000002-<revision-id>.json
  inputs/
    <section-id>-<input-hash>.json # 已提交章节的规范化段落
  provenance/
    initial/                      # v1 导入来源与人工修正记录、migration_map
    <update-run-id>/               # 提交所用 delta、id_map、base hash 与输入产物
```

快照不依赖旧 runs 的绝对路径。内部引用使用受 store 根目录限制的相对路径，加载时拒绝路径越界。给 `stores/` 加 gitignore，不把小说输入或模型产物加入版本库。

完整快照在这个阶段是有意的简单选择：读第 N 章的历史状态不需要重跑 LLM，也不用实现复杂数据库或事件重放引擎。当前文件内的 records/transitions 保留完整知识历史；快照提供准确的当时视图。后续再考虑空间优化。

### 8.3 一次 update 的提交边界

1. 读取并验证当前文件与已提交输入，记录 base 文件 SHA-256/revision；在独立 run 目录保存 base 副本。
2. 校验书籍版本、章节顺序与可靠边界，再调用 API。已有同章结果时提前退出，不花费第二次调用。
3. delta 结构、引用和所有操作通过后，在内存生成 after，校验完整累计模型；旧 records/transitions 必须是 after 的未修改前缀。
4. 提交时取得 store 进程锁，重新核对 base hash。如果已变化，记录 `stale_base`，退出 5，不修改最新文件。本轮目标为 macOS/Linux，可使用标准库 `fcntl.flock`；不要用“检查 lock 文件存在”替代进程锁。
5. 先写完整输入、provenance 和唯一命名的 revision 快照，再写同目录临时 latest 文件并 flush/fsync，最后 `os.replace` 原子替换 `story_model.json`；必要时 fsync 目录以保证持久化。
6. 最新文件与对应快照字节一致；新 revision 的 parent 路径/哈希指向旧快照。revision_id 用随机唯一值，避免崩溃遗留的同编号未提交快照挡住重试。
7. `story_model.json` 的原子替换是提交点。替换前出错，旧版本不变；替换后即使 run 报告写入失败，也应记录“状态已提交、报告未完成”，不能声称没有更新或再次应用 delta。
8. `show --revision` 只接受从当前 revision 的 parent 链可达的历史快照；目录里存在但未被提交链引用的文件不算成功版本。

不必构建通用事务框架，但必须用故障注入测试上述边界。提交锁可以只持有短暂的验证与写盘阶段，不必在漫长 API 调用期间持有。

## 9. 更新运行产物与报告

新增 update 运行继续保留 `chapter.json/txt, prompt.txt, schema.json, request.json, response.json, run.json`。另外保存：

| 文件 | 内容 |
| --- | --- |
| `base_story_model.json` | 调用前的完整累计状态副本 |
| `context.json` | 实际传给 LLM 的 prior/new 数据，便于检查漏章或泄漏 |
| `delta.candidate.json` | 模型增量原样 JSON，失败也保留 |
| `delta.json` | 通过校验的增量，不能覆盖 candidate |
| `id_map.json` | local ID 到正式 ID 的程序映射 |
| `story_model.after.json` | 合并成功的候选累计状态，尚不代表已提交 |
| `validation.json` | delta、完整状态、历史保护和证据校验 |
| `diff.md` | 人可读的新人物/别名/属性/关系/事件/身份揭示/修订/已解答疑点 |
| `review.md` | 当前状态、重要变化、证据、疑点、待人工判断的问题 |
| `failure.json` | 失败原因（若有） |

`run.json` 明确区分 `base_revision`、`candidate_revision`、`committed_revision`、`commit_status` 和 API/validation 状态。`story_model.after.json` 存在并不表示 store 更新成功。dry-run 没有 delta/after，也不能改 store。

报告必须显示被替代的旧主张、新主张和新章证据。人工修正沿用独立原始备份与留痕原则，不把修正后通过当作模型首次生成通过。本轮不添加自动修正或自动再次请求 LLM。

## 10. 应修改和新增的文件

```text
src/loremark_story_lab/
  epub.py                         # 边界修复
  cli.py                          # init/update/show，复用模型参数
  openai_client.py                 # 参数化输出 schema，保留旧行为
  prompting.py                    # 参数化 schema、累计上下文与增量 prompt
  pipeline.py                     # 分派原有与累计流程，旧接口兼容
  cumulative_schemas.py            # v2、StoryDelta、typed payload、transitions
  migration.py                    # v1 -> v2 离线迁移
  cumulative_validation.py         # 跨章引用、ID、操作和历史不变量
  merge.py                        # 纯函数 apply_delta 与 current 投影
  story_store.py                  # 快照、输入保存、锁与原子提交、历史读取
  incremental_pipeline.py          # update 流程，不把逻辑全挤进 CLI
  reporting.py                    # 复用通用格式工具
  incremental_reporting.py         # diff、累计视图、历史视图
  prompts/update_story_v1.txt
tests/
  test_epub.py                     # 新边界回归
  test_migration.py
  test_merge.py
  test_story_store.py
  test_incremental_pipeline.py
  test_cli.py                      # 兼容与新增命令
  fixtures/                       # 两章合成文本/增量，禁止放真实小说全文
evaluation/
  incremental_chapter2_review.md  # 实际运行/未运行状态、跨章准确度记录
```

可以根据实际职责少量合并模块，不新增空壳类。`schemas.py` 的 v1 定义继续保留。README 增加累计模式、每章顺序、文件结构、提交语义及旧命令说明，锁文件仅在依赖实际变化时更新。

## 11. 必须验证的行为

默认全部离线；真实调用单独显式启用。

### 基础、迁移与历史

- 旧 63 个离线测试继续通过；新增边界失败测试按第 3 节执行。
- 导入修正后的第一章，ID 和事实不变，引用全部加 section_id，人工修正 provenance 存在；旧目录逐文件哈希不变。
- 两章都含 p0001，引用能正确区分；错误章节中的同一句 quote 不能借别章匹配通过。
- 缺失历史 input、哈希错误、current 投影与 records 不一致都拒绝，而不是信任已保存的 passed 标记。

### 增量合并

使用两章合成故事测试：

1. 第一章已有角色 A，第二章再次出现 A：沿用 c001，不重复创建。
2. 新角色获得新 ID；本次所有前向引用正确映射；local ID 重复或悬空引用拒绝。
3. 追加人物属性，旧属性仍保留；角色没在新章出现也不会被删除。
4. 相同关系维度从敌对变成合作：明确 supersede 后最新状态改变，第一章仍敌对；亲属关系等其他维度保持。
5. 第二章是旧关系的倒叙，不自动覆盖当前关系。
6. 第二章揭示两个 ID 同一身份：当前身份组汇合，第一章仍分开；推断身份不能自动合并。
7. 新章解答第一章疑点：当前有答案，第一章疑点仍未解答。
8. 缺当前章证据、伪造 quote、错误 transition target、非法替代类型都拒绝。
9. 同一 base/delta 的合并知识与 ID 映射可重复；旧事实与旧转换逐条保持不变。
10. 第一次导入旧模型时含错误的事实不会被代码“顺便修好”，缺失事实也不会凭空补齐。

### 调用、失败与磁盘

- mock 请求确实包含 base 模型和第二章正文；不包含第三章哨兵；旧全文不被额外发送。
- adapter 使用 StoryDelta schema，原 `generate` 仍使用 ChapterStoryModel，request/schema 文件与实际请求一致。
- incomplete、refusal、解析失败、引用失败、网络失败：均保存诊断，不更新 store。
- 重复处理同一节：不调用 API，不增加 revision。
- 错书、跳章、倒序和哈希冲突：联网前失败；间章不能被 chapter_number 跳过。
- 用 mock 同时基于 revision 1 准备两次更新：第一次提交后，第二次必须 stale_base，不能丢失第一次更新。
- 模拟写快照失败、replace 前失败、replace 后报告失败，验证原子提交和可识别的真实状态。
- 历史 show 无网络、不写 latest；update 的 validate 不提交到 store。

运行：

```bash
tools/story_model_lab/.venv/bin/python -m pytest tools/story_model_lab/tests -m 'not live'
tools/story_model_lab/.venv/bin/python -m ruff check tools/story_model_lab
tools/story_model_lab/.venv/bin/python -m ruff format --check tools/story_model_lab
```

## 12. 实施顺序与真实实验验收

1. **先修边界并验证样本提取不变。** 不在不可靠的输入上做累计模型。
2. 实现 v2 schema、离线迁移、稳定 ID、纯函数合并和历史投影，用合成两章数据跑通。
3. 实现 store、原子提交、init/show，验证第一章可以离线导入并回看。
4. 扩展 Responses adapter 与 update prompt、CLI，跑 dry-run 和 mock pipeline。
5. 实现 diff/review/跨章引用验证，完成失败和并发测试。
6. 有凭证和模型配置时，只做一次目标明确的 Chapter 2 实验，默认沿用用户已有 provider/model；不要自行批量跑全书或切到更贵模型。模型缺配置时，完成所有离线工作并给出待执行命令。
7. 核对第二章至少 10 条主张和所有实际发生的旧事实修订/身份链接/疑点解答。若某类变化为零，真实记录为零，不能编造来证明功能；该能力由合成测试覆盖。
8. 人工从第二章选出至少 10 个重要信息点检查覆盖，记录错误关联、重复人物、旧事实误删、误解倒叙、遗漏等。第一章已有的错误与本次增量新增错误分开统计。
9. 对比第一章快照更新前后哈希完全一致；第二章最新文件同时包含旧知识、新知识、来源和修改历史。说明起始覆盖不包含前面的序章。

交付必须能演示：

```text
init 第一章 → show revision 1
update 第二章 → show latest
show revision 1 仍与原先一致
再次 update 第二章 → already_processed，零请求
```

最终报告：修复点、代码位置、测试数、实际 provider/model、旧/新 revision、输出路径、真实内容评审结论及未完成项。明确哪些通过了 mock、哪些经过真实 API；不把格式通过或自动提交成功当成事实准确率。

本文件仅规定下一阶段实现，未声称章节边界已修复或第二章累计模型已生成。
