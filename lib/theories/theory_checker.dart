/// This file holds the theory checker: it splits a reader's theories into
/// sub-theories and checks them, one finished section at a time, against the
/// book with the reader's own API key.
///
/// Spoiler and privacy rules it keeps (see docs/theories.md, part 2):
/// - Only whole sections the reader has finished are sent ([finishedSectionCount]):
///   a section is finished once the reader has turned past its end, never
///   while they are still on its last page. Only the last section of the book,
///   which has nothing to turn to, counts when its last page is reached.
///   The section in progress and later ones are never sent.
/// - One section per request, and no personal notes.
/// - A verdict counts only when its quote is really in that section's text.
/// - A failed request changes no note and never stops the reader reading.
library;

import 'dart:async';
import 'dart:convert';

import '../notes/annotation_service.dart';
import '../notes/note.dart';
import '../notes/theory.dart';
import '../reader/reader_position.dart';
import '../search/search_cutoff.dart';
import '../settings/ai_settings.dart';
import '../story_update/story_api_client.dart';
import '../story_update/story_book.dart';
import '../story_update/story_model_choice.dart';
import 'theory_requests.dart';

/// This is a theory whose status changed during a check, for the banner.
class TheoryStatusChange {
  const TheoryStatusChange({
    required this.noteId,
    required this.body,
    required this.from,
    required this.to,
  });

  /// The id of the theory's note.
  final String noteId;

  /// What the reader wrote.
  final String body;
  final TheoryStatus from;
  final TheoryStatus to;

  /// The banner text, with the theory shortened. (Ex. 'Theory confirmed: "Mara
  /// is the thief"')
  String get bannerText {
    final what = switch (to) {
      TheoryStatus.confirmed => 'Theory confirmed',
      TheoryStatus.partiallyCorrect => 'Theory partially correct',
      TheoryStatus.differentOutcome => 'Theory had a different outcome',
      TheoryStatus.invalidated => 'Theory invalidated',
      TheoryStatus.unconfirmed => 'Theory unconfirmed',
    };
    final short = body.length <= 60 ? body : '${body.substring(0, 57)}...';
    return '$what: "$short"';
  }
}

/// This tells how many sections count as finished for the given positions.
/// Section indexes below the returned number are finished; the rest are not.
///
/// A section counts as finished only after the reader has turned past its end,
/// because a page just turned to has not been read yet. So every section
/// before the one being read is finished, and the one being read is not, even
/// on its last page. The one exception is [lastSection], the index of the
/// book's last linear section: it has nothing to turn to, so reaching its
/// last page (progression 1) is enough. Without [lastSection] there is no
/// exception.
int finishedSectionCount({
  ReaderPosition? current,
  ReaderPosition? furthest,
  int? lastSection,
}) {
  final reached = searchCutoff(current: current, furthest: furthest);
  if (reached.sectionIndex < 0) return 0;
  final atBookEnd =
      lastSection != null &&
      reached.sectionIndex == lastSection &&
      reached.progression == 1;
  return atBookEnd ? reached.sectionIndex + 1 : reached.sectionIndex;
}

/// This class checks theories against the book. It is created once per open
/// book. Everything it needs from outside is passed in, so tests need no
/// network, device or book file.
class TheoryChecker {
  TheoryChecker({
    required this.annotations,
    required this.loadSectionTexts,
    required this.credentials,
    required this.isOnline,
    this.post = postStoryRequest,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The book's notes. Every write goes through [AnnotationService.updateTheory].
  final AnnotationService annotations;

  /// Reads the plain text of every section of the book, in spine order.
  /// It is only called when a check is about to be sent.
  final Future<List<String>> Function() loadSectionTexts;

  /// The reader's provider and key, or null when none is saved.
  final AiCredentials? Function() credentials;

  /// Whether the device is online.
  final bool Function() isOnline;

  /// Sends a request. Tests replace the network call.
  final StoryHttpPost post;

  final DateTime Function() _clock;

  final _changes = StreamController<TheoryStatusChange>.broadcast();
  (ReaderPosition?, ReaderPosition?, int?)? _pending;
  Future<void>? _active;
  List<String>? _sections;

  /// This says why the last run stopped early, by category only (Ex.
  /// 'authentication', 'rate_limit', 'timeout'), never the key or any book
  /// text. It is null after a run that did not fail.
  String? lastError;

  /// This emits each theory whose status changed from Unconfirmed or
  /// Partially correct to a new one. Theories that now build on a lost
  /// theory are included, because their derived status changed too.
  Stream<TheoryStatusChange> get changes => _changes.stream;

  /// This runs a check for the reader's positions: it splits theories that
  /// are not split yet, then checks every finished section no theory has seen.
  /// A call made while a run is going is merged into one follow-up run.
  /// It never throws; a failure is in [lastError].
  Future<void> run({
    ReaderPosition? current,
    ReaderPosition? furthest,
    int? lastSection,
  }) {
    _pending = (current, furthest, lastSection);
    return _active ??= _drain();
  }

  /// This ends the checker. Later runs do nothing.
  void dispose() {
    _disposed = true;
    _changes.close();
  }

  bool _disposed = false;

  Future<void> _drain() async {
    try {
      while (_pending != null && !_disposed) {
        final (current, furthest, lastSection) = _pending!;
        _pending = null;
        await _runOnce(current, furthest, lastSection);
      }
    } finally {
      _active = null;
    }
  }

  Map<String, TheoryStatus> _statuses() => {
    for (final theory in annotations.theories)
      theory.id: annotations.statusOf(theory.id),
  };

  bool _needsWork(Note theory) =>
      theory.theory!.subTheories.isEmpty ||
      theory.theory!.subTheories.any((sub) => sub.isOpen);

  Future<void> _runOnce(
    ReaderPosition? current,
    ReaderPosition? furthest,
    int? lastSection,
  ) async {
    final key = credentials();
    if (key == null || !isOnline()) return;
    if (!annotations.theories.any(_needsWork)) return;

    final before = _statuses();
    lastError = null;
    try {
      final model = StoryModelChoice.forProvider(key.provider.name).first;
      // The lowest effort the model accepts: this is a light task.
      final effort = model.efforts.first;
      await _split(key, model, effort);
      await _check(
        key,
        model,
        effort,
        finishedSectionCount(
          current: current,
          furthest: furthest,
          lastSection: lastSection,
        ),
      );
    } on _CheckFailure catch (failure) {
      lastError = failure.category;
    } on Object {
      // A save that failed or any other surprise: stop, keep what was applied.
      lastError = 'internal_error';
    } finally {
      _sections = null;
      _announce(before);
    }
  }

  void _announce(Map<String, TheoryStatus> before) {
    if (_disposed) return;
    final after = _statuses();
    for (final theory in annotations.theories) {
      final from = before[theory.id];
      final to = after[theory.id];
      if (from == null || to == null || from == to) continue;
      if (from != TheoryStatus.unconfirmed &&
          from != TheoryStatus.partiallyCorrect) {
        continue;
      }
      _changes.add(
        TheoryStatusChange(
          noteId: theory.id,
          body: theory.body,
          from: from,
          to: to,
        ),
      );
    }
  }

  /// Sends one request and returns its decoded answer, or throws.
  Future<Object?> _send(
    AiCredentials key,
    StoryModelChoice model,
    JsonMap request,
  ) async {
    final result = await callResponsesApi(
      model: model,
      apiKey: key.apiKey,
      body: jsonEncode(request),
      post: post,
    );
    if (result.status != 'completed') {
      throw _CheckFailure(
        (result.error?['category'] as String?) ?? result.status,
      );
    }
    return result.candidate;
  }

  Future<void> _split(
    AiCredentials key,
    StoryModelChoice model,
    StoryEffort effort,
  ) async {
    for (final theory in annotations.theories) {
      if (theory.theory!.subTheories.isNotEmpty) continue;
      final body = theory.body;
      final texts = parseSplit(
        await _send(
          key,
          model,
          buildSplitRequest(
            model: model,
            effort: effort,
            theory: body,
            passage: theory.selectedText,
          ),
        ),
      );
      if (texts == null) throw const _CheckFailure('invalid_output');
      final subs = [
        for (var i = 0; i < texts.length; i++)
          SubTheory(id: 's${i + 1}', text: texts[i]),
      ];
      final latest = _find(theory.id);
      // The reader may have edited or deleted it meanwhile (an edit starts
      // the theory over), so the answer is for text that no longer exists.
      if (latest == null ||
          latest.body != body ||
          latest.theory!.subTheories.isNotEmpty) {
        continue;
      }
      await annotations.updateTheory(
        theory.id,
        (state) => state.subTheories.isEmpty
            ? state.copyWith(subTheories: subs)
            : state,
      );
    }
  }

  Note? _find(String id) =>
      annotations.theories.where((note) => note.id == id).firstOrNull;

  /// The first section this theory still has to be checked against.
  int _startOf(Note theory) {
    final next = theory.theory!.checkedThroughSection + 1;
    return next > theory.anchor.sectionIndex
        ? next
        : theory.anchor.sectionIndex;
  }

  /// The theories a check may still change: split, with an open sub-theory,
  /// and not already lost because an older theory they build on was.
  List<Note> _checkable() => [
    for (final theory in annotations.theories)
      if (theory.theory!.subTheories.any((sub) => sub.isOpen) &&
          annotations.statusOf(theory.id) != TheoryStatus.invalidated)
        theory,
  ];

  Future<void> _check(
    AiCredentials key,
    StoryModelChoice model,
    StoryEffort effort,
    int finished,
  ) async {
    // Section indexes >= finished are never read, let alone sent.
    for (var section = 0; section < finished; section++) {
      final due = [
        for (final theory in _checkable())
          if (_startOf(theory) <= section) theory,
      ];
      if (due.isEmpty) continue;

      final sections = _sections ??= await loadSectionTexts();
      if (section >= sections.length) return;
      final text = sections[section];
      final paragraphs = [
        for (final line in text.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ];

      // The request carries each open sub-theory under a key that names its
      // theory, so one request can cover several theories.
      final sent = <String, Set<String>>{};
      final open = <OpenSubTheory>[];
      for (final theory in due) {
        sent[theory.id] = {
          for (final sub in theory.theory!.subTheories) sub.id,
        };
        for (final sub in theory.theory!.subTheories.where((s) => s.isOpen)) {
          open.add(OpenSubTheory(id: '${theory.id}/${sub.id}', text: sub.text));
        }
      }

      var answers = const <String, CheckAnswer>{};
      if (paragraphs.isNotEmpty) {
        final parsed = parseCheck(
          await _send(
            key,
            model,
            buildCheckRequest(
              model: model,
              effort: effort,
              paragraphs: paragraphs,
              openSubTheories: open,
            ),
          ),
        );
        if (parsed == null) throw const _CheckFailure('invalid_output');
        answers = parsed;
      }

      for (final theory in due) {
        await _apply(theory.id, section, sent[theory.id]!, answers, text);
      }
    }
  }

  /// Applies one section's answers to one theory and moves its progress on.
  Future<void> _apply(
    String id,
    int section,
    Set<String> sentIds,
    Map<String, CheckAnswer> answers,
    String sectionText,
  ) async {
    if (_find(id) == null) return;
    final now = _clock();
    await annotations.updateTheory(id, (state) {
      // The theory was started over while the request was out: the answer
      // is for sub-theories that no longer exist.
      final ids = {for (final sub in state.subTheories) sub.id};
      if (ids.length != sentIds.length || !ids.containsAll(sentIds)) {
        return state;
      }
      if (state.checkedThroughSection >= section) return state;
      return state.copyWith(
        checkedThroughSection: section,
        subTheories: [
          for (final sub in state.subTheories)
            _resolve(sub, answers['$id/${sub.id}'], section, sectionText, now),
        ],
      );
    });
  }

  SubTheory _resolve(
    SubTheory sub,
    CheckAnswer? answer,
    int section,
    String sectionText,
    DateTime now,
  ) {
    // A resolved sub-theory never changes again.
    if (!sub.isOpen || answer == null || answer.verdict == 'undecided') {
      return sub;
    }
    // A verdict without a real quote from this section is not accepted.
    if (!quoteOccursIn(answer.quote, sectionText)) return sub;
    return sub.copyWith(
      verdict: answer.verdict == 'confirmed'
          ? SubTheoryVerdict.confirmed
          : SubTheoryVerdict.refuted,
      evidence: TheoryEvidence(
        sectionIndex: section,
        chapterLabel: 'Section ${section + 1}',
        quote: normalizeWhitespace(answer.quote),
      ),
      resolvedAt: now,
    );
  }
}

class _CheckFailure implements Exception {
  const _CheckFailure(this.category);

  final String category;
}
