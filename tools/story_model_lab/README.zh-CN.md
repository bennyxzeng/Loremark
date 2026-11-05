# Story Model Lab

[![English](https://img.shields.io/badge/English-64748B?style=for-the-badge)](README.md) [![简体中文](https://img.shields.io/badge/%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-2563EB?style=for-the-badge)](README.zh-CN.md)

[![Story Model 文件结构与标签](https://img.shields.io/badge/Story_Model-%E6%96%87%E4%BB%B6%E7%BB%93%E6%9E%84%E4%B8%8E%E6%A0%87%E7%AD%BE-0F766E?style=for-the-badge)](STORY_MODEL_FORMAT.zh-CN.md)

**`story_model.json` 里面记录了什么？** 先看[一图看懂（附《86》例子）](STORY_MODEL_FORMAT.zh-CN.md#at-a-glance)，再查[文件结构与标签说明](STORY_MODEL_FORMAT.zh-CN.md)：人物、地点、组织、关系、事件、证据、疑点、历史修订，以及 `inferred`、flashback（对应 `past`）等依据和时间标签的完整含义。[English](STORY_MODEL_FORMAT.md)。

[查看结构关系图](STORY_MODEL_FORMAT.zh-CN.md#visual-overview)：直观看每个字段存什么，以及实体、记录、证据和历史修订之间如何通过 ID 关联。

[准备](#setup) · [新书](#new-book) · [继续已有 store](#continue-store) · [运行失败时](#run-fails) · [参考](#commands)

Loremark 的本地命令行实验工具：**按阅读顺序、一次一节**地为 EPUB 建立 story model。每次 `update` 把目前为止的模型和下一节正文，通过 **Responses API 的 Structured Outputs** 发给模型；模型只返回这一节新增或修改的内容（增量），程序校验、分配稳定 ID，并提交一个新修订。一本书的第一次 `update` 从空模型开始，同时创建 store。历史事实和修订都会保留，可以回看书中任何一个位置当时的状态。

模型永远看不到后续章节；文本尚未确定的身份、指代或原因保留为疑点，不会补全。工具独立于 Flutter App，App 只读取最终的 `story_model.json`。

## 入门教程

下面所有操作都通过一个文件完成：[`run_story_model.py`](run_story_model.py)。改文件顶部的设置、保存、运行，不需要敲任何命令行参数。每次运行时，文件会先打印对应的 `story-model` 命令，所以[命令参考](#commands)里的说明同样适用。

<a id="setup"></a>

### 0. 一次性准备

**1. 安装**（需要 Python 3.11 或更新版本）。在 Terminal 里，从仓库根目录执行：

```bash
cd /Users/frankhao76/MineApps/vscode/loremark/Loremark
python3 -m venv tools/story_model_lab/.venv
tools/story_model_lab/.venv/bin/python -m pip install -e './tools/story_model_lab[dev]'
```

`requirements.lock.txt` 记录已测试的精确依赖版本（macOS、Python 3.14.6）；要复现，先运行 `tools/story_model_lab/.venv/bin/python -m pip install -r tools/story_model_lab/requirements.lock.txt`，再执行上面的可编辑安装。

**2. 保存一次 API key。** 把 `tools/story_model_lab/.env.example` 复制为 `tools/story_model_lab/.env`（已被 git 忽略），把 key 粘贴到等号后面：DeepSeek 填 `DEEPSEEK_API_KEY=`，GPT 填 `OPENAI_API_KEY=`。之后新开 Terminal 也会自动读取。列出章节、查看模型和 dry run 都不需要 key。

**3. 在 VS Code 里选解释器：** 按 `Cmd+Shift+P` → **Python: Select Interpreter** → 选 `tools/story_model_lab/.venv/bin/python`。

**怎么运行：** 打开 `run_story_model.py`，点右上角的 **Run Python File**（▶ 按钮）；或者在 Terminal 里执行：

```bash
tools/story_model_lab/.venv/bin/python tools/story_model_lab/run_story_model.py
```

在哪个目录运行都可以；设置里的相对路径都以仓库根目录为准。

**你会用到的设置：**

| 设置 | 填什么 |
| --- | --- |
| `COMMAND` | 要做什么：`Command.CHAPTERS`（列出各节）、`Command.UPDATE`（加入一节）、`Command.SHOW`（查看模型）、`Command.COMMIT` / `Command.VALIDATE`（运行失败后用） |
| `EPUB` | 书的文件，例如 `"sample_epub/86v1_chapters.epub"` |
| `STORE` | 存这本书模型的文件夹，例如 `"tools/story_model_lab/stores/86v1"`；文件夹不存在时，第一次 update 会创建它 |
| `CHAPTER` / `SECTION` | 要加入哪一节。都为 `None` 表示下一节；只有新 store 需要指定，作为起点 |
| `MODEL`、`EFFORT` | `Model.DEEPSEEK_FLASH` 或 `Model.GPT_6_1_TERRA`；推理强度例如 `Effort.HIGH`，`None` 表示用模型默认值 |
| `DRY_RUN` | `True` = 只写出将要发送的内容，不调用 API，store 不变 |
| `CHECK_QUOTES` | `False` = 引用和所标段落对不上时只算警告，照常提交（见[关闭引用校验](#quote-check)） |
| `RUN` | 某次运行的文件夹，给 `Command.COMMIT` / `Command.VALIDATE` 用 |
| `REVISION`、`SHOW_JSON` | 给 `Command.SHOW` 用：查看更早的修订（`None` = 最新）；`True` = 输出完整 JSON 而不是 Markdown |

<a id="new-book"></a>

### A. 新的一本书

**第一步：列出各节，确认 EPUB 能读取。**

```python
COMMAND = Command.CHAPTERS
EPUB = "sample_epub/86v1_chapters.epub"
```

运行。每一行是阅读顺序中的一节：ID（`section-004`）、章节号、段落数和标题。`CHAPTER = 1` 指的是标题为 "Chapter 1" 的那一节（样本中是 `section-004`），不是第一行。

**第二步：先预览第一节，不调用 API。** 选一个新的 store 文件夹，以及模型从哪一节开始：

```python
COMMAND = Command.UPDATE
STORE = "tools/story_model_lab/stores/my-book"
CHAPTER = 1
DRY_RUN = True
```

输出最后会显示 `Context: new store + section-004` 和 `no store created`。打印出的 `Output:` 文件夹里有 `chapter.txt`（将要发送的原文）和 `request.json`。

起点之前的节（扉页、序章等）会记为未覆盖，以后不能补。如果序章重要，就设 `SECTION = "section-003"`、`CHAPTER = None`，从序章开始。

**第三步：真正建立 store。** 只改一项：

```python
DRY_RUN = False
```

这一步会调用 API，可能需要几分钟。看到 `Status: committed` 和 `created at revision 1` 就表示 store 已建立。如果失败了，见 [C](#run-fails)。

**第四步：继续加入后面的节。** 只改一项：

```python
CHAPTER = None
```

之后每运行一次，就按阅读顺序加入下一节（间章也算一节）。每一节运行一次即可，其他设置不用再改。

<a id="continue-store"></a>

### B. 继续已有的 store

App 读取的演示 store 是 `tools/story_model_lab/stores/86v1`。

**查看目前覆盖到哪里：**

```python
COMMAND = Command.SHOW
STORE = "tools/story_model_lab/stores/86v1"
REVISION = None
```

开头会列出已处理的节。`REVISION = 1` 显示处理完第一节时的模型。

**加入下一节。** 可以先用 `DRY_RUN = True` 预览，然后：

```python
COMMAND = Command.UPDATE
STORE = "tools/story_model_lab/stores/86v1"
CHAPTER = None
SECTION = None
DRY_RUN = False
```

`Status: committed` 之后，`stores/86v1/story_model.json` 就包含到这一节为止的知识，历史快照在 `revisions/`。间章也是一节，所以修订号统计的是已处理的节，**不是小说章节号**。

**导出可读的 Markdown：** 设 `COMMAND = Command.SHOW`，然后在 Terminal 里执行：

```bash
tools/story_model_lab/.venv/bin/python tools/story_model_lab/run_story_model.py > story_model_latest.md
```

<a id="run-fails"></a>

### C. 运行失败时

运行失败不会改动 store。打开打印出的 `Output:` 文件夹中的 `review.md`，开头列出了所有问题。

- **只是证据位置错了**（`quote_not_found`：段落号差一，或者引号用错）：可以手工修正，不用再调用 API。在这个运行文件夹里写 `manual_corrections.json`（格式见[人工修正后提交](#manual-corrections)），然后：

  ```python
  COMMAND = Command.COMMIT
  RUN = "tools/story_model_lab/runs/<运行文件夹>"
  ```

  用同一个 `RUN` 设 `Command.VALIDATE`，可以离线复查这次运行，但不提交。

  如果不想逐条修，也可以设 `CHECK_QUOTES = False` 后重新运行 update（见[关闭引用校验](#quote-check)）。
- **其他问题**（事实错误、API 错误、`incomplete`）：重新运行同一次 update。

### 结果与常见问题

| 状态或问题 | 处理方式 |
| --- | --- |
| `committed` | 更新成功；查看 store 里的 `story_model.json` |
| `already_processed` | 这一节已在 store 中，没有发送请求；把 `CHAPTER`、`SECTION` 都设为 `None` 即可选下一节 |
| `validation_failed` / `schema_invalid` | store 未改变；见 [C](#run-fails) |
| 其他 API 错误或 `incomplete` | 查看运行文件夹里的 `failure.json`，然后重新运行；不要手改 store 绕过校验 |
| `A new store needs its starting section` | store 的第一次 update 需要设 `CHAPTER` 或 `SECTION` |
| 提示会跳过某一节 | 把 `CHAPTER`、`SECTION` 都设为 `None`，或者改成报错中提到的那一节 |
| `... is not set`（缺 key） | 把 key 填进 `tools/story_model_lab/.env` |
| `loremark_story_lab is not installed for this Python` | 用 `tools/story_model_lab/.venv/bin/python` 运行，或在 VS Code 里选这个解释器 |
| 看本次新增了什么 | 打开打印出的 `Output:` 文件夹中的 `diff.md` |

真实请求成功不等于事实正确；`review.md` 和 `diff.md` 会列出需要人工检查的地方。

### 改用 GPT

在 `.env` 里填 `OPENAI_API_KEY`，再设 `MODEL = Model.GPT_6_1_TERRA` 即可，provider 由模型决定。`gpt-6.1-terra` 支持所有 `Effort` 值。中途换模型不需要重建 store。

### 改用命令行

每个设置都对应 `story-model` 命令的一个参数，文件运行的就是这个命令：它打印的 `$ story-model ...` 那一行可以直接粘贴到 Terminal 里。注意 `story-model` 只读取已 export 的环境变量，不读 `.env`：

```zsh
source tools/story_model_lab/.venv/bin/activate
read -rs 'DEEPSEEK_API_KEY?粘贴 DeepSeek API key，然后按回车（输入不显示）：'
export DEEPSEEK_API_KEY
export DEEPSEEK_MODEL=deepseek-flash
story-model update --store tools/story_model_lab/stores/86v1 \
  --epub sample_epub/86v1_chapters.epub --provider deepseek --dry-run
```

所有命令和参数见[命令参考](#commands)。

<a id="commands"></a>

## 命令参考

所有命令从仓库根目录执行。`python -m loremark_story_lab ...` 与 `story-model ...` 等效。

| 命令 | 是否调用模型 | 用途 |
| --- | --- | --- |
| `chapters --epub E` | 否 | 按阅读顺序列出各节：ID、章节号、段落/字符/图片数、资源路径、标题 |
| `update --store S --epub E [--chapter N \| --section ID]` | 是 | 加入下一节（store 不存在时从所选节建立） |
| `show --store S [--revision N] [--json]` | 否 | 以 Markdown 或完整 JSON 显示某个已提交修订 |
| `commit --run R --epub E` | 否 | 人工修正证据后提交某次更新运行 |
| `validate --run R` | 否 | 离线复查已保存的更新运行，不改 store |

### 选择节和章节边界

- `--chapter N` 依据目录标题中的 Chapter N（阿拉伯或罗马数字），不是第 N 个 XHTML。样本第一章是第 4 个 spine 文档。无法识别或多个标题匹配时，用 `--section`。
- `section-001` 等 ID 按阅读顺序分配。目录未引用的 spine 文档单独列出并标注，不会默默拼接进上一章。
- 不传 `--chapter` / `--section` 时，`update` 选 store 的下一节；新 store 必须指定其中一个。
- 提取前验证章节边界。某 XHTML 中的任一目录锚点缺失、重复、位于 head 或其他不提取的节点，或不同章节指向同一起点，该文档的所有节都标为不可可靠提取，`update` 在联网前以退出码 2 停止，`chapters` 仍列出问题；其他文档不受影响。
- 相同目标与标题的完全重复目录链接只保留一项，并显示警告。

### `update` 参数

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| `--provider` | `openai` | 选择 `openai` 或 `deepseek` 及其环境变量 |
| `--model` | 对应 provider 的模型环境变量 | 不内置模型；真实运行未配置模型会退出 2 |
| `--prompt-file` | 内置 `update_story_v2.txt` | 替换 system prompt |
| `--max-output-tokens` | 不发送 | 可选输出上限；未指定时仍受模型自身上限限制 |
| `--reasoning-effort` | 不发送 | 原样传递为 `reasoning.effort`；允许值取决于模型 |
| `--timeout` | 无 | 每次 HTTP 尝试的超时秒数；未指定时无限等待 |
| `--out` | `tools/story_model_lab/runs/<UTC时间>-<随机ID>` | 运行目录，必须不存在或为空 |
| `--dry-run` | 关闭 | 保存输入、prompt、schema 和请求；不要求 key，不发送请求，store 不变（或不创建） |
| `--no-quote-check` | 关闭 | 引用和所标段落对不上时只算警告，照常提交（见[关闭引用校验](#quote-check)） |

SDK 对网络错误、429 和 5xx 最多重试两次。没有额外业务重试，不会自动换模型、缩短文本、增加其他节或再找模型修复结果。设置 timeout 后，超时请求可能被重试，也可能仍被 provider 计费。

即使不传 `--max-output-tokens`，模型仍有输出上限。返回 `incomplete` 时退出 3，不把部分 JSON 当作成功结果。

### 退出码

| 退出码 | 含义 |
| --- | --- |
| 0 | 成功、dry-run 或 already_processed |
| 2 | 输入或配置错误，例如 EPUB、选择、store、缺 key/model、输出目录非空 |
| 3 | API 错误、拒绝、不完整或空响应 |
| 4 | JSON/schema、实体引用、原文证据或历史校验失败 |
| 5 | 本次更新读取后 store 已被其他更新改变或创建（stale_base）；未提交，不自动重试模型 |

## 模型服务配置

变量名称见 `.env.example`。

| Provider | API key | 模型 | Base URL 环境变量及默认值 |
| --- | --- | --- | --- |
| `openai` | `OPENAI_API_KEY` | `OPENAI_MODEL` | `OPENAI_BASE_URL`：`https://api.openai.com/v1` |
| `deepseek` | `DEEPSEEK_API_KEY` | `DEEPSEEK_MODEL` | `DEEPSEEK_BASE_URL`：`https://api.deepseek.com` |

两者都通过官方 `openai` Python SDK 的 `responses.parse` 调用，输出类型为 `StoryDelta`（严格 JSON Schema）。system 指令与 user 数据分开，不启用 tools、搜索、会话状态或 `previous_response_id`，不发送 temperature/seed；只有显式指定时才发送 reasoning effort。

- **OpenAI**：发送 `store: false` 和 `truncation: "disabled"`，关闭供后续 API 检索的响应存储，并在输入过长时失败而非截断。`store: false` 不等于零数据保留。
- **DeepSeek**：依据 [Responses API 文档](https://api-docs.deepseek.com/guides/responses_api)，支持 `text.format`，忽略 store/truncation，因此工具不向它发送这两个参数。该文档所述行为是不存储响应、过长输入返回 400；写文档时列出的模型包括 `deepseek-flash` 和 `deepseek-v4-pro`。使用独立 key/base URL，不向其转发 `OPENAI_ORG_ID` / `OPENAI_PROJECT_ID`。
- **推理强度**：默认不指定。[DeepSeek thinking mode 文档](https://api-docs.deepseek.com/guides/thinking_mode)列出 low/high/max，默认 high；minimal/low 映射到 low，medium/high/xhigh 映射到 high，none 关闭推理。工具自身不做这些转换，只原样发送参数。OpenAI 允许值取决于所用模型。

不支持参数或 Structured Outputs 时，保留错误并退出 3，不自动回退到其他模型或格式。即使 provider 未严格执行 schema，本地校验仍会检查输出结构。

## 节顺序

- 同一本书由 EPUB SHA-256 判定，不只比较书名。
- store 的第一次 `update` 可以从任意节开始；之前的节记录在 `coverage.omitted_prefix_section_ids`，模型**不**描述从全书开头开始的状态。
- 之后每次只能加入阅读顺序的下一节，即 `story-model chapters` 中紧跟最后已处理节的那一节，而不是"章节号 + 1"。第三章和第四章之间的间章必须先处理。
- 下一节不可提取时退出 2，不自动跳过非主章节。
- 相同节、相同文本再次请求返回 already_processed，退出 0，不联网也不改 store。
- 错书、已处理节哈希变化、倒序或跳节都在联网前拒绝；本版不支持 rebase、重跑替换或历史编辑。

## 模型返回的增量

update 的 system prompt 是 `prompts/update_story_v2.txt`；user 消息包含两块数据：`PRIOR_STORY_MODEL`（所有实体、事实与证据、状态转换和当前索引，JSON 格式；省略运行元数据、文件路径和书名）以及 `NEW_SECTION`（带段落 ID 的新节正文）。store 的第一节时，`PRIOR_STORY_MODEL` 是空的 revision 0。不发送旧章完整正文或后续章，不自动摘要或裁剪。

严格输出 `StoryDelta`：

- `new_entities`：`{local_id, kind}`，如 new_entity_001；每个新实体必须有名称。
- `new_records`：names、aliases、attributes、relationships、events、uncertainties、identity_links 七组，记录格式 `{local_id, payload, evidence}`。
- `transitions`：`{target_record_id, action, replacement_local_id, resolution, reason, evidence}`。supersede 是替代旧记录，retract 是撤回被推翻的主张，resolve 是解答疑点。第一节时总为空。

程序校验 local ID 格式；每个实体引用必须是已有实体或本次增量的新实体（模型编造的稳定 ID 会被拒绝，不会被绑定到新实体上），且类别正确；新节证据和逐字引用；以及各操作是否合法。转换只能针对旧版本有效记录，同一目标最多一次。supersede 保持相同主体/类型；属性还需相同 label，关系还需同向端点、label 和时间上下文。倒叙不替代当前关系。事件/疑点替换需要重点人工审阅；resolve 只能针对疑点。

正式 ID 从已有最大编号之后按固定顺序分配，映射保存在 id_map.json。相同 base/delta 得到相同知识和 ID。旧实体、记录、转换和已处理节必须是新版本中未修改的前缀。新章没提到某条事实不等于撤回它；空 delta 合法，但会提示检查遗漏。

## 模型结构（`story_model.json`）

store 中的 `story_model.json` 的 `schema_version` 为 `2.0`，`scope` 为 `cumulative`：

| 字段 | 含义 |
| --- | --- |
| `book` | 书名与 EPUB SHA-256 |
| `revision` | 修订号、ID、时间、来源运行、父快照路径和哈希（revision 1 为 `null`） |
| `processed_sections` | 已处理节、顺序、输入路径和哈希 |
| `coverage` | 起点和未处理的前置内容 |
| `entities` | 稳定实体 ID、类别和首次引入修订 |
| `records` | 七类知识记录，旧记录不删除或修改 |
| `transitions` | 所有替代、撤回、解答及理由和证据 |
| `current` | 程序计算的有效记录、已解答疑点、明确身份组 |
| `provenance` | `manual_corrections`：提交前人工修正过的每处证据位置 |

显示名来自所查看修订的有效名称，较新的优先；多个有效名称会显示冲突。同一身份揭示保留原始 ID 和记录，只将同类实体的 explicit link 合并为展示组，最早实体作为 canonical ID。组内矛盾属性会提示，不自动解决。逐字段说明见 [Story Model：文件结构与标签说明](STORY_MODEL_FORMAT.zh-CN.md)。

## Store 文件与提交

```text
tools/story_model_lab/stores/<name>/
  story_model.json                 最新模型，唯一提交入口
  .lock                            提交时使用的进程锁
  revisions/000001-<id>.json       完整、不可变的历史快照
  inputs/<section>-<hash>.json     各节规范化正文
  provenance/<update-run-id>/      增量、ID 映射、commit 信息和 manifest
```

读取 store 时先验证：latest 与快照一致；输入哈希一致；每个修订都有自己的 provenance manifest，且所有 manifest 哈希一致；父链完整回到 revision 1；模型本身通过完整校验（`quotes_checked` 为 `false` 的节，引用对不上只算警告）。

成功 update 自动提交：保存输入、来源和快照，在锁内重新检查 base 哈希（新 store 则检查文件仍不存在）后，以 fsync + os.replace 原子替换最新文件。API 请求期间不持锁。别人已更新时返回 stale_base，不覆盖。replace 前失败保留旧版本（退出 2，commit_failed）；遗留但不在父链上的文件不算历史。replace 后报告失败仍算已提交，run.json 会明确记录。

### 与组员共享模型

演示 store 的 [`story_model.json`](stores/86v1/story_model.json) 和 [`revisions/`](stores/86v1/revisions/) 已纳入 Git；App 直接打包 `stores/86v1/story_model.json`。每次要共享新的更新结果，都需要提交这些改动。不要手动编辑模型和快照，程序会检查它们的一致性与哈希。

**Git 中的文件并不是可直接运行的完整 store。** `show`、`update` 和 store 校验还需要该 store 的本地 `inputs/`、`provenance/`；更新还需要同一份 EPUB。这些数据、其他 store、锁文件和运行产物仍被忽略。新克隆的仓库可以直接查看共享 JSON；要用 CLI 继续这个 store，需要向运行者获取完整的 store（以及同一份 EPUB），或者用自己的第一次 `update` 建一个新 store。完整 store 不依赖原 runs 目录。

<a id="manual-corrections"></a>

### 人工修正后提交

当增量仅因证据位置或逐字引用出错而未通过校验时，可以人工确认原文并记录修正，再离线提交，不用重新调用 API：

```bash
# <run>/manual_corrections.json 为修正数组，每项包含：
# {"path": "new_records.names[6].evidence[0].paragraph_id", "from": "p0094", "to": "p0093",
#  "reason": "...", "corrected_by": "...", "corrected_at": "..."}
story-model commit --run tools/story_model_lab/runs/<update-run-id> \
  --epub sample_epub/86v1_chapters.epub
```

- 只允许改 evidence 中的 paragraph_id 或 quote，不允许改事实和 ID；`from` 必须与模型原始值一致。
- store 必须仍处于该 run 的 base 修订（对原本要创建 store 的 run：store 必须仍不存在），否则退出 5；这一节仍须是下一节。修正后重新完整校验，失败退出 4 且不提交。
- 原始 delta.candidate.json 与 validation.json 保留，新增 delta.corrected.json、validation.corrected.json。store provenance 保存原增量、修正、修正后增量和原校验；模型的 `provenance.manual_corrections` 记录每项修正，show 和 review 会明确标注不是原样输出。

<a id="quote-check"></a>

### 关闭引用校验

引用校验默认开启。可以在 `run_story_model.py` 里设 `CHECK_QUOTES = False`，或在命令行给 `update` 加 `--no-quote-check` 来关闭。仓库里的 `run_story_model.py` 目前设的是 `False`。

- **只影响 `quote_not_found`：** 也就是段落号标错，或引用文字和原文不一致。段落不存在、引用为空或超长、引用了其他节等其他校验仍会失败。
- **问题仍会显示：** 对不上的引用会以警告形式写入 `validation.json` 和 `review.md`，但不阻止提交，也不会被修正。
- **由 store 记住：** 这一节的 `processed_sections[].quotes_checked` 记为 `false`，`run.json` 也会记录。`show` 和 `review.md` 会标注；后续的 `show`、`update`、`validate`、`commit` 不用再传这个开关。
- **重新开启只影响之后的节：** 已提交的节继续被接受，新的节恢复严格校验。
- **对已失败的运行不起作用：** 开关只在 `update` 时生效，已经失败的运行要重新跑 update，或者用[人工修正](#manual-corrections)。

关闭后，模型里可能留下错误的引用，App 也会原样显示。

## 更新运行的产物

| 文件 | 内容 |
| --- | --- |
| `chapter.json`、`chapter.txt` | 规范化的本节输入，以及 `[p0001] 正文` 格式的同一文本 |
| `prompt.txt`、`schema.json`、`request.json` | 实际发送的 system prompt、JSON Schema 和请求（不含 key） |
| `context.json` | 实际发送的 prior/new 输入 |
| `base_story_model.json` | 更新前的最新模型，逐字节副本（新 store 为 revision 0） |
| `base_inputs/` | 旧版本各节输入，用于离线复查 |
| `run.json` | ID、时间、哈希、版本、token usage、状态、校验摘要 |
| `response.json` | 收到的 API 原始响应 |
| `delta.candidate.json` | 模型原始增量，失败也保留 |
| `validation.json` | 增量、合并结果、历史保护和证据检查 |
| `delta.json` / `id_map.json` | 合格增量和正式 ID 映射 |
| `story_model.after.json` | 合并候选，不代表已提交 |
| `diff.md` | 新增、替代、撤回、疑点解答 |
| `review.md` | 提交状态、变化、证据和人工审阅提示 |
| `failure.json` | 未提交原因（失败时） |

run.json 记录 base_revision（新建 store 时为 `null`）、candidate/committed revision、commit_status（not_attempted/committed/stale_base/failed）、report_status 和 API/校验结果。dry-run 只写到 run.json 为止，不产生 delta 或 after。`validate --run` 重新检查 base、增量和合并结果，写入 validation.recheck.json，不应用增量，也不改 store。

## 如何判断结果

自动校验检查结构而不是真实性：schema（类型、枚举、禁止额外字段）、ID 与引用、每条记录都有证据且 quote 是对应段落的**精确**连续子串（不做模糊匹配，最长 300 字符；`[start, end)` 位置由程序按 Unicode code point 计算；对不上的检查可以[关闭](#quote-check)）、每节内事件按 1、2、3… 叙述顺序，以及历史约束。空结果允许，但会提示。

**引用匹配仅证明这句话存在于该段，不证明它支持对应结论。** 通过校验不等于事实正确；用 `review.md` 和 `diff.md` 对照原文检查，结构化人工评审可用 `evaluation/rubric.md` 和 `evaluation/review_template.json`。

`assertion` 区分直接叙述 explicit、角色或书内来源的说法 reported（可能是假的）、推断 inferred；`temporal_context` 区分当前、过去、未来、假设和未知。不使用置信度百分比。

## 测试

```bash
python -m pytest tools/story_model_lab/tests -m 'not live'
python -m ruff check tools/story_model_lab
python -m ruff format --check tools/story_model_lab
```

离线测试不需要 key，并阻止网络访问。覆盖 EPUB nav/NCX、同文件多章节、损坏锚点、特殊字符、错误路径，以及通过 mock HTTP 驱动真实 SDK 的请求内容、成功、拒绝、incomplete、超时、401/429/404/500、无效 JSON、schema 不匹配、校验失败和 DeepSeek 路由。用户样本测试只在 `sample_epub/86v1_chapters.epub` 存在时运行。

store 测试使用 `tests/fixtures/story/` 中的合成故事，覆盖从空模型建 store、合并（ID 复用与新建、编造的 ID、前向引用、替代/撤回/解答、倒叙与身份揭示、无效增量、确定性）、store（原子提交、stale base、写入与替换故障注入、文件损坏、真实 `flock`），以及 update 端到端（各类失败、自动选下一节、重复与乱序、并发更新、人工修正、离线复查、历史修订的 show）。

显式启用的真实 smoke test 只验证接口接线，使用两节的合成书（先建 store，再更新一次）：

```bash
RUN_LIVE_OPENAI=1 python -m pytest tools/story_model_lab/tests -m live -s
RUN_LIVE_DEEPSEEK=1 python -m pytest tools/story_model_lab/tests -m live -s
```

还需配置相应 provider 的 key 和模型；否则跳过。

## 已知限制

- 一次处理一节，不自动分块；超长时报错，不静默裁剪。已有模型随每一节增长，并且总是完整发送。
- 只处理文字，统计但不读取图片，无 OCR。
- 同文件章节按目录锚点切分；跨多个 XHTML 的章节不自动拼接，额外文件单独列出并标注。
- Chapter 数字识别依赖目录标题（"Chapter 3"、"Chapter IV"）；其他命名使用 `--section`。
- 保留源 EPUB 的段落；样本中少数 `<p>` 包含两个场景（例如第一章 p0090），不再拆分。
- 不支持重跑或 rebase 之前的节；不包含阅读进度、数据库、Web 服务或向量检索。
