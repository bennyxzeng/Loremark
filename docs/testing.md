# Testing and Continuous Integration

This page says what we test today, how the tests run, and what is not tested yet. It extends the
test plan in our living document (Process description → Test Plan & Bugs). Where the plan
describes something we have not built or run, this page says so.

## At a glance

- **Tests in CI:** CI runs `flutter test --exclude-tags "live || benchmark"` on every push and
  pull request. The same command run in full on Windows on 2026-11-02 found 726 tests:
  724 passed, 1 skipped, 1 failed. The skip is the 50-book corpus test, which needs the books
  (`LOREMARK_CORPUS`). The failure is one test of how file locations are passed to Android
  (`readium_session_test.dart`, "Android receives an encoded file URI"). It fails only on
  Windows, because Windows paths use `\` (issue #49), and it passes on the Linux CI runner.
- **Emulator acceptance workflow:** a separate GitHub Actions workflow runs 20 force-quits,
  offline reading and a network-traffic check on an Android emulator. It runs by hand, every
  Monday, and on pull requests labeled `device-tests`. The latest run passed (see
  [Evidence](#evidence)). Details are in [acceptance.md](acceptance.md).
- **Suites we run by hand:** the 500,000-word benchmark ([benchmarks.md](benchmarks.md)) and the
  50-book corpus ([corpus-testing.md](corpus-testing.md)). Neither runs in CI.
- **Bug tracking:** 36 bugs are in GitHub Issues (32 closed, 4 open), listed in
  [bug-log.md](bug-log.md).
- **Code coverage:** <!-- CODE COVERAGE NUMBER -->

Not tested yet: everything that needs the AI client (which does not exist in `lib/` yet), notes
and theories on `ui`, the end-to-end flow as an `integration_test`, the weekly spoiler review and
usability sessions. See [Not automated yet](#not-automated-yet).

## Test plan status

Statuses: **Automated (CI)** runs on every push and pull request. **Automated (emulator)** runs
in the emulator workflow. **Automated (run by hand)** is automated but we start it ourselves.
**Partly automated** has gaps, named in Notes. **Manual** is done by people. **Planned** is not
built or run yet.

| Test plan item | Status | Where / how | Notes |
| :--- | :--- | :--- | :--- |
| EPUB reader: a big jump asks the user to confirm before sections count as read | Partly automated | `ReadingProgressTracker`: `test/reading/reading_progress_tracker_test.dart`, "big jump needs confirmation and keeps the boundary" | The rule is tested in sections (more than 2 sections ahead), not pages. No screen asks the user yet: nothing in `lib/` calls the tracker. |
| EPUB reader: position, sections, table of contents, page ends | Automated (CI) | `test/reader/`, `test/home/read_screen_test.dart`, `test/library/` | Uses a fake reader. The real renderer needs a device (emulator rows below). |
| Story model: relationships that change across chapters, aliases connected only after the reveal | Partly automated | `test/story_model/story_snapshot_test.dart`, "merges entities with a revealed identity" and "applies the rename"; `test/acceptance/story_model_spoiler_test.dart`, "identity links merge entities only once revealed" | No test names a relationship that changes (enemies in chapter 12, allies from chapter 16). Changes are tested in general (supersede, retract, resolve). More story-model tests are on Frank's `story-model` branch, not merged. |
| Story model: nothing past the reader is shown | Automated (CI) | `test/acceptance/story_model_spoiler_test.dart`, "shows nothing past the reader in any section", on the bundled model and seeded synthetic models; "audit catches planted leaks" checks that the audit can fail | Synthetic models have made-up facts. The audit does not cover a real book's model. |
| Notes: create, edit, delete, save | Planned | Tests are written in PR #12 (about 720 lines in `test/notes/` and `test/home/notes_screen_test.dart`) | Not on `ui` until PR #12 merges. |
| Theories: status Correct / Partially Correct / Wrong | Planned | None | Theories are deferred until after the beta. |
| AI request coordinator: `ContextManager` retrieves only within the reading cutoff; `ResponseValidator` rejects bad formats and references past the cutoff | Planned | None | No `ContextManager`, `ResponseValidator` or LLM client in `lib/` yet. The text the AI will be given is built by `PassageExtractor`, which is tested: `test/reading/passage_extractor_test.dart`, "never returns text past the boundary for any input". |
| Local data storage: read, write, missing and corrupted files, interrupted saves | Automated (CI) | Reading position: `test/reader/reading_position_store_test.dart`, "has no position for a book never saved", the group "a file that cannot be read", "ignores a leftover temporary file", the group "a failed write". Search index: `test/search/search_index_store_test.dart`, "a damaged file is replaced by a fresh index". Library: `test/library/book_repository_test.dart` | Covers the stores that exist today. Notes storage comes with PR #12. |
| API errors: invalid keys, rate limits, timeouts, malformed responses | Planned | None | No API code yet. |
| Nondeterministic prompt tests: prompts never see text past the reader, answers cite passages, notes are not treated as facts | Planned | The `live` tag is registered in `dart_test.yaml`; no test uses it | Needs the AI client. Run by hand when it exists, because it costs money and the output varies (Risk 4). |
| Full flow: import a book, process a few chapters, character cards show only what the reader has seen | Partly automated | Import: `test/library/`. Cards follow the reader: `test/story_map/story_map_screen_test.dart`. Open from the library on a device: emulator workflow | No end-to-end test, and there is no `integration_test/` folder. "Process a few chapters" needs the AI client. |
| Full flow on EPUBs with different structures (Risk 3): edge cases | Automated (CI) | `test/corpus/edge_cases_test.dart` (odd markup, entities, ruby, nesting, a 2 MB paragraph, strange queries) | Hand-built cases only. |
| Full flow on EPUBs with different structures (Risk 3): 50 real books | Automated (run by hand) | `flutter test --tags corpus test/corpus` with `LOREMARK_CORPUS` set, then `tool/corpus/device_run.py` on an emulator ([corpus-testing.md](corpus-testing.md)) | Needs about 300 MB of books and, for the device part, an emulator. |
| Spoiler test: two teammates check 150 fixed questions across 3 books weekly | Planned | None | Needs AI answers to review. Starts once the AI client exists. |
| Search never shows unread text (not listed separately in the plan) | Automated (CI) | `test/search/spoiler_property_test.dart`, "no result, score, snippet or count depends on text past the cutoff"; `test/search/search_cutoff_test.dart`, "renderer percentages never reveal text in an unfinished section"; `test/home/read_screen_search_test.dart` | Also run on the 50 books by hand (row above). |
| Reliability: force-quit 20 times, reopens within one page of the last position | Automated (emulator) | `tool/acceptance/run.dart`, [acceptance.md](acceptance.md) | Measured on a generated 12-chapter book, not on real books. The latest run passed 20 of 20. |
| Reliability: offline reading works | Automated (emulator) | Same harness: airplane mode, open the book, turn pages, force-stop, reopen | Reading only. |
| Reliability: offline notes work and the AI is blocked | Planned | None | Notes are not on `ui` yet (PR #12) and there is no AI to block. |
| Scalability: each chapter of a 500,000-word book processes in under a minute | Automated (run by hand) | `dart run tool/benchmark/run.dart`, `flutter test --tags benchmark` ([benchmarks.md](benchmarks.md)) | Measures text extraction only (0.17 s for the whole book). The AI step is not measured because it does not exist. Run on a desktop, not a phone. |
| Scalability: 28 of 30 character cards open within a second | Automated (run by hand) | Same benchmark. 30 of 30 opened in under 1 s | Uses a synthetic story model of the spec's size (about 20,000 records). Run on a desktop. |
| Privacy: all traffic is HTTPS, no unexpected destination | Automated (emulator) | Per-UID byte counters and a packet capture in the emulator workflow | Today the app makes no requests. The counters show 0 bytes. The capture check is inconclusive (issue #52), so the counters are the evidence. |
| Privacy: no request has more than one chapter; notes only sent for recaps, chat and theory checks | Planned | None | A capture cannot read encrypted request bodies. Needs the AI client and a debug request log ([acceptance.md](acceptance.md#what-the-privacy-audit-cannot-see-yet)). |
| Usability testing with outside readers | Planned | None | No session has been run. |
| Bugs tracked in GitHub Issues with a template and P0/P1/P2 | Manual | `.github/ISSUE_TEMPLATE/bug_report.yml`; [Bug tracking](#bug-tracking) | 36 issues so far. |

## Test automation infrastructure

We use [`flutter_test`](https://api.flutter.dev/flutter/flutter_test/), which is built on
[`package:test`](https://pub.dev/packages/test). Tests live in `test/`, mostly mirroring `lib/`,
and run with `flutter test`. It covers both kinds of automated test the app needs today:

- **Unit tests** (`test(...)`) for plain Dart logic: the reading position and large-jump check,
  the versioned story model, passage extraction, the search index, and local JSON storage for the
  reading position and the search index.
- **Widget tests** (`testWidgets(...)`) that build screens in memory and tap, scroll and read
  them without a device, for example "the chapter slider cannot pass the reader's position".

Tests for the AI request coordinator, API errors and theories will use the same framework once
that code exists.

### Why this framework

- **`flutter_test` is the Flutter SDK's own test framework.** It ships with Flutter, so there is
  nothing extra to install or keep compatible. It is the only framework that can pump Flutter
  widgets without a device, which a general Dart runner cannot do.
- **One command for the whole app.** `flutter test` runs unit and widget tests together, and the
  same command runs locally and in CI.
- **Tags fit our test plan.** `dart_test.yaml` registers three tags. `benchmark` marks timing
  tests and `corpus` marks tests over a folder of real books; both are in use. `live` is meant for
  tests that call a real LLM and is registered, but no test uses it yet because there is no AI
  client. CI excludes `live` and `benchmark`, and `corpus` tests skip themselves without books.
  This matches the plan's split between deterministic unit tests and separate nondeterministic
  prompt runs.

Tests that need a real device or emulator (force-quit, offline, privacy) are not `flutter_test`
tests. A Dart harness drives the app through `adb` ([acceptance.md](acceptance.md)). Its pure
parts are unit tested in `test/acceptance/`.

## How to add a new test

Each feature pull request includes tests for that feature, following the test plan's schedule
of testing components as they are built. For example, the reading position PR adds
`test/reading/`. The tests in `test/widget_test.dart` are only smoke tests for the app shell.

1. **Create the file** under `test/`, mirroring the path of the code under test and ending in
   `_test.dart`. For `lib/reading/text_position.dart` the test is
   `test/reading/text_position_test.dart`. `flutter test` finds every `*_test.dart` file
   automatically, and CI picks it up with no configuration change.
2. **Write the test.** Import the code with a `package:loremark/...` import:

   ```dart
   import 'package:flutter_test/flutter_test.dart';
   import 'package:loremark/reading/text_position.dart';

   void main() {
     test('an earlier chapter is before a later one', () {
       expect(const TextPosition(1, 0.9) < const TextPosition(2, 0.1), isTrue);
     });
   }
   ```

   Use `testWidgets` instead of `test` for UI; see `test/widget_test.dart`. Group related
   cases with `group(...)`.
3. **Do not call a real LLM in a normal test.** This rule applies once the AI client exists;
   there is no `LLMClient` yet. Then, pass a fake `LLMClient` that returns a fixed response. A
   test that must call a real provider goes in its own file tagged `live`:

   ```dart
   @Tags(['live'])
   library;
   ```

   Skip the test when the API key is missing, so `flutter test --tags live` never fails just
   because a key is not set.
4. **Run the same checks CI runs** before pushing:

   ```bash
   flutter pub get
   dart format .
   flutter analyze
   flutter test --exclude-tags "live || benchmark"
   ```

   Run a single file with `flutter test test/reading/text_position_test.dart`, or one test by
   name with `flutter test --plain-name 'an earlier chapter'`.
5. **Open a pull request.** CI runs the new test automatically.

## Continuous integration

### Service and how the repository is linked to it

We use **GitHub Actions**. It is built into GitHub, so there is no external account or access
token to set up. The link between CI and the repository is the workflow file committed at
`.github/workflows/ci.yml`, which defines one job, `Flutter (format, analyze, test)`.

GitHub reads this file on every matching event and runs the job on a fresh GitHub-hosted
Ubuntu runner. The job checks out the commit with `actions/checkout`, using the
`GITHUB_TOKEN` that GitHub creates for each run. The workflow only requests
`contents: read` permission and uses no secrets, so pull requests from forks run safely. Results
appear as checks on the commit and the pull request, and in the repository's **Actions** tab.

To reproduce the setup in another repository:

1. Copy `ci.yml` into `.github/workflows/` and push it. GitHub Actions is enabled by default, so
   the workflow starts running on the next pull request or push to `main` or `ui`.
2. Check that **Settings → Actions → General → Actions permissions** allows actions to run.
3. Make CI block merging (a repository admin does this once): in
   **Settings → Branches → Add branch ruleset** (or **Add classic branch protection rule**) for
   `main`, turn on **Require a pull request before merging** with one approval, and
   **Require status checks to pass**, then select the `Flutter (format, analyze, test)` check.

### Why GitHub Actions

- **Already where our code is.** Our repository, pull requests, code review and bug issues are
  all on GitHub. Checks appear directly on each pull request, and branch protection can require
  them without another service.
- **Free for our use.** Public repositories get unlimited minutes on standard GitHub-hosted
  runners, and private repositories get a monthly free quota. Travis CI and CircleCI use
  credit-based plans, so a busy week of pull requests could run out of free builds.
- **Ready-made Flutter support.** `subosito/flutter-action` installs and caches an exact Flutter
  version in one step.
- **macOS runners are available** when we add iOS builds and simulator integration tests,
  without changing services.
- **Less setup than Azure Pipelines,** which needs a separate Azure DevOps organization and
  project linked to GitHub.

### What a CI build runs

The `CI` workflow uses Flutter **3.47.7**, the version in `.metadata`, so CI and our machines
agree. If the team upgrades Flutter, update `flutter-version` in `ci.yml` in the same pull
request. The steps are:

1. `flutter pub get --enforce-lockfile`: installs the exact versions in `pubspec.lock`, and fails
   if `pubspec.yaml` changed without updating the lock file.
2. `dart format --output=none --set-exit-if-changed .`: fails if any file is not formatted
   (Effective Dart, as in [coding-guidelines.md](../coding-guidelines.md)).
3. `flutter analyze`: fails on any analyzer error, warning or `flutter_lints` issue.
4. `flutter test --coverage --exclude-tags "live || benchmark"`: runs the deterministic unit and
   widget tests and records coverage. It excludes provider calls and timing benchmarks.
5. A coverage report step writes the coverage to the job summary and uploads
   `coverage/lcov.info` as an artifact.

Any failing step fails the build and marks the commit or pull request with a red check.

### What triggers a CI build

| Action | Runs CI? |
| :--- | :--- |
| Open, push to, or reopen a pull request (into any branch) | Yes |
| Push or merge to `main` or `ui` (our integration branch) | Yes |
| Manual run (**Actions → CI → Run workflow**) | Yes |
| Push to a feature branch with no pull request | No |

Feature-branch pushes are checked once a pull request is open, so each change is tested once
instead of twice. Pushes to `ui` and `main` are checked again after merging, because two pull
requests can each pass on their own but break once combined. A newer push to the same pull
request cancels the older run that is still in progress.

The emulator workflow (`.github/workflows/acceptance.yml`) is separate, because it takes about 20
minutes. It runs by hand, every Monday at 09:00 UTC, and on pull requests labeled
`device-tests`. GitHub starts the manual and Monday runs only for workflow files on the default
branch.

## Code coverage

<!-- CODE COVERAGE SECTION -->

## Bug tracking

Bugs are tracked in GitHub Issues. Anyone can open one with the **Bug report** form
(`.github/ISSUE_TEMPLATE/bug_report.yml`). The form follows the living doc's Test Plan & Bugs
section and asks for:

- **Priority** (required): P0 is a spoiler leak, a crash or lost data; P1 is wrong results or
  hard to use; P2 is small or cosmetic.
- **Environment** (required): device or runner, and how the app was run.
- **Steps to reproduce**, **Expected** and **Actual** (all required).
- **Book / chapter** (optional).
- **Build / commit** (required): branch and commit hash, or the CI run link.

The form adds the `bug` label. We also label each issue with its priority (`P0`, `P1`, `P2`) and,
where one fits, `spoiler`, `crash`, `AI-quality`, `timeline`, `usability` or `test-harness`. The
assignee is set in the issue's sidebar. P0 bugs are fixed before new feature work.

An issue is closed with a comment that names the fix commit.

Many of our bugs were written up in fix commits, CI runs and session notes first. On 2026-11-02
we collected them into Issues #17 to #52 and into [bug-log.md](bug-log.md). So far there are 36
issues: 32 closed and 4 open. Ten are P0 (nine in the app, one in the test harness).

## Not automated yet

| What | Why not yet | When |
| :--- | :--- | :--- |
| Tests for the AI request coordinator, API errors and the `live` prompt tests | There is no LLM client, `ContextManager`, `ResponseValidator` or API code in `lib/`. The `live` tag is registered; no test uses it. | Written with each piece as it lands. `live` tests stay manual (Risk 4). |
| Notes tests | Written in PR #12, not merged into `ui`. | When PR #12 merges. |
| Theory tests | Theories are deferred. | After the beta. |
| Large-jump confirmation on screen | The tracker logic is tested, but nothing in the app calls it yet. | When the confirmation is wired in. |
| End-to-end flow as a Flutter `integration_test` | There is no `integration_test/` folder. The "process chapters" step needs the AI client. | After the beta. |
| Privacy: request size and what notes are sent | Encrypted request bodies cannot be read from a capture. | When the AI client exists. See [acceptance.md](acceptance.md#what-the-privacy-audit-cannot-see-yet). |
| Privacy capture check (issue #52) | The harness's DNS probe never shows up in the emulator's capture, so the capture is inconclusive on CI and the workflow runs with `--capture-optional`. The per-UID counters are the evidence for now. | Before the app makes its first network request. |
| iOS build and tests in CI | They need a macOS runner. CI builds and tests on Linux only. | After the beta. |
| Weekly 150-question spoiler review | It needs AI answers, and two teammates to check them. | Once the AI client exists. |
| Usability sessions with outside readers | They need people and a build to test. No session has been run. | After the beta. |
| SwiftLint | [coding-guidelines.md](../coding-guidelines.md) lists it, but the only Swift code is Flutter's generated `ios/Runner`. | When we write our own Swift code. |

## Evidence

- Latest green CI run on `ui`:
  [run 41586891749](https://github.com/bennyxzeng/Loremark/actions/runs/41586891749).
- Latest passing emulator acceptance run (20 of 20 force-quits, offline reading, open from the
  library, 0 bytes of app traffic):
  [run 41586486304](https://github.com/bennyxzeng/Loremark/actions/runs/41586486304).
- Full local test run, 2026-11-02, Windows, `flutter test --exclude-tags "live || benchmark"`:
  726 tests, 724 passed, 1 skipped, 1 failed. Passed per folder: `test/reader` 245,
  `test/search` 184, `test/acceptance` 119, `test/home` 69, `test/corpus` 33 (plus the skipped
  corpus test), `test/reading` 30, `test/library` 20, `test/story_model` 14, `test/story_map` 6,
  `test/widget_test.dart` 3, `test/support` 1. The failing test is "native file location
  Android receives an encoded file URI" (issue #49, Windows only).
- Bug issues #17 to #52, listed in [bug-log.md](bug-log.md).
- Method and results of the other suites: [acceptance.md](acceptance.md),
  [benchmarks.md](benchmarks.md), [corpus-testing.md](corpus-testing.md).
