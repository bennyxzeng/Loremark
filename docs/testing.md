# Testing and Continuous Integration

This page says what we test, how to run it, and how bugs are tracked. It extends the test plan in
our living document (Process description → Test Plan & Bugs).

## Test types

| Type | What it checks | Where | Runs in CI? |
| :--- | :--- | :--- | :--- |
| Unit tests | Plain Dart logic: reading position, large-jump rule, story model, passage extraction, search index, local storage | `test/reading/`, `test/reader/`, `test/story_model/`, `test/search/`, `test/library/`, `test/notes/` | Yes |
| Widget tests | Screens in memory: library, API key, reader, notes, search sheet, Story Map | `test/home/`, `test/library/`, `test/settings/`, `test/story_map/`, `test/notes/` | Yes |
| Spoiler tests | Nothing past the reader is ever shown (search, story model, text extraction) | `test/search/spoiler_property_test.dart`, `test/acceptance/story_model_spoiler_test.dart` | Yes |
| Edge-case tests | Odd EPUB markup, huge paragraphs, strange search queries | `test/corpus/edge_cases_test.dart` | Yes |
| **Integration test** | The whole app on a device: first launch, import, read, search, notes, API key, offline | `integration_test/app_test.dart` | Emulator workflow (Android), `ios.yml` (iPhone simulator) |
| Acceptance tests | 20 force-quits, offline reading, no unexpected network traffic | `tool/acceptance/`, [acceptance.md](acceptance.md) | Emulator workflow |
| Benchmarks | A 500,000-word book stays fast enough | `flutter test --tags benchmark`, [benchmarks.md](benchmarks.md) | No (manual) |
| Real-book corpus | 50 public-domain EPUBs and 24 broken variants | `flutter test --tags corpus`, [corpus-testing.md](corpus-testing.md) | No (needs the books) |
| Manual | Usability sessions with outside readers | Not run yet | No |

Tests use `flutter_test`, the test framework that ships with Flutter. It runs unit and widget
tests with one command, so there is nothing else to install. `integration_test` is also part of
the Flutter SDK.

## Run the tests

```bash
flutter pub get
flutter test --exclude-tags "live || benchmark"        # all unit and widget tests (CI does this)
flutter test test/reading/text_position_test.dart      # one file
flutter test --plain-name 'an earlier chapter'         # one test by name
flutter test integration_test -d <device id>           # integration test, needs an emulator
dart format lib test integration_test tool && flutter analyze
```

Start an emulator with `flutter emulators --launch <name>`, and find the device id with
`flutter devices`.

## Integration test

`integration_test/app_test.dart` runs the real app, with the real EPUB reader, on an Android
emulator or phone. It uses a generated 3-chapter book, so it needs no files or network.

Only three things are replaced: the file picker (returns the generated book), the key store
(kept in memory) and the API key check (answers by itself).

| Test | Steps and checks |
| :--- | :--- |
| Reader without an API key | First launch shows "Connect an AI provider". Skip it. Import the book. It opens in the reader. Next page moves the progress. Search finds a word from a read chapter, and finds nothing for a word in a chapter not reached yet. Notes is empty. Ask and Story Map say "needs an API key". Back in the library the book is "LAST OPENED". |
| Rejected API key | A key the check rejects keeps the reader on the key screen. |
| Valid API key | A valid key opens the library. After import, Ask opens, and Story Map shows its chapter slider. |
| Offline | The "You're offline" banner shows. Ask is locked, Story Map still opens. Going back online unlocks Ask. |

It cannot select text, so creating a highlight or note is covered by widget tests
(`test/home/read_screen_notes_test.dart`, `test/notes/`) instead. The generated book has no table
of contents, so Contents is covered by `test/reader/toc_builder_test.dart` and the real-book corpus.

It is not in the normal CI build, because it needs an emulator, which takes about 10 minutes to
start and build. It runs in the emulator workflow (see below), or by hand before a release.

## Add a new test

1. Create `test/<same folder as lib>/<name>_test.dart`. `flutter test` finds it by itself.
2. Import the code with `package:loremark/...`:

   ```dart
   import 'package:flutter_test/flutter_test.dart';
   import 'package:loremark/reading/text_position.dart';

   void main() {
     test('an earlier chapter is before a later one', () {
       expect(const TextPosition(1, 0.9) < const TextPosition(2, 0.1), isTrue);
     });
   }
   ```

   Use `testWidgets` for screens. Use a fake instead of a real service: see
   `test/home/fake_epub_reader_service.dart`.
3. Run the CI checks (above) and open a pull request. Each feature pull request includes tests for
   that feature.

## Continuous integration

We use **GitHub Actions**. The link to the repository is the file `.github/workflows/ci.yml`.
GitHub runs it on a fresh Ubuntu machine for every matching event, and shows the result as a check
on the commit and pull request.

Why GitHub Actions: our code, pull requests and bug issues are already on GitHub, it is free for
us, `subosito/flutter-action` installs the exact Flutter version, and it needs no other account.

What a build runs, using Flutter 3.47.7 (the version in `.metadata`):

1. `flutter pub get --enforce-lockfile`: fails if `pubspec.yaml` and `pubspec.lock` disagree.
2. `dart format --output=none --set-exit-if-changed .`: fails on unformatted code.
3. `flutter analyze`: fails on any error, warning or lint.
4. `flutter test --coverage --exclude-tags "live || benchmark"`: runs the tests and records
   coverage.
5. A coverage report is written to the job summary, and `lcov.info` is uploaded.

Any failing step makes the check red.

| Event | Runs CI? |
| :--- | :--- |
| Pull request opened, pushed to or reopened | Yes |
| Push or merge to `main` or `ui` | Yes |
| Manual run (Actions → CI → Run workflow) | Yes |
| Push to a branch with no pull request | No |

**Device workflows.** Two more workflows run the integration test on a simulated phone:
`.github/workflows/acceptance.yml` (Android emulator, plus the acceptance tests) and
`.github/workflows/ios.yml` (iPhone simulator). Each is slow (an emulator or simulator has to start and the app has to build), so they run by hand,
every Monday, and on pull requests labeled `device-tests`.

To make CI block merging, an admin turns on **Require status checks to pass** for `main` in
Settings → Branches and selects `Flutter (format, analyze, test)`.

## Code coverage

Coverage is the share of lines in `lib/` that run during the tests. It shows where no test
reaches. It does not show that a test checks the right thing.

```bash
flutter test --coverage --exclude-tags "live || benchmark"
dart run tool/coverage/report.dart
```

In CI, the same table is in the job summary and `coverage/lcov.info` is uploaded as an artifact.

Result on 2026-11-04 (900 tests): **94.1%** of lines in `lib/` ran (4,508 of 4,792), and every
file in `lib/` is loaded by at least one test.

| Folder | Lines covered | % |
| :--- | ---: | ---: |
| `lib/reading` | 75 of 75 | 100.0% |
| `lib/story_model` | 318 of 320 | 99.4% |
| `lib/theme` | 56 of 57 | 98.2% |
| `lib/search` | 1,181 of 1,218 | 97.0% |
| `lib/home` | 492 of 512 | 96.1% |
| `lib/story_map` | 804 of 851 | 94.5% |
| `lib/reader` | 555 of 598 | 92.8% |
| `lib/notes` | 381 of 411 | 92.7% |
| `lib/library` | 311 of 351 | 88.6% |
| `lib/settings` | 318 of 365 | 87.1% |
| `lib/main.dart` | 17 of 34 | 50.0% |

The lowest are `main.dart` (the real keychain and file picker, which the tests replace) and the
real-device parts of the reader, which only the emulator tests reach.

## Bug tracking

Bugs are tracked in [GitHub Issues](https://github.com/bennyxzeng/Loremark/issues). The full list
with causes and fixes is in [bug-log.md](bug-log.md): 46 bugs so far: 38 fixed, 1 worked around, 1 fix in review and 6 open.

- **File an issue** with the "Bug report" form (`.github/ISSUE_TEMPLATE/bug_report.yml`). It asks
  for steps to reproduce, expected and actual result, and the build.
- **Priority label** (one per bug):
  - **P0**: spoiler leak, crash or lost data. Fix before any new feature.
  - **P1**: a feature gives wrong results or is hard to use.
  - **P2**: small or cosmetic.
- **Type label** (when it fits): `spoiler`, `crash`, `AI-quality`, `timeline`, `usability`,
  `test-harness`.
- **Title** starts with an ID: `BUG-nn` (app), `CI-nn` (tests and CI), `OPEN-nn` (not fixed yet).
- **Assign** the person who fixes it. When the fix is merged, close the issue with a comment
  naming the fix commit and pull request. A fix includes a test that fails without it.
- Add a row to [bug-log.md](bug-log.md).

## Not tested yet

- **Theories.** Deferred until after the beta.
- **Usability sessions.** They need outside readers.
- **The large-jump confirmation.** The rule is tested, but no screen asks the reader to confirm
  yet (issue #53).
- **iOS has not run yet.** The integration test is written to run on an iPhone simulator
  (`.github/workflows/ios.yml`), but we develop on Windows and Android, so nobody has seen it
  pass on iOS. Run the workflow by hand (Actions → Integration (iOS) → Run workflow) and fix
  what it finds. The acceptance tests (force-quit, offline, privacy) are Android only.
