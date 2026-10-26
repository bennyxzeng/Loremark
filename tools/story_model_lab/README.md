# Story Model Lab

A terminal experiment for Loremark: parse an EPUB locally, pick **one** chapter, send only
that chapter to a model through the **Responses API with Structured Outputs**, and save the
characters, locations, organizations, relationships, events, and open questions it finds,
together with everything needed to check the result by hand.

The result describes only what that chapter says. It is not a whole-book model: identities,
references, or causes that need earlier chapters are kept as uncertainties, not filled in.

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

## Model providers

Configuration comes only from environment variables; no `.env` file is loaded.
`.env.example` lists the names.

| Provider | Key | Model | Base URL (default) |
| --- | --- | --- | --- |
| `openai` | `OPENAI_API_KEY` | `OPENAI_MODEL` | `OPENAI_BASE_URL` (`https://api.openai.com/v1`) |
| `deepseek` | `DEEPSEEK_API_KEY` | `DEEPSEEK_MODEL` | `DEEPSEEK_BASE_URL` (`https://api.deepseek.com`) |

Both use the official `openai` Python SDK and `client.responses.parse(text_format=ChapterStoryModel)`
(Responses API, strict JSON Schema), with the system prompt and the chapter as separate
`system` and `user` messages. No tools, web search, conversation state, or
`previous_response_id` are used; `temperature`, `seed`, and `reasoning` are not sent.

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
(nav, NCX fallback, several chapters in one file, special characters, missing text, unsafe
paths) and drive the real OpenAI SDK through a mock HTTP transport (success, refusal,
incomplete, timeout, 429/401/404/500, invalid JSON, schema mismatch, failed validation,
DeepSeek routing). The user sample test runs only if `sample_epub/86v1_chapters.epub` exists.

Live smoke tests send a three-paragraph synthetic chapter and only check the wiring:

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
- IDs (`c001`, `e001`, ...) are local to one run; nothing links entities across chapters or
  runs.
- No app integration, reading progress, database, web service, or vector search.
