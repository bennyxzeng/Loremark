import 'package:loremark/ask/ask_backend.dart';
import 'package:loremark/ask/ask_boundary.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/epub_reader_service.dart';
import 'package:loremark/reader/epub_sections.dart';
import 'package:loremark/reading/text_position.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/story_model/story_snapshot.dart';
import 'package:loremark/story_update/story_paragraphs.dart';

/// An Ask backend in memory: a map, its paragraphs, and where the reader is.
class FakeAskBackend implements AskBackend {
  FakeAskBackend({this.model, required this.reach, this.all = const {}});

  StoryModel? model;
  AskReach reach;

  /// Every section's paragraphs; [paragraphs] keeps what [reach] lets through.
  Map<String, List<StoryParagraph>> all;

  /// If set, working out where the reader is fails with it.
  Object? error;

  /// The passages [passageTarget] was asked to place.
  final placed = <StoryParagraph>[];

  int reaches = 0;

  /// The page ends [recentPages] was asked about.
  final pagesAsked = <TextPosition>[];

  /// The section's text before the recent pages in [reach], which Ask wasn't
  /// sent.
  String textBefore = '';

  @override
  Future<StoryModel?> loadModel(Book book) async => model;

  @override
  Future<AskReach> askReach(Book book, List<StorySection> sections) async {
    reaches++;
    if (error case final error?) throw error;
    return reach;
  }

  @override
  Future<StoryParagraphs> paragraphs(
    Book book,
    StoryReadingProgress progress,
  ) async {
    final sections = model?.sections ?? const <StorySection>[];
    return StoryParagraphs({
      for (final (i, section) in sections.take(progress.shown).indexed)
        section.id: i == progress.finished
            ? (all[section.id] ?? const [])
                  .take(progress.paragraphsReadInNext)
                  .toList()
            : all[section.id] ?? const [],
    });
  }

  @override
  Future<PassageTarget?> passageTarget(
    Book book,
    StorySection section,
    StoryParagraph paragraph,
  ) async {
    placed.add(paragraph);
    return PassageTarget(
      sectionIndex: section.order,
      progression: 0,
      highlight: paragraph.text,
    );
  }

  /// The recent pages in [reach], wherever [end] says they ended.
  @override
  Future<RecentPages?> recentPages(Book book, TextPosition end) async {
    pagesAsked.add(end);
    final text = reach.page?.text;
    if (text == null) return null;
    final section = '$textBefore$text';
    return RecentPages(
      end.sectionIndex,
      PageText(section, pageLines(text, textBefore.length), section.length),
    );
  }
}
