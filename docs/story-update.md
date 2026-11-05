# Story Map updates

The app builds a book's story model itself, one section at a time, with the reader's own API
key. There is no backend. Pressing **Update** on the Story Map tab sends the next section and
the model so far to the provider, checks the answer, and saves a new revision.

The code in `lib/story_update/` is a port of the story model lab (`tools/story_model_lab/` on
the `story-model` branch). It needs no Flutter, so `tool/story_update/run.dart` can run it from
the command line.

| File | Port of | What it does |
| --- | --- | --- |
| `story_book.dart` | `epub.py` | Splits an EPUB into sections and paragraphs |
| `delta_schema.dart` | `cumulative_schemas.py` | Checks the model's answer against the schema sent with the request |
| `story_merge.dart` | `merge.py` | Applies an answer to the model, assigns stable IDs |
| `story_validation.dart` | `cumulative_validation.py` | Every check, with the lab's codes and paths |
| `story_store.dart` | `story_store.py` | The store on disk, in the lab's layout |
| `story_api_client.dart` | `openai_client.py`, `prompting.py` | Builds the request, calls the Responses API, classifies the result |
| `story_model_choice.dart` | `config.py` | The models and reasoning efforts readers can pick |
| `story_updater.dart` | `incremental_pipeline.py` | Next section → request → checks → commit |

Not ported: the command line, the `review.md` and `diff.md` reports, and committing a run after
manual corrections. A reader can't correct a run, so a failed one is simply tried again.

A book's store is at `<app support>/library/story_models/<book id>/`, and goes when the book does.

## Behavior

- **One press, one section, one paid request.** Nothing retries by itself. A retry is another
  paid request, so it is the reader's call.
- **A failed update changes nothing.** The store only moves when the whole answer passes.
- **Updating isn't tied to reading progress.** The reader can update past where they are. The
  slider asks before showing anything past their position instead (`StoryMapScreen`). That uses
  `ReaderPosition.current`, because the furthest position isn't stored yet; once it is, pass it to
  `completedSectionCutoff` in `finishedStorySections`.
- **The quote check is a setting, off by default.** Off, a quote that isn't in its paragraph is
  only a warning, and `processed_sections[].quotes_checked` remembers that for the section. The
  Chapter page says so. On, one bad quote rejects an update that has already been paid for.
- **Requests run in the foreground.** Leaving the book doesn't stop one, but the OS can suspend
  the app, which ends the request. Nothing is saved then, though the provider may still charge.

## Where it differs from the lab

- **XHTML parsing.** The lab uses BeautifulSoup, which guesses at broken markup. The port parses
  XML like the rest of the app, and flags a section whose document isn't well-formed.
- **Sections with no text are stepped over.** The lab stops at one for good, and a full-page
  illustration is common in light novels. The lab's checks still accept the result, since they
  only need sections in increasing order.
- **A 15-minute request timeout, and no automatic retries.** The lab has no timeout, and its
  SDK retries twice.

## Staying in step with the lab

`test/story_update/` checks the port against what the lab produces, from
`test/fixtures/story_update/`. After changing the lab, regenerate them; nothing here calls an API:

```bash
git archive story-model tools/story_model_lab | tar -x -C /tmp/lab
PYTHONPATH=/tmp/lab/tools/story_model_lab/src \
  tools/story_model_lab/.venv/bin/python tool/story_update/gen_goldens.py \
  --lab /tmp/lab/tools/story_model_lab
```

This also rewrites `assets/story_update/`, the prompt and schema the app sends.

Two more checks need files that aren't in the repository, and skip without them: the sample book
(`sample_epub/86v1_chapters.epub`), and real lab stores, which replay every delta and compare the
result with what the lab committed:

```bash
LOREMARK_STORY_STORES=<folder of stores> flutter test --tags corpus test/story_update
```

A store written here can be checked the other way, with the lab's `story-model show --store <path>`.

## Running one update by hand

```bash
dart run tool/story_update/run.dart --epub=book.epub --store=some/folder \
  --section=section-004 --model=deepseek-flash --effort=high --out=some/run --dry-run
```

`--section` is only for a new store. `--dry-run` writes the request to `--out` and sends nothing.
Without it, the key comes from `DEEPSEEK_API_KEY` or `OPENAI_API_KEY`. `--ledger=<file>` caps
spending: it refuses to send after `--max-successes` updates (default 4) or `--max-failures`
failures in a row (default 2).

## Models

`deepseek-flash` and `gpt-6.1-terra` were tested with the lab, and `deepseek-flash` with this port.
`gpt-6.1-sol`'s name and efforts come from third-party sources, and it has not been run yet. If a
provider rejects a model or an effort, the reader sees the error; nothing falls back silently.
