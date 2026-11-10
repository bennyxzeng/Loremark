import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/ask/ask_citations.dart';

void main() {
  bool exists(String section, String paragraph) =>
      section == 'section-004' && paragraph != 'p9999';

  group('cleanCitations', () {
    test('keeps real references and drops the rest', () {
      expect(
        cleanCitations(
          'A [section-004/p0012]. B [section-004/p9999]. '
          'C [section-004/p0001, section-007/p0002]. D [page].',
          exists,
        ),
        'A [section-004/p0012]. B. C [section-004/p0001]. D [page].',
      );
    });

    test('leaves brackets that aren\'t citations alone', () {
      expect(cleanCitations('He said [sic] so.', exists), 'He said [sic] so.');
    });

    test('takes the separators a Chinese answer uses', () {
      expect(
        cleanCitations('甲[section-004/p0001，section-004/p0002]。', exists),
        '甲 [section-004/p0001, section-004/p0002]。'.replaceFirst(' ', ''),
      );
    });
  });

  group('splitAnswer', () {
    test('separates citations from the words', () {
      final parts = splitAnswer('Mara [s1/p0001, page] left [page].');
      expect(parts, hasLength(5));
      expect((parts[0] as AnswerText).text, 'Mara ');
      expect((parts[1] as AnswerCitation).refs, const [
        AskRef('s1', 'p0001'),
        AskRef.page(),
      ]);
      expect((parts[2] as AnswerText).text, ' left ');
      expect((parts[3] as AnswerCitation).refs.single.isPage, isTrue);
      expect((parts[4] as AnswerText).text, '.');
      expect(citesAnything(parts), isTrue);
    });

    test('holds back a citation still arriving', () {
      final parts = splitAnswer('Mara left [s1/p00', streaming: true);
      expect(parts, hasLength(1));
      expect((parts.single as AnswerText).text, 'Mara left ');
      expect(
        (splitAnswer('Mara left [s1/p00').single as AnswerText).text,
        'Mara left [s1/p00',
      );
    });

    test('says when nothing is cited', () {
      expect(citesAnything(splitAnswer('Just words.')), isFalse);
    });
  });
}
