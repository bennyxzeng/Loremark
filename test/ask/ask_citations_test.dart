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
          pageLines: 3,
        ),
        'A [section-004/p0012]. B. C [section-004/p0001]. D [page].',
      );
    });

    test('keeps lines of the recent pages that were sent', () {
      expect(
        cleanCitations(
          'A [page/1]. B [page/3, section-004/p0012]. C [page/4]. D [page/0]. '
          'E [page/99999999999999999999999].',
          exists,
          pageLines: 3,
        ),
        'A [page/1]. B [page/3, section-004/p0012]. C. D. E.',
      );
    });

    test('drops the recent pages when none were sent', () {
      expect(
        cleanCitations(
          'A [page/1]. B [page]. C [section-004/p0012].',
          exists,
          pageLines: 0,
        ),
        'A. B. C [section-004/p0012].',
      );
    });

    test('leaves brackets that aren\'t citations alone', () {
      expect(
        cleanCitations('He said [sic] so.', exists, pageLines: 0),
        'He said [sic] so.',
      );
    });

    test('takes the separators a Chinese answer uses', () {
      expect(
        cleanCitations('甲[section-004/p0001，page/2]。', exists, pageLines: 2),
        '甲 [section-004/p0001, page/2]。'.replaceFirst(' ', ''),
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

    test('reads lines of the recent pages', () {
      final parts = splitAnswer('Mara [page/12, s1/p0001] left [page/3].');
      expect((parts[1] as AnswerCitation).refs, const [
        AskRef.page(12),
        AskRef('s1', 'p0001'),
      ]);
      expect((parts[3] as AnswerCitation).refs.single, const AskRef.page(3));
      expect(const AskRef.page(3), isNot(const AskRef.page()));
      expect('${const AskRef.page(3)}', 'page/3');
      expect('${const AskRef.page()}', 'page');
    });

    test('holds back a citation still arriving', () {
      final parts = splitAnswer('Mara left [s1/p00', streaming: true);
      expect(parts, hasLength(1));
      expect((parts.single as AnswerText).text, 'Mara left ');
      expect(
        (splitAnswer('Mara left [s1/p00').single as AnswerText).text,
        'Mara left [s1/p00',
      );
      expect(
        (splitAnswer('Mara left [page/1', streaming: true).single as AnswerText)
            .text,
        'Mara left ',
      );
    });

    test('says when nothing is cited', () {
      expect(citesAnything(splitAnswer('Just words.')), isFalse);
    });
  });
}
