import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/epub_sections.dart';
import 'package:loremark/story_map/story_map_backend.dart';
import 'package:loremark/story_model/story_model.dart';

/// A spine of [count] documents, `c0.xhtml` onwards.
List<SpineItem> _spine(int count) => [
  for (var i = 0; i < count; i++)
    SpineItem(path: 'OEBPS/c$i.xhtml', linear: true),
];

/// A section in the spine's document [index], or in none if it's null.
StorySection _section(int order, int? index, {String? fragment}) =>
    StorySection(
      id: 's$order',
      order: order,
      chapterNumber: order,
      title: 'Chapter $order',
      href: index == null
          ? null
          : 'OEBPS/c$index.xhtml${fragment == null ? '' : '#$fragment'}',
    );

void main() {
  final spine = _spine(10);

  test('with no map, there is none', () {
    expect(storyCoverage(null, spine, 3), StoryCoverage.none);
    expect(storyCoverage(const [], spine, 3), StoryCoverage.none);
  });

  group('a map of documents 2 to 5', () {
    final sections = [_section(1, 2), _section(2, 3), _section(3, 5)];

    test('leaves out what comes before it', () {
      expect(storyCoverage(sections, spine, 0), StoryCoverage.before);
      expect(storyCoverage(sections, spine, 1), StoryCoverage.before);
    });

    test('covers its first and last documents and all between', () {
      for (final index in [2, 3, 4, 5]) {
        expect(
          storyCoverage(sections, spine, index),
          StoryCoverage.inMap,
          reason: 'document $index',
        );
      }
    });

    test('is behind a reader past its last document', () {
      expect(storyCoverage(sections, spine, 6), StoryCoverage.ahead);
      expect(storyCoverage(sections, spine, 9), StoryCoverage.ahead);
    });
  });

  test('a document holding several sections counts as one', () {
    final sections = [
      _section(1, 2, fragment: 'part1'),
      _section(2, 2, fragment: 'part2'),
    ];
    expect(storyCoverage(sections, spine, 2), StoryCoverage.inMap);
    expect(storyCoverage(sections, spine, 3), StoryCoverage.ahead);
  });

  test('a map from a file needn\'t be in reading order', () {
    final sections = [_section(3, 6), _section(1, 2)];
    expect(storyCoverage(sections, spine, 1), StoryCoverage.before);
    expect(storyCoverage(sections, spine, 4), StoryCoverage.inMap);
    expect(storyCoverage(sections, spine, 7), StoryCoverage.ahead);
  });

  test('sections that can\'t be placed are left out', () {
    final sections = [_section(1, 2), _section(2, null), _section(3, 99)];
    expect(storyCoverage(sections, spine, 2), StoryCoverage.inMap);
    expect(storyCoverage(sections, spine, 3), StoryCoverage.ahead);
  });

  test('if none can be placed, the map counts as none', () {
    final sections = [_section(1, null)];
    expect(storyCoverage(sections, spine, 0), StoryCoverage.none);
  });
}
