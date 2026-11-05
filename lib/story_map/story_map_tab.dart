import 'package:flutter/material.dart';

import '../library/book.dart';
import '../settings/ai_settings.dart';
import '../settings/connection_status.dart';
import '../story_model/story_model.dart';
import '../story_update/story_updater.dart';
import 'story_map_backend.dart';
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
  int _finishedSections = 0;
  bool _loaded = false;
  Object? _loadError;
  StoryUpdateStatus? _status;
  bool _updating = false;
  String? _notice;
  String? _failure;

  StoryMapBackend get _backend => widget.backend;

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (mounted && widget.active) _inspect();
    });
    final running = _backend.running(widget.book);
    if (running != null) {
      _updating = true;
      _awaitOutcome(running);
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
      final finished = model == null
          ? 0
          : await _backend.finishedSections(widget.book, model.sections);
      if (!mounted) return;
      setState(() {
        _model = model;
        _finishedSections = finished;
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

  Future<void> _refreshPosition() async {
    final model = _model;
    if (model == null) return;
    try {
      final finished = await _backend.finishedSections(
        widget.book,
        model.sections,
      );
      if (mounted) setState(() => _finishedSections = finished);
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
    final settings = AiSettingsScope.of(context);
    final credentials = settings.credentials;
    final status = _status;
    if (credentials == null || status == null) return;
    String? start;
    if (status.isNewStore) {
      start = await showStoryStartDialog(
        context,
        status: status,
        providerLabel: credentials.provider.label,
      );
      if (start == null) return;
    }
    setState(() {
      _updating = true;
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
        startSectionId: start,
      ),
    );
  }

  /// Waits for an update, then shows how it went. If the reader has left, it
  /// still finishes and is found on the store next time.
  Future<void> _awaitOutcome(Future<StoryUpdateOutcome> update) async {
    final outcome = await update;
    if (!mounted) return;
    if (!outcome.committed) {
      setState(() {
        _updating = false;
        _failure = describeStoryUpdateFailure(outcome);
      });
      return;
    }
    await _load();
    await _inspect();
    if (!mounted) return;
    final sections = _model?.sections.length ?? 0;
    setState(() {
      _updating = false;
      _notice = [
        'Added ${outcome.sectionTitle}.',
        // Never jump past the reader: the slider asks first.
        if (_finishedSections < sections) 'Drag the slider to see it.',
        if (outcome.unmatchedQuotes > 0)
          '${outcome.unmatchedQuotes} quote(s) couldn’t be matched to the book.',
      ].join(' ');
    });
  }

  @override
  Widget build(BuildContext context) {
    final model = _model;
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
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Press Update to start this book’s Story Map, one section at a '
            'time.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      body = StoryMapScreen(model: model, finishedSections: _finishedSections);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StoryUpdateBar(
          status: _status,
          updating: _updating,
          online: ConnectionScope.of(context).isOnline,
          notice: _notice,
          failure: _failure,
          onUpdate: _pressUpdate,
        ),
        Expanded(child: body),
      ],
    );
  }
}
