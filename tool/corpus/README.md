# Corpus testing

Runs the app's EPUB, table-of-contents and search code over 50 real books and
24 variants made from them. Results and how to read them are in
[docs/corpus-testing.md](../../docs/corpus-testing.md).

The books are public domain, from Project Gutenberg. They are not kept in the
repository (about 280 MB); `gather.py` fetches them.

```bash
# 1. Download 50 books into <corpus>/raw (one folder per book), politely.
python -X utf8 -I tool/corpus/gather.py <corpus>/raw

# 2. Make the variants: no table of contents, a broken one, everything in one
#    file, truncated zips. Written to <corpus>/variants.
python -X utf8 -I tool/corpus/mutate.py <corpus>/raw <corpus>/variants

# 3. Host checks, through the app's own code (about 10 minutes).
LOREMARK_CORPUS=<corpus> LOREMARK_CORPUS_OUT=<corpus>/results.jsonl \
  flutter test --tags corpus test/corpus
#    LOREMARK_CORPUS_ONLY=84,1661-notoc  limits it to some folders.

# 4. Device checks, with the real renderer. Needs a debug build installed on one
#    running emulator (adb on PATH, or set ADB). About 2 minutes a book.
python -X utf8 -I tool/corpus/device_run.py <corpus> <corpus>/device.jsonl \
  64317 11 84 84-onefile 11-notoc

# 5. Turn the results into the tables in docs/corpus-testing.md.
python -X utf8 -I tool/corpus/report.py <corpus> > report.md
```

Run the scripts with `-I` and keep the corpus outside the repository. The books
and the files made from them are untrusted input: the scripts only read them as
zip data.

`device_run.py` types search words with `adb shell input text`, which can only
type ASCII, so it skips the search check for books whose rare words would not
be (Chinese, Japanese, Hebrew and Arabic). Those are covered by the host checks.
