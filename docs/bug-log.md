# Bug Log

Every bug and failed check we know of, from the start of the project to 2026-11-02.

**How this log was made.** While we built features, each bug was written up where it was fixed:
the fix commit's message says what went wrong, why, and how it was fixed, and CI and the coding
session notes kept the failures. That record stayed on each developer's branches instead of in a
shared tracker. On 2026-11-02 we gathered it into this log and into GitHub Issues (#17 to #52),
where the team tracks bugs from now on. The sources were:

- **Git history:** every commit whose message starts with `fix`, plus commits that fixed problems
  found by testing (on every branch on GitHub).
- **CI history:** all 47 GitHub Actions runs (41 passed, 4 failed, 2 cancelled). Both cancelled
  runs were stopped by a newer push to the same branch, not by a failure.
- **Agent session notes:** the notes kept by the coding-agent sessions, which recorded what was
  found on the emulator and why.
- **Discord:** bugs teammates reported in #general.

What it cannot include: test failures on our own machines that were fixed before anything was
pushed. Only CI keeps a record of failed runs.

Priorities and labels follow the living doc's Test Plan & Bugs section:

- **P0:** a spoiler leak, a crash, or lost data. Fixed before any new feature work.
- **P1:** a feature gives wrong results or is hard to use.
- **P2:** small or cosmetic problems.

## Summary

| | Count |
| :--- | :--- |
| App bugs fixed and merged into `ui` | 18 (7 of them P0) |
| App bugs fixed in reading insights (PR #13, merges after the beta) | 9 (2 of them P0) |
| Test-harness and CI failures | 5 (4 fixed, 1 worked around) |
| Still open | 5 |

Nearly every fix came with a regression test. The exceptions are the build fixes (they change
build settings, not app code) and one cosmetic text fix; each row says which.

## All bugs

Each ID links to its GitHub issue (#17 to #53). Commit hashes link to
`https://github.com/bennyxzeng/Loremark/commit/<hash>`. CI runs link to
`https://github.com/bennyxzeng/Loremark/actions/runs/<id>`.

| ID | Found | Priority | Label | What went wrong | Status | Fix |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| [BUG-01](https://github.com/bennyxzeng/Loremark/issues/17) | 2026-10-26 | P1 | bug | `flutter analyze` failed on `ui` because the template test still used `MyApp` | Fixed | `d25327b` (PR #1) |
| [BUG-02](https://github.com/bennyxzeng/Loremark/issues/18) | 2026-10-31 | P1 | bug | Android build failed when the project and the build tools were on different disks | Fixed | `796164f` |
| [BUG-03](https://github.com/bennyxzeng/Loremark/issues/19) | 2026-11-01 | P1 | bug | The last page of a chapter never counted as finished, so the end of a book was never reached | Fixed | `cdc3ec2` (PR #6) |
| [BUG-04](https://github.com/bennyxzeng/Loremark/issues/20) | 2026-11-01 | P1 | crash | Closing one book could close the next book opened right after it | Fixed | `f235ccd` (PR #6) |
| [BUG-05](https://github.com/bennyxzeng/Loremark/issues/21) | 2026-11-01 | P0 | spoiler | Jumping ahead marked the chapters you skipped as finished | Fixed | `f235ccd` (PR #6) |
| [BUG-06](https://github.com/bennyxzeng/Loremark/issues/22) | 2026-11-01 | P0 | bug | Saving a reading position erased other saved data | Fixed | `426ba8b` (PR #6) |
| [BUG-07](https://github.com/bennyxzeng/Loremark/issues/23) | 2026-11-01 | P0 | spoiler | Search ranking and word stemming were influenced by text the reader had not reached | Fixed | `92c0944` (PR #10) |
| [BUG-08](https://github.com/bennyxzeng/Loremark/issues/24) | 2026-11-01 | P0 | spoiler | The search cutoff could fall partway into a page the reader had not finished | Fixed | `0e47427` (PR #10) |
| [BUG-09](https://github.com/bennyxzeng/Loremark/issues/25) | 2026-11-01 | P0 | spoiler | Search said how many matches were in unread chapters | Fixed | `5f7b07b` (PR #10) |
| [BUG-10](https://github.com/bennyxzeng/Loremark/issues/26) | 2026-11-01 | P1 | bug | Search could not find "Gatsby" in *The Great Gatsby* until chapter 6 | Fixed | `415da5b` (PR #10) |
| [BUG-11](https://github.com/bennyxzeng/Loremark/issues/27) | 2026-11-01 | P1 | bug | The script that marks the end of the page loaded as a web page instead of a script | Fixed | `415da5b` (PR #10) |
| [BUG-12](https://github.com/bennyxzeng/Loremark/issues/28) | 2026-11-01 | P1 | usability | Books with no usable table of contents had no Contents list | Fixed | `950bc6d` (PR #16) |
| [BUG-13](https://github.com/bennyxzeng/Loremark/issues/29) | 2026-11-01 | P1 | bug | Choosing a chapter in another file opened that file's last page | Fixed | `950bc6d` (PR #16) |
| [BUG-14](https://github.com/bennyxzeng/Loremark/issues/30) | 2026-11-01 | P1 | bug | The chapter bar named the wrong chapter when several chapters share one file | Fixed | `950bc6d`, `eacf524` (PR #16) |
| [BUG-15](https://github.com/bennyxzeng/Loremark/issues/31) | 2026-11-01 | P0 | spoiler | Right-to-left books (Hebrew, Arabic) marked each file finished on its first page | Fixed | `e4462fc` (PR #16) |
| [BUG-16](https://github.com/bennyxzeng/Loremark/issues/32) | 2026-11-01 | P2 | usability | Very large books without a table of contents froze the screen for over a second | Fixed | `e4462fc` (PR #16) |
| [BUG-17](https://github.com/bennyxzeng/Loremark/issues/33) | 2026-11-01 | P0 | spoiler | A miscount between the page and our copy of the chapter could unlock too much text | Fixed | `eacf524` (PR #16) |
| [BUG-18](https://github.com/bennyxzeng/Loremark/issues/34) | 2026-11-02 | P1 | bug | iOS could not open any EPUB and called it "damaged" | Fixed | `9def285` (PR #15) |
| [INS-01](https://github.com/bennyxzeng/Loremark/issues/35) | 2026-11-01 | P0 | spoiler | Jumping ahead and back made search open every chapter | Fixed, PR #13 | `ce58ab6` |
| [INS-02](https://github.com/bennyxzeng/Loremark/issues/36) | 2026-11-01 | P0 | spoiler | A damaged reading-log line could make search open the whole book | Fixed, PR #13 | `dff3096` |
| [INS-03](https://github.com/bennyxzeng/Loremark/issues/37) | 2026-11-01 | P1 | bug | Reading time kept counting while the Read tab was hidden | Fixed, PR #13 | `9075d7e` |
| [INS-04](https://github.com/bennyxzeng/Loremark/issues/38) | 2026-11-01 | P1 | bug | Tapping a hint's action counted as dismissing it | Fixed, PR #13 | `376b975` |
| [INS-05](https://github.com/bennyxzeng/Loremark/issues/39) | 2026-11-01 | P1 | bug | Readers with large pages (tablets, small text) never got a reading pace | Fixed, PR #13 | `1d84fbe` |
| [INS-06](https://github.com/bennyxzeng/Loremark/issues/40) | 2026-11-01 | P1 | usability | The reader waited for reading insights to load before showing the book | Fixed, PR #13 | `0f3b0fc` |
| [INS-07](https://github.com/bennyxzeng/Loremark/issues/41) | 2026-11-01 | P2 | bug | The reading log could grow past its size limit, and pace mixed languages | Fixed, PR #13 | `235d40b` |
| [INS-08](https://github.com/bennyxzeng/Loremark/issues/42) | 2026-11-01 | P2 | usability | A book opened for the first time showed numbers that looked like its own data | Fixed, PR #13 | `4ffa8e5` |
| [INS-09](https://github.com/bennyxzeng/Loremark/issues/43) | 2026-11-01 | P2 | bug | The story model loading text lost its "…" | Fixed, PR #13 | `1a2ec6d` |
| [CI-01](https://github.com/bennyxzeng/Loremark/issues/44) | 2026-11-01 | P0 | test-harness | The privacy capture check passed while looking at zero packets | Fixed | `3a112fc` (PR #11) |
| [CI-02](https://github.com/bennyxzeng/Loremark/issues/45) | 2026-11-01 | P1 | test-harness | The emulator workflow could not build the app (wrong Java version) | Fixed | `0fbc21c` (PR #11) |
| [CI-03](https://github.com/bennyxzeng/Loremark/issues/46) | 2026-11-01 | P1 | test-harness | The harness waited forever for the network after airplane mode | Fixed | `361033a` (PR #11) |
| [CI-04](https://github.com/bennyxzeng/Loremark/issues/47) | 2026-11-01 | P1 | test-harness | One force-quit trial failed on a rounding difference, not a real wrong page | Fixed | `27f5fae` (PR #11) |
| [CI-05](https://github.com/bennyxzeng/Loremark/issues/48) | 2026-11-01 | P2 | test-harness | CI failed whenever the capture could not be checked, even with every real check passing | Worked around | `e0d5fc8` (PR #11) |
| [OPEN-01](https://github.com/bennyxzeng/Loremark/issues/49) | 2026-11-02 | P2 | test-harness | One iOS-fix test fails on Windows only | Open | |
| [OPEN-02](https://github.com/bennyxzeng/Loremark/issues/50) | 2026-11-02 | P1 | AI-quality | Story-model quotes from the LLM differ from the book's text and fail validation | Open | |
| [OPEN-03](https://github.com/bennyxzeng/Loremark/issues/51) | 2026-11-02 | P1 | bug | Building after pulling `main` looped for 15 minutes on Vitalii's machine | Open, cause unknown | |
| [OPEN-04](https://github.com/bennyxzeng/Loremark/issues/52) | 2026-11-01 | P2 | test-harness | The emulator capture never contains the harness's DNS check lookups | Open, cause unknown | |
| [OPEN-05](https://github.com/bennyxzeng/Loremark/issues/53) | 2026-11-02 | P1 | timeline | The large-jump confirmation is never shown, because nothing in the app calls `ReadingProgressTracker` | Open | |

## Details

### App bugs merged into `ui`

**BUG-01: `flutter analyze` failed on `ui`.** Found 2026-10-26 by Greg. The Flutter template's
`test/widget_test.dart` still built `MyApp`, which the app had renamed to `LoremarkApp`, so the
analyzer failed on the integration branch. Fixed by replacing it with app smoke tests (`d25327b`,
then `846d68b`).

**BUG-02: Android build failed across disks.** Found 2026-10-31 by Vitalii. The build broke when
the project and the build tools were on different disks. Fixed in `796164f`. This is a build
setting, so there is no test.

**BUG-03: The end of a chapter never counted as finished.** Readium reports where a page *starts*,
so the last page of a chapter was always below 100%. flutter_readium 0.8.0 also never sends its
"end of book" event, so the book could never be finished. The app now uses the page number to
tell when the reader is on the last page (`cdc3ec2`). Has a test.

**BUG-04: Closing one book could close the next.** Opening and closing ran in parallel, so the
close of the old book could shut a book opened right after it. Open and close now run one at a
time (`f235ccd`). Has a test.

**BUG-05: Jumping ahead finished chapters (spoiler).** Leaving a chapter by jumping counted it as
finished, which would let search open chapters the reader skipped. Leaving a chapter before its
last page is now a jump, not a finished chapter (`f235ccd`). Has a test.

**BUG-06: Saving a position erased other data (lost data).** Saving one book's reading position
rewrote the whole file with only that key. It now keeps the other keys (`426ba8b`). Has a test.

**BUG-07: Unread text influenced search (spoiler).** Search guessed the book's language, which
picks how words are stemmed, from the whole book, including unread text. Unread text also
reached the ranking. Stemming is now always on and does not depend on unread text, and unread
text never reaches ranking (`92c0944`). Found during a code review of the search engine. Has
tests.

**BUG-08: The search cutoff could cut into an unfinished page (spoiler).** The renderer's layout
position cannot safely mark a point inside a chapter. The search screen now rounds the cutoff
down to the last fully finished section (`0e47427`). Has tests.

**BUG-09: Search counted matches ahead (spoiler).** Search said how many matches were in unread
chapters. How often a name or a word like "died" comes up later is itself a hint, so it now only
says that there are more matches ahead (`5f7b07b`). Has a test.

**BUG-10: "Gatsby" not found in *The Great Gatsby*.** Reported by Kevin on the emulator. The
book's first file holds chapters 1 to 5 (about 26,000 words), and search only opened whole
finished files, so nothing could be found until chapter 6. Search now covers every page read
(`415da5b`). Checked on the emulator: a word on the next page is not found, and is found after
turning the page.

**BUG-11: The page-end script loaded as a web page.** flutter_readium only serves its own files
and declared fonts, so the first device run got an HTML page instead of our script. The script is
now served by declaring it as a font file. Found on the emulator during PR #10.

**BUG-12: Books without a table of contents had no Contents list.** Reported by Kevin with the
no-contents Alice test book. Books with a missing, empty, single-entry or broken contents list
are now cut into sections of about 5,000 words, as the living doc plans for Risk 3 (`950bc6d`).
Checked on the emulator. Has tests.

**BUG-13: Choosing a chapter opened the wrong page.** In *Gatsby*, choosing chapter I from the
contents landed at the end of the file, because Readium treats a jump into another file like
turning back into it. The reader now asks again once the file shows (`950bc6d`). On the emulator,
jumps to I, III and IX land at 3%, 21% and 84%.

**BUG-14: The chapter bar named the wrong chapter.** When several chapters share one file, the bar
named them all as the last one. It now uses the chapter the renderer reports for the page, and
after a contents jump it keeps the chosen chapter until the reader moves (`950bc6d`, `eacf524`).

**BUG-15: Right-to-left books finished each file at once (spoiler).** Found by the 50-book corpus
test on the Hebrew book. Readium numbers right-to-left pages backwards, so the first page looked
like the last, the position said "chapter finished", and search opened the whole file. The page
number is now read in the right direction, and every page of files from 1 to 200 pages is
checked both ways (`e4462fc`). Has tests.

**BUG-16: Large books without a table of contents froze the screen.** Building the 5,000-word
sections ran on the screen's thread and took over a second for the biggest corpus book. It now
runs in the background (`e4462fc`).

**BUG-17: A page miscount could unlock unread text (spoiler).** Found while running the corpus
tests. If the page script and our copy of the chapter counted characters differently, the cutoff
could land past the page. The script now sends the last 12 characters before the page end, and
the app ignores the report if they don't match its own text (`eacf524`). No leak was seen; this
closes the path.

**BUG-18: iOS could not open EPUBs.** Found 2026-11-02 by Frank in the iOS simulator. The app
passed a `file://` address, but flutter_readium 0.8.0 on iOS needs a plain file path. The error
was shown as "this EPUB may be damaged", which hid the cause. iOS now gets a plain path and
Android keeps the address (`9def285`). Frank reported 197 related tests passing. Has a test.

### Reading insights (PR #13, merging after the beta)

These were found and fixed on `feat/reading-insights` before its pull request. They reach `ui`
when PR #13 merges.

**INS-01: Jumping ahead and back opened every chapter (spoiler).** A contents jump or a long swipe
moved the reader's "furthest point" ahead, so jumping to the last chapter and back made search
open everything. The furthest point now only moves through continuous page turns (`ce58ab6`).
Has tests.

**INS-02: A damaged log line could open the whole book (spoiler).** A broken line naming section
999 became the furthest point. Positions in sections the book doesn't have are now ignored
(`dff3096`). Has tests.

**INS-03: Hidden time counted as reading.** Reading time kept counting while the Read tab was
hidden behind another tab or a sheet. Tracking now pauses when the reader is not visible
(`9075d7e`).

**INS-04: Taking a hint counted as dismissing it.** Tapping "See who's who" or "Search this
chapter" counted as a dismissal, which hid hints for an hour (`376b975`). Has tests.

**INS-05: Large pages never got a pace.** On tablets or with small text, every page turn looked
like a jump, so the app never learned the reader's pace (`1d84fbe`). Has tests.

**INS-06: The reader waited for insights.** The book did not appear until the insights had
unzipped and counted the whole EPUB. The reader now shows first and insights attach after
(`0f3b0fc`). Has tests.

**INS-07: The reading log could outgrow its limit.** Old events are now folded into daily totals
to keep the log under its size cap, and reading pace only compares books in the same writing
system (`235d40b`). Has tests.

**INS-08: First-open numbers looked like book data.** A book opened for the first time showed
today's minutes (from all books) and a default pace of 230 words a minute. The labels now say
what they are (`4ffa8e5`). Has a test.

**INS-09: Missing "…" in the loading text.** Cosmetic (`1a2ec6d`). No test.

### Test-harness and CI failures

These were bugs in our test tools, not the app. CI-01 matters most: a check that passes without
looking is worse than no check.

**CI-01: The privacy check passed without looking.** The emulator stamps captured packets with
local time as if it were UTC, so the session's time window matched no packets and the check
passed with nothing in it. The harness now looks up a unique web address before and after the
session, uses those lookups to line up the clock, and reports INCONCLUSIVE, never PASS, if it
can't find them (`3a112fc`). Has tests.

**CI-02: CI could not build the app.** First emulator run,
[41358068972](https://github.com/bennyxzeng/Loremark/actions/runs/41358068972): flutter_readium
needs Java 18 or later, and the runner used 17 ("invalid source release: 18"). The workflow now
uses Java 21 (`0fbc21c`).

**CI-03: The harness waited forever for the network.** Runs
[41358604715](https://github.com/bennyxzeng/Loremark/actions/runs/41358604715): GitHub's runners
block ping, so after airplane mode was turned off the harness never saw the network come back
("Airplane mode off did not take effect"). It now checks by looking up a web address instead
(`361033a`).

**CI-04: A force-quit trial failed on rounding.** Run
[41359690539](https://github.com/bennyxzeng/Loremark/actions/runs/41359690539): 19 of 20 trials
passed. The one failure was measured from the saved file's page, which is converted from a
percentage and can round one page off. The living doc measures where the app reopens, so the
trial now judges that, and still reports the saved page (`27f5fae`).

**CI-05: CI failed on a capture it could not check.** Runs
[41359690539](https://github.com/bennyxzeng/Loremark/actions/runs/41359690539) and
[41361493120](https://github.com/bennyxzeng/Loremark/actions/runs/41361493120): every real check
passed (20 of 20 force-quits, offline, open from library, 0 bytes of app traffic), but the job
failed because the capture did not contain the harness's address lookups (CI-01's check). The
new `--capture-optional` flag reports such a capture as INCONCLUSIVE without failing the run;
any failed trial, any app traffic, or a verified capture showing a violation still fails it
(`e0d5fc8`). The flag must come off once the app makes any network request. Every emulator run
since has passed.

### Still open

**OPEN-01: A test fails on Windows only.** The iOS fix's test "native file location Android
receives an encoded file URI" fails on Windows because Windows paths use `\`. It fails the same
way on `main`, and passes in CI, which runs Linux. Low priority: the app itself is unaffected.

**OPEN-02: Story-model quotes don't match the book.** Reported by Frank on 2026-11-02 after trying
DeepSeek and ChatGPT. The LLM's quotes differ slightly from the book's text, so the story model's
own validation rejects them. Frank is choosing between prompt changes, close matching, or
removing the check. Removing it would weaken the citation rule in the Test Plan's
nondeterministic criteria.

**OPEN-03: A build loop after pulling `main`.** Reported by Vitalii on 2026-11-02: the build looped
for 15 minutes, then finished with a lot of errors. The cause is unknown, since the error log
wasn't readable in Discord. One guess is the missing Android SDK Platform 37. CI only formats,
analyzes and tests; it does not build the app, so a green CI run doesn't rule this out.

**OPEN-04: Why the capture misses the lookups.** CI-05 works around this but does not fix it. It
happens on GitHub's runners and on Windows. The raw capture is now saved with every report, so
the next run can show whether the capture is empty or only the lookups are missing.

**OPEN-05: The large-jump confirmation is never shown.** Found on 2026-11-02 while checking the
test plan against the code. The plan says a big jump asks the reader to confirm before the skipped
sections count as read. `ReadingProgressTracker` (PR #2) implements that rule and its tests pass,
but nothing in `lib/` creates or calls it, so no confirmation appears. The reader still refuses to
count a jumped-over chapter as finished (BUG-05), so search does not open skipped chapters; what
is missing is the confirmation itself. Fix: call the tracker from the Read tab, show the
confirmation, and add a widget test.
