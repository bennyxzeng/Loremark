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
| `story_run_folder.dart` | `pipeline.py`, `artifacts.py` | Keeps a folder of everything about each update |
| `story_archive.dart` | (new) | Zips a book's store and run folders to export them |
| `story_import.dart` | (new) | Checks a file and loads it as a book's store |
| `story_paragraphs.dart` | (new) | Finds the paragraphs a model's evidence cites, and what of a section a reader hasn't reached |

Not ported: the command line, the `review.md` and `diff.md` reports, and committing a run after
manual corrections. A reader can't correct a run in the app, so a failed one is tried again, or
exported and corrected with the lab: see [Files on the phone](#files-on-the-phone).

A book's store is at `<app support>/library/story_models/<book id>/`, and its run folders are beside
it, in `<book id>.runs/`. Both go when the book does.

## Behavior

- **One press, one section, one paid request.** Nothing retries by itself. A retry is another
  paid request, so it is the reader's call.
- **Update adds the next section; Choose picks a later one.** Sections only go in reading order,
  because each is built on those before it and an earlier one would mix in later knowledge. So the
  reader can skip ahead, but not go back: the dialog names what a pick leaves out, for good. The map
  doesn't mark the gap, and the slider just lists what was processed.
- **A section that can't be read doesn't end the map.** Update stops there rather than stepping past
  it unasked, and Choose gets past it. A section with no text is stepped over and not counted.
- **The bar shows how long an update has been running,** and the result says how long it took. The
  time is read from the clock and from when the update really began, so it stays right after the
  system holds the app back, and after leaving the book and coming back.
- **A failed update changes nothing.** The store only moves when the whole answer passes.
- **Every update leaves a folder.** The bar names the first check that failed, and the update's run
  folder holds the rest: see [Files on the phone](#files-on-the-phone).
- **Looking at a map needs no API key.** Only Update and Choose do, since a map is stored data. So a
  reader with no key can load a map from a file, and look at it.
- **Updating isn't tied to reading progress.** The reader can update past where they are. The
  slider asks before showing anything past their position instead (`StoryMapScreen`). That uses
  `ReaderPosition.current`, because the furthest position isn't stored yet; once it is, pass it to
  `completedSectionCutoff` in `finishedStorySections`.
- **The map follows the page being looked at, down to the paragraph.** Each page, Readium reports its
  first visible element, kept as a `PageStart` beside the reading position. The paragraphs before that
  element have been read, so the section being read shows only what they establish
  (`hiddenWithinSection`, which leans towards showing a fact late, since the model read the whole
  section before writing any of it). A page just turned to hasn't been read, so a section is finished
  only once the reader has turned past it. Turning back takes the map back too. If a page can't be
  placed, only finished sections show.
- **The quote check is a setting, off by default.** Off, a quote that isn't in its paragraph is
  only a warning, and `processed_sections[].quotes_checked` remembers that for the section. The
  Chapter page says so. On, one bad quote rejects an update that has already been paid for.
- **Requests run in the foreground.** Leaving the book doesn't stop one, but the OS can suspend
  the app, which ends the request. Nothing is saved then, though the provider may still charge.
- **Update turns into Cancel while an update runs.** It asks first, since pressing Update twice
  would otherwise throw a paid request away. Cancelling drops the request's connection and saves
  nothing, though the provider may still charge. An answer that has already come has been paid
  for, so it is checked and kept as usual (`StoryUpdater.cancel`). The run folder ends `cancelled`,
  which the lab doesn't have, with exit code 130.

## Where it differs from the lab

- **XHTML parsing.** The lab uses BeautifulSoup, which guesses at broken markup. The port parses
  XML like the rest of the app, and flags a section whose document isn't well-formed.
- **Sections with no text are stepped over.** The lab stops at one for good, and a full-page
  illustration is common in light novels. The lab's checks still accept the result, since they
  only need sections in increasing order.
- **Sections can be skipped on purpose.** The lab's `update` refuses to skip one. It can still read
  a store with gaps, check it and carry on from it, since its checks only need increasing order.
- **A 15-minute request timeout, and no automatic retries.** The lab has no timeout, and its
  SDK retries twice.
- **Run folders leave some things out.** No `diff.md` or `review.md`, whose reports aren't ported,
  and no `evidence` or `counts` in `validation.json`. `response.json` is the reply byte for byte,
  where the lab re-encodes it, and a reply that isn't JSON goes in `response.txt`.

## Files on the phone

**Each update leaves a run folder**, `<book id>.runs/<run id>/`, in the lab's format. Its run ID is
the one in the store's `provenance/`.

| When | Files |
| --- | --- |
| Before sending | `chapter.json`, `chapter.txt`, `prompt.txt`, `schema.json`, `request.json`, `context.json`, `base_story_model.json`, `base_inputs/`, `run.json` |
| On the reply | `response.json` (or `response.txt`), `delta.candidate.json` |
| After the checks | `validation.json`; if it passed, also `delta.json`, `id_map.json`, `story_model.after.json` |
| At the end | `run.json` again, with how it ended and how long it took; if it failed, also `failure.json` |

If the folder can't be written before sending, nothing is sent, since the answer couldn't be kept.
After that the request has been paid for, so failing to write never changes how the update ends. The
key is never written, and is taken out of whatever a provider says in case it repeats it.

These add up: a rough estimate is 50–60 MB for a whole 18-section novel, and 2–3 MB per failed try.
Most of that is copies the lab also keeps, which its `validate --run` needs. Nothing clears them
short of removing the book.

**Export files…** in the ⋯ menu saves one zip, wherever the reader chooses, in the system's dialog:

```text
store/   story_model.json, revisions/, inputs/, provenance/
runs/    <run id>/...
```

It holds the book's text and no key. Unzipped, the lab can read it:

```bash
story-model show --store store
story-model validate --run runs/<run id>
```

A failed run can be corrected with the lab's `story-model commit --run`, after pointing `store.path`
in its `run.json` at the unzipped store. Zipping `store/` and `runs/` again gives a file the app can
load, with the correction on record.

**Load from file…** in the same menu takes:

| File | What the reader gets |
| --- | --- |
| A zip from **Export files…** | The map and its run folders, ready to update. Runs already here aren't overwritten |
| A zip of a store's folder, from the lab | The map, ready to update |
| A `story_model.json` alone, or in a zip | The map, which can only be viewed |

A lone model can't be continued, because `StoryStore.load` needs every revision's snapshot and
provenance, as does the lab.

Nothing in a file is trusted. It is unpacked and checked beside the store, which stays as it is
until the reader agrees to replace it:

- It has to be from this EPUB file, by `epub_sha256`.
- A zip is refused whole if a path leads outside its folder or an entry is a symbolic link, and
  there are limits on its size and number of files. Only the store's own files and `runs/` are
  taken, so `.lock`, `.DS_Store` and `__MACOSX/` are left behind. Run folders are never read again.
- A store has to pass `StoryStore.load`, which checks all of it.
- A lone model is checked against text extracted from the book, since it brings none of its own.

Replacing goes by renames, and `recoverReplacedStore` finishes the job if the app stops partway, so
the store is always the old one or the new. The replaced store is deleted, and its run folders stay.

## Reading the paragraphs back

Every update saves its section's paragraphs in the store's `inputs/`, each with an ID such as `p0012`,
and every record's evidence names a `section_id` and a `paragraph_id`. So answering from the map goes
from the facts to the text behind them. Ask does this: see [ask.md](ask.md).

```dart
final progress = (await backend.askReach(book, model.sections)).progress;
final paragraphs = await backend.paragraphs(book, progress);
final snapshot = StorySnapshot( // if progress.shown > 0
  model,
  model.sections[progress.shown - 1],
  hidden: progress.hiddenInNext ?? const {},
);
// `records` are the facts picked out of the snapshot for a question.
final context = paragraphs.forEvidence(
  records.expand((record) => record.evidence),
  context: 1,
);
// Each StoryParagraph: sectionId, id, number, text. In reading order, no repeats.
```

- **`StoryReadingProgress` is the spoiler boundary**, and it is required. Finished sections come
  whole, and of the section being read only the paragraphs turned past. Nothing else is kept, so a
  lookup can't reach it, and neither can `forEvidence`'s neighbors.
- **Answers go to the end of the page; the map stops at its start.** A reader asks about what they
  are looking at, so Ask counts the whole page as read: `askReach` measures to the first text block
  not wholly on the page (`PageEnd`), and a paragraph that carries on to the next page isn't
  counted. The map keeps to `readingProgress`, where a page just turned to hasn't been read. Both
  go through the same `hiddenWithinSection`, and if the page's end can't be measured, Ask falls back
  to the map's boundary. Don't work out a third.
- **Evidence always comes from the section its record was learned in**, so records from a snapshot
  never lead past it. A citation ahead of the page just isn't found: a name shows at its first
  citation, so its later ones can be further on.
- **Answer from the paragraph, not the quote.** With the quote check off a quote may not match, but
  `unknown_paragraph` is always an error, so the paragraph it names is real.
- **A map loaded from a lone `story_model.json` has no `inputs/`.** Its text comes from the EPUB
  instead, and is used only if it hashes to the model's `text_sha256`. The same goes for a saved file
  that is missing or changed.
- **These aren't search's paragraphs.** `ParagraphIndex` numbers by spine item and cuts long
  paragraphs up, so a `Passage` and a `StoryParagraph` can't be matched by number.

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

`LOREMARK_STORY_LIBRARY=<an app's library folder>` does the same for paragraph progress, over the maps
and books on a device. On an iOS simulator that folder is under the app's `Library/Application Support`.

A store written here can be checked the other way, with the lab's `story-model show --store <path>`.

## Running one update by hand

```bash
dart run tool/story_update/run.dart --epub=book.epub --store=some/folder \
  --section=section-004 --model=deepseek-flash --effort=high --out=some/runs --dry-run
```

`--section` is where a new store starts, or a later section to skip ahead to; without it, the next
section. `--out` is a folder to keep run folders in, the same as the app's. `--dry-run` sends nothing.
Without it, the key comes from `DEEPSEEK_API_KEY` or `OPENAI_API_KEY`. `--ledger=<file>` caps
spending: it refuses to send after `--max-successes` updates (default 4) or `--max-failures`
failures in a row (default 2).

## Models

`deepseek-flash` and `gpt-6.1-terra` were tested with the lab, and `deepseek-flash` with this port.
`gpt-6.1-sol`'s name and efforts come from third-party sources, and it has not been run yet. If a
provider rejects a model or an effort, the reader sees the error; nothing falls back silently.
