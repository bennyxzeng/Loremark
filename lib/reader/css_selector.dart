import 'package:xml/xml.dart';

/// The first element of [document] that [selector] matches, in document order.
///
/// Understands what Readium writes for a page's first element: type, `#id`,
/// `.class`, `[attribute]`, `:root`, `:nth-child(n)` and `:nth-of-type(n)`,
/// joined by `>` or a space. Null if nothing matches, or if [selector] uses
/// anything else, so an unexpected one can't find the wrong element.
XmlElement? firstElementMatching(XmlDocument document, String selector) {
  final steps = _SelectorParser(selector.trim()).parse();
  if (steps == null) return null;
  for (final element in document.descendantElements) {
    if (_matches(element, steps, steps.length - 1)) return element;
  }
  return null;
}

bool _matches(XmlElement element, List<_Step> steps, int index) {
  final step = steps[index];
  if (!step.accepts(element)) return false;
  if (index == 0) return true;
  final parent = element.parentElement;
  if (step.isChild) return parent != null && _matches(parent, steps, index - 1);
  for (var above = parent; above != null; above = above.parentElement) {
    if (_matches(above, steps, index - 1)) return true;
  }
  return false;
}

/// One compound selector, such as `p.note:nth-child(2)`.
class _Step {
  _Step({required this.isChild});

  /// Whether a `>` joins this to the step before, rather than a space.
  final bool isChild;
  String? tag;
  String? id;
  bool isRoot = false;
  int? nthChild;
  int? nthOfType;
  final classes = <String>[];
  final attributes = <(String, String?)>[];

  bool accepts(XmlElement element) {
    if (isRoot && element.parentElement != null) return false;
    if (tag case final tag? when tag != '*' && !_isTag(element, tag)) {
      return false;
    }
    if (id case final id? when element.getAttribute('id') != id) return false;
    if (classes.isNotEmpty) {
      final own = (element.getAttribute('class') ?? '').split(RegExp(r'\s+'));
      if (!classes.every(own.contains)) return false;
    }
    for (final (name, value) in attributes) {
      final found = element.attributes.where(
        (attribute) =>
            attribute.name.qualified == name || attribute.name.local == name,
      );
      if (found.isEmpty) return false;
      if (value != null && found.first.value != value) return false;
    }
    if (nthChild case final n? when !_isNth(element, n, (_) => true)) {
      return false;
    }
    if (nthOfType case final n?) {
      final tag = element.localName.toLowerCase();
      if (!_isNth(element, n, (other) => _isTag(other, tag))) return false;
    }
    return true;
  }

  static bool _isTag(XmlElement element, String tag) =>
      element.localName.toLowerCase() == tag.toLowerCase();

  /// Whether [element] is number [n], from 1, of its siblings that [counts].
  static bool _isNth(
    XmlElement element,
    int n,
    bool Function(XmlElement) counts,
  ) {
    var count = 0;
    for (final sibling in element.parent!.children.whereType<XmlElement>()) {
      if (!counts(sibling)) continue;
      count++;
      if (identical(sibling, element)) return count == n;
      if (count >= n) return false;
    }
    return false;
  }
}

class _SelectorParser {
  _SelectorParser(this.text);

  final String text;
  var _at = 0;

  bool get _atEnd => _at >= text.length;
  String get _here => text[_at];

  static final _space = RegExp(r'\s');
  static final _nameEnd = RegExp(
    r'[\s>#.\[\]:+~,()="'
    "'"
    r']',
  );
  static final _hex = RegExp(r'[0-9a-fA-F]');

  void _skipSpace() {
    while (!_atEnd && _space.hasMatch(_here)) {
      _at++;
    }
  }

  /// The steps of the whole selector, or null if it can't be read.
  List<_Step>? parse() {
    final steps = <_Step>[];
    var isChild = false;
    while (true) {
      final step = _compound(isChild: isChild);
      if (step == null) return null;
      steps.add(step);
      final before = _at;
      _skipSpace();
      if (_atEnd) return steps;
      if (_here == '>') {
        isChild = true;
        _at++;
        _skipSpace();
      } else if (_at > before) {
        isChild = false;
      } else {
        return null;
      }
    }
  }

  _Step? _compound({required bool isChild}) {
    final step = _Step(isChild: isChild);
    final start = _at;
    while (!_atEnd && !_space.hasMatch(_here) && _here != '>') {
      final char = _here;
      if (char == '#') {
        _at++;
        step.id = _name();
        if (step.id == null) return null;
      } else if (char == '.') {
        _at++;
        final name = _name();
        if (name == null) return null;
        step.classes.add(name);
      } else if (char == '[') {
        if (!_attribute(step)) return null;
      } else if (char == ':') {
        if (!_pseudo(step)) return null;
      } else if (_at == start) {
        if (char == '*') {
          step.tag = '*';
          _at++;
        } else {
          step.tag = _name();
          if (step.tag == null) return null;
        }
      } else {
        return null;
      }
    }
    return _at == start ? null : step;
  }

  /// An identifier here, with any CSS escapes undone; null if there is none.
  String? _name() {
    final out = StringBuffer();
    while (!_atEnd && !_nameEnd.hasMatch(_here)) {
      if (_here != r'\') {
        out.write(_here);
        _at++;
      } else if (!_escape(out)) {
        return null;
      }
    }
    return out.isEmpty ? null : out.toString();
  }

  /// Reads the escape at a backslash: a code point in hex and one space after
  /// it, as in `\31 `, or a single character.
  bool _escape(StringBuffer out) {
    _at++;
    if (_atEnd) return false;
    final start = _at;
    while (!_atEnd && _at - start < 6 && _hex.hasMatch(_here)) {
      _at++;
    }
    if (_at == start) {
      out.write(_here);
      _at++;
      return true;
    }
    out.writeCharCode(int.parse(text.substring(start, _at), radix: 16));
    if (!_atEnd && _space.hasMatch(_here)) _at++;
    return true;
  }

  bool _attribute(_Step step) {
    _at++;
    // A prefix joins the name with an escaped colon, as in `epub\:type`.
    final name = _name();
    if (name == null || _atEnd) return false;
    String? value;
    if (_here == '=') {
      _at++;
      if (_atEnd || (_here != '"' && _here != "'")) return false;
      final quote = _here;
      _at++;
      final end = text.indexOf(quote, _at);
      if (end < 0) return false;
      value = text.substring(_at, end);
      _at = end + 1;
    }
    if (_atEnd || _here != ']') return false;
    _at++;
    step.attributes.add((name, value));
    return true;
  }

  bool _pseudo(_Step step) {
    _at++;
    final name = _name();
    if (name == 'root') {
      step.isRoot = true;
      return true;
    }
    if (name != 'nth-child' && name != 'nth-of-type') return false;
    if (_atEnd || _here != '(') return false;
    final end = text.indexOf(')', _at);
    if (end < 0) return false;
    final n = int.tryParse(text.substring(_at + 1, end).trim());
    if (n == null || n < 1) return false;
    _at = end + 1;
    if (name == 'nth-child') {
      step.nthChild = n;
    } else {
      step.nthOfType = n;
    }
    return true;
  }
}
