# Chapter 2 累计更新评估 / Chapter 2 Cumulative Update Evaluation

> **更新（2026-10-26）：已真实运行一次，结果 `validation_failed`；10 处证据位置经人工修正后提交为 revision 2，见第 5.1、5.2 节。正式内容评审尚未进行。** 以下为运行前的原始说明。
>
> **状态：真实 Chapter 2 更新尚未运行。** 本文件只记录已经真实完成的离线步骤、预先登记的评审标准和待执行命令。
> 下文没有任何关于第二章模型输出准确度的结论；那些小节在真实运行后填写。
>
> **Status: the real Chapter 2 update has not been run.** This file records the offline steps that
> were actually done, the review criteria registered in advance, and the command still to run. It
> makes no claim about the accuracy of a Chapter 2 model output.

| 项 / Item | 值 / Value |
| --- | --- |
| 日期 / Date | 2026-10-26 |
| 书 / Book | 86—EIGHTY-SIX, Vol. 1 · EPUB SHA-256 `452d8183…911317` |
| Store | `tools/story_model_lab/stores/86v1`（git 忽略 / ignored by git） |
| Base | revision 1 `f97526f46e1b`，快照 / snapshot `revisions/000001-f97526f46e1b.json`，SHA-256 `0259216bb657b4e6cbd604da1e30d3e514bd4b0aee90ea7673cb55cca0de1723` |
| 新节 / New section | `section-005` “Chapter 2: All Quiet on the Skeletal Front”（285 段 / paragraphs，66,622 字符，1 张图片省略） |
| 真实 API 调用 / Real API call | **未执行**：本次执行环境中没有 `DEEPSEEK_API_KEY` / `DEEPSEEK_MODEL`，也没有 OpenAI 凭证 / **not run**: no DeepSeek or OpenAI credentials in this environment |
| OpenAI 官方接口 / OpenAI API | 仍无已核实的真实运行记录（`generate` 和 `update` 都没有）/ still no verified real run (neither `generate` nor `update`) |
| 评审者 / Reviewer | Claude Code（AI，非人工评审 / AI, not a human reviewer） |

---

## 1. 已真实完成的离线步骤

1. **章节边界修复后样本不变。** `story-model chapters` 仍列出 18 节；7 个主章节仍映射到 `section-004/005/006/008/010/012/014`；Chapter 1 文本哈希仍为 `d1053fa1…53f9d549`；样本中没有任何节被标为不可提取。（`tests/test_epub.py::test_user_sample_chapter_mapping`）
2. **`init`：** 由 `runs/20261026T032410Z-2c6f50` 离线导入为 revision 1。30 个实体（人物 12、地点 10、组织 8）、205 条记录、240 条证据全部逐字匹配；1 处人工修正（`characters[1].attributes[6].evidence[0].paragraph_id`：p0164 → p0163）带入 `provenance`，映射到记录 `f000064`；原始输出 `candidate.original.json` 复制到 `provenance/initial/`。
3. **覆盖范围：** 起点 `section-004`；`section-001`（Front Matter）、`section-002`（Epigraph）、`section-003`（Coquelicots Blooming Across the Battlefield，序章）未处理。该模型**不是**“全书开头到第一章结束”的完整状态。
4. **原运行目录未改变：** `init` 前后逐文件 SHA-256 一致。
5. **`show --revision 1`** 与 `show`（此时最新即 revision 1）输出逐字节一致（446 行）。
6. **Chapter 2 `--dry-run`**（`runs/chapter2-update-dry-run/`）：
   - 用户消息 158,037 字符（上一版模型 JSON + 第二章 285 段），system prompt 8,449 字符；未发送请求，store 未改变。
   - 上下文包含 revision 1 的全部 30 个实体、205 条记录及证据；不含书名、Front Matter、第三章或第一章正文（只有记录里的短引文）。
   - Prompt `builtin:update_story_v1.txt`，SHA-256 `30c24b1d…ab76d08`；Schema `StoryDelta`，SHA-256 `70e8068e…a3f42fd`；context SHA-256 `552de1d6…f969b39`。

## 2. 待执行命令

```bash
source tools/story_model_lab/.venv/bin/activate
export DEEPSEEK_API_KEY=...          # 只在 shell 中设置
export DEEPSEEK_MODEL=deepseek-flash # 沿用第一章的 provider/model

story-model update --store tools/story_model_lab/stores/86v1 \
  --epub sample_epub/86v1_chapters.epub --chapter 2 --provider deepseek

story-model show --store tools/story_model_lab/stores/86v1               # 最新（revision 2）
story-model show --store tools/story_model_lab/stores/86v1 --revision 1  # 应与更新前一致
shasum -a 256 tools/story_model_lab/stores/86v1/revisions/000001-f97526f46e1b.json
#   必须仍为 0259216bb657b4e6cbd604da1e30d3e514bd4b0aee90ea7673cb55cca0de1723
story-model update --store tools/story_model_lab/stores/86v1 \
  --epub sample_epub/86v1_chapters.epub --chapter 2 --provider deepseek
#   第二次应输出 already_processed，零请求
```

只做这一次目标明确的调用；不批量跑全书，不换更贵的模型。若结果 `validation_failed`，不要自动重试或修正；按第 4 节记录失败原因。

## 3. 预先登记的评审标准（在任何第二章模型输出存在之前写定）

以下信息点只依据第二章原文（`runs/chapter2-update-dry-run/chapter.txt`）选出。评审者是 AI 且事先知道这部小说，这可能影响选择；已尽量只选原文明确写出的内容。

### 3.1 跨章关联（最重要）

| # | 期望 | 依据段落 |
| --- | --- | --- |
| X1 | 第一章的 `c006` Undertaker 就是第二章的 Shin / Shinei Nouzen：应复用 `c006`（新增名称记录，必要时 supersede 旧主名称并保留 Undertaker 为别名），**不应**新建重复人物 | p0012、p0013、p0020、p0130 |
| X2 | 第二章的 Handler One 应关联到第一章已有别名 “Handler One” 的 `c001`，不应新建无名 Handler | p0146、p0183、p0235 |
| X3 | Spearhead squadron 复用 `g005`，Legion 复用 `g003` | p0002、p0154 |
| X4 | 疑点 `f000200`（Pleiades 的 Processor 与 Undertaker 是否同一人）与 `f000201`（Undertaker 前任 Handler 为何听到鬼魂声音）第二章都没有给出答案，应保持未解答 | p0147、p0234 只是暗示 |
| X5 | 第一章 `c006` 的属性（Spearhead 队长、被称为 Reaper 等）与第二章一致，不应被撤回 | p0130、p0131 |

### 3.2 第二章重要信息点（16 个）

| # | 信息点 | 依据段落 |
| --- | --- | --- |
| P1 | Shin 的外貌与血统：Pyrope 红眼、Onyx 黑发，半 Aquila 半 Rubela，今年将满十六岁 | p0005、p0013 |
| P2 | Kujo 十天前死于自走地雷（夜间救援任务）；是本中队两个月来第三名阵亡者 | p0004、p0023、p0128 |
| P3 | Lev Aldrecht：Spearhead 维修班长，五十多岁，九年前战争的幸存者；抱怨 Shin 每次出击都弄坏机体 | p0013–p0016 |
| P4 | Fido：跟随 Shin 约五年的 Scavenger；与 Shin 是一场战斗仅有的两个幸存者，由 Shin 命名 | p0103–p0105 |
| P5 | Raiden：副队长，纯血 Eisen，与 Shin 并肩三年，Personal Name 为 Wehrwolf | p0093、p0094、p0215、p0274–p0276 |
| P6 | Shin 五年来一直提交同一份伪造巡逻报告；新 Handler 读完全部报告，要求补交手写报告 | p0037–p0039、p0245–p0266 |
| P7 | 新 Handler 一周前上任，每天晚饭后 Resonate；前任因为害怕 Reaper 而辞职 | p0042、p0147、p0236 |
| P8 | Legion 来袭：Eintagsfliege 干扰；中队已在 point 204 埋伏（Handler 建议 point 208） | p0115–p0118、p0148–p0149 |
| P9 | Shin 不靠雷达就能感知敌军规模和阵型 | p0119、p0136 |
| P10 | Shin 单机连续击毁多台 Löwe | p0201–p0210 |
| P11 | Handler 发送 Long-Range Observer Unit 坐标；Shin 要求只用口头传递；Kurena 狙击 | p0183–p0189 |
| P12 | Spearhead 全员都是有 4–6 年经验的 Name Bearer；各人 Personal Name（Black Dog = Daiya，Snow Witch = Anju，Laughing Fox = Theo，Falke = Haruto，Fafnir = Kino，Gunslinger = Kurena） | p0152–p0154、p0174–p0177、p0185 |
| P13 | 成员之间的旧识：Daiya 与 Anju 自入伍同队；Kaie 与 Haruto 同年；Theo、Kurena 与 Shin、Raiden 同队两年 | p0275 |
| P14 | Shin 服役五年、即将期满；被问到退役后的打算时说没想过 | p0278–p0282 |
| P15 | Eighty-Six 没有坟墓，禁止收殓遗体；共和国维持“零伤亡”假象 | p0022、p0108 |
| P16 | Kurena 被同伴取笑喜欢 Shin（转述/调侃，不应记为 explicit 事实） | p0068–p0091 |

### 3.3 预先登记的易错点

- E1 为 Shin、Handler One 新建重复实体（对应 X1、X2）。
- E2 把九年前的战争、Fido 的来历、成员旧识等倒叙写成 `current`，或用它们 supersede 当前状态。
- E3 把 Shin 引用的圣经句 “I am Legion, for we are many” 记成与 `g003` 的关系或身份证据。
- E4 在没有证据时 resolve `f000200`/`f000201`，或 retract 第一章事实。
- E5 引用第一章段落作为新证据（程序会拒绝，应在 `validation.json` 中可见）。

## 4. 真实运行后的评审方法（届时填写）

1. 记录 provider/model、usage、耗时、`run.json` 的 `status`/`commit_status`，以及 revision 1 → 2。
2. 抽查第二章新增主张至少 10 条（按 `diff.md` 顺序每隔固定间隔取样，取样规则先写下再看内容），逐条标 `supported` / `needs_review` / `wrong`。
3. **全部**检查实际发生的 supersede、retract、resolve 与身份链接；若某类为零，如实记为零，不编造。
4. 对照 3.1 与 3.2 记录覆盖：完全 / 部分 / 未覆盖。
5. 错误分两类统计：第一章导入时已有的错误（例如第一章评估中记录的遗漏）与本次增量新引入的错误。
6. 核对 revision 1 快照 SHA-256 不变、`show --revision 1` 与更新前一致、第二次 update 为 `already_processed`。
7. 明确：自动校验通过只代表结构、ID、引用与历史不变量一致，不代表事实准确或完整。

## 5. 结果

### 5.1 第一次真实运行：`validation_failed`，未提交

| 项 | 值 |
| --- | --- |
| 运行 ID | `20261026T234001Z-299093` |
| Provider / 模型 | DeepSeek · `deepseek-flash`（推理等级未设置） |
| 耗时 / Token | 226.6 s，无重试；input 44,905 · output 56,914（reasoning 40,087）· total 101,819 |
| 结果 | 退出码 4；`commit_status=not_attempted`；store 仍为 revision 1，快照 SHA-256 仍为 `0259216b…0de1723` |
| 增量规模 | 新实体 24；新记录：名称 25、别名 11、属性 47、关系 20、事件 22、疑点 5、身份链接 0；转换：替代 1，撤回 0，解答 0 |
| 证据 | 167 条，157 条逐字匹配，10 条不匹配 |

10 个错误全部是证据定位问题：
- 7 条引文逐字正确，但段落号比实际所在段落大 1（应为 p0058、p0093、p0094 的引文被标成 p0059、p0094、p0095）。出错位置紧跟在原 EPUB 中把两个场景合在一个 `<p>` 里的段落之后（p0058、p0092）。
- 3 条引文被改写，不是原文子串：`if we ambush near point 304`（原文 `if we ambush them near point 304`，2 处）；`…machine guns on its shoulders`（原文 `on their shoulders`）。

对照 3.1 的初步检查（只看了候选增量，未逐条核对主张，不是正式评审）：
- X1 符合：复用 `c006`，新增名称 “Shinei Nouzen” 并 supersede 旧名称 `f000006`，“Shin”“Undertaker” 记为别名，没有新建重复的 Shin。
- X2 符合：4 个 Handler One 事件引用 `c001`。
- X3 符合：大量引用 `g005`、`g003`。
- X4、X5 符合：没有 resolve 或 retract，`f000200`、`f000201` 保持未解答。
- P16 处理恰当：Kurena 的感情记为疑点，而不是事实。

按本轮规则，没有自动修正、没有自动重试。

### 5.2 人工修正后提交（用户选择）

- 用户选择人工修正而不是重跑。10 处修正写在运行目录的 `manual_corrections.json`：7 处只改段落号，3 处把改写过的引文换回原文的精确片段，所引段落不变。每处修正都核对过：引文只在唯一一个段落出现，或者恢复后的片段确实在所引段落中。
- `story-model commit` 重新完整校验后提交：0 错误，0 警告，revision 1 → **revision 2**（`5ed0861ea7ed`）。没有发送任何新的请求。
- 模型原始输出 `delta.candidate.json` 和原始 `validation.json` 未改动，并已复制到 `stores/86v1/provenance/20261026T234001Z-299093/`。10 处修正记录在模型的 `provenance.update_manual_corrections` 中，`show` 和 `review.md` 都标明该修订**不是模型原样输出**。
- 交付演示核对：
  - revision 1 快照 SHA-256 仍为 `0259216b…0de1723`；
  - `show --revision 1` 的输出与更新前逐字节一致（SHA-256 `6ed9ad59…`）；
  - 再次 `update --chapter 2` 返回 `already_processed`，零请求。
- 尚未做第 4 节的正式内容评审（≥10 条主张抽查、全部转换、3.2 信息点覆盖）。

### 5.3 汇总

| 项 | 结果 |
| --- | --- |
| 真实运行 | 1 次，`validation_failed`（见 5.1）；10 处证据位置人工修正后提交为 revision 2（见 5.2） |
| 抽查主张 | — |
| 状态转换 / 身份链接 / 已解答疑点 | — |
| 3.1 跨章关联 | — |
| 3.2 信息点覆盖 | — |
| 新引入错误 / 继承错误 | — |
| revision 1 快照哈希 | 更新前后均为 `0259216b…0de1723` |

---

## English summary

- Done for real (offline): the boundary fix leaves the sample's mapping and Chapter 1 hash
  unchanged; `init` imported the corrected Chapter 1 run as revision 1 (30 entities, 205
  records, 240/240 quotes matched, 1 manual correction carried into provenance) without
  changing the run directory; `show --revision 1` works; the Chapter 2 dry run builds a
  158,037-character user message with the full prior model and only Chapter 2's text.
- Not done: the real Chapter 2 call, because no provider credentials were available. There
  is no Chapter 2 accuracy result, and still no verified real run against the OpenAI API.
- Section 3 registers the cross-chapter links (Undertaker = Shin → reuse `c006`; Handler One →
  `c001`), 16 information points, and 5 likely errors before any output exists; section 4
  fixes the review procedure for when the run happens.
