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
  });

  final Book book;
  final StoryMapBackend backend;

  /// Whether this is the tab showing. The reader may have read on since it last
  /// was, so coming back looks at their position again.
  final bool active;

  @override
  State<StoryMapTab> createState() => _StoryMapTabState();
}

class _StoryMapTabState extends State<StoryMapTab> {
  StoryModel? _model;
  StoryReadingProgress _progress = const StoryReadingProgress(0);
  bool _loaded = false;
  Object? _loadError;
  StoryUpdateStatus? _status;

  /// When the update under way began, if one is.
  DateTime? _updateStartedAt;

  /// The section asked of the update under way; null for the next one.
  String? _updateSectionId;
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
    if (running != null) {
      _updateStartedAt = running.startedAt;
      _updateSectionId = running.sectionId;
      _awaitOutcome(running.outcome);
    }
  }

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
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _loadError = error;
      });
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
    final credentials = AiSettingsScope.of(context).credentials;
    final status = _status;
    if (credentials == null || status == null) return;
    if (!status.isNewStore) return _startUpdate();
    final start = await showStoryStartDialog(
      context,
      status: status,
      providerLabel: credentials.provider.label,
    );
    if (start != null) await _startUpdate(sectionId: start);
  }

  Future<void> _pressChoose() async {
    final status = _status;
    if (status == null) return;
    final section = await showStorySectionDialog(context, status: status);
    if (section != null) await _startUpdate(sectionId: section);
  }

  Future<void> _startUpdate({String? sectionId}) async {
    // The reader may have left while a dialog was open.
    if (!mounted) return;
    final settings = AiSettingsScope.of(context);
    final credentials = settings.credentials;
    if (credentials == null) return;
    setState(() {
      _updateStartedAt = DateTime.now();
      _updateSectionId = sectionId;
      _notice = null;
      _failure = null;
    });
    await _awaitOutcome(
      _backend.update(
        widget.book,
        credentials: credentials,
        model: settings.storyModel,
        effort: settings.storyEffort,
        checkQuotes: settings.checkStoryQuotes,
        sectionId: sectionId,
      ),
    );
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

  /// Waits for an update, then shows how it went. If the reader has left, it
  /// still finishes and is found on the store next time.
  Future<void> _awaitOutcome(Future<StoryUpdateOutcome> update) async {
    final outcome = await update;
    if (!mounted) return;
    final took = formatStoryElapsed(
      DateTime.now().difference(_updateStartedAt!),
    );
    if (!outcome.committed) {
      setState(() {
        _updateStartedAt = null;
        _failure = '${describeStoryUpdateFailure(outcome)} Took $took.';
      });
      return;
    }
    await _load();
    await _inspect();
    if (!mounted) return;
    final sections = _model?.sections.length ?? 0;
    setState(() {
      _updateStartedAt = null;
      _notice = [
        'Added ${outcome.sectionTitle} in $took.',
        // Never jump past the reader: the slider asks first.
        if (_progress.shown < sections) 'Drag the slider to see it.',
        if (outcome.unmatchedQuotes > 0)
          '${outcome.unmatchedQuotes} quote(s) couldn’t be matched to the book.',
      ].join(' ');
    });
  }

  @override
  Widget build(BuildContext context) {
    final model = _model;
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
          updateStartedAt: _updateStartedAt,
          updateSectionId: _updateSectionId,
          online: ConnectionScope.of(context).isOnline,
          hasKey: hasKey,
          filesBusy: _filesBusy,
          notice: _notice,
          failure: _failure,
          onUpdate: _pressUpdate,
          onChoose: _pressChoose,
          onLoad: _pressLoad,
          onExport: _pressExport,
        ),
        Expanded(child: body),
      ],
    );
  }
}
