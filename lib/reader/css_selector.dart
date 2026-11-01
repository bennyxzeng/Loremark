import 'package:xml/xml.dart';

/// The first element of [document], in document order, that [selector]
/// matches, like `document.querySelector`. Null if nothing matches or the
/// selector uses syntax this doesn't understand.
///
/// Covers what Readium's selector generator writes for the first visible
/// element: tag names, `*`, `#id`, `.class`, `[attr]`, `[attr="value"]`,
/// `:root`, `:nth-child(n)`, `:nth-of-type(n)`, and the descendant and `>`
/// combinators. Names compare without case and namespace prefixes, since the
/// web view sees the same XHTML.
XmlElement? querySelector(XmlDocument document, String selector) {
  final List<_Step> steps;
  try {
    steps = _parse(selector);
  } on FormatException {
    return null;
  }
  if (steps.isEmpty) return null;
  for (final element in document.descendantElements) {
    if (_matches(element, steps, steps.length - 1)) return element;
  }
  return null;
}

/// One compound selector and the combinator joining it to the previous one.
class _Step {
  _Step(this.child);

  /// Whether this step must be a direct child of the previous one's match.
  final bool child;
  final List<bool Function(XmlElement)> tests = [];
}

/// Whether [element] matches [steps] up to and including [last], with
/// `steps[last]` matching [element] itself.
bool _matches(XmlElement element, List<_Step> steps, int last) {
  final step = steps[last];
  if (!step.tests.every((test) => test(element))) return false;
  if (last == 0) return true;
  var parent = element.parentElement;
  if (step.child) return parent != null && _matches(parent, steps, last - 1);
  for (; parent != null; parent = parent.parentElement) {
    if (_matches(parent, steps, last - 1)) return true;
  }
  return false;
}

List<_Step> _parse(String selector) {
  final steps = <_Step>[];
  final scanner = _Scanner(selector.trim());
  var child = false;
  while (!scanner.done) {
    final step = _Step(child);
    _compound(scanner, step);
    if (step.tests.isEmpty) throw const FormatException('empty compound');
    steps.add(step);
    final hadSpace = scanner.skipSpaces();
    if (scanner.done) break;
    if (scanner.peek == '>') {
      scanner.next();
      scanner.skipSpaces();
      child = true;
    } else if (hadSpace) {
      child = false;
    } else {
      throw FormatException('unexpected ${scanner.peek}');
    }
  }
  return steps;
}

void _compound(_Scanner scanner, _Step step) {
  if (scanner.peek == '*') {
    scanner.next();
    step.tests.add((_) => true);
  } else if (_isNameChar(scanner.peek)) {
    final tag = scanner.identifier().toLowerCase();
    step.tests.add((e) => e.name.local.toLowerCase() == tag);
  }
  while (!scanner.done) {
    switch (scanner.peek) {
      case '#':
        scanner.next();
        final id = scanner.identifier();
        step.tests.add((e) => e.getAttribute('id') == id);
      case '.':
        scanner.next();
        final name = scanner.identifier();
        step.tests.add(
          (e) => (e.getAttribute('class') ?? '')
              .split(RegExp(r'\s+'))
              .contains(name),
        );
      case '[':
        scanner.next();
        step.tests.add(_attribute(scanner));
      case ':':
        scanner.next();
        step.tests.add(_pseudo(scanner));
      default:
        return;
    }
  }
}

bool Function(XmlElement) _attribute(_Scanner scanner) {
  scanner.skipSpaces();
  final name = scanner.identifier().toLowerCase();
  scanner.skipSpaces();
  String? value;
  if (scanner.peek == '=') {
    scanner.next();
    scanner.skipSpaces();
    value = scanner.peek == '"' || scanner.peek == "'"
        ? scanner.quoted()
        : scanner.identifier();
    scanner.skipSpaces();
  }
  scanner.expect(']');
  return (e) {
    for (final attribute in e.attributes) {
      if (attribute.name.local.toLowerCase() != name) continue;
      return value == null || attribute.value == value;
    }
    return false;
  };
}

bool Function(XmlElement) _pseudo(_Scanner scanner) {
  final name = scanner.identifier().toLowerCase();
  if (name == 'root') return (e) => e.parent is XmlDocument;
  if (name != 'nth-child' && name != 'nth-of-type') {
    throw FormatException('unsupported :$name');
  }
  scanner.expect('(');
  scanner.skipSpaces();
  final n = int.tryParse(scanner.identifier());
  scanner.skipSpaces();
  scanner.expect(')');
  if (n == null || n < 1) throw const FormatException('unsupported nth');
  final ofType = name == 'nth-of-type';
  return (e) {
    final parent = e.parentElement;
    if (parent == null) return n == 1;
    var count = 0;
    for (final sibling in parent.childElements) {
      if (ofType && sibling.name.local != e.name.local) continue;
      count++;
      if (identical(sibling, e)) return count == n;
    }
    return false;
  };
}

bool _isNameChar(String c) =>
    c.isNotEmpty &&
    (RegExp(r'[A-Za-z0-9_-]').hasMatch(c) ||
        c == r'\' ||
        c.codeUnitAt(0) > 0x7F);

class _Scanner {
  _Scanner(this._text);

  final String _text;
  var _at = 0;

  bool get done => _at >= _text.length;
  String get peek => done ? '' : _text[_at];
  String next() => _text[_at++];

  bool skipSpaces() {
    final from = _at;
    while (!done && peek.trim().isEmpty) {
      _at++;
    }
    return _at > from;
  }

  void expect(String c) {
    if (peek != c) throw FormatException('expected $c');
    _at++;
  }

  /// A CSS identifier, with `\` escapes resolved.
  String identifier() {
    final out = StringBuffer();
    while (!done && _isNameChar(peek)) {
      if (peek == r'\') {
        out.write(_escape());
      } else {
        out.write(next());
      }
    }
    if (out.isEmpty) throw const FormatException('expected a name');
    return out.toString();
  }

  String quoted() {
    final quote = next();
    final out = StringBuffer();
    while (!done && peek != quote) {
      out.write(peek == r'\' ? _escape() : next());
    }
    expect(quote);
    return out.toString();
  }

  /// `\` followed by up to six hex digits and an optional space, or by any
  /// other character taken literally.
  String _escape() {
    _at++;
    if (done) throw const FormatException('dangling escape');
    final hex = RegExp(r'[0-9A-Fa-f]{1,6}').matchAsPrefix(_text, _at);
    if (hex == null) return next();
    _at = hex.end;
    if (!done && peek == ' ') _at++;
    return String.fromCharCode(int.parse(hex[0]!, radix: 16));
  }
}
