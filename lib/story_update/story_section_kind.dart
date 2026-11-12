/// What part of a book a section looks like, so a reader picking sections for
/// the Story Map can tell the story from what surrounds it.
///
/// Only a guess. It labels sections and decides what "Select all main text"
/// picks, and the reader can always pick differently.
enum StorySectionKind {
  story(null),
  illustrations('Illustrations'),
  frontMatter('Front matter'),
  afterword('Afterword'),
  backMatter('Back matter'),
  supplementary('Outside reading order');

  const StorySectionKind(this.label);

  /// What the section is labelled with; null for the story, which isn't.
  final String? label;
}

/// Guesses what [title]'s section is. The book's own word comes first, where
/// it gives one, since many books give none:
///
/// 1. [types]: the `epub:type`s and `doc-` roles of the section, and of the
///    landmarks or guide entries pointing at it.
/// 2. Where it falls next to the book's landmarks: before [bodyStart], the
///    section where the body matter starts, or from [backStart] on. Either only
///    takes a section out of the story; one inside the body may still be a page
///    of illustrations.
/// 3. Whether the spine lists it as [linear].
/// 4. Its title, in English, Chinese or Japanese.
/// 5. Its text: a little text around pictures is a page of illustrations.
StorySectionKind classifyStorySection({
  required String title,
  required int textChars,
  required int imageCount,
  Set<String> types = const {},
  int? order,
  int? bodyStart,
  int? backStart,
  bool linear = true,
}) {
  final declared = _declaredKind(types);
  if (declared != null) return declared;
  if (order != null) {
    if (bodyStart != null && order < bodyStart) {
      return StorySectionKind.frontMatter;
    }
    if (backStart != null && order >= backStart) {
      return StorySectionKind.backMatter;
    }
  }
  if (!linear) return StorySectionKind.supplementary;
  for (final (kind, pattern) in _titles) {
    if (pattern.hasMatch(title)) return kind;
  }
  if (imageCount > 0 && textChars < 500 && textChars < 100 * imageCount) {
    return StorySectionKind.illustrations;
  }
  return StorySectionKind.story;
}

/// The kind [types] say, if they say one. A section that says it is front or
/// back matter is taken at its word over one that also says `chapter`.
StorySectionKind? _declaredKind(Set<String> types) {
  if (types.any(_frontTypes.contains)) return StorySectionKind.frontMatter;
  if (types.contains('afterword')) return StorySectionKind.afterword;
  if (types.any(_backTypes.contains)) return StorySectionKind.backMatter;
  if (types.any(_storyTypes.contains)) return StorySectionKind.story;
  return null;
}

// From the EPUB Structural Semantics Vocabulary, which DPUB-ARIA's `doc-` roles
// follow. `bodymatter` isn't here: books that use it often put it on every
// document of the body, pages of illustrations too, so it only marks where the
// body starts.
const _frontTypes = {
  'cover',
  'titlepage',
  'halftitlepage',
  'toc',
  'frontmatter',
  'preface',
  'foreword',
  'introduction',
  'dedication',
  'epigraph',
  'copyright-page',
  'imprint',
  'loi',
  'lot',
};
const _backTypes = {
  'backmatter',
  'appendix',
  'colophon',
  'acknowledgments',
  'contributors',
  'other-credits',
  'glossary',
  'index',
  'bibliography',
  'endnotes',
  'footnotes',
  'rearnotes',
  'errata',
};
const _storyTypes = {
  'chapter',
  'part',
  'volume',
  'prologue',
  'epilogue',
  'conclusion',
};

/// A title starting with one of [english], or holding one of [cjk] anywhere.
/// English is held to the start, so "Under Cover" stays a chapter; Chinese and
/// Japanese titles often put a volume or number first.
RegExp _title(String english, String cjk) =>
    RegExp('^\\W*(?:$english)\\b|$cjk', caseSensitive: false);

/// In order: the first that matches is taken.
final _titles = [
  (
    StorySectionKind.frontMatter,
    _title(
      r"front ?matter|cover|title ?page|copyright|(?:table of )?contents|"
          r"dedication|epigraph|preface|foreword",
      '封面|扉页|扉頁|目录|目錄|目次|版权|版權|献词|獻詞|题记|題記|前言|序言|'
          '内容简介|內容簡介|内容提要|內容提要',
    ),
  ),
  (
    StorySectionKind.afterword,
    _title(
      r"afterword|author['’]?s note|translator['’]?s note|postscript",
      '后记|後記|あとがき|作者的话|作者的話|解说|解說|解説',
    ),
  ),
  (
    StorySectionKind.backMatter,
    _title(
      r"back ?matter|about the authors?|acknowledg\w*|newsletter|colophon|"
          r"also by|bonus preview|sneak peek",
      '作者简介|作者簡介|作者介绍|作者介紹|著者紹介|致谢|致謝|奥付',
    ),
  ),
  (
    StorySectionKind.illustrations,
    _title(
      r'illustrations?|plates?|colou?r (?:inserts?|pages?|illustrations?)|'
          r'gallery',
      '插图|插圖|插画|插畫|彩页|彩頁|彩插|口绘|口繪|口絵|イラスト',
    ),
  ),
];
