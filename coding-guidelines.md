# Coding Guidelines

This document lists the existing style guidelines that Loremark contributors follow, why we chose them, and how they are enforced. We do not define custom guidelines.

## Languages and Guidelines

Loremark is a single Flutter app that builds for both Android and iOS, so all of our code is Dart.

| Language | Guideline | Linter / Formatter |
|---|---|---|
| Dart / Flutter | [Effective Dart](https://dart.dev/effective-dart) | `flutter_lints` via `flutter analyze`, and `dart format` |

The `android/` and `ios/` folders hold the platform projects that Flutter generates. We don't write code there by hand.

## Why These Guidelines

- **Effective Dart** is the official style, documentation, and design guide from the Dart team. Flutter and most Flutter packages follow it, so our code matches the libraries we depend on.
- **`flutter_lints`** turns the recommended rules into automated checks, so we do not rely on memory or manual review alone.
- **`dart format`** gives everyone the same formatting, so reviews focus on what the code does.

## Enforcement

1. **Local linting.** Before pushing, contributors run `dart format .` and `flutter analyze`.
2. **Continuous integration.** A GitHub Actions workflow runs the linters on every pull request. A pull request that fails the lint checks cannot be merged.
3. **Code review.** Every pull request needs at least one teammate's approval. The reviewer checks style points the linters cannot catch, such as naming and documentation comments.
4. **Exceptions.** A lint rule may be disabled only with an inline comment explaining why, and the change is reviewed in the pull request.

## Setup

The `flutter_lints` package is listed in `pubspec.yaml`, and rules are configured in `analysis_options.yaml`.
