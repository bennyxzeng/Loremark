# Story Model Lab

[![English](https://img.shields.io/badge/English-2563EB?style=for-the-badge)](README.md) [![简体中文](https://img.shields.io/badge/%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-64748B?style=for-the-badge)](README.zh-CN.md)

[![Story Model structure & labels](https://img.shields.io/badge/Story_Model-Structure_%26_Labels-0F766E?style=for-the-badge)](STORY_MODEL_FORMAT.md)

**What does `story_model.json` contain?** Start with the [one-page diagram with 86 examples](STORY_MODEL_FORMAT.md#at-a-glance), then read the [file structure and label guide](STORY_MODEL_FORMAT.md) for characters, places, organizations, relationships, events, evidence, open questions, revisions, and every assertion/time label, including `inferred` and flashbacks (`past`). [简体中文](STORY_MODEL_FORMAT.zh-CN.md).

[View the structure diagrams](STORY_MODEL_FORMAT.md#visual-overview): field contents and the ID links between entities, records, evidence, and revisions.

[Setup](#0-one-time-setup) · [A new book](#a-a-new-book) · [Continue a store](#b-continue-a-store) · [When a run fails](#c-when-a-run-fails) · [Reference](#commands)

A terminal experiment for Loremark: build a story model of an EPUB **one section at a time,
in reading order**. Each `update` sends the model built so far and the next section's text
to a model through the **Responses API with Structured Outputs**; the model returns only
what that section adds or changes (a delta), and code checks it, assigns stable IDs, and
commits a new revision. The first `update` of a book starts from an empty model and creates
the store. Earlier facts and revisions are kept, so every point of the book can be looked at
again as it was.

The model never sees later sections, and identities, references, or causes the text has not
settled yet are kept as open questions, not filled in. This tool is independent of the
Flutter app, which only reads the resulting `story_model.json`.

## Step-by-step guide

Everything below runs from one file, [`run_story_model.py`](run_story_model.py): change the
settings at its top, save, and run it. You never type command-line flags. The file prints
the matching `story-model` command first, so the [command reference](#commands) still
explains what happened.

### 0. One-time setup

**1. Install** (Python 3.11 or newer). In a terminal, from the repository root:

```bash
cd /Users/frankhao76/MineApps/vscode/loremark/Loremark
python3 -m venv tools/story_model_lab/.venv
tools/story_model_lab/.venv/bin/python -m pip install -e './tools/story_model_lab[dev]'
```

`requirements.lock.txt` records the exact versions this was tested with (Python 3.14.6 on
macOS); install it with `tools/story_model_lab/.venv/bin/python -m pip install -r
tools/story_model_lab/requirements.lock.txt` before the editable install to reproduce them.

**2. Save your API key once.** Copy `tools/story_model_lab/.env.example` to
`tools/story_model_lab/.env` (gitignored) and paste the key after the `=`:
`DEEPSEEK_API_KEY=` for DeepSeek, `OPENAI_API_KEY=` for GPT. New terminals pick it up
automatically. Listing chapters, `show`, and dry runs need no key.

**3. Choose the interpreter in VS Code:** Command Palette (`Cmd+Shift+P`) → **Python: Select
Interpreter** → `tools/story_model_lab/.venv/bin/python`.

**How to run the file:** open `run_story_model.py` and click **Run Python File** (the ▶
button at the top right), or in a terminal:

```bash
tools/story_model_lab/.venv/bin/python tools/story_model_lab/run_story_model.py
```

Either way works from any directory; relative paths in the settings are from the
repository root.

**The settings you will change:**

| Setting | What to put there |
| --- | --- |
| `COMMAND` | what to do: `Command.CHAPTERS` (list sections), `Command.UPDATE` (add a section), `Command.SHOW` (read the model), `Command.COMMIT` / `Command.VALIDATE` (after a failed run) |
| `EPUB` | the book file, e.g. `"sample_epub/86v1_chapters.epub"` |
| `STORE` | the folder that holds this book's model, e.g. `"tools/story_model_lab/stores/86v1"`; a missing folder is created by the first update |
| `CHAPTER` / `SECTION` | which section to add. Both `None` = the next one. Only a new store needs one: its starting section |
| `MODEL`, `EFFORT` | `Model.DEEPSEEK_FLASH` or `Model.GPT_6_1_TERRA`; reasoning effort such as `Effort.HIGH`, or `None` for the model's default |
| `DRY_RUN` | `True` = only write what would be sent, no API call, store unchanged |
| `CHECK_QUOTES` | `False` = a quote not found in its paragraph is a warning and the update still commits (see [Turning the quote check off](#turning-the-quote-check-off)) |
| `RUN` | a run folder, for `Command.COMMIT` / `Command.VALIDATE` |
| `REVISION`, `SHOW_JSON` | for `Command.SHOW`: an earlier revision (`None` = latest); `True` = full JSON instead of Markdown |

### A. A new book

**Step 1: list the sections and check that the EPUB opens.**

```python
COMMAND = Command.CHAPTERS
EPUB = "sample_epub/86v1_chapters.epub"
```

Run. Each line is one section in reading order: its ID (`section-004`), chapter number,
paragraph count, and title. `CHAPTER = 1` means the section titled "Chapter 1"
(`section-004` in this sample), not the first line.

**Step 2: preview the first section without calling the API.** Pick a new store folder and
the section the model should start from:

```python
COMMAND = Command.UPDATE
STORE = "tools/story_model_lab/stores/my-book"
CHAPTER = 1
DRY_RUN = True
```

The output ends with `Context: new store + section-004` and `no store created`. The printed
`Output:` folder holds `chapter.txt` (the exact text that would be sent) and `request.json`.

Sections before the starting one (front matter, a prologue) are recorded as not covered and
can never be added later. If the prologue matters, start there with `SECTION =
"section-003"` and `CHAPTER = None`.

**Step 3: create the store for real.** Change only:

```python
DRY_RUN = False
```

This calls the API and may take several minutes. `Status: committed` with
`created at revision 1` means the store exists. If the run fails instead, see
[C](#c-when-a-run-fails).

**Step 4: add the following sections.** Change only:

```python
CHAPTER = None
```

From now on, every run adds the next section in reading order, interludes included. Run the
file again for each section; nothing else needs editing.

### B. Continue a store

The demo store the app reads is `tools/story_model_lab/stores/86v1`.

**See what is covered so far:**

```python
COMMAND = Command.SHOW
STORE = "tools/story_model_lab/stores/86v1"
REVISION = None
```

The processed sections are listed at the top. `REVISION = 1` shows the model as it was after
the first section.

**Add the next section.** Optionally preview with `DRY_RUN = True` first, then:

```python
COMMAND = Command.UPDATE
STORE = "tools/story_model_lab/stores/86v1"
CHAPTER = None
SECTION = None
DRY_RUN = False
```

After `Status: committed`, `stores/86v1/story_model.json` holds the knowledge up to that
section; earlier snapshots are in `revisions/`. Interludes are sections too, so a revision
number counts processed sections, **not novel chapters**.

**Export a readable Markdown file:** set `COMMAND = Command.SHOW`, then run in a terminal:

```bash
tools/story_model_lab/.venv/bin/python tools/story_model_lab/run_story_model.py > story_model_latest.md
```

<a id="c-when-a-run-fails"></a>

### C. When a run fails

A failed run never changes the store. Open `review.md` in the printed `Output:` folder; it
lists every problem at the top.

- **Only evidence locations are wrong** (`quote_not_found`: a paragraph ID off by one, or a
  quote with different quotation marks): fix them by hand without another API call. Write
  `manual_corrections.json` in that run folder (format in
  [Committing a run after manual corrections](#committing-a-run-after-manual-corrections)),
  then:

  ```python
  COMMAND = Command.COMMIT
  RUN = "tools/story_model_lab/runs/<run-folder>"
  ```

  `Command.VALIDATE` with the same `RUN` re-checks a run offline without committing it.

  To skip the fixes, set `CHECK_QUOTES = False` and run the update again (see
  [Turning the quote check off](#turning-the-quote-check-off)).
- **Anything else** (wrong facts, API errors, `incomplete`): run the same update again.

### Results and troubleshooting

| Status or question | What to do |
| --- | --- |
| `committed` | The update succeeded; inspect `story_model.json` in the store |
| `already_processed` | That section is already in the store; no request was sent. Set `CHAPTER = None` and `SECTION = None` to take the next one |
| `validation_failed` / `schema_invalid` | The store is unchanged; see [C](#c-when-a-run-fails) |
| Other API errors or `incomplete` | Inspect `failure.json` in the run folder and run again; never edit the store to get around validation |
| `A new store needs its starting section` | Set `CHAPTER` or `SECTION` for the first update of a store |
| A section would be skipped | Set `CHAPTER = None` and `SECTION = None`, or pick the section named in the error |
| `... is not set` (a missing key) | Put the key in `tools/story_model_lab/.env` |
| `loremark_story_lab is not installed for this Python` | Run with `tools/story_model_lab/.venv/bin/python`, or select it as the VS Code interpreter |
| What changed in this update? | Open `diff.md` in the printed `Output:` folder |

A successful request does not establish factual accuracy; `review.md` and `diff.md` show
what to check by hand.

### Using GPT instead of DeepSeek

Put `OPENAI_API_KEY` in `.env` and set `MODEL = Model.GPT_6_1_TERRA`; the provider follows
from the model. `gpt-6.1-terra` accepts every `Effort` value. You can switch models between
sections without rebuilding the store.

### Using the terminal instead

Every setting maps to a flag of the `story-model` command, which is what the file runs: the
`$ story-model ...` line it prints can be pasted into a terminal. `story-model` reads keys
and models only from exported environment variables, not from `.env`:

```zsh
source tools/story_model_lab/.venv/bin/activate
read -rs 'DEEPSEEK_API_KEY?Paste your DeepSeek API key and press Enter (input is hidden): '
export DEEPSEEK_API_KEY
export DEEPSEEK_MODEL=deepseek-flash
story-model update --store tools/story_model_lab/stores/86v1 \
  --epub sample_epub/86v1_chapters.epub --provider deepseek --dry-run
```

See the [command reference](#commands) for every command and option.

## Commands

All commands run from the repository root. `python -m loremark_story_lab ...` works the same
as `story-model ...`.

| Command | Calls the model | What it does |
| --- | --- | --- |
| `chapters --epub E` | no | List every section in reading order: ID, chapter number, paragraphs, characters, images, resource, title |
| `update --store S --epub E [--chapter N \| --section ID]` | yes | Add the next section (or create the store from the chosen section) |
| `show --store S [--revision N] [--json]` | no | Print a committed revision as Markdown or full JSON |
| `commit --run R --epub E` | no | Commit an update run after manual evidence corrections |
| `validate --run R` | no | Re-check a saved update run offline; never touches the store |

### Selecting a section

- `--chapter N` means the section whose **table-of-contents title** reads "Chapter N" (Arabic
  or Roman numerals), not the Nth XHTML file. In the sample, Chapter 1 is the 4th spine
  document (`EPUB/section-004.xhtml`). If no title or several titles match, the command stops
  and asks for `--section`.
- Section IDs are `section-001`, `section-002`, ... in reading order: TOC entries sorted by
  their position in the spine, plus any spine documents the TOC never points to (listed
  separately with a note, never merged silently).
- Without `--chapter` / `--section`, `update` takes the next section of the store. A new store
  needs one of them.
- Chapter boundaries are checked before any text is extracted. When one TOC entry of an
  XHTML file cannot be located exactly (missing anchor, an ID used twice, an anchor inside
  `<head>` or another unextracted element, or two different titles starting at the same
  place), **every** section of that file is marked as unsupported and `update` stops with
  exit code 2 before any request. `chapters` still lists them with the reason. Other files
  are not affected. An exact duplicate TOC link (same target and title) is listed once with a
  warning.

### `update` options

| Option | Default | Meaning |
| --- | --- | --- |
| `--provider` | `openai` | `openai` or `deepseek`; selects which environment variables are read |
| `--model` | `$OPENAI_MODEL` / `$DEEPSEEK_MODEL` | Model name. No model is built in; a live call without one fails with exit code 2 |
| `--prompt-file` | built-in `update_story_v2.txt` | Alternative system prompt |
| `--max-output-tokens` | not sent | Optional output cap. Without it, only the provider/model's own maximum applies |
| `--reasoning-effort` | not sent | Optional `reasoning.effort`. Values depend on the provider and model (see below) |
| `--timeout` | none | Optional seconds per HTTP attempt. Without it, the client waits for the response indefinitely |
| `--out` | `tools/story_model_lab/runs/<UTC time>-<random>` | Run directory; must not exist or must be empty |
| `--dry-run` | off | Write the input, prompt, schema, and request; no key needed, nothing sent, store unchanged (or not created) |
| `--no-quote-check` | off | A quote not found in its paragraph is a warning and the update still commits (see [Turning the quote check off](#turning-the-quote-check-off)) |

The SDK retries network errors, 429, and 5xx at most twice (`max_retries=2`). There is no
other retry: the tool never switches models, shortens the text, adds other sections, or asks
a second model to repair output. If you set `--timeout`, a timed-out attempt is retried and
may still be billed by the provider.

Even without `--max-output-tokens`, the model's own output maximum still exists; if the model
reaches it, the response is `incomplete` and the run fails with exit code 3 instead of
saving partial JSON.

### Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Success, dry run, or section already processed |
| 2 | Input or configuration error (EPUB, selection, store, missing key/model, output dir) |
| 3 | API error, refusal, incomplete output, or empty output |
| 4 | Output is not valid JSON for the schema, or fails reference/quote/ID/history validation |
| 5 | The store changed (or was created) after this update read it (`stale_base`); nothing was committed and the model is not called again |

## Model providers

`.env.example` lists the variable names.

| Provider | Key | Model | Base URL (default) |
| --- | --- | --- | --- |
| `openai` | `OPENAI_API_KEY` | `OPENAI_MODEL` | `OPENAI_BASE_URL` (`https://api.openai.com/v1`) |
| `deepseek` | `DEEPSEEK_API_KEY` | `DEEPSEEK_MODEL` | `DEEPSEEK_BASE_URL` (`https://api.deepseek.com`) |

Both use the official `openai` Python SDK and `client.responses.parse` with `StoryDelta`
(Responses API, strict JSON Schema), with the system prompt and the data as separate
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

## Section order

- Same book means the same EPUB SHA-256, not the same title.
- The first `update` of a store may start at any section; the sections before it are listed
  in `coverage.omitted_prefix_section_ids`, and the model does **not** describe the book from
  its beginning.
- After that, only the **next** section in reading order can be added: the one right after
  the last processed section in `story-model chapters`, not "chapter number + 1". An
  interlude between Chapter 3 and Chapter 4 must be processed before Chapter 4.
- Non-chapter entries are not skipped automatically. If the next section cannot be
  extracted, `update` stops with exit code 2 and says so; it is not jumped over.
- The same section with the same text again: `already_processed`, exit code 0, no request,
  store unchanged.
- A processed section whose text now hashes differently, a different EPUB, an earlier
  section, or one that would skip an unprocessed section: refused before any request. There
  is no rebase, re-run, or history editing in this version.

## What the model returns

`update` sends a system prompt (`prompts/update_story_v2.txt`) and one user message with two
data blocks: `PRIOR_STORY_MODEL` (every entity, record with payload and evidence, transition,
and the current index, as JSON; run metadata, file paths, and the book title are left out)
and `NEW_SECTION` (the paragraphs as `[p0001] ...` lines). For the first section of a store,
`PRIOR_STORY_MODEL` is revision 0 and empty. Earlier sections' text and later sections are
not sent. Nothing is summarized or trimmed; if the request is too long or the output is
incomplete, the update fails.

The model answers with a `StoryDelta` (strict Structured Outputs):

- `new_entities`: `{local_id: new_entity_001, kind}`; each needs a name record in the delta.
- `new_records`: seven arrays (`names`, `aliases`, `attributes`, `relationships`, `events`,
  `uncertainties`, `identity_links`) of `{local_id: new_record_001, payload, evidence}`.
  Payloads refer to existing IDs or this delta's local entity IDs.
- `transitions`: `{target_record_id, action, replacement_local_id, resolution, reason,
  evidence}` with action `supersede` (a new record of the same kind and subject replaces
  the target), `retract` (the target is shown false), or `resolve` (an uncertainty is
  answered). Always empty for the first section.

Code then checks the delta and the merged result:

- local IDs unique and well-formed; every entity reference is a prior entity or a new one of
  this delta (a stable ID the model made up is refused, never bound to a new entity) and of
  the right kind;
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

## The model (`story_model.json`)

`story_model.json` in a store has `schema_version: "2.0"`, `scope: "cumulative"`, and:

| Field | Meaning |
| --- | --- |
| `book` | title and EPUB SHA-256 |
| `revision` | number, random ID, time, source run, parent snapshot path and SHA-256 (`null` for revision 1) |
| `processed_sections` | each processed section with its order, text hash, and saved input |
| `coverage` | starting section and the earlier sections that were never processed |
| `entities` | stable IDs and kinds, with the revision that introduced each |
| `records` | the seven record collections; records are never edited or deleted |
| `transitions` | every supersede/retract/resolve, with reason and evidence |
| `current` | active record IDs, resolved uncertainties, explicit identity groups (computed) |
| `provenance` | `manual_corrections`: every evidence location corrected by hand before a commit |

Display names come from the active name records of the revision being shown (newest first;
several active names are listed as a conflict). Two entities revealed to be one keep their
IDs and records; only `explicit` identity links between entities of the same kind group them
in `current`, and the earliest one is shown as the group's ID. Conflicting facts of a merged
identity are reported, not resolved. Field-by-field explanations are in
[Story Model: file structure and labels](STORY_MODEL_FORMAT.md).

## Store layout and commits

```text
tools/story_model_lab/stores/<name>/
  story_model.json             latest revision (the only commit point)
  .lock                        fcntl.flock lock taken while committing
  revisions/000001-<id>.json   full, immutable snapshot of each committed revision
  inputs/<section>-<hash>.json normalized text of each processed section
  provenance/<update-run-id>/  delta, id_map, commit.json (base revision and hash), manifest
```

Every command that reads a store checks it first: the latest file must equal its snapshot,
every saved input must match its SHA-256, every revision must have its provenance manifest
and every manifest must match, the parent chain of snapshots must be intact back to
revision 1, and the model must pass full validation (in a section with `quotes_checked:
false`, a quote not found is only a warning).

A successful `update` commits automatically: it writes the new input, provenance, and
snapshot, then, holding the lock and after checking that `story_model.json` still has the
hash it started from (or, for a new store, still does not exist), replaces it atomically
(`os.replace` after `fsync`). The lock is not held during the API call. If another update
committed in between, nothing is written and the run ends with `stale_base` (exit code 5). A
failure before the replace leaves the previous revision in place (exit code 2,
`commit_failed`); leftover files are not part of the history, and `show --revision` only
accepts revisions reachable from the latest one's parent chain. A failure after the replace
(for example while writing the report) still counts as committed and is recorded as such in
`run.json`.

### Sharing the model with teammates

The demo store's [`story_model.json`](stores/86v1/story_model.json) and
[`revisions/`](stores/86v1/revisions/) are tracked by Git; the app bundles
`stores/86v1/story_model.json` directly. Commit their changes after each update you want to
share. Do not edit the model or snapshots by hand: their consistency and hashes are checked
by the tool.

**The tracked files are not a complete runnable store.** `show`, `update`, and store
validation also need the store's local `inputs/` and `provenance/` directories; `update`
additionally needs the original EPUB. These, other stores, locks, and run artifacts remain
ignored. A fresh clone can read the shared JSON; to continue the store with the CLI it needs
the complete store from the teammate who ran it (and the same EPUB), or it creates a new
store with its own first `update`. A complete store does not need the run directories it
came from.

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
- The store must still be at the run's base revision (for a run that would have created the
  store: the store must still not exist), otherwise exit code 5; the section must still be
  the next one. The corrected delta is fully validated again (exit code 4 if it still fails;
  nothing is committed).
- `delta.candidate.json` and the original `validation.json` are not changed. The run gains
  `delta.corrected.json` and `validation.corrected.json`; the store's provenance keeps the
  raw delta, the corrections, the corrected delta, and the original validation; and every
  correction is listed in the model's `provenance.manual_corrections`, so `show` and
  `review.md` mark that revision as not the model's unmodified output.

### Turning the quote check off

The quote check is on by default. Turn it off with `CHECK_QUOTES = False` in
`run_story_model.py`, or `--no-quote-check` on `update`. `run_story_model.py` in the repository
currently sets it to `False`.

- **It only covers `quote_not_found`:** a wrong paragraph ID, or quote text that differs from
  the book. Other checks still fail the run: an unknown paragraph, an empty or too long
  quote, or evidence from another section.
- **Problems stay visible:** a quote not found is a warning in `validation.json` and
  `review.md`. It does not block the commit, and it is not corrected.
- **The store remembers it:** the section gets `processed_sections[].quotes_checked: false`,
  and `run.json` records it too. `show` and `review.md` flag it, and later `show`, `update`,
  `validate`, and `commit` commands do not need the switch.
- **Turning it back on only affects later sections:** committed sections stay accepted, and
  new sections are checked strictly again.
- **It does not rescue a failed run:** the switch only applies to `update`, so run the update
  again, or use [manual corrections](#committing-a-run-after-manual-corrections).

With the check off, the model can keep wrong quotes, and the app shows them as they are.

## What an update run saves

| File | Content |
| --- | --- |
| `chapter.json`, `chapter.txt` | the normalized section input, and the same text as `[p0001] ...` lines |
| `prompt.txt`, `schema.json`, `request.json` | system prompt, JSON Schema, and request actually sent (no key) |
| `context.json` | exactly the prior model and new section sent to the model |
| `base_story_model.json` | the store's latest revision before the call, byte for byte (revision 0 for a new store) |
| `base_inputs/` | the saved inputs of the base's sections (for offline re-checks) |
| `run.json` | IDs, timestamps, hashes, versions, usage, status, validation summary |
| `response.json` | raw API response body, when one was received |
| `delta.candidate.json` | the model's delta as returned, kept even when invalid |
| `validation.json` | delta, merged-model, history, and evidence checks |
| `delta.json`, `id_map.json` | the validated delta and the local → stable ID map |
| `story_model.after.json` | the merged candidate revision (not proof that it was committed) |
| `diff.md` | new entities and records, superseded and retracted claims, answered questions |
| `review.md` | commit status, important changes with evidence, items for manual judgment |
| `failure.json` | why the run did not commit, when it did not |

`run.json` records `base_revision` (`null` when the run creates the store),
`candidate_revision`, `committed_revision`, `commit_status` (`not_attempted`, `committed`,
`stale_base`, `failed`), `report_status`, and the API and validation results. `--dry-run`
writes the files up to `run.json` and no delta or merged model. `validate --run` checks the
base, the delta, and the merged result again and writes `validation.recheck.json`; it never
applies the delta to the store.

## Reading the results

Automatic validation checks structure, not truth: schema (types, enums, no extra fields),
IDs and references, evidence on every record with **exact** quotes (no fuzzy matching, at
most 300 characters; `[start, end)` offsets in code points are computed locally; the match
itself [can be turned off](#turning-the-quote-check-off)), events in narrative order 1, 2, 3, ... within a section, and history. Empty results are allowed but
flagged.

**A matched quote only proves the quote exists in that paragraph. It does not prove the
quote supports the claim.** Passing validation is not factual accuracy; use `review.md` and
`diff.md` to check the facts, and `evaluation/rubric.md` and
`evaluation/review_template.json` for a structured manual review.

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

Offline tests need no key and block network access. They build small EPUBs on the fly (nav,
NCX fallback, several chapters in one file, missing/duplicate/misplaced anchors, special
characters, missing text, unsafe paths) and drive the real OpenAI SDK through a mock HTTP
transport (request contents, success, refusal, incomplete, timeout, 429/401/404/500, invalid
JSON, schema mismatch, failed validation, DeepSeek routing). The user sample test runs only
if `sample_epub/86v1_chapters.epub` exists.

The store is tested on a synthetic story (`tests/fixtures/story/`): creating a store from an
empty model, merging (reused and new IDs, made-up IDs, forward references,
supersede/retract/resolve, flashbacks, identity reveals, invalid deltas, determinism), the
store (atomic commits, stale bases, injected write and replace failures, damaged files, a
real `flock`), and `update` end to end (every failure kind, the next section taken
automatically, repeated and out-of-order sections, concurrent updates, manual corrections,
offline re-validation, `show` of old revisions).

Live smoke tests send a two-section synthetic book (a new store, then one update) and only
check the wiring:

```bash
RUN_LIVE_OPENAI=1 python -m pytest tools/story_model_lab/tests -m live -s
RUN_LIVE_DEEPSEEK=1 python -m pytest tools/story_model_lab/tests -m live -s
```

They also need the provider's key and model variables, and are skipped otherwise.

## Known limits

- One section per request, no chunking. A section too long for the model fails; it is never
  truncated silently. The prior model grows with every section and is always sent in full.
- Text only. Images are counted (`omitted_image_count`) but not read; no OCR.
- Chapters that start mid-document are cut at TOC anchors. A chapter spread across several
  XHTML files is not merged: extra files appear as their own sections with a note.
- Chapter numbers come from TOC titles ("Chapter 3", "Chapter IV"); other naming schemes
  need `--section`.
- The source EPUB's paragraphs are kept as they are. In the sample, a few `<p>` elements
  contain two scenes (for example p0090 of Chapter 1); the tool does not re-split them.
- No rebase or re-run of an earlier section, no reading progress, database, web service, or
  vector search.
