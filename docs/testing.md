# Testing and Continuous Integration

This page describes how Loremark's tests are automated and how CI runs them. It extends the
test plan in our living document (Process description → Test Plan & Bugs).

## Test-automation infrastructure

We use [`flutter_test`](https://api.flutter.dev/flutter/flutter_test/), which is built on
[`package:test`](https://pub.dev/packages/test). Tests live in `test/`, mirroring `lib/`, and
run with `flutter test`. It covers both kinds of automated test our plan needs for the app:

- **Unit tests** (`test(...)`) for plain Dart logic: the reading cutoff and large-jump check,
  the versioned story model, theory status and dependencies, `ContextManager` filtering,
  `ResponseValidator`, local JSON storage, and API error handling.
- **Widget tests** (`testWidgets(...)`) that build screens in memory and tap, scroll and read
  them without a device, for example "the chapter slider cannot pass the reader's position".

### Why this framework

- **`flutter_test` is the Flutter SDK's own test framework.** It ships with Flutter, so there is
  nothing extra to install or keep compatible. It is the only framework that can pump Flutter
  widgets without a device, which a general Dart runner cannot do.
- **One command for the whole app.** `flutter test` runs unit and widget tests together, and the
  same command runs locally and in CI.
- **Tags fit our test plan.** Tests that call a real LLM are tagged `live` and excluded by
  default (see below). This matches the plan's split between deterministic unit tests with mock
  LLM responses and the separate nondeterministic prompt runs.

### Test categories and where they run

| Test-plan category | How it is automated | In CI? |
| :--- | :--- | :--- |
| Unit tests (EPUB reader, story model, notes and theories, AI request coordinator, local storage, API errors) | `flutter test`, with a fake `LLMClient` returning fixed responses | Yes, every push and PR |
| Widget tests (screens and navigation) | `flutter test` | Yes, every push and PR |
| Nondeterministic prompt tests | Tagged `live` | No: needs API keys, costs money, output varies (Risks 1 and 4) |
| Weekly 150-question spoiler run | Two teammates review answers by hand | No |
| Integration, reliability, scalability, privacy (force-quit, 500,000-word book, Proxyman) | Run on a device or simulator | No: needs a device and network capture |
| Usability sessions | External readers | No |

## How to add a new test

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
3. **Do not call a real LLM in a normal test.** Pass a fake `LLMClient` that returns a fixed
   response. A test that must call a real provider goes in its own file tagged `live`:

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
   flutter test --exclude-tags live
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
`contents: read` permission and use no secrets, so pull requests from forks run safely. Results
appear as checks on the commit and the pull request, and in the repository's **Actions** tab.

To reproduce the setup in another repository:

1. Copy `ci.yml` into `.github/workflows/` and push it. GitHub Actions is enabled by default, so
   the workflow starts running on the next pull request or push to `main`.
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
   (Effective Dart, as in `coding-guidelines.md`).
3. `flutter analyze`: fails on any analyzer error, warning or `flutter_lints` issue.
4. `flutter test --exclude-tags live`: runs every unit and widget test except `live` ones.

Any failing step fails the build and marks the commit or pull request with a red check.

### What triggers a CI build

| Action | Runs CI? |
| :--- | :--- |
| Open, push to, or reopen a pull request (into any branch) | Yes |
| Push or merge to `main` | Yes |
| Manual run (**Actions → CI → Run workflow**) | Yes |
| Push to a feature branch with no pull request | No |

Feature-branch pushes are checked once a pull request is open, so each change is tested once
instead of twice. A newer push to the same pull request cancels the older run that is still in
progress.

### Not yet in CI

- **SwiftLint.** `coding-guidelines.md` lists it, but the only Swift code is Flutter's generated
  `ios/Runner`. We will add a SwiftLint job when we write our own Swift code.
- **iOS build and simulator integration tests.** These need a macOS runner. We plan to add an
  `integration_test` job before the beta build.
- **Live LLM tests.** These stay manual to protect our API budget (Risk 4).
