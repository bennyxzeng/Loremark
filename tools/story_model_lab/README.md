# Story Model Lab

[![English](https://img.shields.io/badge/English-2563EB?style=for-the-badge)](README.md) [![简体中文](https://img.shields.io/badge/%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-64748B?style=for-the-badge)](README.zh-CN.md)

[![Story Model structure & labels](https://img.shields.io/badge/Story_Model-Structure_%26_Labels-0F766E?style=for-the-badge)](STORY_MODEL_FORMAT.md)

**What does `story_model.json` contain?** Read the [file structure and label guide](STORY_MODEL_FORMAT.md) for characters, places, organizations, relationships, events, evidence, open questions, revisions, and every assertion/time label, including `inferred` and flashbacks (`past`). [简体中文](STORY_MODEL_FORMAT.zh-CN.md).

[View the structure diagrams](STORY_MODEL_FORMAT.md#visual-overview): field contents and the ID links between entities, records, evidence, and revisions.

[First run](#a-first-run-build-a-new-model-from-chapter-1) · [Update an existing model](#b-update-an-existing-model) · [Cumulative reference](#cumulative-mode)

## Step-by-step guide

Run these commands in a **macOS zsh terminal**, one block at a time. Continue only after the previous step succeeds.

**If you already have a model, use B: Update an existing model.** At the time this guide was written, the local `stores/86v1` store contained Chapters 1 and 2. Its next update is Chapter 3. There is no need to generate Chapter 1 again or repeat `init`. Check your own store before continuing.

### 0. Prepare your terminal

Enter the repository root. Change this path if your checkout is elsewhere:

```bash
cd /Users/frankhao76/MineApps/vscode/loremark/Loremark
```

**Install once:**

```bash
python3 -m venv tools/story_model_lab/.venv
source tools/story_model_lab/.venv/bin/activate
python -m pip install -e './tools/story_model_lab[dev]'
```

**If already installed, activate the environment in each new terminal:**

```bash
source tools/story_model_lab/.venv/bin/activate
```

The existing experiments use DeepSeek. To continue with it, set the key and model in each new terminal before a live request:

```zsh
read -rs 'DEEPSEEK_API_KEY?Paste your DeepSeek API key and press Enter (input is hidden): '
export DEEPSEEK_API_KEY
export DEEPSEEK_MODEL=deepseek-flash
```

The `read` command waits for your key; paste it and press Enter. Hidden input is normal. Do not put the key in this README or `.env.example`; the tool does not automatically load `.env` files. Viewing, exporting Markdown, initializing a store, and `--dry-run` do not need a key.

### A. First run: build a new model from Chapter 1

Use this section to **start a fresh experiment**. These examples use `86v1-new`, leaving the existing `86v1` store untouched.

**Step 1: List the sections and check that the EPUB opens.**

```bash
story-model chapters --epub sample_epub/86v1_chapters.epub
```

`--chapter 1` selects the novel's first numbered chapter, which maps to `section-004` in this sample, not the first table-of-contents entry.

**Step 2: Generate the Chapter 1 model.** This calls the API and may take several minutes.

```bash
story-model generate \
  --epub sample_epub/86v1_chapters.epub \
  --chapter 1 \
  --provider deepseek \
  --out tools/story_model_lab/runs/first-chapter1
```

Continue only after `Status: succeeded`. The result is `tools/story_model_lab/runs/first-chapter1/story_model.json`; the readable report is `review.md` in the same directory.

If you see `validation_failed`, `schema_invalid`, or another error, **stop here** and inspect `review.md` / `failure.json` in the printed output directory. Do not initialize a store from a failed run. An API response is not necessarily a validated result.

**Step 3: Initialize a cumulative store from Chapter 1.** This runs offline.

```bash
story-model init \
  --from-run tools/story_model_lab/runs/first-chapter1 \
  --store tools/story_model_lab/stores/86v1-new
```

After `Status: initialized`, the authoritative cumulative file is:

```text
tools/story_model_lab/stores/86v1-new/story_model.json
```

**Step 4: Add Chapter 2 to the existing Chapter 1 knowledge.**

```bash
story-model update \
  --store tools/story_model_lab/stores/86v1-new \
  --epub sample_epub/86v1_chapters.epub \
  --chapter 2 \
  --provider deepseek
```

`Status: committed` means the cumulative file was updated and the previous revision was preserved. Use `update` for each subsequent section; do not repeat `generate` or `init`.

If `first-chapter1` or `86v1-new` already exists and is not empty, the command refuses to overwrite it. Use section B to continue that experiment, or choose new directory names and change every corresponding path in this workflow. Do not delete an existing model just to run another experiment.

### B. Update an existing model

The current local cumulative model is `tools/story_model_lab/stores/86v1/story_model.json`. **Pass its directory, `stores/86v1`, to `--store`, not the JSON file or `ch2_story_model.md`.**

**Step 1: Check which sections are already processed.**

```bash
story-model show --store tools/story_model_lab/stores/86v1
```

Look at the coverage and processed-section list at the beginning of the output. The current local example lists Chapters 1 and 2. Then inspect the reading order:

```bash
story-model chapters --epub sample_epub/86v1_chapters.epub
```

**Step 2 (optional): Preview the Chapter 3 request without calling the API.**

```bash
story-model update \
  --store tools/story_model_lab/stores/86v1 \
  --epub sample_epub/86v1_chapters.epub \
  --chapter 3 \
  --provider deepseek \
  --dry-run
```

`Status: dry_run` means the request files were saved; the cumulative store has not changed.

**Step 3: Run the real Chapter 3 update.** Configure the key and model in step 0 first.

```bash
story-model update \
  --store tools/story_model_lab/stores/86v1 \
  --epub sample_epub/86v1_chapters.epub \
  --chapter 3 \
  --provider deepseek
```

After `Status: committed`, open the same `stores/86v1/story_model.json`: it now includes cumulative knowledge from Chapters 1–3. Earlier snapshots are in the store's `revisions/` directory.

**Step 4: Export a readable Markdown version.**

```bash
story-model show --store tools/story_model_lab/stores/86v1 > story_model_latest.md
```

Open `story_model_latest.md` at the repository root. Run this export after each successful update to refresh it. It overwrites the previous Markdown export, not the authoritative JSON. The earlier `ch2_story_model.md` is a Chapter 2 export and does not refresh automatically.

**After Chapter 3, process the interlude before Chapter 4.** In this EPUB the next section is `section-007`:

```bash
# After Chapter 3 commits successfully, process the next interlude.
story-model update \
  --store tools/story_model_lab/stores/86v1 \
  --epub sample_epub/86v1_chapters.epub \
  --section section-007 \
  --provider deepseek

# After the interlude commits successfully, process Chapter 4.
story-model update \
  --store tools/story_model_lab/stores/86v1 \
  --epub sample_epub/86v1_chapters.epub \
  --chapter 4 \
  --provider deepseek
```

Continue in the order shown by `chapters`, one section at a time. To revisit the first revision:

```bash
story-model show --store tools/story_model_lab/stores/86v1 --revision 1
```

A revision number counts successful imports/updates; **it is not necessarily a novel chapter number**, because interludes also create revisions.

### Results and troubleshooting

| Status or question | What to do |
| --- | --- |
| `succeeded` | Single-chapter generation succeeded; you can run `init` |
| `committed` | Cumulative update succeeded; inspect `stores/<your-store>/story_model.json` |
| `already_processed` | This section was already processed; no request was sent. Check coverage and select the next section |
| `validation_failed` / `schema_invalid` | The previous cumulative file is unchanged. Inspect `review.md` and `validation.json` in the printed run directory |
| Other API errors or `incomplete` | Inspect `failure.json`; do not treat the run as successful or edit the store to bypass validation |
| Missing key or model | Repeat the environment setup in step 0 in this terminal |
| A section would be skipped | Process the next `--section ...` named in the error |
| `story-model: command not found` | Enter the repository root and activate `.venv`; on first use, install the package |
| What changed in this update? | Open `diff.md` in the directory printed as `Output:` |
| Where can I read the current story? | Open the exported `story_model_latest.md` at the repository root |

A successful request does not establish factual accuracy. Inspect evidence errors; do not copy corrections from an older run into a new one. Manual correction and offline submission are advanced operations described in [Committing a run after manual corrections](#committing-a-run-after-manual-corrections).

### Using OpenAI instead

Configure an OpenAI key and an available model that supports Responses and Structured Outputs:

```zsh
read -rs 'OPENAI_API_KEY?Paste your OpenAI API key and press Enter (input is hidden): '
export OPENAI_API_KEY
read 'OPENAI_MODEL?Enter the OpenAI model ID to use: '
export OPENAI_MODEL
```

Replace `--provider deepseek` with `--provider openai` in the `generate` / `update` commands above. `init` and `show` stay the same. Changing providers does not require rebuilding the store. OpenAI and DeepSeek keys are not interchangeable.

---

A terminal experiment for Loremark: parse an EPUB locally, pick **one** chapter, send only
that chapter to a model through the **Responses API with Structured Outputs**, and save the
characters, locations, organizations, relationships, events, and open questions it finds,
together with everything needed to check the result by hand.

The result describes only what that chapter says. It is not a whole-book model: identities,
references, or causes that need earlier chapters are kept as uncertainties, not filled in.

A second mode keeps a **cumulative** model: start from an existing single-chapter result,
then add the next section one at a time. The model receives the previous structured model
and the new section's text, and returns only a delta; code checks it, assigns stable IDs,
and commits a new revision. Earlier facts and revisions are kept, so every chapter can be
looked at again as it was. See [Cumulative mode](#cumulative-mode).

This tool is independent of the Flutter app. It does not touch `lib/`, `pubspec.yaml`, or
any app code.

## Install

Python 3.11 or newer. From the repository root:

```bash
python3 -m venv tools/story_model_lab/.venv
source tools/story_model_lab/.venv/bin/activate
python -m pip install -e './tools/story_model_lab[dev]'
```

`requirements.lock.txt` records the exact versions this was tested with (Python 3.14.6 on
macOS). To reproduce them: `python -m pip install -r tools/story_model_lab/requirements.lock.txt`
and then the editable install above.

## Commands

All commands run from the repository root. `python -m loremark_story_lab ...` works the same
as `story-model ...`.

```bash
# List every section in reading order: section ID, chapter number, paragraphs, characters,
# images, resource path, and title.
story-model chapters --epub sample_epub/86v1_chapters.epub

# Offline: write the exact Chapter 1 text that would be sent.
story-model extract --epub sample_epub/86v1_chapters.epub \
  --chapter 1 --out tools/story_model_lab/runs/chapter1-input

# Pick a prologue or interlude by its section ID (from `chapters`).
story-model extract --epub sample_epub/86v1_chapters.epub \
  --section section-003 --out tools/story_model_lab/runs/prologue-input

# No key, no request: write the prompt, schema, and request that would be sent.
story-model generate --epub sample_epub/86v1_chapters.epub --chapter 1 --dry-run

# Real call with OpenAI.
export OPENAI_API_KEY=...        # in your shell; never paste keys into files or chats
export OPENAI_MODEL=...          # a model that supports Responses + Structured Outputs
story-model generate --epub sample_epub/86v1_chapters.epub --chapter 1

# Real call with DeepSeek (its Responses-compatible endpoint).
export DEEPSEEK_API_KEY=...
export DEEPSEEK_MODEL=deepseek-flash
story-model generate --epub sample_epub/86v1_chapters.epub --chapter 1 --provider deepseek

# Re-check a saved run offline (no network).
story-model validate --run tools/story_model_lab/runs/<run-id>
```

### Selecting a chapter

- Exactly one of `--chapter N` or `--section ID` is required.
- `--chapter N` means the section whose **table-of-contents title** reads "Chapter N" (Arabic
  or Roman numerals), not the Nth XHTML file. In the sample, Chapter 1 is the 4th spine
  document (`EPUB/section-004.xhtml`). If no title or several titles match, the command stops
  and asks for `--section`.
- Section IDs are `section-001`, `section-002`, ... in reading order: TOC entries sorted by
  their position in the spine, plus any spine documents the TOC never points to (listed
  separately with a note, never merged silently).
- Chapter boundaries are checked before any text is extracted. When one TOC entry of an
  XHTML file cannot be located exactly (missing anchor, an ID used twice, an anchor inside
  `<head>` or another unextracted element, or two different titles starting at the same
  place), **every** section of that file is marked as unsupported and `extract`, `generate`,
  and `update` stop with exit code 2 before any request. `chapters` still lists them with the
  reason. Other files are not affected. An exact duplicate TOC link (same target and title)
  is listed once with a warning.

### `generate` options

| Option | Default | Meaning |
| --- | --- | --- |
| `--provider` | `openai` | `openai` or `deepseek`; selects which environment variables are read |
| `--model` | `$OPENAI_MODEL` / `$DEEPSEEK_MODEL` | Model name. No model is built in; a live call without one fails with exit code 2 |
| `--prompt-file` | built-in `extract_story_v1.txt` | Alternative system prompt |
| `--max-output-tokens` | not sent | Optional output cap. Without it, only the provider/model's own maximum applies |
| `--reasoning-effort` | not sent | Optional `reasoning.effort`. Values depend on the provider and model (see below) |
| `--timeout` | none | Optional seconds per HTTP attempt. Without it, the client waits for the response indefinitely |
| `--out` | `tools/story_model_lab/runs/<UTC time>-<random>` | Must not exist or must be empty |
| `--dry-run` | off | Write inputs, prompt, schema, request; no key needed, nothing sent |

The SDK retries network errors, 429, and 5xx at most twice (`max_retries=2`). There is no
other retry: the tool never switches models, shortens the text, adds other chapters, or asks
a second model to repair output. If you set `--timeout`, a timed-out attempt is retried and
may still be billed by the provider.

Even without `--max-output-tokens`, the model's own output maximum still exists; if the model
reaches it, the response is `incomplete` and the run fails with exit code 3 instead of
saving partial JSON.

### Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Success, or dry run |
| 2 | Input or configuration error (EPUB, selection, missing key/model, output dir) |
| 3 | API error, refusal, incomplete output, or empty output |
| 4 | Output is not valid JSON for the schema, or fails reference/quote/ID validation |
| 5 | `update` only: the store changed after this update read it (`stale_base`); nothing was committed and the model is not called again |

## Model providers

Configuration comes only from environment variables; no `.env` file is loaded.
`.env.example` lists the names.

| Provider | Key | Model | Base URL (default) |
| --- | --- | --- | --- |
| `openai` | `OPENAI_API_KEY` | `OPENAI_MODEL` | `OPENAI_BASE_URL` (`https://api.openai.com/v1`) |
| `deepseek` | `DEEPSEEK_API_KEY` | `DEEPSEEK_MODEL` | `DEEPSEEK_BASE_URL` (`https://api.deepseek.com`) |

Both use the official `openai` Python SDK and `client.responses.parse` with
`ChapterStoryModel` for `generate` or `StoryDelta` for `update`
(Responses API, strict JSON Schema), with the system prompt and the chapter as separate
`system` and `user` messages. No tools, web search, conversation state, or
`previous_response_id` are used; `temperature` and `seed` are not sent. Reasoning effort
is sent only when explicitly configured.

Provider differences:

- **OpenAI**: the request also sends `store: false` (the response is not kept for later
  retrieval through the API; this is not the same as zero data retention) and
  `truncation: "disabled"` (over-long input fails instead of being cut).
- **DeepSeek**: according to [DeepSeek's Responses API guide](https://api-docs.deepseek.com/guides/responses_api),
  `text.format` is supported, while `store` and `truncation` are ignored: responses are
  never stored and over-long input returns HTTP 400. The tool therefore does not send those
  two fields to DeepSeek. Model names listed there at the time of writing: `deepseek-flash`
  and `deepseek-v4-pro`. The DeepSeek key is only ever sent to the DeepSeek base URL, and
  `OPENAI_ORG_ID` / `OPENAI_PROJECT_ID` headers are not forwarded to it.

Reasoning effort: by default nothing is sent and the model's own default applies. Per
[DeepSeek's thinking-mode guide](https://api-docs.deepseek.com/guides/thinking_mode),
thinking is on by default at `high`, accepted levels are `low`, `high`, and `max`
(`minimal`/`low` map to `low`, `medium`/`high`/`xhigh` to `high`), and `none` turns
thinking off. For OpenAI, the accepted values depend on the model. The value is passed
through unchanged; an unsupported one returns an API error (exit code 3).

If the chosen model does not support Structured Outputs, the API error is saved and the run
exits with code 3; the tool does not fall back to another mode. Local validation runs either
way, so a provider that does not enforce the schema strictly is still caught.

## What a run saves

```text
<run-dir>/
  chapter.json      normalized input: paragraphs with IDs, hashes, image count
  chapter.txt       the same text as "[p0001] ..." lines
  prompt.txt        system prompt actually used
  schema.json       JSON Schema actually sent as text.format
  request.json      provider, base URL, model, full input messages, parameters (no key)
  run.json          IDs, timestamps, hashes, versions, usage, status, validation summary
  response.json     raw API response body, when one was received
  candidate.json    model output that parsed as JSON, kept even when invalid
  validation.json   every error and warning, counts, quote positions
  story_model.json  only when the output passed validation
  review.md         report for manual review (failures are shown at the top)
  failure.json      only when the run failed
```

`dry-run` writes only the first six files with status `dry_run`. `extract` writes only
`chapter.json` and `chapter.txt`. `validate` rewrites `validation.json`, `review.md`,
the validation fields of `run.json`, and creates or removes `story_model.json`; it never
changes `request.json` or `response.json`.

`story_model.json` is `{schema_version, scope: "single_chapter", source, model}`, where
`model` holds `characters`, `locations`, `organizations`, `relationships`, `events`, and
`uncertainties`. Book and chapter metadata come from the code, never from the model.

For field-by-field explanations and the cumulative v2 format, see [Story Model: file structure and labels](STORY_MODEL_FORMAT.md).

## Reading the results

Automatic validation checks structure, not truth:

- Schema: types, enums, no extra fields (Pydantic).
- IDs are unique, every reference exists and points to the right kind (a `location_id`
  must be a location; participants and speakers must be characters or organizations).
- Every record has evidence; each `paragraph_id` belongs to this chapter; each quote is an
  **exact** substring of that paragraph (no fuzzy matching, at most 300 characters). The
  `[start, end)` offsets in code points are computed locally for every occurrence.
- Events are listed in narrative order 1, 2, 3, ...; evidence that runs backwards is a
  warning for manual review, not an error.
- Empty results are allowed but flagged.

**A matched quote only proves the quote exists in that paragraph. It does not prove the
quote supports the claim.** Passing validation is not factual accuracy. Use
`evaluation/rubric.md` and `evaluation/review_template.json` for manual review; record
results like `evaluation/sample_review.md`.

`assertion` separates `explicit` narration, `reported` claims by a character or in-world
source (which may be false), and `inferred` statements. `temporal_context` separates the
present narrative from flashbacks, plans, and hypotheticals. There are no confidence
percentages.

## Tests

```bash
python -m pytest tools/story_model_lab/tests -m 'not live'
python -m ruff check tools/story_model_lab
python -m ruff format --check tools/story_model_lab
```

Offline tests need no key and block network access. They build small EPUBs on the fly
(nav, NCX fallback, several chapters in one file, missing/duplicate/misplaced anchors,
special characters, missing text, unsafe paths) and drive the real OpenAI SDK through a mock
HTTP transport (success, refusal, incomplete, timeout, 429/401/404/500, invalid JSON, schema
mismatch, failed validation, DeepSeek routing). The user sample test runs only if
`sample_epub/86v1_chapters.epub` exists; it also checks that the seven chapters map as before
and that Chapter 1's text hash is unchanged.

Cumulative mode is tested on a synthetic two-chapter story (`tests/fixtures/story/`):
migration (faithful import, refusals, provenance), merging (reused and new IDs, forward
references, supersede/retract/resolve, flashbacks, identity reveals, invalid deltas,
determinism), the store (atomic commits, stale bases, injected write and replace failures,
damaged files, a real `flock`), and `update` end to end (request contents, every failure
kind, repeated and out-of-order sections, concurrent updates, offline re-validation, `show`
of old revisions).

Live smoke tests send three-paragraph synthetic chapters (one `generate`, one `update`
with `StoryDelta`) and only check the wiring:

```bash
RUN_LIVE_OPENAI=1 python -m pytest tools/story_model_lab/tests -m live -s
RUN_LIVE_DEEPSEEK=1 python -m pytest tools/story_model_lab/tests -m live -s
```

They also need the provider's key and model variables, and are skipped otherwise.

## Known limits

- One chapter per request, no chunking. A chapter too long for the model fails; it is
  never truncated silently.
- Text only. Images are counted (`omitted_image_count`) but not read; no OCR.
- Chapters that start mid-document are cut at TOC anchors. A chapter spread across several
  XHTML files is not merged: extra files appear as their own sections with a note.
- Chapter numbers come from TOC titles ("Chapter 3", "Chapter IV"); other naming schemes
  need `--section`.
- The source EPUB's paragraphs are kept as they are. In the sample, a few `<p>` elements
  contain two scenes (for example p0090 of Chapter 1); the tool does not re-split them.
- In `generate`, IDs (`c001`, `e001`, ...) are local to one run. Only cumulative mode links
  entities across sections.
- No app integration, reading progress, database, web service, or vector search.

## Cumulative mode

```bash
# 1. Start a store from an existing Chapter 1 generate run (offline; Chapter 1 is not
#    generated again).
story-model init \
  --from-run tools/story_model_lab/runs/20261026T032410Z-2c6f50 \
  --store tools/story_model_lab/stores/86v1

# 2. Inspect exactly what would be sent for Chapter 2 (no key, no request, store unchanged).
story-model update --store tools/story_model_lab/stores/86v1 \
  --epub sample_epub/86v1_chapters.epub --chapter 2 --provider deepseek --dry-run

# 3. Real update: Chapter 1 model + Chapter 2 text -> cumulative model after Chapter 2.
story-model update --store tools/story_model_lab/stores/86v1 \
  --epub sample_epub/86v1_chapters.epub --chapter 2 --provider deepseek

# 4. Latest state as Markdown, an earlier revision, or the full v2 JSON.
story-model show --store tools/story_model_lab/stores/86v1
story-model show --store tools/story_model_lab/stores/86v1 --revision 1
story-model show --store tools/story_model_lab/stores/86v1 --json

# 5. Re-check an update run offline; never touches the store.
story-model validate --run tools/story_model_lab/runs/<update-run-id>
```

`update` takes the same model options as `generate` (`--provider`, `--model`,
`--prompt-file`, `--max-output-tokens`, `--timeout`, `--reasoning-effort`, `--out`,
`--dry-run`) and the same `--chapter N` / `--section ID` choice.

### `init`

- The store directory must not exist or must be empty.
- The v1 run is checked again, not trusted: `story_model.json`, `chapter.json`, and
  `run.json` must exist and agree; the model is re-validated against the chapter text;
  `candidate.json`, when present, must equal the model; a recorded manual correction needs
  its original output (`candidate.original.json`).
- The EPUB is read from `run.json` (`source.epub_path`), or from `--epub` when that path is
  gone; its SHA-256 must be the one the run used. The chapter is extracted again with the
  current extractor and must give exactly the saved text, so an input that mixed in another
  section is refused instead of migrated. Without the EPUB, `init` stops; section order is
  never guessed.
- Facts are imported one for one: entity IDs (`c001`, `l001`, `g001`) are kept, every name,
  alias, attribute, relationship, event, and uncertainty becomes a record `f000001`, ...
  (relationship/event IDs are kept as `legacy_id`), and evidence gains the section ID. No
  model is called, nothing is added, and known errors are not fixed, so later changes can be
  compared with what was really there. Manual corrections are listed in the model's
  `provenance` and the original files are copied to `provenance/initial/`.
- Sections before the starting chapter (front matter, a prologue) are listed in
  `coverage.omitted_prefix_section_ids`: the model does **not** describe the book from its
  beginning.

### Section order

- Same book means the same EPUB SHA-256, not the same title.
- After `init`, only the **next** section in reading order can be added: the one right after
  the last processed section in `story-model chapters`, not "chapter number + 1". An
  interlude between Chapter 3 and Chapter 4 must be processed before Chapter 4.
- Non-chapter entries are not skipped automatically. If the next section cannot be
  extracted, `update` stops with exit code 2 and says so; it is not jumped over.
- The same section with the same text again: `already_processed`, exit code 0, no request,
  store unchanged.
- A processed section whose text now hashes differently, a different EPUB, an earlier
  section, or one that would skip an unprocessed section: refused before any request. There
  is no rebase, re-run, or history editing in this version.

### What the model returns

`update` sends a system prompt (`prompts/update_story_v1.txt`) and one user message with two
data blocks: `PRIOR_STORY_MODEL` (every entity, record with payload and evidence, transition,
and the current index, as JSON; run metadata, file paths, and the book title are left out)
and `NEW_SECTION` (the paragraphs as `[p0001] ...` lines). Earlier sections' text and later
sections are not sent. Nothing is summarized or trimmed; if the request is too long or the
output is incomplete, the update fails.

The model answers with a `StoryDelta` (strict Structured Outputs):

- `new_entities`: `{local_id: new_entity_001, kind}`; each needs a name record in the delta.
- `new_records`: seven arrays (`names`, `aliases`, `attributes`, `relationships`, `events`,
  `uncertainties`, `identity_links`) of `{local_id: new_record_001, payload, evidence}`.
  Payloads refer to existing IDs or this delta's local entity IDs.
- `transitions`: `{target_record_id, action, replacement_local_id, resolution, reason,
  evidence}` with action `supersede` (a new record of the same kind and subject replaces
  the target), `retract` (the target is shown false), or `resolve` (an uncertainty is
  answered).

Code then checks the delta and the merged result:

- local IDs unique and well-formed; every reference resolves to an entity of the right kind;
- every new record and transition has evidence, all of it from the **new** section, with
  exact quotes (a quote from another section's `p0001` does not count);
- transitions target records that are active in the prior revision, at most one each;
  `supersede` keeps the same entity (and label, for attributes), the same direction and label
  (for relationships), and the same `temporal_context` (a flashback is added, it does not
  replace the present); events and questions replaced by `supersede` are flagged for manual
  review because code cannot judge meaning; `resolve` only applies to uncertainties;
- the prior revision's entities, records, transitions, and sections are an unchanged prefix
  of the new one, and `current` matches the index computed from them.

IDs are assigned after the largest number in use (entities per kind in array order, records
over the fixed collection order, transitions in array order) and written to `id_map.json`.
The same base and delta always give the same knowledge and IDs. Records that the new section
does not mention stay active: absence is not a retraction. An empty delta is valid but
flagged for checking omissions.

### The v2 model

`story_model.json` in a store has `schema_version: "2.0"`, `scope: "cumulative"`, and:

| Field | Meaning |
| --- | --- |
| `book` | title and EPUB SHA-256 |
| `revision` | number, random ID, time, source run, parent snapshot path and SHA-256 |
| `processed_sections` | each processed section with its order, text hash, and saved input |
| `coverage` | starting section and the earlier sections that were never processed |
| `entities` | stable IDs and kinds, with the revision that introduced each |
| `records` | the seven record collections; records are never edited or deleted |
| `transitions` | every supersede/retract/resolve, with reason and evidence |
| `current` | active record IDs, resolved uncertainties, explicit identity groups (computed) |
| `provenance` | the imported v1 run and its manual corrections |

Display names come from the active name records of the revision being shown (newest first;
several active names are listed as a conflict). Two entities revealed to be one keep their
IDs and records; only `explicit` identity links between entities of the same kind group them
in `current`, and the earliest one is shown as the group's ID. Conflicting facts of a merged
identity are reported, not resolved.

### Store layout and commits

```text
tools/story_model_lab/stores/<name>/
  story_model.json             latest revision (the only commit point)
  .lock                        fcntl.flock lock taken while committing
  revisions/000001-<id>.json   full, immutable snapshot of each committed revision
  inputs/<section>-<hash>.json normalized text of each processed section
  provenance/initial/          copied v1 run files, migration_map.json, manifest.json
  provenance/<update-run-id>/  delta, id_map, commit.json (base revision and hash), manifest
```

### Sharing the model with teammates

The authoritative, continuously updated file is
[`stores/86v1/story_model.json`](stores/86v1/story_model.json). Successful updates replace
this file, while [`stores/86v1/revisions/`](stores/86v1/revisions/) preserves earlier
snapshots. Both are tracked by Git for team review. Commit their changes after each update
you want to share; committing locally does not upload them to the remote repository.

Teammates can read the JSON directly or use the exported Markdown, such as
[`ch2_story_model.md`](../../ch2_story_model.md). That Markdown is a static export, not the
file used by `update`. Do not edit the model or snapshots by hand: their consistency and
hashes are checked by the tool.

**The tracked snapshots are not a complete runnable store.** `show`, `update`, and store
validation also need that store's local `inputs/` and `provenance/` directories; `update`
additionally needs the original EPUB. These files, other stores, locks, and run artifacts
remain ignored. A fresh clone can inspect the shared JSON, but to use the CLI it must
either obtain the complete matching store from the teammate who ran it (and the same EPUB
for updates), or generate a first chapter and initialize a separate new store. Do not run
`init` over the checked-out `86v1` directory. Back up the full local store, not just the
tracked JSON. A complete store does not need the run directories it came from.

Every command that reads a store checks it first: the latest file must equal its snapshot,
every saved input must match its SHA-256, provenance manifests must match, the parent chain
of snapshots must be intact back to revision 1, and the model must pass full validation.

A successful `update` commits automatically: it writes the new input, provenance, and
snapshot, then, holding the lock and after checking that `story_model.json` still has the
hash it started from, replaces `story_model.json` atomically (`os.replace` after `fsync`).
The lock is not held during the API call. If another update committed in between, nothing
is written and the run ends with `stale_base` (exit code 5). A failure before the replace
leaves the previous revision in place (exit code 2, `commit_failed`); leftover files are not
part of the history, and `show --revision` only accepts revisions reachable from the latest
one's parent chain. A failure after the replace (for example while writing the report)
still counts as committed and is recorded as such in `run.json`.

### Committing a run after manual corrections

When the model's delta fails validation only because evidence points to the wrong place (a
paragraph ID off by one, a quote with a changed word), it can be corrected by hand and
committed without another API call:

```bash
# <run>/manual_corrections.json: a list of
#   {"path": "new_records.names[6].evidence[0].paragraph_id", "from": "p0094", "to": "p0093",
#    "reason": "...", "corrected_by": "...", "corrected_at": "..."}
story-model commit --run tools/story_model_lab/runs/<update-run-id> \
  --epub sample_epub/86v1_chapters.epub
```

- Only `...evidence[N].paragraph_id` and `...evidence[N].quote` can be corrected, never facts
  or IDs; `from` must equal what the model returned.
- The store must still be at the run's base revision (otherwise exit code 5), and the section
  must still be the next one. The corrected delta is fully validated again (exit code 4 if it
  still fails; nothing is committed).
- `delta.candidate.json` and the original `validation.json` are not changed. The run gains
  `delta.corrected.json` and `validation.corrected.json`; the store's provenance keeps the
  raw delta, the corrections, the corrected delta, and the original validation; and every
  correction is listed in the model's `provenance.update_manual_corrections`, so `show`
  and `review.md` mark that revision as not the model's unmodified output.

### What an update run saves

Besides `chapter.json/txt`, `prompt.txt`, `schema.json`, `request.json`, `response.json`,
and `run.json`:

| File | Content |
| --- | --- |
| `base_story_model.json` | the store's latest revision before the call, byte for byte |
| `base_inputs/` | the saved inputs of the base's sections (for offline re-checks) |
| `context.json` | exactly the prior model and new section sent to the model |
| `delta.candidate.json` | the model's delta as returned, kept even when invalid |
| `validation.json` | delta, merged-model, history, and evidence checks |
| `delta.json`, `id_map.json` | the validated delta and the local → stable ID map |
| `story_model.after.json` | the merged candidate revision (not proof that it was committed) |
| `diff.md` | new entities and records, superseded and retracted claims, answered questions |
| `review.md` | commit status, important changes with evidence, items for manual judgment |
| `failure.json` | why the run did not commit, when it did not |

`run.json` records `base_revision`, `candidate_revision`, `committed_revision`,
`commit_status` (`not_attempted`, `committed`, `stale_base`, `failed`), `report_status`, and
the API and validation results. `--dry-run` writes neither a delta nor a merged model.
`validate --run` on an update run checks the base, the delta, and the merged result again
and writes `validation.recheck.json`; it never applies the delta to the store.

Passing these checks means the structure, IDs, references, and quotes are consistent. It
does not mean the facts are right or complete; use `review.md` and `diff.md` to check them.
