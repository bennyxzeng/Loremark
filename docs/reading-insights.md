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
closes the service. Log failures leave the book usable, without estimates.
Other consumers can listen to `signals` (`Stream<ConfusionSignal>`), read
`furthest`, or add a listener for summary changes. Close the service when its
book closes; only one instance per book should write at a time.

`BookUnits` counts whitespace-delimited words and CJK characters in an isolate.
The position log stores exact progression, section, cause and timestamp, never
text. `ViewTracker` sessionizes idle gaps and excludes background time. Dwells
below three seconds are flip-throughs; time above two minutes is capped.
Pace uses first-read forward page turns, a trimmed ratio of total time to text
units, and a prior from the reader's other books. Contents/search jumps and
revisits do not establish pace. The estimate is approximate: EPUB progression
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

`furthest` means the furthest *visited* position, including contents jumps.
TODO(kevin): use Grisha's authoritative spoiler boundary once his tracker lands;
this log must not replace jump confirmation or decide which future chapters a
reader deliberately unlocked. Consumers should enforce their own hard cutoff.

## Storage and recovery

Under the application support directory's `library/reading_log/`:

- `<book id>.jsonl`: versioned append-only position/lifecycle events.
- `<book id>.stats.json`: atomic summary used by other books for pace and totals.
- `settings.json`: persisted Reading hints setting.

Writes queue in order and coalesce same-turn events. Hiding/closing flushes to
storage. A torn JSONL line is skipped; the next append begins a new line.
A newer log format is read-only to avoid an older app damaging it. Old events
are compacted in an isolate when a book opens, into daily totals plus furthest
position, retaining recent raw events for replay. The byte limits trigger
retention reduction (60 days, then 14), rather than guaranteeing a strict byte
ceiling for unusually intense activity within those days. A crash cannot reveal
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
