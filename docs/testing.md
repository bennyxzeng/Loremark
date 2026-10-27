# Testing and Continuous Integration

This page describes how Loremark's tests are automated and how CI runs them. It extends the
test plan in our living document (Process description → Test Plan & Bugs).

## Test-automation infrastructure

| Code | Framework | Where tests live | Run locally |
| :--- | :--- | :--- | :--- |
| Flutter app (Dart) | [`flutter_test`](https://api.flutter.dev/flutter/flutter_test/) (built on [`package:test`](https://pub.dev/packages/test)) | `test/`, mirroring `lib/` | `flutter test` |
| Story model lab (Python) | [pytest](https://docs.pytest.org/) | `tools/story_model_lab/tests/` | `python -m pytest tools/story_model_lab/tests -m 'not live'` |

`flutter_test` covers both kinds of automated test our plan needs for the app:

- **Unit tests** (`test(...)`) for plain Dart logic: the reading cutoff and large-jump check,
  the versioned story model, theory status and dependencies, `ContextManager` filtering,
  `ResponseValidator`, local JSON storage, and API error handling.
- **Widget tests** (`testWidgets(...)`) that build screens in memory and tap, scroll and read
  them without a device, for example "the chapter slider cannot pass the reader's position".

### Why these frameworks

- **`flutter_test` is the Flutter SDK's own test framework.** It ships with Flutter, so there is
  nothing extra to install or keep compatible. It is the only framework that can pump Flutter
  widgets without a device, which a general Dart runner cannot do.
- **One command for the whole app.** `flutter test` runs unit and widget tests together, and the
  same command runs locally and in CI.
- **Tags fit our test plan.** Tests that call a real LLM are tagged `live` and excluded by
  default (see below). This matches the plan's split between deterministic unit tests with mock
  LLM responses and the separate nondeterministic prompt runs.
- **pytest** is the standard Python test runner and was already used by the story model lab, so
  CI runs those tests as they are.

### Test categories and where they run

| Test-plan category | How it is automated | In CI? |
| :--- | :--- | :--- |
| Unit tests (EPUB reader, story model, notes and theories, AI request coordinator, local storage, API errors) | `flutter test`, with a fake `LLMClient` returning fixed responses | Yes, every push and PR |
| Widget tests (screens and navigation) | `flutter test` | Yes, every push and PR |
| Story model lab (EPUB parsing, extraction pipeline, validation) | pytest with a mocked HTTP transport | Yes, when `tools/story_model_lab/` changes |
| Nondeterministic prompt tests | Tagged `live` (Dart) or marked `live` (pytest) | No: needs API keys, costs money, output varies (Risks 1 and 4) |
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

For the Python lab, add a `test_*.py` file under `tools/story_model_lab/tests/`. Mark tests that
call a real model API with `@pytest.mark.live`.

## Continuous integration

### Service and how the repository is linked to it

We use **GitHub Actions**. It is built into GitHub, so there is no external account or access
token to set up. The link between CI and the repository is the set of workflow files committed
under `.github/workflows/`:

| Workflow | File | Job |
| :--- | :--- | :--- |
| CI | `.github/workflows/ci.yml` | `Flutter (format, analyze, test)` |
| Story model lab | `.github/workflows/story-model-lab.yml` | `Python (ruff, pytest)` |

GitHub reads these files on every matching event and runs the jobs on a fresh GitHub-hosted
Ubuntu runner. Each job checks out the commit with `actions/checkout`, using the
`GITHUB_TOKEN` that GitHub creates for each run. The workflows only request
`contents: read` permission and use no secrets, so pull requests from forks run safely. Results
appear as checks on the commit and the pull request, and in the repository's **Actions** tab.

To reproduce the setup in another repository:

1. Copy the two files into `.github/workflows/` and push them. GitHub Actions is enabled by
   default, so the workflows start running on the next push or pull request.
2. Check that **Settings → Actions → General → Actions permissions** allows actions to run.
3. Make CI block merging (a repository admin does this once): in
   **Settings → Branches → Add branch ruleset** (or **Add classic branch protection rule**) for
   `main`, turn on **Require a pull request before merging** with one approval, and
   **Require status checks to pass**, then select the `Flutter (format, analyze, test)` check.
   Do not require the story model lab check: it only runs when the lab changes, so a required
   check would block unrelated pull requests.

### Why GitHub Actions

- **Already where our code is.** Our repository, pull requests, code review and bug issues are
  all on GitHub. Checks appear directly on each pull request, and branch protection can require
  them without another service.
- **Free for our use.** Public repositories get unlimited minutes on standard GitHub-hosted
  runners, and private repositories get a monthly free quota. Travis CI and CircleCI use
  credit-based plans, so a busy week of pull requests could run out of free builds.
- **Ready-made Flutter support.** `subosito/flutter-action` installs and caches an exact Flutter
  version in one step. `actions/setup-python` does the same for Python.
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

The `Story model lab` workflow uses Python 3.14 and the pinned `requirements.lock.txt`, then
runs `ruff check`, `ruff format --check`, and `pytest -m 'not live'`.

Any failing step fails the build and marks the commit or pull request with a red check.

### What triggers a CI build

| Action | `CI` (Flutter) | `Story model lab` (Python) |
| :--- | :--- | :--- |
| Open, push to, or reopen a pull request (into any branch) | Yes | If the PR changes `tools/story_model_lab/` |
| Push or merge to `main` | Yes | If the push changes `tools/story_model_lab/` |
| Manual run (**Actions → workflow → Run workflow**) | Yes | Yes |
| Push to a feature branch with no pull request | No | No |

Feature-branch pushes are checked once a pull request is open, so each change is tested once
instead of twice. A newer push to the same pull request cancels the older run that is still in
progress.

### Not yet in CI

- **SwiftLint.** `coding-guidelines.md` lists it, but the only Swift code is Flutter's generated
  `ios/Runner`. We will add a SwiftLint job when we write our own Swift code.
- **iOS build and simulator integration tests.** These need a macOS runner. We plan to add an
  `integration_test` job before the beta build.
- **Live LLM tests.** These stay manual to protect our API budget (Risk 4).
