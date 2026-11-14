# Scalability benchmarks

The spec sets three scalability targets for a 500,000-word book: chapter processing under 60 s,
and 28 of 30 character cards opening in under 1 s. This page says how we measure them and
what the latest numbers are. Spoiler and device checks are described in `docs/testing.md`.

## What is measured

| Step | What it stands for |
| :--- | :--- |
| Extract text, whole book | The text-extraction part of chapter processing: `sectionTextsFromBytes` over a generated 100-chapter × 5,000-word EPUB (about 500,200 words, 1.0 MB). |
| Extract text, one chapter | The same call on a one-chapter, 5,000-word EPUB, 30 different chapters. |
| Load story model | `jsonDecode` plus `StoryModel.fromJson` of a 9.8 MB model: 100 sections, 2,300 entities, about 24,000 records and 6,000 transitions. |
| StorySnapshot construction | `StorySnapshot(model, section)` at each of the last 30 of 100 sections. |
| Character card lookup | What a card shows about one character: name, aliases, attributes, relationships, events, questions and changes, as text. We use the busiest characters the reader has met by that section, so these are the slowest cards. |
| Character card: snapshot + lookup | The two above together; this is the "28 of 30 under 1 s" figure. The model is already loaded, as it is when the app is running. |

The book and the story model are generated from a seed (`test/support/synthetic_book.dart`,
`test/acceptance/synthetic_story_model.dart`), so runs are repeatable and nothing copyrighted is
in the repo. The story model is synthetic: its record counts follow the spec (about 2,000
characters, about 20,000 records, 100 sections), but its facts are made up. Each row is
timed with `Stopwatch`. p50 and p95 are nearest-rank percentiles.

Chapter processing in the spec may also include search indexing and LLM calls. Only text extraction
is measured here; see "Not measured yet".

## Results

Machine: AMD Ryzen 9 7900X (12 cores, 24 logical processors), Windows 11 Pro, Dart 3.13.5. Times are
in milliseconds. Host numbers: a phone is slower, so the 60 s budget has a large safety margin
to spend on that difference.

### AOT (`dart compile exe`)

This is the headline: it is what ships and has no JIT warm-up.

| Step | Runs | p50 (ms) | p95 (ms) | Max (ms) |
| :--- | ---: | ---: | ---: | ---: |
| Extract text, whole book (100 chapters) | 5 | 167 | 170 | 170 |
| Extract text, one 5000-word chapter | 30 | 1.69 | 1.86 | 2.53 |
| Load story model (JSON decode + parse) | 3 | 92.9 | 100 | 100 |
| StorySnapshot construction | 30 | 2.29 | 2.96 | 4.10 |
| Character card lookup | 30 | 7.51 | 13.0 | 21.7 |
| Character card: snapshot + lookup | 30 | 9.95 | 15.4 | 24.3 |

Character cards under 1 s: **30 of 30** (spec: at least 28 of 30). Whole-book text extraction:
0.17 s against the 60 s budget.

### JIT (`dart run`)

| Step | Runs | p50 (ms) | p95 (ms) | Max (ms) |
| :--- | ---: | ---: | ---: | ---: |
| Extract text, whole book (100 chapters) | 5 | 146 | 156 | 156 |
| Extract text, one 5000-word chapter | 30 | 1.49 | 2.05 | 3.53 |
| Load story model (JSON decode + parse) | 3 | 109 | 111 | 111 |
| StorySnapshot construction | 30 | 2.59 | 9.74 | 10.9 |
| Character card lookup | 30 | 6.99 | 13.8 | 22.8 |
| Character card: snapshot + lookup | 30 | 9.74 | 24.7 | 32.6 |

Character cards under 1 s: **30 of 30**. JIT is slightly faster than AOT on some rows here; the timed work is the same, so
treat differences of this size as noise. Two AOT runs differed by under 7% on the p50 of every
row.

The numbers vary a little from run to run. `flutter test --tags benchmark` runs the same code
under the test runner (JIT, assertions on) and passed with similar numbers.

## How to run

```sh
# JIT, quick look
dart run tool/benchmark/run.dart

# AOT, for numbers worth quoting
dart compile exe tool/benchmark/run.dart -o build/benchmark/run.exe
build/benchmark/run.exe            # build\benchmark\run.exe in PowerShell
```

Both print the table and write `build/benchmark/results.json` and `results.md` (change it with `--out=<path>`;
`--chapters=<n>` and `--words-per-chapter=<n>` make a smaller run). The command exits 1 if fewer
than 28 of 30 cards open in under a second or whole-book extraction takes 60 s or more.

`flutter test --tags benchmark` runs the same code with loose budgets (whole book under 20 s,
at least 28 of 30 cards under 1 s, card p95 under 2 s). Normal CI skips it with
`--exclude-tags "live || benchmark"`, because timings on a shared runner are noise.

## Not measured yet

Passage search is merged, and it has its own timing test:
`flutter test --tags benchmark test/search/search_index_perf_test.dart` builds and queries the
index for a generated 500,000-word book (results in [search.md](search.md), host JIT timings). It
is not in this AOT runner yet. To add it, add two cases to `benchmarkCases` in
`tool/benchmark/benchmark.dart` (the list is marked as the extension point):

- search index build over `BenchmarkContext.sectionTexts`, as the "chapter processing" part
  that happens after extraction;
- search latency: p50 and p95 over a few hundred seeded queries at a late cutoff.

Also not covered: a phone. The numbers above are for a desktop CPU; this code has not been
timed on a mid-range device, so the large margin is the only evidence for the phone case.
