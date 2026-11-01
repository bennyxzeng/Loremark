# Reading insights

Reading insights run entirely on the device. Open a book, turn pages, then tap
**Reading insights** in the chapter bar. The sheet shows active reading today,
a 14-day chart, a streak (five minutes makes a day), pace, and time remaining.
The bottom label cycles between chapter time, book time and percent. It stays
at percent until six usable page turns or twenty pooled samples establish pace.
**Reading hints** turns the optional nudges off and survives an app restart.
No book text or reading events are sent to a service.

## Computation and integration

`FileReadingInsights.open(bookId:, epubPath:)` implements `ReadingInsights`.
`ReadScreen` records each position with a navigation cause, and pauses the log
when the app, Read tab, or reader text is covered. On disposal it flushes and
closes the service. Log failures leave the book usable, without estimates. The reader appears as
soon as the book and its saved position are ready; the insights open alongside
and attach when they arrive (the page then showing is logged as the open), so a
large book never delays the text.
Other consumers can listen to `signals` (`Stream<ConfusionSignal>`), read
`furthest`, or add a listener for summary changes. Close the service when its
book closes; only one instance per book should write at a time.

`BookUnits` counts whitespace-delimited words and CJK characters in an isolate.
The position log stores exact progression, section, cause and timestamp, never
text. `ViewTracker` sessionizes idle gaps and excludes background time. Dwells
below three seconds are flip-throughs; time above two minutes is capped.
Pace uses first-read forward page turns, a trimmed ratio of total time to text
units, and a prior from the reader's other books with the same word/character units. Contents/search jumps and
revisits do not establish pace. A page's length is the median of recent
forward turns. Until five are seen, a longer move within a section that was
read for a normal time (up to four default pages) also counts as one, so a
tablet or small type, with pages beyond the usual swipe limit, can still
teach it. The estimate is approximate: EPUB progression
is a location fraction, not a measured word boundary or eye-tracking signal.

Confusion detection is deliberately explainable: repeated backward visits to
an overlapping span, unusually slow dwell followed by looking back (median/MAD
of log pace), and repeated chapter bounces. Search bursts can corroborate a
signal but never nudge alone. `InsightsConfig` holds the thresholds. The nudge
policy adds warmup, per-span deduplication, 30 minutes plus 25 forward pages
between prompts, and session/day limits. Dismissal suppresses later prompts.
These are heuristics, not validated diagnoses; synthetic tests verify the rules.
The Story Map action uses the existing Story Map tab. Search is a callback for
the passage-search integration; this independent feature branch does not own it.

`furthest` is the *contiguous reading frontier*, not the furthest visited
position. It advances only through continuous reading: a forward page turn or
swipe of about a page from a page at or just behind the frontier, including the
two positions of a section turn. A contents or search jump, or a swipe over many
pages, records where the reader is but leaves the frontier alone, and so does
reading on from there. When a book opens a few pages ahead of the frontier (the
reader turned pages before the log was ready) it catches up. Pages behind the
frontier are revisits for pace and totals; pages ahead of it are new. The
frontier is what `FurthestRecord` keeps through compaction, and search uses it
(alone, not the current page) as its cutoff, so jumping to the last chapter
never opens the chapters in between.
TODO(kevin): use Grisha's authoritative spoiler boundary once his tracker lands;
this log must not replace jump confirmation or decide which future chapters a
reader deliberately unlocked. Consumers should enforce their own hard cutoff.

## Storage and recovery

Under the application support directory's `library/reading_log/`:

- `<book id>.jsonl`: versioned append-only position/lifecycle events.
- `<book id>.stats.json`: atomic summary used by other books for pace and totals.
- `<book id>.units.json`: the counted size of each section, keyed by book id
  (the EPUB's hash) and a format version, so later opens skip unzipping and
  counting. A missing, damaged or old file is counted again.
- `settings.json`: persisted Reading hints setting.

Writes queue in order and coalesce same-turn events. Hiding/closing flushes to
storage. A torn JSONL line is skipped; the next append begins a new line. A position or
furthest record naming a section the book doesn't have (a damaged line) is
ignored when replayed, so it can't widen what search opens.
A newer log format is read-only to avoid an older app damaging it. Old events
are compacted in an isolate when a book opens, into daily totals plus furthest
position, retaining recent raw events for replay. The byte limits first reduce
retention (60 days, then 14). If recent events alone still exceed the cap, the
oldest raw prefix becomes daily totals while the newest session/position
checkpoint stays. The byte budget has an unavoidable minimum: header, one
summary per historical day, furthest position and live checkpoint. Extremely
small configured budgets below that minimum cannot be met without discarding
historical totals. This can shorten the detector/pace replay window, but not
forget the furthest position or recorded reading time. A crash cannot reveal
how long its final page was read: replay credits at most one capped dwell.
Summaries of other books update when those books flush/close; they are not a
live cross-book analytics service.

## Validation

Run `flutter analyze` and `flutter test --exclude-tags live`. Deterministic tests
cover dwell and session boundaries, CJK units, pace and daily totals, all detector
rules, nudge cooldowns, settings, corruption/crash replay, compaction, concurrent
close, and reader lifecycle/tab visibility. Widget tests use fake readers;
Android Readium and platform lifecycle still require device verification.

## Sources consulted

The design takes the min/max dwell and suspend/resume ideas from
[KOReader's statistics plugin](https://github.com/koreader/koreader/blob/master/plugins/statistics.koplugin/main.lua)
(AGPL; no source code copied). Its defaults are 5 and 120 seconds; Loremark uses
3 and 120. The lifecycle wiring follows Flutter's
[AppLifecycleListener](https://api.flutter.dev/flutter/widgets/AppLifecycleListener-class.html).
The statistical thresholds are explicit product choices, not claims from those
projects. No dependencies were added.
