/// This file holds the data classes for a reader's theories: predictions the
/// reader wrote about the book that Loremark tracks as the story goes on.
/// A theory is the reader's own guess and is never a fact about the book.
library;

import 'package:flutter/foundation.dart';

import 'note.dart';

/// This enum lists how a theory is doing. It is worked out from the verdicts of
/// the theory's sub-theories by [theoryStatus] and is never saved.
/// (See Use Case #2 and the "Different outcome" wording of milestone #8)
enum TheoryStatus {
  /// Nothing in the book has settled the theory yet.
  unconfirmed,

  /// Every part of the theory came true.
  confirmed,

  /// Some parts came true or are still open, and some did not.
  partiallyCorrect,

  /// Every part of the theory turned out differently.
  differentOutcome,

  /// The theory builds on another theory that turned out differently or was invalidated.
  invalidated,
}

/// This extension gives each [TheoryStatus] the name the reader sees.
/// The screens use only this label, so the wording lives in one place.
extension TheoryStatusLabel on TheoryStatus {
  /// This is the name shown to the reader. (Ex. 'Partially correct')
  String get label => switch (this) {
    TheoryStatus.unconfirmed => 'Unconfirmed',
    TheoryStatus.confirmed => 'Confirmed',
    TheoryStatus.partiallyCorrect => 'Partially correct',
    TheoryStatus.differentOutcome => 'Different outcome',
    TheoryStatus.invalidated => 'Invalidated',
  };
}

/// This enum tells what the book has shown about one sub-theory so far.
enum SubTheoryVerdict {
  /// The book has not settled it yet.
  open,

  /// The book showed it came true.
  confirmed,

  /// The book showed it did not happen that way.
  refuted,
}

/// This class is the passage of the book that settled a sub-theory.
/// The quote is text the reader has already read, saved so the reader can see why.
class TheoryEvidence {
  /// This is the index of the section (EPUB spine item) the quote is in.
  final int sectionIndex;

  /// This is the chapter name shown with the evidence. (Ex. 'Chapter 12')
  final String chapterLabel;

  /// This is the exact text from the book that settled the sub-theory.
  final String quote;

  const TheoryEvidence({
    required this.sectionIndex,
    required this.chapterLabel,
    required this.quote,
  });

  /// This reads evidence that was saved by [toJson].
  /// Throws a [FormatException] if a value is missing or invalid.
  factory TheoryEvidence.fromJson(Map<String, dynamic> json) {
    final sectionIndex = json['sectionIndex'];
    final chapterLabel = json['chapterLabel'];
    final quote = json['quote'];
    if (sectionIndex is! int ||
        sectionIndex < 0 ||
        chapterLabel is! String ||
        quote is! String) {
      throw FormatException('Invalid TheoryEvidence: $json');
    }
    return TheoryEvidence(
      sectionIndex: sectionIndex,
      chapterLabel: chapterLabel,
      quote: quote,
    );
  }

  /// This turns the evidence into JSON so it can be saved in the notes file.
  Map<String, dynamic> toJson() => {
    'sectionIndex': sectionIndex,
    'chapterLabel': chapterLabel,
    'quote': quote,
  };

  @override
  bool operator ==(Object other) =>
      other is TheoryEvidence &&
      other.sectionIndex == sectionIndex &&
      other.chapterLabel == chapterLabel &&
      other.quote == quote;

  @override
  int get hashCode => Object.hash(sectionIndex, chapterLabel, quote);
}

/// This class is one checkable part of a theory.
/// Ex. the theory "Mara is the thief and she works for Elian" has two:
/// "Mara is the thief" and "Mara works for Elian".
class SubTheory {
  /// This is the id of the sub-theory, unique inside its theory.
  final String id;

  /// This is the prediction itself.
  final String text;

  /// This is what the book has shown about it so far.
  final SubTheoryVerdict verdict;

  /// This is the passage that settled it. Present only when [verdict] is not open.
  final TheoryEvidence? evidence;

  /// This is when the verdict was first set. Null while it is open.
  final DateTime? resolvedAt;

  const SubTheory({
    required this.id,
    required this.text,
    this.verdict = SubTheoryVerdict.open,
    this.evidence,
    this.resolvedAt,
  });

  /// This is true when the book has not settled this sub-theory yet.
  bool get isOpen => verdict == SubTheoryVerdict.open;

  /// This reads a sub-theory that was saved by [toJson].
  /// Throws a [FormatException] if a value is missing or invalid.
  factory SubTheory.fromJson(Map<String, dynamic> json) {
    try {
      final evidence = json['evidence'];
      final resolvedAt = json['resolvedAt'];
      return SubTheory(
        id: json['id'] as String,
        text: json['text'] as String,
        verdict: SubTheoryVerdict.values.byName(json['verdict'] as String),
        evidence: evidence == null
            ? null
            : TheoryEvidence.fromJson(evidence as Map<String, dynamic>),
        resolvedAt: resolvedAt == null
            ? null
            : DateTime.parse(resolvedAt as String),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      // A missing field shows up as a TypeError and an unknown verdict as an
      // ArgumentError, so both are turned into one FormatException for the caller.
      throw FormatException('Invalid SubTheory: $json');
    }
  }

  /// This turns the sub-theory into JSON so it can be saved in the notes file.
  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'verdict': verdict.name,
    'evidence': evidence?.toJson(),
    'resolvedAt': resolvedAt?.toUtc().toIso8601String(),
  };

  /// This makes a copy with only the given fields changed.
  /// Pass [resolvedAt] together with the first verdict. A copy that is only
  /// given a new verdict keeps the time it already had.
  SubTheory copyWith({
    String? text,
    SubTheoryVerdict? verdict,
    TheoryEvidence? evidence,
    DateTime? resolvedAt,
  }) => SubTheory(
    id: id,
    text: text ?? this.text,
    verdict: verdict ?? this.verdict,
    evidence: evidence ?? this.evidence,
    resolvedAt: resolvedAt ?? this.resolvedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is SubTheory &&
      other.id == id &&
      other.text == text &&
      other.verdict == verdict &&
      other.evidence == evidence &&
      _sameMoment(other.resolvedAt, resolvedAt);

  @override
  int get hashCode => Object.hash(
    id,
    text,
    verdict,
    evidence,
    resolvedAt?.millisecondsSinceEpoch,
  );
}

/// This class is everything saved about a theory besides the note itself.
class TheoryState {
  /// These are the checkable parts of the theory. Empty means it is not split yet.
  final List<SubTheory> subTheories;

  /// This is the id of the older theory of the same book this one builds on. (Optional)
  final String? dependsOnId;

  /// This is the last section (EPUB spine item) already checked against the
  /// theory, or -1 if none has been.
  final int checkedThroughSection;

  const TheoryState({
    this.subTheories = const [],
    this.dependsOnId,
    this.checkedThroughSection = -1,
  });

  /// This reads a theory state that was saved by [toJson].
  /// Throws a [FormatException] if a value is missing or invalid.
  factory TheoryState.fromJson(Map<String, dynamic> json) {
    try {
      final checked = json['checkedThroughSection'];
      if (checked is! int || checked < -1) {
        throw FormatException('Invalid TheoryState: $json');
      }
      return TheoryState(
        subTheories: [
          for (final sub in json['subTheories'] as List<dynamic>)
            SubTheory.fromJson(sub as Map<String, dynamic>),
        ],
        dependsOnId: json['dependsOnId'] as String?,
        checkedThroughSection: checked,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw FormatException('Invalid TheoryState: $json');
    }
  }

  /// This turns the state into JSON so it can be saved in the notes file.
  Map<String, dynamic> toJson() => {
    'subTheories': [for (final sub in subTheories) sub.toJson()],
    'dependsOnId': dependsOnId,
    'checkedThroughSection': checkedThroughSection,
  };

  /// This makes a copy with only the given fields changed.
  /// Set [clearDependsOn] to remove the link, since a null [dependsOnId]
  /// means "keep it".
  TheoryState copyWith({
    List<SubTheory>? subTheories,
    String? dependsOnId,
    bool clearDependsOn = false,
    int? checkedThroughSection,
  }) => TheoryState(
    subTheories: subTheories ?? this.subTheories,
    dependsOnId: clearDependsOn ? null : dependsOnId ?? this.dependsOnId,
    checkedThroughSection: checkedThroughSection ?? this.checkedThroughSection,
  );

  @override
  bool operator ==(Object other) =>
      other is TheoryState &&
      listEquals(other.subTheories, subTheories) &&
      other.dependsOnId == dependsOnId &&
      other.checkedThroughSection == checkedThroughSection;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(subTheories),
    dependsOnId,
    checkedThroughSection,
  );
}

bool _sameMoment(DateTime? a, DateTime? b) =>
    a == null || b == null ? a == b : a.isAtSameMomentAs(b);

/// This works out how a theory is doing from what the book has shown so far.
/// The status is always worked out fresh and never saved, so it cannot go stale.
/// The rules, in order:
/// 1. If the theory builds on one whose own verdicts make it Different outcome,
///    or on one that is Invalidated, it is Invalidated. This follows the chain.
/// 2. With no sub-theories yet, or all of them open, it is Unconfirmed.
/// 3. With all sub-theories confirmed, it is Confirmed.
/// 4. With all sub-theories refuted, it is Different outcome.
/// 5. Anything else, including a mix with some still open, is Partially correct.
/// A dependency that no longer exists is ignored, and a loop in the links
/// cannot hang it.
/// Parameters:
/// - note: The theory to judge. Throws an [ArgumentError] if it is not a theory.
/// - notesById: Every note of the book by id, used to find the theories it builds on.
TheoryStatus theoryStatus(Note note, Map<String, Note> notesById) {
  final theory = note.theory;
  if (note.kind != NoteKind.theory || theory == null) {
    throw ArgumentError.value(note.id, 'note', 'is not a theory');
  }
  // Walk up the chain of "builds on" links. A theory whose own verdicts are
  // Different outcome makes everything below it Invalidated, and that carries
  // down the chain, so one such theory anywhere above is enough.
  final seen = <String>{note.id};
  var dependsOnId = theory.dependsOnId;
  while (dependsOnId != null && seen.add(dependsOnId)) {
    final parentTheory = notesById[dependsOnId]?.theory;
    if (parentTheory == null) break;
    if (_ownStatus(parentTheory) == TheoryStatus.differentOutcome) {
      return TheoryStatus.invalidated;
    }
    dependsOnId = parentTheory.dependsOnId;
  }
  return _ownStatus(theory);
}

// This is the status from the theory's own sub-theories alone.
TheoryStatus _ownStatus(TheoryState theory) {
  final subs = theory.subTheories;
  if (subs.isEmpty || subs.every((sub) => sub.isOpen)) {
    return TheoryStatus.unconfirmed;
  }
  if (subs.every((sub) => sub.verdict == SubTheoryVerdict.confirmed)) {
    return TheoryStatus.confirmed;
  }
  if (subs.every((sub) => sub.verdict == SubTheoryVerdict.refuted)) {
    return TheoryStatus.differentOutcome;
  }
  return TheoryStatus.partiallyCorrect;
}

/// This shortens a theory's text so it fits on one line, like in the "Builds on"
/// picker or a banner. Line breaks become spaces.
/// Ex. a 90-letter theory becomes its first 40 letters and an ellipsis.
String shortenTheoryText(String text, [int maxLength = 40]) {
  final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return oneLine.length <= maxLength
      ? oneLine
      : '${oneLine.substring(0, maxLength)}…';
}
