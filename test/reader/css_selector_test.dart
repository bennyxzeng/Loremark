import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/reader/css_selector.dart';
import 'package:xml/xml.dart';

void main() {
  final document = XmlDocument.parse('''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>t</title></head>
<body>
  <h1 id="top">Title</h1>
  <p class="lead first">One</p>
  <p>Two<span id="chapter.1">inner</span></p>
  <div><p>Three</p><p epub:type="note" data-x="y">Four</p></div>
  <p id="123">Five</p>
</body>
</html>''');

  String? textAt(String selector) =>
      firstElementMatching(document, selector)?.innerText.trim();

  test('follows the path Readium writes for a page', () {
    expect(textAt(':root > :nth-child(2) > :nth-child(2)'), 'One');
    expect(
      textAt(':root > :nth-child(2) > :nth-child(4) > :nth-child(2)'),
      'Four',
    );
    expect(firstElementMatching(document, ':root')?.localName, 'html');
  });

  test('finds by type, id, class and attribute', () {
    expect(textAt('h1'), 'Title');
    expect(textAt('#top'), 'Title');
    expect(textAt('.lead'), 'One');
    expect(textAt('p.first.lead'), 'One');
    expect(textAt("[data-x='y']"), 'Four');
    expect(textAt(r'[epub\:type="note"]'), 'Four');
    expect(textAt('[data-x]'), 'Four');
  });

  test('undoes escapes in names', () {
    expect(textAt(r'#chapter\.1'), 'inner');
    expect(textAt(r'#\31 23'), 'Five');
  });

  test('undoes escapes in attribute values', () {
    // What Readium writes for a page that starts with a picture.
    final picture = XmlDocument.parse(
      '<html><body><p>Text</p><figure>'
      '<img src="images/010.jpg" alt="it\'s"/></figure></body></html>',
    );
    String? found(String selector) =>
        firstElementMatching(picture, selector)?.getAttribute('src');
    expect(found(r"[src='images\/010\.jpg']"), 'images/010.jpg');
    expect(found(r'[src="images\/010\.jpg"]'), 'images/010.jpg');
    expect(found("[src='images/010.jpg']"), 'images/010.jpg');
    expect(found(r"[src='images\2f 010.jpg']"), 'images/010.jpg');
    // An escaped quote doesn't end the value.
    expect(found(r"[alt='it\'s']"), 'images/010.jpg');
    expect(found(r"[src='images\/011\.jpg']"), isNull);
  });

  test('tells a child from a descendant', () {
    expect(textAt('body > p:nth-of-type(2)'), 'Twoinner');
    expect(textAt('div p'), 'Three');
    expect(textAt('body p:nth-child(2)'), 'One');
    expect(textAt('div > p:nth-child(2)'), 'Four');
    expect(textAt('body > span'), isNull);
    expect(textAt('p span'), 'inner');
  });

  test('takes the first match in document order', () {
    expect(textAt('p'), 'One');
    expect(textAt('*'), isNotNull);
  });

  test('finds nothing where nothing matches', () {
    expect(textAt('h2'), isNull);
    expect(textAt('#nope'), isNull);
    expect(textAt(':root > :nth-child(9)'), isNull);
  });

  for (final selector in [
    '',
    '> p',
    ':root >',
    'p:not(.lead)',
    'p + p',
    'p ~ p',
    'h1, p',
    ':nth-child(2n)',
    ':nth-child(0)',
    '[data-x=y]',
    '[data-x',
    "[data-x='y]",
    r"[data-x='y\']",
    r'p\',
  ]) {
    test('refuses "$selector" rather than guess', () {
      expect(firstElementMatching(document, selector), isNull);
    });
  }
}
