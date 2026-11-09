import 'dart:io';
import 'dart:math';

import '../story_model/story_model.dart';
import 'story_book.dart';
import 'story_store.dart';
import 'story_updater.dart';

/// One paragraph of a processed section, as the Story Map's evidence cites it.
///
/// These are not the paragraphs of `ParagraphIndex`, which search uses: those
/// are cut differently and numbered by spine item, so the two can't be swapped.
class StoryParagraph {
  const StoryParagraph({
    required this.sectionId,
    required this.id,
    required this.number,
    required this.text,
  });

  final String sectionId;

  /// Such as `p0012`, unique within its section.
  final String id;

  /// Position in its section, from 1.
  final int number;
  final String text;
}

/// The paragraphs of the sections a reader may see, for answering from them.
///
/// Later sections aren't left out by a check on each call: they were never
/// loaded, so nothing here can reach them. See [readStoryParagraphs].
class StoryParagraphs {
  /// [_sections] holds each section's paragraphs, in reading order.
  StoryParagraphs(this._sections)
    : _byId = {
        for (final MapEntry(key: section, value: paragraphs)
            in _sections.entries)
          section: {for (final item in paragraphs) item.id: item},
      };

  final Map<String, List<StoryParagraph>> _sections;
  final Map<String, Map<String, StoryParagraph>> _byId;

  /// The paragraph called [paragraphId], or null if there is none or its
  /// section isn't visible.
  StoryParagraph? paragraph(String sectionId, String paragraphId) =>
      _byId[sectionId]?[paragraphId];

  /// The paragraphs [evidence] cites, each with [context] neighbors on either
  /// side from its own section. No paragraph appears twice, they come in reading
  /// order, and evidence from a section that isn't visible is skipped.
  ///
  /// With the quote check off a quote may not match its paragraph, but the
  /// paragraph it names is always real, so answer from this text, not the quote.
  List<StoryParagraph> forEvidence(
    Iterable<Evidence> evidence, {
    int context = 0,
  }) {
    final wanted = <String, Set<int>>{};
    for (final item in evidence) {
      final cited = paragraph(item.sectionId, item.paragraphId);
      if (cited == null) continue;
      final index = cited.number - 1;
      final last = _sections[item.sectionId]!.length - 1;
      final indexes = wanted[item.sectionId] ??= {};
      for (
        var i = max(index - context, 0);
        i <= min(index + context, last);
        i++
      ) {
        indexes.add(i);
      }
    }
    return [
      for (final MapEntry(key: section, value: paragraphs) in _sections.entries)
        if (wanted[section] case final indexes?)
          for (final index in indexes.toList()..sort()) paragraphs[index],
    ];
  }
}

/// The paragraphs of the first [visibleSections] sections of the Story Map at
/// [storePath]. Empty if there is no map.
///
/// [visibleSections] is the spoiler boundary. For answering a reader, that is
/// `StoryMapBackend.reachedSections`. A map can hold sections the reader hasn't
/// reached, since updating isn't tied to reading progress.
///
/// A section comes from its saved text. A map loaded from a single
/// `story_model.json` has none, so its text comes from the EPUB at [epubPath],
/// and is used only if it hashes to what the model recorded.
///
/// Throws a [StoryStoreError] or a [StoryEpubError] if a section's text can't be
/// had either way, rather than returning part of what is visible.
StoryParagraphs readStoryParagraphs(
  String storePath,
  String epubPath, {
  required int visibleSections,
}) {
  final model = readStoryModel(storePath);
  if (model == null) return StoryParagraphs(const {});
  final store = StoryStore(Directory(storePath));
  final processed = (model['processed_sections'] as List)
      .cast<JsonMap>()
      .toList();
  processed.sort(
    (a, b) => (a['section_order'] as int).compareTo(b['section_order'] as int),
  );

  StoryBook? book;
  StoryBook openBook() => book ??= _openBookOf(model, epubPath);

  return StoryParagraphs({
    for (final section in processed.take(max(visibleSections, 0)))
      section['section_id'] as String: _paragraphsOf(
        section['section_id'] as String,
        _savedInput(store, section) ?? _extractedInput(openBook(), section),
      ),
  });
}

/// The saved text of [section], or null if it can't be trusted: missing, not
/// what the model recorded, or at a path outside the store.
JsonMap? _savedInput(StoryStore store, JsonMap section) {
  try {
    return store.readInput(section);
  } on StoryStoreError {
    return null;
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}

StoryBook _openBookOf(JsonMap model, String epubPath) {
  final StoryBook book;
  try {
    book = StoryBook.open(File(epubPath).readAsBytesSync());
  } on FileSystemException catch (error) {
    throw StoryEpubError('Cannot read the EPUB: ${error.message}');
  }
  checkStoryContinues(model, book);
  return book;
}

/// The text of [section] taken from [book], which `checkStoryContinues` has
/// shown to hold it.
JsonMap _extractedInput(StoryBook book, JsonMap section) {
  final id = section['section_id'] as String;
  final input = book.extract(
    book.sections.firstWhere((source) => source.sectionId == id),
  );
  if (input['text_sha256'] != section['text_sha256']) {
    throw StoryStoreError('The text of $id is not what the Story Map recorded');
  }
  return input;
}

List<StoryParagraph> _paragraphsOf(String sectionId, JsonMap input) {
  final paragraphs = (input['paragraphs'] as List).cast<JsonMap>();
  return [
    for (var i = 0; i < paragraphs.length; i++)
      StoryParagraph(
        sectionId: sectionId,
        id: paragraphs[i]['id'] as String,
        number: i + 1,
        text: paragraphs[i]['text'] as String,
      ),
  ];
}
