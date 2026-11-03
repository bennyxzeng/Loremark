import 'dart:convert';

/// A reader position in Readium pages, as the app prints it in its debug-only
/// `LOREMARK_POSITION` logcat line.
///
/// Pages are zero-based within their section and Readium paginates per section,
/// so two positions are only comparable through [pageDistance].
class PagePosition {
  const PagePosition({
    required this.section,
    required this.page,
    required this.pages,
    this.progression,
  });

  factory PagePosition.fromJson(Map<String, dynamic> json) => PagePosition(
    section: json['section'] as int,
    page: json['currentPage'] as int,
    pages: json['totalPages'] as int,
    progression: (json['progression'] as num?)?.toDouble(),
  );

  /// The page a saved progression falls on in a section of [pages] pages.
  ///
  /// The saved file has no page number. Readium saves where a page starts, and
  /// the last page saves exactly 1.0, hence the clamp.
  factory PagePosition.fromProgression({
    required int section,
    required double progression,
    required int pages,
  }) {
    // The epsilon keeps 3/8 * 8 from landing on 2.9999999.
    final page = (progression * pages + 1e-6).floor().clamp(0, pages - 1);
    return PagePosition(
      section: section,
      page: page,
      pages: pages,
      progression: progression,
    );
  }

  final int section;
  final int page;
  final int pages;
  final double? progression;

  /// Whether this is the last page of its section.
  bool get isLastPage => page >= pages - 1;

  Map<String, dynamic> toJson() => {
    'section': section,
    'page': page,
    'pages': pages,
    if (progression != null) 'progression': progression,
  };

  @override
  String toString() => 's$section p${page + 1}/$pages';

  @override
  bool operator ==(Object other) =>
      other is PagePosition &&
      other.section == section &&
      other.page == page &&
      other.pages == pages;

  @override
  int get hashCode => Object.hash(section, page, pages);
}

/// How many page turns apart [a] and [b] are, or null if they can't be
/// compared.
///
/// Within a section it is the page difference. Across the boundary of two
/// neighbouring sections it counts the turns through the boundary. Sections
/// further apart, or a section that repaginated between the two readings
/// (same section, different page count), return null: the harness reports
/// those as failures instead of guessing.
int? pageDistance(PagePosition a, PagePosition b) {
  final gap = b.section - a.section;
  if (gap == 0) {
    if (a.pages != b.pages) return null;
    return (a.page - b.page).abs();
  }
  if (gap.abs() > 1) return null;
  final earlier = gap > 0 ? a : b;
  final later = gap > 0 ? b : a;
  return (earlier.pages - 1 - earlier.page) + 1 + later.page;
}

const _logTag = 'LOREMARK_POSITION';

/// Every position line in [logcat], oldest first.
///
/// Lines of other tags, partial lines and lines whose JSON doesn't parse are
/// skipped, since logcat interleaves everything the process prints.
List<PagePosition> parsePositionLines(String logcat) {
  final positions = <PagePosition>[];
  for (final line in const LineSplitter().convert(logcat)) {
    final start = line.indexOf(_logTag);
    if (start < 0) continue;
    final json = line.substring(start + _logTag.length).trim();
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) {
        positions.add(PagePosition.fromJson(decoded));
      }
    } on Object {
      continue;
    }
  }
  return positions;
}
