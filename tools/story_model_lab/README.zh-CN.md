# Story Model Lab

[![English](https://img.shields.io/badge/English-64748B?style=for-the-badge)](README.md) [![简体中文](https://img.shields.io/badge/%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-2563EB?style=for-the-badge)](README.zh-CN.md)

[![Story Model 文件结构与标签](https://img.shields.io/badge/Story_Model-%E6%96%87%E4%BB%B6%E7%BB%93%E6%9E%84%E4%B8%8E%E6%A0%87%E7%AD%BE-0F766E?style=for-the-badge)](STORY_MODEL_FORMAT.zh-CN.md)

**`story_model.json` 里面记录了什么？** 查看[文件结构与标签说明](STORY_MODEL_FORMAT.zh-CN.md)：人物、地点、组织、关系、事件、证据、疑点、历史修订，以及 `inferred`、flashback（对应 `past`）等依据和时间标签的完整含义。[English](STORY_MODEL_FORMAT.md)。

[查看结构关系图](STORY_MODEL_FORMAT.zh-CN.md#visual-overview)：直观看每个字段存什么，以及实体、记录、证据和历史修订之间如何通过 ID 关联。

[第一次运行](#a-第一次运行从第一章建立一个新模型) · [更新已有模型](#b-更新已有模型你现在应该用这一节) · [累计模式参考](#cumulative-mode)

## 入门教程：直接照着运行

所有命令都在 **macOS 的 zsh Terminal** 中执行，一块一块复制，看到成功后再执行下一步。

**已有模型就走「B：更新已有模型」。** 本仓库已经有 `stores/86v1`，截至编写本教程时已处理第一、二章；下一次应更新第三章。不用重新生成第一章，也不用再次 `init`。

### 0. 准备环境（A、B 都先看这里）

先进入仓库根目录；如果你把项目放在其他位置，修改第一行路径：

```bash
cd /Users/frankhao76/MineApps/vscode/loremark/Loremark
```

**仅首次安装时执行：**

```bash
python3 -m venv tools/story_model_lab/.venv
source tools/story_model_lab/.venv/bin/activate
python -m pip install -e './tools/story_model_lab[dev]'
```

**已经安装过，每次新开 Terminal 只需激活：**

```bash
source tools/story_model_lab/.venv/bin/activate
```

现有实验使用 DeepSeek，下面继续沿用。每次新开 Terminal、准备真实生成时设置 key 和模型：

```zsh
read -rs 'DEEPSEEK_API_KEY?粘贴 DeepSeek API key，然后按回车（输入不显示）：'
export DEEPSEEK_API_KEY
export DEEPSEEK_MODEL=deepseek-flash
```

`read` 会等待你粘贴 key，按回车后继续；不显示输入是正常的。不要把 key 填进 README 或 `.env.example`，程序也不会自动读取 `.env`。查看模型、导出 Markdown、初始化和 `--dry-run` 都不用 key。

### A. 第一次运行：从第一章建立一个新模型

这一节用于**从头开始一个新实验**。示例使用 `86v1-new`，不会覆盖目前已经处理到第二章的 `86v1`。

**第一步：列出章节，确认 EPUB 能读取。**

```bash
story-model chapters --epub sample_epub/86v1_chapters.epub
```

这里 `--chapter 1` 是小说第一章，程序会对应到 `section-004`，不是目录里的第一个条目。

**第二步：调用模型生成第一章。** 这一步会调用 API，可能等待几分钟。

```bash
story-model generate \
  --epub sample_epub/86v1_chapters.epub \
  --chapter 1 \
  --provider deepseek \
  --out tools/story_model_lab/runs/first-chapter1
```

看到 `Status: succeeded` 后再继续。第一章结果在 `tools/story_model_lab/runs/first-chapter1/story_model.json`；方便阅读的版本是同目录的 `review.md`。

如果显示 `validation_failed`、`schema_invalid` 或其他错误，**先停在这里**，查看打印出的运行目录中的 `review.md` / `failure.json`，不要直接执行初始化。API 返回内容不代表已经通过校验。

**第三步：把第一章结果变成可以持续更新的累计模型。** 这一步不调用 API。

```bash
story-model init \
  --from-run tools/story_model_lab/runs/first-chapter1 \
  --store tools/story_model_lab/stores/86v1-new
```

看到 `Status: initialized` 后，正式累计文件就是：

```text
tools/story_model_lab/stores/86v1-new/story_model.json
```

**第四步：分析第二章，接到第一章后面。**

```bash
story-model update \
  --store tools/story_model_lab/stores/86v1-new \
  --epub sample_epub/86v1_chapters.epub \
  --chapter 2 \
  --provider deepseek
```

看到 `Status: committed` 表示累计文件已更新，旧版本也已保存。之后每章都用 `update`，不再用 `generate` 或 `init`。

如果 `first-chapter1` 或 `86v1-new` 已经存在且非空，程序会拒绝覆盖。要继续原实验就使用 B 的更新方法；要重做独立实验，就选新的目录名，并同步修改该流程中的对应路径。不要为了重跑删除原模型。

### B. 更新已有模型：你现在应该用这一节

你现在的正式累计模型是 `tools/story_model_lab/stores/86v1/story_model.json`。**向命令传它所在的目录 `stores/86v1`，不是 JSON 文件，也不是 `ch2_story_model.md`。**

**第一步：确认已经处理到哪里。**

```bash
story-model show --store tools/story_model_lab/stores/86v1
```

看输出开头的「覆盖范围」和「已处理」；目前应列出 Chapter 1、Chapter 2。再用下列命令查看阅读顺序：

```bash
story-model chapters --epub sample_epub/86v1_chapters.epub
```

**第二步（可选）：先预览第三章请求，不调用 API。**

```bash
story-model update \
  --store tools/story_model_lab/stores/86v1 \
  --epub sample_epub/86v1_chapters.epub \
  --chapter 3 \
  --provider deepseek \
  --dry-run
```

看到 `Status: dry_run`，说明已保存待发送的输入，但累计模型还没有更新。

**第三步：真正更新第三章。** 先完成第 0 节的 key/模型设置。

```bash
story-model update \
  --store tools/story_model_lab/stores/86v1 \
  --epub sample_epub/86v1_chapters.epub \
  --chapter 3 \
  --provider deepseek
```

看到 `Status: committed` 后，仍然打开同一个 `stores/86v1/story_model.json`，其中已经包含第一至第三章的累计知识。历史快照在该目录的 `revisions/` 中。

**第四步：导出方便阅读的 Markdown。**

```bash
story-model show --store tools/story_model_lab/stores/86v1 > story_model_latest.md
```

在 IDE 打开根目录的 `story_model_latest.md`。以后每次成功更新后重新执行这一行，即可刷新阅读版；该命令会覆盖旧的阅读版，但不会修改正式 JSON。你之前的 `ch2_story_model.md` 是第二章时的导出，不会自动更新。

**第三章之后先处理间章，再处理第四章。** 这本 EPUB 的下一节是 `section-007`，不能直接跳到 Chapter 4：

```bash
# 确认第三章成功提交后，处理紧接着的间章。
story-model update \
  --store tools/story_model_lab/stores/86v1 \
  --epub sample_epub/86v1_chapters.epub \
  --section section-007 \
  --provider deepseek

# 间章成功提交后，再处理第四章。
story-model update \
  --store tools/story_model_lab/stores/86v1 \
  --epub sample_epub/86v1_chapters.epub \
  --chapter 4 \
  --provider deepseek
```

后续也遵循 `chapters` 列出的顺序，每次处理一节。想回看第一章时，运行：

```bash
story-model show --store tools/story_model_lab/stores/86v1 --revision 1
```

修订号是成功导入/更新的次数，**不一定等于小说章节号**，因为间章也会生成一个修订。

### 运行完看哪里？出错怎么办？

| 看到的提示 / 想查看的内容 | 怎么做 |
| --- | --- |
| `succeeded` | 单章生成成功，可以 `init` |
| `committed` | 累计更新成功，查看 `stores/你的目录/story_model.json` |
| `already_processed` | 这一节已经处理，不会再次请求；查看覆盖范围，选择下一节 |
| `validation_failed` / `schema_invalid` | 结果未通过校验，旧累计文件不变；打开终端打印的运行目录中的 `review.md` 和 `validation.json` |
| 其他 API 错误或 `incomplete` | 打开运行目录中的 `failure.json`；不要当作成功，也不要手改正式模型绕过检查 |
| 提示缺少 key / model | 在当前 Terminal 重新执行第 0 节的环境变量设置 |
| 提示会跳过某一节 | 按报错中的 `--section ...` 处理下一节 |
| `story-model: command not found` | 先确认在仓库根目录并激活 `.venv`；首次使用还需完成安装 |
| 看本次新增了什么 | 打开终端打印的 `Output:` 目录中的 `diff.md` |
| 看当前故事内容 | 查看根目录导出的 `story_model_latest.md` |

真实请求成功不等于事实完全正确；原文引用错误需要检查，不能把旧文件的修正记录直接套用到新运行。人工修正与离线提交属于进阶操作，见下方 [人工修正后提交](#manual-corrections)。

### 如果改用 OpenAI

先配置 OpenAI 的 key 和你账户可用、支持 Responses + Structured Outputs 的模型：

```zsh
read -rs 'OPENAI_API_KEY?粘贴 OpenAI API key，然后按回车（输入不显示）：'
export OPENAI_API_KEY
read 'OPENAI_MODEL?输入要使用的 OpenAI 模型 ID：'
export OPENAI_MODEL
```

然后将上面 `generate/update` 命令的 `--provider deepseek` 改成 `--provider openai`。`init/show` 命令不变，也不需要因为切换 provider 重建已有 store。OpenAI 的 key 和 DeepSeek 的 key 不能混用。

---

## 工具概览

Loremark 的本地命令行实验工具：解析 EPUB，选取一章，通过 Responses API 的 Structured Outputs 抽取人物、地点、组织、关系、事件和疑点，并保存检查结果所需的原文与产物。

提供两种模式：

- **单章模式 `generate`**：只依据当前章节。需要前文才能确认的信息保留为疑点。
- **累计模式 `init/update/show`**：从已有单章模型开始，每次加入下一节。LLM 读取旧模型和新正文，只返回增量；程序校验、分配稳定 ID 并保存新修订，保留历史事实和快照。详见[累计模式](#cumulative-mode)。

工具独立于 Flutter App，不修改 `lib/`、`pubspec.yaml` 或其他 App 代码。

## 安装与版本

需要 Python 3.11 或更新版本。安装命令见上方入门教程。`requirements.lock.txt` 记录已测试的精确依赖版本，测试环境为 macOS、Python 3.14.6。

要复现依赖版本，先激活虚拟环境，运行：

```bash
python -m pip install -r tools/story_model_lab/requirements.lock.txt
python -m pip install -e './tools/story_model_lab[dev]'
```

## 命令参考

所有命令从仓库根目录执行。`python -m loremark_story_lab ...` 与 `story-model ...` 等效。

| 命令 | 用途 | 是否调用模型 |
| --- | --- | --- |
| `chapters` | 列出阅读顺序、章节号、标题、路径、段落/字符/图片数量 | 否 |
| `extract` | 保存选中章节的规范化正文 | 否 |
| `generate` | 独立生成一个章节的模型 | 是，除非 `--dry-run` |
| `init` | 将已成功生成的单章模型导入累计 store | 否 |
| `update` | 使用旧累计模型和下一节正文更新 store | 是，除非 dry-run 或已经处理 |
| `show` | 展示最新累计状态或历史修订 | 否 |
| `validate` | 重新校验某个运行目录 | 否 |
| `commit` | 人工修正证据后提交已有更新运行 | 否 |

其他常用命令：

```bash
# 只提取第一章正文。
story-model extract --epub sample_epub/86v1_chapters.epub \
  --chapter 1 --out tools/story_model_lab/runs/chapter1-input

# 通过目录节 ID 选择序章。
story-model extract --epub sample_epub/86v1_chapters.epub \
  --section section-003 --out tools/story_model_lab/runs/prologue-input

# 检查一次已保存运行；将占位符换成实际目录名。
story-model validate --run tools/story_model_lab/runs/<run-id>
```

### 章节选择和边界

- `--chapter N` 与 `--section ID` 必须且只能选一个。
- `--chapter N` 依据目录标题中的 Chapter N（阿拉伯或罗马数字），不是第 N 个 XHTML。样本第一章是第 4 个 spine 文档。如果无法识别或多个标题匹配，使用 `--section`。
- `section-001` 等 ID 按阅读顺序分配。目录未引用的 spine 文档单独列出并标注，不会默默拼接进上一章。
- 提取前验证章节边界。某 XHTML 中的任一目录锚点缺失、重复、位于 head 或其他不提取的节点，或不同章节指向同一起点，该文档的所有章节均标为不可可靠提取。`extract/generate/update` 在联网前以退出码 2 停止，`chapters` 仍列出问题；其他文档不受影响。
- 相同目标与标题的完全重复目录链接只保留一项，并显示警告。

### 生成和更新参数

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| `--provider` | `openai` | 选择 `openai` 或 `deepseek` 及其环境变量 |
| `--model` | 对应 provider 的模型环境变量 | 不内置模型；真实运行未配置模型会退出 2 |
| `--prompt-file` | 内置 prompt | `generate` 用 `extract_story_v1.txt`；`update` 用 `update_story_v1.txt` |
| `--max-output-tokens` | 不发送 | 可选输出上限；未指定时仍受模型自身上限限制 |
| `--reasoning-effort` | 不发送 | 原样传递为 `reasoning.effort`；允许值取决于模型 |
| `--timeout` | 无 | 每次 HTTP 尝试的超时秒数；未指定时无限等待 |
| `--out` | `tools/story_model_lab/runs/<UTC时间>-<随机ID>` | 指定目录必须不存在或为空 |
| `--dry-run` | 关闭 | 保存输入与请求，不要求 key，不发送请求 |

SDK 对网络错误、429 和 5xx 最多重试两次。没有额外业务重试，不会自动换模型、缩短文本、增加其他章节或再找模型修复结果。设置 timeout 后，超时请求可能被重试，也可能仍被 provider 计费。

即使不传 `--max-output-tokens`，模型仍有输出上限。返回 `incomplete` 时退出 3，不保存部分 JSON 为成功结果。

### 退出码

| 退出码 | 含义 |
| --- | --- |
| 0 | 成功、dry-run 或 already_processed |
| 2 | 输入、配置或提交错误，例如错 EPUB、缺 key/model、目录非空 |
| 3 | API 错误、拒绝、不完整或空响应 |
| 4 | JSON/schema、实体引用或原文证据校验失败 |
| 5 | 更新时旧 store 已被其他更新改变（stale_base）；未提交，不自动重试模型 |

## 模型服务配置

只读取环境变量，不自动加载 `.env`；变量名称见 `.env.example`。

| Provider | API key | 模型 | Base URL 环境变量及默认值 |
| --- | --- | --- | --- |
| `openai` | `OPENAI_API_KEY` | `OPENAI_MODEL` | `OPENAI_BASE_URL`：`https://api.openai.com/v1` |
| `deepseek` | `DEEPSEEK_API_KEY` | `DEEPSEEK_MODEL` | `DEEPSEEK_BASE_URL`：`https://api.deepseek.com` |

两者都通过官方 `openai` Python SDK 的 Responses parse 调用：单章输出类型为 `ChapterStoryModel`，累计更新为 `StoryDelta`。system 指令与 user 数据分开，不启用 tools、搜索、会话状态或 `previous_response_id`，不发送 temperature/seed；只有显式指定时才发送 reasoning effort。

- **OpenAI**：发送 `store: false` 和 `truncation: "disabled"`，关闭供后续 API 检索的响应存储，并在输入过长时失败而非截断。`store: false` 不等于零数据保留。
- **DeepSeek**：原有接入依据 [Responses API 文档](https://api-docs.deepseek.com/guides/responses_api)，支持 `text.format`，忽略 store/truncation，因此工具不向它发送这两个参数。该文档所述行为是不存储响应、过长输入返回 400，写文档时列出的模型包括 `deepseek-flash` 和 `deepseek-v4-pro`。使用独立 key/base URL；不向其转发 `OPENAI_ORG_ID` / `OPENAI_PROJECT_ID`。
- **推理强度**：默认不指定。原有接入引用的 [DeepSeek thinking mode 文档](https://api-docs.deepseek.com/guides/thinking_mode)列出 low/high/max，默认 high；minimal/low 映射到 low，medium/high/xhigh 映射到 high，none 关闭推理。工具自身不做这些转换，只原样发送参数。OpenAI 允许值取决于所用模型。

不支持参数或 Structured Outputs 时，保留错误并退出 3，不自动回退到其他模型或格式。即使 provider 未严格执行 schema，本地校验仍会检查输出结构。

## 单章运行保存的文件

| 文件 | 内容 |
| --- | --- |
| `chapter.json` | 规范化章节、段落 ID、哈希和图片数量 |
| `chapter.txt` | 便于阅读的 `[p0001] 正文` 格式 |
| `prompt.txt` | 实际 system prompt |
| `schema.json` | 实际发送的输出 JSON Schema |
| `request.json` | provider、URL、模型、输入与参数，不含 key |
| `run.json` | 时间、ID、哈希、版本、token usage、状态、校验摘要 |
| `response.json` | 收到的 API 原始响应 |
| `candidate.json` | 能解析成 JSON 的候选输出，即使不合格也保留 |
| `validation.json` | 错误、警告、计数、引用匹配位置 |
| `story_model.json` | 校验通过后才生成的单章模型 |
| `review.md` | 人工审阅用报告，失败状态会标在开头 |
| `failure.json` | 失败原因，仅失败时生成 |

`dry-run` 只写前六个输入/配置文件；`extract` 只写 chapter.json/txt。单章 `validate` 会重写 validation/review 和 run 中的校验字段，并按结果创建或删除 story_model.json，不修改 request/response。

单章模型格式是 `{schema_version, scope: "single_chapter", source, model}`，model 内含人物、地点、组织、关系、事件和疑点；书籍/章节元信息由程序填写。

逐字段说明及累计 v2 格式见 [Story Model：文件结构与标签说明](STORY_MODEL_FORMAT.zh-CN.md)。

## 如何判断结果

自动校验包括：类型、枚举、禁止额外字段；ID 唯一与引用类别；证据属于当前章节且 quote 是对应段落的精确连续子串，最长 300 字符；事件叙述顺序。引用位置由程序计算，区间为 `[start, end)`，单位为 Unicode code point。证据逆序、空结果等会提示人工检查。

**引用匹配仅证明这句话存在，不证明它支持对应结论。** 评审标准见 `evaluation/rubric.md`，记录模板为 `evaluation/review_template.json`，已有样例为 `evaluation/sample_review.md`。

`assertion` 区分直接叙述 explicit、角色/书内来源的说法 reported、推断 inferred；`temporal_context` 区分当前、过去、未来、假设和未知。不使用未标定的“置信度百分比”。

## 测试

```bash
python -m pytest tools/story_model_lab/tests -m 'not live'
python -m ruff check tools/story_model_lab
python -m ruff format --check tools/story_model_lab
```

离线测试不需要 key，阻止网络访问。覆盖 EPUB nav/NCX、同文件多章节、损坏锚点、特殊字符、错误路径，以及通过 mock HTTP 驱动真实 SDK 的成功、拒绝、incomplete、超时、401/429/404/500、schema 和引用错误、provider 路由。用户 EPUB 测试只在样本存在时运行，检查章节映射和第一章文本哈希不变。

累计测试使用 `tests/fixtures/story/` 合成两章故事，覆盖迁移与来源、ID 复用、前向引用、修订/撤回/解答、倒叙与身份、确定性合并、锁、原子提交、并发冲突、故障注入、文件损坏、顺序、重复处理、离线复查和历史视图。

显式启用的真实 smoke test 只验证接口接线，使用短合成章节，包括 generate 与 StoryDelta update：

```bash
RUN_LIVE_OPENAI=1 python -m pytest tools/story_model_lab/tests -m live -s
RUN_LIVE_DEEPSEEK=1 python -m pytest tools/story_model_lab/tests -m live -s
```

还需配置相应 provider 的 key/model；否则跳过。

## 已知限制

- 一次处理一节，不自动分块；上下文超长时报错，不静默裁剪。
- 只处理文字，统计但不读取图片，无 OCR。
- 同文件章节按目录锚点切分；跨多个 XHTML 的章节不自动拼接，额外文件单独列出并标注。
- Chapter 数字识别依赖英文目录标题；其他命名使用 `--section`。
- 保留源 EPUB 的段落，样本中少数 `<p>` 包含两个场景，不再拆分。
- 单章 generate 的 ID 仅本次运行有效；累计模式才维护跨节关联。
- 不包含 App、阅读进度、数据库、Web 服务或向量检索。

<a id="cumulative-mode"></a>

## 累计模式

入门示例见上方 A/B。`update` 与 `generate` 共用模型参数，但默认 prompt 和输出 schema 不同。

### 初始化 init

- store 必须不存在或为空。
- 重新校验 v1 的 story_model/chapter/run 是否存在且一致，不盲信保存的 passed；candidate 存在时须与 model 一致；有人工修正时需原始 candidate.original.json。
- 从 run.json 的 EPUB 路径读取原书，也可用 `--epub` 覆盖失效路径；SHA-256 必须一致。重新提取初始章并比对文本，拒绝导入曾混入其他章节的数据。缺 EPUB 时停止，不猜章节顺序。
- 逐条迁移，不调用模型、不补充或修正事实。c/l/g 实体 ID 保留，名称/别名/属性/关系/事件/疑点获得 f000001 等记录 ID；旧关系/事件 ID 放入 legacy_id，证据加 section_id。
- 人工修正记录进入 provenance，原始来源复制到 `provenance/initial/`。
- 起始章节之前未处理的节记录在 `coverage.omitted_prefix_section_ids`；不能把从第一章开始的模型称为覆盖全书开头的完整状态。

### 节顺序

- 同一本书由 EPUB SHA-256 判定，不只比较书名。
- 每次只能加入阅读顺序的下一节。第三章和第四章之间的间章不能跳过。
- 下一节不可提取时退出 2，不自动跳过非主章节。
- 相同节、相同文本再次请求返回 already_processed，退出 0，不联网也不改 store。
- 错书、已处理节哈希变化、倒序或跳节都在联网前拒绝；本版不支持 rebase、重跑替换或历史编辑。

### 模型返回的增量

update 输入包含 `PRIOR_STORY_MODEL`（所有实体、事实与证据、状态转换和当前索引）以及 `NEW_SECTION`（带段落 ID 的新节正文）。省略旧运行元数据、绝对路径和书名；不发送旧章完整正文或后续章，不自动摘要/裁剪。

严格输出 `StoryDelta`：

- `new_entities`：`{local_id, kind}`，如 new_entity_001；每个新实体必须有名称。
- `new_records`：names、aliases、attributes、relationships、events、uncertainties、identity_links 七组，记录格式 `{local_id, payload, evidence}`。
- `transitions`：`{target_record_id, action, replacement_local_id, resolution, reason, evidence}`。supersede 是替代旧记录，retract 是撤回被推翻的主张，resolve 是解答疑点。

程序校验 local ID、引用类别、新章证据，以及操作合法性。转换只能针对旧版本有效记录，同一目标最多一次。supersede 保持相同主体/类型；属性还需相同 label，关系还需同向端点、label 和时间上下文。倒叙不替代当前关系。事件/疑点替换需要重点人工评审；resolve 只能针对疑点。

正式 ID 从已有最大计数后按固定顺序分配，映射保存在 id_map.json。相同 base/delta 得到相同知识和 ID。旧实体、记录、转换和处理节必须是新版本中未修改的前缀。新章没提到某条事实不等于撤回它；空 delta 合法，但会提示检查遗漏。

### v2 累计模型结构

正式文件的 `schema_version` 为 `2.0`，`scope` 为 `cumulative`：

| 字段 | 含义 |
| --- | --- |
| `book` | 书名与 EPUB SHA-256 |
| `revision` | 修订号、ID、时间、来源运行、父快照路径和哈希 |
| `processed_sections` | 已处理节、顺序、输入路径和哈希 |
| `coverage` | 起点和未处理的前置内容 |
| `entities` | 稳定实体 ID、类别和首次引入修订 |
| `records` | 七类知识记录，旧记录不删除或修改 |
| `transitions` | 所有替代、撤回、解答及理由和证据 |
| `current` | 程序计算的有效记录、已解答疑点、明确身份组 |
| `provenance` | 初始来源与人工修正记录 |

显示名来自所查看修订的有效名称，按较新的优先；多个有效名称会显示冲突。同一身份揭示保留原始 ID/记录，只将同类实体的 explicit link 合并为展示组，最早实体作为 canonical ID。组内矛盾属性会提示，不自动解决。

### Store 文件与提交

```text
tools/story_model_lab/stores/<name>/
  story_model.json                 最新累计模型，唯一提交入口
  .lock                            提交时使用的进程锁
  revisions/000001-<id>.json        完整、不可变的历史快照
  inputs/<section>-<hash>.json     各节规范化正文
  provenance/initial/             初始来源、迁移映射和 manifest
  provenance/<update-run-id>/     增量、ID 映射、commit 信息和 manifest
```

### 与组员共享模型

持续更新的正式文件是 [`stores/86v1/story_model.json`](stores/86v1/story_model.json)。成功更新会替换该文件，[`stores/86v1/revisions/`](stores/86v1/revisions/) 保存历史快照。这两部分已纳入 Git，方便组员查看；每次要共享新的更新结果，都需要再次提交。本地 commit 不会自动上传到远程仓库。

组员可以直接阅读 JSON，或查看根目录导出的 [`ch2_story_model.md`](../../ch2_story_model.md)。Markdown 是静态阅读版，不是 `update` 使用的文件。不要手动编辑正式模型和快照，程序会检查它们的一致性与哈希。

**Git 中的快照并不是可直接运行的完整 store。** `show`、`update` 和 store 校验还需要该 store 的本地 `inputs/`、`provenance/`；更新还需要同一份 EPUB。这些数据、其他 store、锁文件和运行产物仍被忽略。新克隆的仓库可以直接查看共享 JSON；要运行 CLI，应向生成者获取完整匹配的 store（更新还需原 EPUB），或重新生成第一章并初始化另一个新 store。不要对克隆得到的 `86v1` 目录再次 `init`。备份时应保留完整本地 store，而不只是已提交的 JSON；完整 store 不依赖原 runs 目录。

读取时验证 latest 与快照一致、输入和 provenance 哈希、完整父链，以及累计模型本身。

成功 update 自动提交：保存输入、来源和快照，在锁内重新检查 base 哈希后，以 fsync + os.replace 原子替换最新文件。API 请求期间不持锁。别人已更新时返回 stale_base，不覆盖。replace 前失败保留旧版本；遗留但不在父链上的文件不算历史。replace 后报告失败仍算已提交，run.json 会明确记录。

<a id="manual-corrections"></a>

### 人工修正后提交

当增量仅因证据位置/逐字引用出错而未通过校验时，可人工确认原文并记录修正，再离线提交，不用重新调用 API：

```bash
# <run>/manual_corrections.json 为修正数组，每项包含：
# {"path": "new_records.names[6].evidence[0].paragraph_id", "from": "p0094", "to": "p0093",
#  "reason": "...", "corrected_by": "...", "corrected_at": "..."}
story-model commit --run tools/story_model_lab/runs/<update-run-id> \
  --epub sample_epub/86v1_chapters.epub
```

只允许改 evidence 中的 paragraph_id 或 quote，不允许改事实和 ID；from 必须与原始值一致。store 必须仍处于该 run 的 base 修订，否则退出 5；新节仍须是下一节。修正后重新完整校验，失败退出 4 且不提交。

原始 delta.candidate.json 与 validation.json 保留，新增 delta.corrected.json、validation.corrected.json。store provenance 保存原增量、修正、修正后增量和原校验；模型的 `provenance.update_manual_corrections` 记录每项修正，show/review 明确标注不是原样输出。

### 更新运行的产物

除 chapter.json/txt、prompt/schema/request/response/run 外，还有：

| 文件 | 内容 |
| --- | --- |
| `base_story_model.json` | 更新前累计模型，逐字节副本 |
| `base_inputs/` | 旧版本章节输入，用于离线校验 |
| `context.json` | 实际 prior/new 输入 |
| `delta.candidate.json` | 模型原始增量，失败也保留 |
| `validation.json` | 增量、历史保护、合并结果和证据检查 |
| `delta.json` / `id_map.json` | 合格增量和正式 ID 映射 |
| `story_model.after.json` | 合并候选，不代表已提交 |
| `diff.md` | 新增、替代、撤回、疑点解答 |
| `review.md` | 提交状态、变化、证据和人工评审提示 |
| `failure.json` | 未提交原因（失败时） |

run.json 区分 base/candidate/committed revision、commit_status（not_attempted/committed/stale_base/failed）、report_status 和 API/校验结果。dry-run 不产生 delta 或 after。

更新运行的 validate 写入 validation.recheck.json，不再次应用增量，也不改变 store。校验通过只能说明结构、引用和历史约束一致，内容正确性及完整性仍需通过 review/diff 对照原文判断。
