# 样本评审记录：86—EIGHTY-SIX, Vol. 1，Chapter 1

> **状态：已完成一次真实运行（DeepSeek `deepseek-flash`，运行 `20261026T032410Z-2c6f50`）及其评审，详见 [`chapter1_deepseek_flash_review.md`](chapter1_deepseek_flash_review.md)（中英双语）。** 第 3 节的预期信息点是在真实运行之前、未看到任何模型输出时独立选出的。

## 1. 输入

| 项 | 值 |
| --- | --- |
| EPUB | `sample_epub/86v1_chapters.epub`（SHA-256 `452d8183147c1d20a0d474b8d0c981556b2f1bdb4bfb7151c25729f413911317`） |
| 选择 | `--chapter 1` → `section-004`，`EPUB/section-004.xhtml`，spine 第 4 项 |
| 段落 / 字符 | 185 段，49,692 字符（规范化后） |
| 文本 SHA-256 | `d1053fa1bbdd5a1609a15112b64f9fa961aa5395f72a2d80bed92ade53f9d549` |
| Prompt | 内置 `extract_story_v1.txt`，SHA-256 `6ae94bfc105ab8fd90929576e68a12601c60e70ed19c2ec7ead173699886ddc0` |
| Schema | SHA-256 `9726d2213492cefd3895a1d4231c9fbbced1c18eeed6ed1e8f814c85fbd821cf` |
| 省略图片 | 6 张（其中 3 张是分隔符小图 `008.png`），未读取 |

以上哈希来自 `generate --chapter 1 --dry-run`。只要 EPUB、prompt 和代码不变，真实运行的 `run.json` 应给出相同的值。

## 2. 提取检查（已完成）

- Chapter 1 选中的是标题为 “Chapter 1: A Battlefield with Zero Casualties” 的第 4 个 spine 文档，而不是第 1 个 XHTML。7 个编号章节与执行计划中的映射表一致（由 `test_user_sample_chapter_mapping` 自动检查）。
- 第一段是章节标题 `p0001`，最后一段 `p0185` 为 “I wish the same to you. I look forward to working with you, Undertaker.”；与前一节（section-003）、后一章（section-005）没有重复的长段落。
- 弯引号、破折号、省略号和重音字符（Liberté et Égalité、Milizé、Václav、Jérôme）保留原样。
- 源 EPUB 自身有几处把两个场景放在同一个 `<p>` 里，提取忠实保留，没有重新拆分：p0090（“I’m off, Mother.” 与下一场景 “You’re changing my assigned squadron…?”）、p0126、p0173。模型可能据此把相邻场景误连，评审时需留意。
- 本章不含 Shin、Nouzen、Raiden 等后续章节才出现的名字（已在规范化文本中检索确认）。若输出出现这些名字，应标为 `outside_chapter_knowledge`。

## 3. 预期重要信息点（看输出之前独立选出）

选取办法：通读全章，按开头（p0001–p0061）、中间（p0062–p0125）、结尾（p0126–p0185）各选主要情节推进、关键人物行为、重要揭示和身份/关系。共 16 点。

| ID | 位置 | 信息点 | 段落 | 短引用 |
| --- | --- | --- | --- | --- |
| R01 | 开头 | Lena 是 16 岁的共和国女军官，Alba，且是纯血 Celena | p0008 | “The sixteen-year-old girl”；“a pureblood Celena” |
| R02 | 开头 | Lena 以 Major Vladilena Milizé 身份认证，是东部战线第九战区第三防卫战队的指挥管制官，呼号 Handler One | p0027, p0032 | “Major Vladilena Milizé, commanding control officer”；“Handler One to Pleiades” |
| R03 | 开头 | Pleiades 是第三战队队长（Processor），对 Lena 语带讽刺 | p0031, p0037 | “the third squadron’s captain, the Processor operating Personal Name unit Pleiades” |
| R04 | 开头（过去） | 九年前 Giad 帝国以 Legion 向邻国开战；Presidential Order #6609 剥夺 Colorata 公民权并将其关押 | p0040, p0042 | “the Empire of Giad, declared war on all its neighboring countries”；“Presidential Order #6609” |
| R05 | 开头 | “Eighty-Six” 是对被逐出 Gran Mule 的 Colorata 的蔑称 | p0038 | “It was a derogatory name for those Colorata cast outside the Gran Mule” |
| R06 | 开头 | Juggernaut 名义上是无人机，实际由 Eighty-Six（Processor）驾驶；“零伤亡”源于他们不被算作人 | p0047, p0048 | “drones manned by living soldiers—and all those soldiers were of the Eighty-Six”；“Since the Eighty-Six were not considered human” |
| R07 | 开头 | 本次战斗中第三战队损失七台机体，驾驶员无人生还 | p0051 | “her third squadron lost seven units” |
| R08 | 中间 | Lena 的母亲劝她退伍嫁人并蔑视 Eighty-Six；Lena 反驳 | p0072, p0076 | “isn’t it about time you quit the army and find a groom from a good family?”；“please don’t call them Eighty-Six” |
| R09 | 中间（过去） | Lena 已故的父亲反对关押 Eighty-Six；Lena 记得一台带无头骷髅骑士徽记的四足机体救过她（救她者身份本章未说明） | p0086 | “who’d greatly objected to the Eighty-Six’s internment until the very end”；“the crest of a headless skeletal knight etched upon its armor” |
| R10 | 中间 | Commodore Karlstahl（Lena 称他 Uncle Jérôme）是 Lena 已故父亲的挚友 | p0091, p0102 | “Commodore Karlstahl”；“Karlstahl had been best friends with Lena’s late father” |
| R11 | 中间 | Karlstahl 任命 Lena 为 Spearhead 战队（东部战线第一战区第一防卫战队）的指挥官 | p0099, p0125 | “also known as the Spearhead squadron”；“I hereby appoint you to the role of commanding officer” |
| R12 | 中间 | Spearhead 队长 Undertaker 据说会“弄坏”Handler；多名 Handler 调离、辞职，部分自杀，称听到亡灵声音（均为转述） | p0106, p0107, p0110, p0111 | “It seems he has a tendency to…break his Handlers.”；“hear the ghosts’ voices” |
| R13 | 结尾 | Annette 即 Technical Lieutenant Henrietta Penrose，是 Lena 的同龄好友，负责 Para-RAID 开发小组 | p0019, p0021, p0127 | “a friend of Lena’s since secondary school”；“Technical Lieutenant Henrietta Penrose”；“Annette was the officer in charge of the Para-RAID development team” |
| R14 | 结尾 | 共和国认为帝国已于四年前灭亡，Legion 因处理器寿命将在两年内全部停机（共和国的判断，不是叙述者确认的事实） | p0121, p0146, p0147 | “The Empire had certainly fallen.”；“all Legion units would shut down” |
| R15 | 结尾（过去） | Annette 的父亲 Josef von Penrose 在 RAID 实验事故中发疯并死亡；Annette 对 Para-RAID 的安全性有疑虑 | p0149, p0159 | “there’s no telling if the Para-RAID is actually safe”；“Professor Josef von Penrose, was involved in an accident” |
| R16 | 结尾 | Lena 首次与 Spearhead 战队共鸣，Undertaker 以队长身份回应 | p0177, p0180 | “Handler One to all units in the Spearhead squadron”；“This is the Spearhead squadron’s captain, Personal Name: Undertaker, speaking.” |

### 身份与疑点的预期

本章本身支持的别名链接：

- Lena = Vladilena Milizé = Handler One（p0027 她本人认证；p0032 她以 Handler One 发话）。
- Annette = Henrietta Penrose（p0021 Annette 自称）。
- Undertaker = “the Reaper”（p0107 Handler 们这样称呼他）。
- Karlstahl = “Uncle Jérôme”（p0102 Lena 当面这样称呼）。

本章不能确定、应保留为疑点或推断的：

- p0086 救过 Lena 的机体驾驶者是谁。若输出把他与 Undertaker 合并，属于身份混淆或章外知识。
- “Václav”（p0125）是否就是 Lena 的父亲：文本暗示但未明说，应为 `inferred` 而非 `explicit`。
- Pleiades 的 Processor 的真实姓名（本章未给出）。
- 帝国灭亡原因（p0121 文本本身提出了这个问题）。

## 4. 生成主张抽查

- 运行 `20261026T032410Z-2c6f50`，DeepSeek，请求/响应模型均为 `deepseek-flash`；原始输出 1 处段落号错误，已人工修正并记录（`run.json` → `manual_corrections`）。
- 抽查 20 条：20 supported，0 needs_review（抽查支持率 20/20）；其中 2 条有 assertion 标签或事件粒度的小问题。
- 主要问题：遗漏 p0086 的关键回忆；身份判断偏保守（Annette = Henrietta Penrose 未合并）；1 条证据与结论无关。

明细见 [`chapter1_deepseek_flash_review.md`](chapter1_deepseek_flash_review.md) 附录 A。

## 5. 信息点覆盖

yes 12 · partial 3（R05、R13、R14）· no 1（R09）→ 所选重要信息点覆盖率 12/16。明细见同一文件附录 B。

## 6. 运行命令

```bash
source tools/story_model_lab/.venv/bin/activate

# OpenAI
export OPENAI_API_KEY=...   OPENAI_MODEL=...
RUN_LIVE_OPENAI=1 python -m pytest tools/story_model_lab/tests -m live -s
story-model generate --epub sample_epub/86v1_chapters.epub --chapter 1

# 或 DeepSeek
export DEEPSEEK_API_KEY=...   DEEPSEEK_MODEL=deepseek-flash
RUN_LIVE_DEEPSEEK=1 python -m pytest tools/story_model_lab/tests -m live -s
story-model generate --epub sample_epub/86v1_chapters.epub --chapter 1 --provider deepseek
```

运行结束后打开输出目录中的 `review.md`，按第 4、5 节完成评审。
