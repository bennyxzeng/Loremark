import 'dart:async';

import 'package:flutter/material.dart';

import '../library/book.dart';
import '../settings/ai_settings.dart';
import '../settings/connection_status.dart';
import '../story_model/story_model.dart';
import '../story_model/story_snapshot.dart';
import '../story_update/story_import.dart';
import '../story_update/story_updater.dart';
import 'story_map_backend.dart';
import 'story_map_intro.dart';
import 'story_map_screen.dart';
import 'story_map_status.dart';
import 'story_update_bar.dart';

/// The Story Map tab of [book]: its stored map, and the button that adds to it.
///
/// Updating doesn't depend on how far the reader has got. Instead, the map asks
/// before showing anything past their position: see [StoryMapScreen].
class StoryMapTab extends StatefulWidget {
  const StoryMapTab({
    super.key,
    required this.book,
    required this.backend,
    required this.active,
    this.status,
    this.onKeepReading,
    this.onUpdateFinished,
  });

  final Book book;
  final StoryMapBackend backend;

  /// Whether this is the tab showing. The reader may have read on since it last
  /// was, so coming back looks at their position again.
  final bool active;

  /// Told how updates and the map change, for the rest of the book to show.
  final StoryMapStatusController? status;

  /// Goes back to the book while an update runs.
  final VoidCallback? onKeepReading;

  /// Told how each update ended, however the reader got to it, while this tab
  /// is there to see it end: once for all the sections it was asked to add.
  final ValueChanged<StoryBatchOutcome>? onUpdateFinished;

  @override
  State<StoryMapTab> createState() => _StoryMapTabState();
}

class _StoryMapTabState extends State<StoryMapTab> {
  StoryModel? _model;
  StoryReadingProgress _progress = const StoryReadingProgress(0);
  bool _loaded = false;
  Object? _loadError;
  StoryUpdateStatus? _status;

  /// The sections being added, if they are.
  RunningStoryBatch? _batch;
  StreamSubscription<void>? _batchChanges;

  /// How many of [_batch]'s sections were done when it last changed.
  int _batchSeen = 0;

  /// The map being read again after a section went in, if it is.
  Future<void>? _reloading;

  /// The sections asked for, and when, until the update has begun. Starting
  /// one takes a moment, and the tab already shows it as under way.
  List<StorySectionChoice>? _starting;
  DateTime? _startingAt;

  /// Whether the reader has cancelled the update under way, which hasn't
  /// stopped yet.
  bool _cancelling = false;
  String? _notice;
  String? _failure;

  /// Whether files are being exported or loaded.
  bool _filesBusy = false;

  /// Whether the intro shows. It starts hidden, so a reader who closed it
  /// before doesn't see it flash while the backend is asked.
  bool _showIntro = false;

  /// Counts the maps loaded from a file. What the slider remembers belongs to the
  /// map it was on, so a different map starts it afresh.
  int _mapsLoaded = 0;

  StoryMapBackend get _backend => widget.backend;

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (mounted && widget.active) _inspect();
    });
    _loadIntro();
    final running = _backend.running(widget.book);
    // The status already knows of it, having asked the backend too.
    if (running != null) _follow(running, tellStatus: false);
  }

  @override
  void dispose() {
    _batchChanges?.cancel();
    super.dispose();
  }

  bool get _updating => _batch != null || _starting != null;

  @override
  void didUpdateWidget(StoryMapTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _refreshPosition();
      if (_status == null) _inspect();
    }
  }

  Future<void> _load() async {
    try {
      final model = await _backend.loadModel(widget.book);
      final progress = model == null
          ? const StoryReadingProgress(0)
          : await _backend.readingProgress(widget.book, model.sections);
      if (!mounted) return;
      setState(() {
        _model = model;
        _progress = progress;
        _loaded = true;
        _loadError = null;
      });
      widget.status?.mapLoaded(model?.sections);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _loadError = error;
      });
      widget.status?.mapUnreadable();
    }
  }

  Future<void> _loadIntro() async {
    try {
      final seen = await _backend.introSeen();
      if (mounted && !seen) setState(() => _showIntro = true);
    } on Object {
      // Leave it hidden rather than show it on every visit.
    }
  }

  /// Hides the intro now, and for good once that is saved. If saving fails,
  /// it shows again next time.
  Future<void> _dismissIntro() async {
    setState(() => _showIntro = false);
    try {
      await _backend.markIntroSeen();
    } on Object {
      // Nothing else depends on it.
    }
  }

  Future<void> _refreshPosition() async {
    final model = _model;
    if (model == null) return;
    try {
      final progress = await _backend.readingProgress(
        widget.book,
        model.sections,
      );
      if (mounted) setState(() => _progress = progress);
    } on Object {
      // Keep the last known position: it only decides when to ask first.
    }
  }

  Future<void> _inspect() async {
    try {
      final status = await _backend.inspect(widget.book);
      if (mounted) setState(() => _status = status);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _status = StoryUpdateStatus.blocked('$error'));
      }
    }
  }

  Future<void> _pressUpdate() async {
    final status = _status;
    if (status == null) return;
    if (status.isNewStore) return _pressChoose();
    final next = status.next;
    if (next != null) await _startUpdate([next]);
  }

  Future<void> _pressChoose() async {
    final credentials = AiSettingsScope.of(context).credentials;
    final status = _status;
    if (credentials == null || status == null) return;
    final sections = await showStorySectionsSheet(
      context,
      status: status,
      providerLabel: credentials.provider.label,
    );
    if (sections != null && sections.isNotEmpty) await _startUpdate(sections);
  }

  Future<void> _startUpdate(List<StorySectionChoice> sections) async {
    // The reader may have left while a dialog was open.
    if (!mounted || _updating) return;
    final settings = AiSettingsScope.of(context);
    final credentials = settings.credentials;
    if (credentials == null) return;
    final startedAt = DateTime.now();
    setState(() {
      _starting = sections;
      _startingAt = startedAt;
      _cancelling = false;
      _notice = null;
      _failure = null;
    });
    widget.status?.updateStarted(startedAt, total: sections.length);
    final RunningStoryBatch batch;
    try {
      batch = await _backend.update(
        widget.book,
        credentials: credentials,
        model: settings.storyModel,
        effort: settings.storyEffort,
        checkQuotes: settings.checkStoryQuotes,
        sections: sections,
      );
    } on Object catch (error) {
      // Nothing was sent, so there is nothing to be charged for.
      widget.status?.updateEnded();
      if (mounted) {
        setState(() {
          _starting = null;
          _startingAt = null;
          _failure = 'The update couldn’t start: $error';
        });
      }
      return;
    }
    _starting = null;
    _startingAt = null;
    // If the reader has left, it still finishes and is found on the store next
    // time.
    if (mounted) _follow(batch);
  }

  /// Shows [batch] as it goes, and how it ended. While the tab is first being
  /// built, the status mustn't be told, since the header is being built too.
  void _follow(RunningStoryBatch batch, {bool tellStatus = true}) {
    _batchChanges?.cancel();
    _batch = batch;
    // One just started may have finished a section already. One found on
    // coming back has its sections in the map the tab is loading.
    _batchSeen = tellStatus ? 0 : batch.outcomes.length;
    _cancelling = batch.cancelling;
    _batchChanges = batch.changes.listen((_) => _batchChanged(batch));
    // Rebuilds, and tells the status which section is under way.
    if (tellStatus) _batchChanged(batch);
    batch.done.then((outcome) => _batchEnded(batch, outcome));
  }

  void _batchChanged(RunningStoryBatch batch) {
    if (!mounted || !identical(batch, _batch)) return;
    final outcomes = batch.outcomes;
    if (outcomes.length > _batchSeen) {
      _batchSeen = outcomes.length;
      // Show each section as it goes in, rather than all at the end.
      if (outcomes.last.committed) _reloading = _reload();
    }
    if (outcomes.length <= batch.index) {
      widget.status?.updateStarted(
        batch.currentStartedAt,
        step: batch.index,
        total: batch.total,
      );
    }
    setState(() {});
  }

  Future<void> _reload() async {
    await _load();
    await _inspect();
  }

  Future<void> _pressCancel() async {
    final batch = _batch;
    if (batch == null) return;
    final remaining = batch.stopping ? 0 : batch.total - batch.index - 1;
    final choice = await showStoryCancelDialog(
      context,
      current: batch.current.title,
      remaining: remaining,
    );
    // The update may have ended while the dialog was open.
    if (choice == null || !mounted || !identical(batch, _batch)) return;
    switch (choice) {
      case StoryStopChoice.afterThisOne:
        _backend.stopAfterCurrent(widget.book);
        widget.status?.stopRequested();
        setState(() {});
      case StoryStopChoice.now:
        setState(() => _cancelling = true);
        widget.status?.cancelRequested();
        _backend.cancelUpdate(widget.book);
    }
  }

  Future<void> _pressExport() async {
    setState(() {
      _filesBusy = true;
      _notice = 'Preparing your files…';
      _failure = null;
    });
    String? notice;
    String? failure;
    try {
      notice = switch (await _backend.exportFiles(widget.book)) {
        StoryExportOutcome.saved => 'Exported.',
        StoryExportOutcome.nothing => 'Nothing to export yet.',
        StoryExportOutcome.cancelled => null,
      };
    } on Object {
      failure = 'Couldn’t export the files.';
    }
    if (!mounted) return;
    setState(() {
      _filesBusy = false;
      _notice = notice;
      _failure = failure;
    });
  }

  Future<void> _pressLoad() async {
    final path = await _backend.pickStoryFile();
    if (path == null || !mounted) return;
    setState(() {
      _filesBusy = true;
      _notice = 'Checking that file…';
      _failure = null;
    });
    String? notice;
    String? failure;
    try {
      notice = await _loadFile(path);
    } on StoryImportError catch (error) {
      failure = error.message;
    } on Object {
      failure = 'Couldn’t load that file.';
    }
    if (!mounted) return;
    setState(() {
      _filesBusy = false;
      _notice = notice;
      _failure = failure;
    });
  }

  /// Loads the file at [path], asking first if that replaces a map. Returns how
  /// it went, or null if the reader backed out.
  Future<String?> _loadFile(String path) async {
    final staged = await _backend.stageImport(widget.book, path);
    final hasMap = _model != null || _loadError != null;
    if (hasMap) {
      final confirmed =
          mounted &&
          await showStoryReplaceDialog(
            context,
            currentSections: _model?.sections.length,
            staged: staged,
          );
      if (!confirmed) {
        await _backend.discardImport(staged);
        return null;
      }
    }
    await _backend.commitImport(widget.book, staged);
    if (!mounted) return null;
    _mapsLoaded++;
    await _load();
    await _inspect();
    final count = staged.sectionCount;
    return [
      count == 1 ? 'Loaded 1 section.' : 'Loaded $count sections.',
      // Never jump past the reader: the slider asks first.
      if (_progress.shown < count)
        'Drag the slider to see ${count == 1 ? 'it' : 'them'}.',
    ].join(' ');
  }

  /// Shows how [batch] ended: [outcome].
  Future<void> _batchEnded(
    RunningStoryBatch batch,
    StoryBatchOutcome outcome,
  ) async {
    // Its changes have ended with it, so there's nothing to wait for.
    unawaited(_batchChanges?.cancel());
    _batchChanges = null;
    await _reloading;
    _reloading = null;
    if (!mounted || !identical(batch, _batch)) return;
    final now = DateTime.now();
    final took = formatStoryElapsed(now.difference(batch.startedAt));
    final sectionTook = formatStoryElapsed(
      now.difference(batch.currentStartedAt),
    );
    final total = outcome.total;
    final added = outcome.added;
    final last = outcome.last;
    final lastTitle = last.sectionTitle ?? outcome.lastSection.title;
    final mapSections = _model?.sections.length ?? 0;
    // Never jump past the reader: the slider asks first.
    final dragHint = added > 0 && _progress.shown < mapSections
        ? 'Drag the slider to see ${added == 1 ? 'it' : 'them'}.'
        : null;
    final quotes = outcome.unmatchedQuotes > 0
        ? '${outcome.unmatchedQuotes} quote(s) couldn’t be matched to the book.'
        : null;
    final soFar = added == 0 ? null : 'Added $added of $total sections.';
    String? notice;
    String? failure;
    if (outcome.cancelled) {
      // The reader asked for it, so it isn't shown as a failure.
      notice = [
        total == 1
            ? 'Cancelled after $sectionTook. Nothing was saved, but your '
                  'provider may still charge for it.'
            : 'Cancelled $lastTitle after $sectionTook. It wasn’t saved, but '
                  'your provider may still charge for it.',
        ?soFar,
        ?dragHint,
      ].join(' ');
    } else if (outcome.failed) {
      final why = '${describeStoryUpdateFailure(last)} Took $sectionTook.';
      if (total == 1) {
        failure = why;
      } else {
        notice = [?soFar, ?dragHint, ?quotes].join(' ');
        failure =
            '$lastTitle didn’t go through. $why '
                    '${outcome.outcomes.length == total ? '' : 'The rest weren’t started.'}'
                .trim();
      }
    } else if (outcome.stopped) {
      notice = [
        batch.cancelling
            // Cancelled too late: the answer had come, and has been kept.
            ? 'Cancelled too late to stop $lastTitle, so it was added.'
            : 'Stopped after $lastTitle.',
        'Added $added of $total sections in $took.',
        ?dragHint,
        ?quotes,
      ].join(' ');
    } else {
      notice = [
        total == 1
            ? 'Added $lastTitle in $took.'
            : 'Added $total sections in $took.',
        ?dragHint,
        ?quotes,
      ].join(' ');
    }
    setState(() {
      _batch = null;
      _cancelling = false;
      _notice = (notice?.isEmpty ?? true) ? null : notice;
      _failure = failure;
    });
    _tellEnded(outcome);
  }

  /// Tells the rest of the book, once this tab shows how [outcome] went.
  void _tellEnded(StoryBatchOutcome outcome) {
    widget.status?.updateEnded();
    widget.onUpdateFinished?.call(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final model = _model;
    final batch = _batch;
    final hasKey = AiSettingsScope.of(context).hasKey;
    final Widget body;
    if (_loadError != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load the Story Map.\n$_loadError'),
        ),
      );
    } else if (!_loaded) {
      // Plain text rather than a spinner: an endless animation would keep
      // widget tests from settling.
      body = const Center(child: Text('Loading Story Map…'));
    } else if (model == null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            hasKey
                ? 'Press Update to start this book’s Story Map, one section at '
                      'a time, or load one from a file with the ⋯ menu.'
                : 'Add an API key to build this book’s Story Map, or load one '
                      'from a file with the ⋯ menu.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      body = StoryMapScreen(
        key: ValueKey(_mapsLoaded),
        model: model,
        finishedSections: _progress.finished,
        hiddenInNext: _progress.hiddenInNext,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_showIntro) StoryMapIntro(onDismiss: _dismissIntro),
        StoryUpdateBar(
          status: _status,
          updateStartedAt: batch?.currentStartedAt ?? _startingAt,
          updateTitle: (batch?.current ?? _starting?.first)?.title,
          updateStep: batch?.index ?? 0,
          updateTotal: batch?.total ?? _starting?.length ?? 1,
          runStartedAt: batch?.startedAt ?? _startingAt,
          cancelling: _cancelling,
          stopping: batch?.stopping ?? false,
          online: ConnectionScope.of(context).isOnline,
          hasKey: hasKey,
          filesBusy: _filesBusy,
          notice: _notice,
          failure: _failure,
          onUpdate: _pressUpdate,
          onCancel: _pressCancel,
          onKeepReading: widget.onKeepReading,
          onChoose: _pressChoose,
          onLoad: _pressLoad,
          onExport: _pressExport,
        ),
        Expanded(child: body),
      ],
    );
  }
}
