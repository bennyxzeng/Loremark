# Coding Guidelines

This document lists the existing style guidelines that Loremark contributors follow, why we chose them, and how they are enforced. We do not define custom guidelines.

## Languages and Guidelines

| Language | Guideline | Linter / Formatter |
|---|---|---|
| Dart / Flutter | [Effective Dart](https://dart.dev/effective-dart) | `flutter_lints` via `flutter analyze`, and `dart format` |
| Swift (iOS) | [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) and [Kodeco Swift Style Guide](https://github.com/kodecocodes/swift-style-guide) | [SwiftLint](https://realm.github.io/SwiftLint/rule-directory.html) |

## Why These Guidelines

- **Effective Dart** is the official style, documentation, and design guide from the Dart team. Flutter and most Flutter packages follow it, so our code matches the libraries we depend on.
- **Swift API Design Guidelines** are the official reference from Swift.org for naming and API clarity.
- **Kodeco Swift Style Guide** is widely used and covers formatting and file organization, which the API guidelines do not. It also has a matching SwiftLint configuration.
- **SwiftLint** turns the Swift rules into automated checks, so we do not rely on memory or manual review alone.

## Enforcement

1. **Local linting.** Before pushing, contributors run:
   - Dart / Flutter: `dart format .` and `flutter analyze`
   - Swift: `swiftlint`
2. **Continuous integration.** A GitHub Actions workflow runs the linters on every pull request. A pull request that fails the lint checks cannot be merged.
3. **Code review.** Every pull request needs at least one teammate's approval. The reviewer checks style points the linters cannot catch, such as naming and documentation comments.
4. **Exceptions.** A lint rule may be disabled only with an inline comment explaining why, and the change is reviewed in the pull request.

## Setup

- Flutter: the `flutter_lints` package is listed in `pubspec.yaml`, and rules are configured in `analysis_options.yaml`.
- Swift: SwiftLint rules are configured in `.swiftlint.yml` at the repository root.
