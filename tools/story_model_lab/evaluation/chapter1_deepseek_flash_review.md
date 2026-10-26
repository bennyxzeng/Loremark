# Chapter 1 评估：DeepSeek `deepseek-flash` / Chapter 1 Evaluation: DeepSeek `deepseek-flash`

| 项 / Item | 值 / Value |
| --- | --- |
| 运行 ID / Run ID | `20261026T032410Z-2c6f50` |
| 书 / 章节 · Book / Section | 86—EIGHTY-SIX, Vol. 1 · `section-004` “Chapter 1: A Battlefield with Zero Casualties”（185 段 / paragraphs） |
| Provider / 模型 · Model | DeepSeek · `deepseek-flash`（推理等级未设置，模型默认 / reasoning effort not set, model default） |
| Prompt / Schema SHA-256 | `6ae94bfc…886ddc0` / `9726d221…5fbd821cf` |
| 耗时 / Time | 258.5 s，无重试 / no retries |
| Token | input 14,143 · output 58,662（reasoning 38,521）· total 72,805 |
| 自动校验 / Validation | 原始输出 1 个错误；人工修正 1 处后 0 错误 0 警告 / 1 error in the raw output; 0 errors, 0 warnings after 1 manual fix |
| 评审者 / Reviewer | Claude Code（AI，非人工评审 / AI, not a human reviewer），2026-10-26 |

Cost: 0.07usd

---

## 中文

### 1. 结论

这次运行在工程上可用，内容质量整体不错，但有一个重要遗漏，身份判断也偏保守。

- 抽查 20 条生成主张，20 条 `supported`，0 条 `needs_review`：抽查支持率 20/20。其中 2 条另有小问题，assertion 标签或事件粒度不够理想，见第 4 节。
- 16 个预期重要信息点中，12 个完全覆盖、3 个部分覆盖、1 个未覆盖：所选信息点覆盖率 12/16（75%）。这 16 个点是在模型运行之前从原文独立选出的。
- 没有发现本章以外的知识：输出里没有 Shin、Raiden 等后续章节的名字，也没有用作品常识回答身份问题。
- 240 条引用里有 1 条段落号标错（p0164 应为 p0163）。逐字校验拦住了它，我按用户要求人工修正，并记录在 `run.json` 的 `manual_corrections`，原始输出保存在 `candidate.original.json`。

这两个比例只针对本次抽样和所选信息点，不是全章准确率或完整召回率。

### 2. 方法

- 只依据本章原文判断，标准见 `rubric.md`。
- **抽查规则：** 事件取 e001、e005、e009、e013、e017 和最后一条 e020；关系取 r001、r005、r009、r013、r017、r021（每隔 4 条取一条）；属性取 Lena、Annette、Pleiades 的 Processor、Undertaker 四个主要人物各自的第一条和最后一条。共 20 条，覆盖章节开头、中间、结尾。别名和疑点另外全部检查。
- 16 个信息点在运行前已写入 `sample_review.md` 第 3 节，评审时没有改动。
- **局限：**
  - 评审者是 AI，事先知道这部小说，可能影响判断，虽然已尽量只看本章原文。
  - 没有第二位评审者。
  - 结论建议由人工复核。

### 3. 做得好的地方

- **时间和叙述顺序清楚：** 九年前开战、#6609 法令、两年后投入 Juggernaut 都标为 `past`；主线事件按本章叙述顺序 1–20 排列，没有警告。
- **区分“说法”和“事实”：** Undertaker 会“弄坏”Handler、Handler 自杀等传闻都标为 `reported`，说话人是 Karlstahl（c004）；Karlstahl 与 Václav 的关系标为 `inferred`，并配了疑点“Václav 是否为 Lena 已故的父亲”。
- **别名有本章依据：** Lena = Vladilena Milizé = Handler One，Karlstahl = Uncle Jérôme，Undertaker = Reaper，Josef von Penrose = Annette 的父亲，每一条都有原文证据。
- **疑点提得合理：** 帝国为何灭亡、Para-RAID 的另一位研究者是谁、Theobald 是否就是相亲对象，都保留为疑点，没有猜答案。

### 4. 问题

1. **遗漏关键回忆（R09）：** p0086 写到 Lena 已故的父亲一直反对关押 Eighty-Six，以及 Lena 记得被一台带“无头骷髅骑士”徽记的四足机体救过。输出里既没有事件、属性，也没有疑点。这是本章最重要的伏笔之一，而且救她者的身份本应作为疑点保留。
2. **身份判断偏保守：**
   - Annette 在 p0021 自称 “certified genius Technical Lieutenant Henrietta Penrose”，本章已足以支持这个别名，模型却只列为疑点。
   - 模型还问 Pleiades 的 Processor 和 Undertaker 是否同一人，但原文写明两人分属第三战队（第九战区）和 Spearhead 战队（第一战区），这个疑点依据不足。
   - 偏保守不会误导读者，但会漏掉可用信息。
3. **证据与结论不符：** Annette 的属性 `family = daughter of the Penrose family` 带了一条无关证据 “Annette smiled mischievously.”（正是段落号标错的那条）。这条属性标成 `inferred`，但 p0165 已直接写出 “daughter of the Penrose family”。这说明引用存在不等于引用支持结论。
4. **assertion 标签不一致：** Lena 的属性 `father = late father was a soldier` 引用的是母亲的话（p0074），却标成 `explicit`。事实本身由 p0102 的叙述确认，所以判 supported，但按所选证据应标 `reported`。
5. **其他问题：**
   - **事件粒度：** e013 把“Karlstahl 警告”和“Lena 接受任命”合成一条。
   - **漏掉政府判断：** “Legion 两年内将全部停机”只体现为 Legion 处理器寿命“5 万小时”这条属性，没有记录共和国据此得出的结论（R14）。
   - **Eighty-Six 没有作为群体建模（R05）。**
   - **低价值记录：** 例如地点“medical room”只有一条“有加固玻璃窗”的属性，增加噪声但没有错误。
6. **成本：** 输出 token 的 66% 是推理 token，总耗时 4 分多钟。如果保留原来 16,000 的输出上限，这次运行会因截断而失败。

### 5. 建议

1. **Prompt v2：**
   - 角色用全名或头衔称呼自己，算本章内的别名依据。
   - 段落中的回忆和闪回也要抽成 `past` 事件，看不清的身份列为疑点。
   - 证据必须支持结论本身，不能只是出现在附近。
   - 只有角色台词作为证据时用 `reported`。
2. **对照实验：** 用 v2 prompt 再跑一次，或用 `--reasoning-effort max`、OpenAI 模型各跑一次，用同一套 16 个信息点比较，修改前后的结果分开保存。
3. **保持现在的修正方式：** 自动修复会掩盖模型弱点。本次段落号错误是人工修正并留痕，建议继续这样做。

---

## English

### 1. Verdict

The run works end to end and the content is mostly sound, but it misses one important memory and is too cautious about identities.

- Spot check of 20 generated claims: 20 `supported`, 0 `needs_review`, so the spot-check support rate is 20/20. Two of them have minor problems with the assertion label or event granularity (section 4).
- Of 16 reference points chosen from the text before the run: 12 fully covered, 3 partially covered, 1 missed. Coverage of the selected points is 12/16 (75%).
- No knowledge from outside the chapter was found. Later-chapter names such as Shin or Raiden do not appear, and no identity question was answered from knowledge of the series.
- 1 of 240 quotes cited the wrong paragraph (p0164 instead of p0163). Exact-match validation caught it. At the user's request I fixed it by hand; the fix is recorded in `run.json` → `manual_corrections`, and the original output is kept in `candidate.original.json`.

These rates apply only to this sample and these reference points. They are not chapter-wide accuracy or recall.

### 2. Method

- Judged against the chapter text only, following `rubric.md`.
- **Sampling rule:** events e001, e005, e009, e013, e017, plus the last one, e020; relationships r001, r005, r009, r013, r017, r021 (every fourth); attributes: the first and last attribute of each of the four main characters (Lena, Annette, Pleiades's Processor, Undertaker). That makes 20 claims across the start, middle, and end of the chapter. All aliases and uncertainties were also checked.
- The 16 reference points were written into section 3 of `sample_review.md` before the run and were not changed.
- **Limits:**
  - The reviewer is an AI that knows the novel, which may bias it despite the effort to judge from the chapter alone.
  - There is no second reviewer.
  - A human should re-check these findings.

### 3. Strengths

- **Clear time framing and order:** the war nine years ago, Order #6609, and the Juggernaut program two years later are all `past`. The main events are numbered 1–20 in the chapter's own order, with no warnings.
- **Claims are kept apart from facts:** rumors that Undertaker "breaks" his Handlers and that Handlers committed suicide are `reported`, attributed to Karlstahl (c004). The Karlstahl–Václav link is `inferred` and paired with the uncertainty "Is Václav the name of Lena's late father?"
- **Aliases are supported by the chapter:** Lena = Vladilena Milizé = Handler One, Karlstahl = Uncle Jérôme, Undertaker = Reaper, Josef von Penrose = Annette's father. Each has evidence in the text.
- **Sensible open questions:** why the Empire fell, who the other Para-RAID researcher was, and whether Theobald is the arranged-marriage candidate are kept as questions, not answered.

### 4. Problems

1. **Key memory missed (R09):** p0086 says Lena's late father opposed the internment of the Eighty-Six to the end, and that Lena remembers being saved by a four-legged machine bearing a headless skeletal knight crest. The output has no event, attribute, or uncertainty for it. This is one of the chapter's main pieces of foreshadowing, and the rescuer's identity should have been an open question.
2. **Over-cautious identity handling:**
   - In p0021 Annette calls herself "certified genius Technical Lieutenant Henrietta Penrose". The chapter supports that alias, but the model only lists it as an uncertainty.
   - The model also asks whether Pleiades's Processor and Undertaker are the same person, although the text places them in different squadrons (third squadron, ninth ward vs. Spearhead, first ward), so that question has little basis.
   - Being cautious does not mislead the reader, but it leaves usable information out.
3. **Evidence that does not support the claim:** Annette's attribute `family = daughter of the Penrose family` cites the irrelevant "Annette smiled mischievously." (the same item that had the wrong paragraph ID). The attribute is labeled `inferred`, although p0165 states "daughter of the Penrose family" directly. A quote that exists is not a quote that supports the claim.
4. **Inconsistent assertion label:** Lena's `father = late father was a soldier` cites her mother's line (p0074) but is labeled `explicit`. The fact is confirmed by narration in p0102, so it counts as supported, but with this evidence the label should be `reported`.
5. **Other problems:**
   - **Event granularity:** e013 merges Karlstahl's warning and Lena's acceptance into one event.
   - **Government conclusion missing:** the Republic's belief that the Legion will all shut down within two years appears only as the Legion's 50,000-hour processor lifespan, not as a conclusion (R14).
   - **The Eighty-Six are not modeled as a group (R05).**
   - **Low-value records:** for example, the location "medical room" has a single "reinforced glass window" attribute. This adds noise but is not wrong.
6. **Cost:** 66% of output tokens were reasoning tokens, and the run took over four minutes. With the earlier 16,000-token output cap, this run would have failed as truncated.

### 5. Recommendations

1. **Prompt v2:**
   - A character naming themself by full name or title counts as alias evidence within the chapter.
   - Memories and flashbacks inside a paragraph should become `past` events, with unclear identities listed as uncertainties.
   - Evidence must support the claim itself, not merely appear nearby.
   - Use `reported` when the only evidence is a character's line.
2. **Comparison runs:** run v2 once, or try `--reasoning-effort max` or an OpenAI model, and compare against the same 16 reference points. Keep the results from before and after the change separate.
3. **Keep fixing by hand with a record:** automatic repair would hide model weaknesses. This run's paragraph-ID error was fixed by hand and recorded; keep doing that.

---

## 附录 A：抽查明细 / Appendix A: Claim checks

位置按证据段落三等分：开头 p0001–p0061，中间 p0062–p0125，结尾 p0126–p0185。
Position by evidence paragraph: start p0001–p0061, middle p0062–p0125, end p0126–p0185.

| # | 记录 / Record | 主张 / Claim | 位置 / Pos. | 证据 / Evidence | 结论 / Verdict | 备注 / Note |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | e001 | Broadcast: Legion invaded the seventeenth ward and were repelled, no loss of life reported | start | p0003 | supported | 作为“广播内容”表述 / framed as what the broadcast says |
| 2 | e005 | Nine years earlier, Giad declared war and attacked with the Legion (`past`) | start | p0040 | supported | story_time 取自 p0039 / story_time from p0039 |
| 3 | e009 | Lena thanks Pleiades and apologizes; Pleiades replies coldly | start | p0060, p0063 | supported | |
| 4 | e013 | Karlstahl warns about Undertaker; Lena accepts | middle | p0107, p0110, p0114 | supported | 两个动作合为一条 / two actions merged |
| 5 | e017 | Annette reveals the other researcher was an Eighty-Six with no recorded name | end | p0157 | supported | |
| 6 | e020 | Lena concludes the Processors are human beings | end | p0184 | supported | |
| 7 | r001 | Lena member_of Republic military | start | p0008 | supported | |
| 8 | r005 | Karlstahl friend_of Václav (`inferred`, `past`) | middle | p0102, p0125 | supported | inferred 使用恰当 / correct use of `inferred` |
| 9 | r009 | Annette daughter_of Josef von Penrose | end | p0159 | supported | |
| 10 | r013 | Spearhead located_in eastern front's first ward | middle | p0099 | supported | |
| 11 | r017 | Republic at_war_with Legion (`current`) | start | p0003, p0004 | supported | |
| 12 | r021 | Theobald arranged_marriage_candidate_of Annette (`inferred`) | end | p0169, p0172 | supported | 另有对应疑点 / paired with an uncertainty |
| 13 | c001.attr[0] | Lena: age 16 | start | p0008 | supported | |
| 14 | c001.attr[8] | Lena: late father was a soldier (`explicit`) | middle | p0074 | supported | 证据是母亲台词，应为 reported；p0102 叙述确认事实 / evidence is the mother's line, should be `reported`; p0102 confirms the fact |
| 15 | c002.attr[0] | Annette: technical lieutenant | start | p0019 | supported | |
| 16 | c002.attr[7] | Annette: father is Professor Josef von Penrose | end | p0159 | supported | |
| 17 | c005.attr[0] | Pleiades's Processor: third squadron captain | start | p0031 | supported | |
| 18 | c005.attr[5] | Pleiades's Processor: cold contempt and hatred toward Lena | middle | p0064 | supported | |
| 19 | c006.attr[0] | Undertaker: Spearhead squadron's captain unit | middle | p0106 | supported | Karlstahl 所说，p0180 本人确认 / said by Karlstahl, confirmed by Undertaker in p0180 |
| 20 | c006.attr[7] | Undertaker: detached demeanor | end | p0183 | supported | |

汇总 / Summary：抽查 20 条，20 supported，0 contradicted，0 unsupported，0 needs_review / 20 checked: 20 supported, 0 contradicted, 0 unsupported, 0 needs_review.

## 附录 B：预期信息点覆盖 / Appendix B: Reference-point coverage

信息点定义见 `sample_review.md` 第 3 节 / Points are defined in `sample_review.md`, section 3.

| ID | 覆盖 / Covered | 对应记录 / Matched records | 说明 / Note |
| --- | --- | --- | --- |
| R01 | yes | c001 attrs 0, 3 | 16 岁、Alba、纯血 Celena / age 16, Alba, pureblood Celena |
| R02 | yes | c001 aliases, attr 5; e003 | |
| R03 | yes | c005; e004, e009 | |
| R04 | yes | e005, e006 | |
| R05 | partial | l005 attrs | 只作为地点人口描述，没有“蔑称”与群体实体 / only as a location's population; no "derogatory name" or group entity |
| R06 | yes | e007; g001 attr 5 | |
| R07 | yes | e008; g006 attr 2 | |
| R08 | yes | e011; c003 attrs | |
| R09 | no | — | p0086 父亲反对关押、无头骷髅骑士徽记的救援者均缺失 / father's opposition and the rescuer with the headless knight crest are missing |
| R10 | yes | c004 alias “Uncle Jérôme”; r005; c004 attr 4 | |
| R11 | yes | e012, e015; r003 | |
| R12 | yes | c006 attrs 1–3 (`reported`); e013 | |
| R13 | partial | r007; c002 attr 5; uncertainty | Henrietta Penrose 未作为别名 / Henrietta Penrose not linked as an alias |
| R14 | partial | e014; g003 attr 3 | 缺“两年内全部停机”的判断 / the "all shut down within two years" belief is missing |
| R15 | yes | e018, e016 | |
| R16 | yes | e019 | |

汇总 / Summary：yes 12 · partial 3 · no 1 → 所选信息点覆盖率 / coverage of selected points 12/16。
