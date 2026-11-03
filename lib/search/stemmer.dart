/// The Porter2 ("English") stemmer, written from Martin Porter's published
/// algorithm: https://snowballstem.org/algorithms/english/stemmer.html
/// (the Snowball 3.1.0 description, including its later exceptions).
///
/// Maps `running`, `runs` and `ran`-like forms of a word to one stem so that
/// a search for one finds the others. Input must be lowercase ASCII letters
/// (the tokenizer folds first); anything else is returned as is.
String porter2Stem(String word) {
  if (word.length <= 2) return word;
  final special = _exceptions1[word];
  if (special != null) return special;
  return _Porter2(word).stem();
}

/// Words the algorithm would get wrong, with their stems (exception list 1).
/// Words that map to themselves are the invariants.
const _exceptions1 = {
  'skis': 'ski',
  'skies': 'sky',
  'idly': 'idl',
  'gently': 'gentl',
  'ugly': 'ugli',
  'early': 'earli',
  'only': 'onli',
  'singly': 'singl',
  'sky': 'sky',
  'news': 'news',
  'howe': 'howe',
  'atlas': 'atlas',
  'cosmos': 'cosmos',
  'bias': 'bias',
  'andes': 'andes',
};

/// Word starts after which R1 is the rest of the word, so that families like
/// generate/general or organ/organic keep apart.
const _r1Prefixes = [
  'gener',
  'commun',
  'arsen',
  'past',
  'univers',
  'later',
  'emerg',
  'organ',
  'inter',
];

class _Porter2 {
  _Porter2(String word) : _w = word.split('') {
    if (_w.first == "'") _w.removeAt(0);
    // Y marks a consonant `y`: at the start, or after a vowel.
    if (_w.isNotEmpty && _w[0] == 'y') _w[0] = 'Y';
    for (var i = 1; i < _w.length; i++) {
      if (_w[i] == 'y' && _isVowel(i - 1)) _w[i] = 'Y';
    }
    _findRegions();
  }

  final List<String> _w;
  late int _r1;
  late int _r2;

  static const _vowels = {'a', 'e', 'i', 'o', 'u', 'y'};

  bool _isVowel(int i) => _vowels.contains(_w[i]);

  String get _word => _w.join();

  /// R1 is the region after the first non-vowel that follows a vowel; R2 is
  /// the same again inside R1.
  void _findRegions() {
    final word = _word;
    var start = 0;
    for (final prefix in _r1Prefixes) {
      if (word.startsWith(prefix)) {
        start = prefix.length;
        break;
      }
    }
    _r1 = start == 0 ? _regionAfter(0) : start;
    _r2 = _regionAfter(_r1);
  }

  int _regionAfter(int from) {
    for (var i = from + 1; i < _w.length; i++) {
      if (!_isVowel(i) && _isVowel(i - 1)) return i + 1;
    }
    return _w.length;
  }

  bool _endsWith(String suffix) {
    if (suffix.length > _w.length) return false;
    final offset = _w.length - suffix.length;
    for (var i = 0; i < suffix.length; i++) {
      if (_w[offset + i] != suffix[i]) return false;
    }
    return true;
  }

  /// The longest of [suffixes] the word ends with, or null.
  String? _longest(List<String> suffixes) {
    String? best;
    for (final suffix in suffixes) {
      if ((best == null || suffix.length > best.length) && _endsWith(suffix)) {
        best = suffix;
      }
    }
    return best;
  }

  int _suffixStart(String suffix) => _w.length - suffix.length;

  bool _inR1(String suffix) => _suffixStart(suffix) >= _r1;
  bool _inR2(String suffix) => _suffixStart(suffix) >= _r2;

  void _replace(String suffix, String with_) {
    _w.removeRange(_w.length - suffix.length, _w.length);
    _w.addAll(with_.split(''));
  }

  bool _containsVowelBefore(int end) {
    for (var i = 0; i < end; i++) {
      if (_isVowel(i)) return true;
    }
    return false;
  }

  /// A vowel followed by a non-vowel other than w, x or Y, and preceded by a
  /// non-vowel; or a vowel at the start followed by a non-vowel; or `past`.
  /// [end] is the length of the word part to look at.
  bool _endsInShortSyllable(int end) {
    if (end == 2) return _isVowel(0) && !_isVowel(1);
    if (end < 3) return false;
    if (end >= 4 && _w.sublist(end - 4, end).join() == 'past') return true;
    final last = _w[end - 1];
    return !_isVowel(end - 3) &&
        _isVowel(end - 2) &&
        !_isVowel(end - 1) &&
        last != 'w' &&
        last != 'x' &&
        last != 'Y';
  }

  bool get _isShort => _r1 == _w.length && _endsInShortSyllable(_w.length);

  String stem() {
    _step0();
    _step1a();
    _step1b();
    _step1c();
    _step2();
    _step3();
    _step4();
    _step5();
    return _word.replaceAll('Y', 'y');
  }

  void _step0() {
    final suffix = _longest(const ["'s'", "'s", "'"]);
    if (suffix != null) _replace(suffix, '');
  }

  void _step1a() {
    final suffix = _longest(const ['sses', 'ied', 'ies', 'us', 'ss', 's']);
    switch (suffix) {
      case 'sses':
        _replace('sses', 'ss');
      case 'ied' || 'ies':
        // "ties" -> "tie", "cries" -> "cri".
        _replace(suffix!, _w.length - suffix.length > 1 ? 'i' : 'ie');
      case 's':
        // Delete if a vowel precedes it, but not immediately.
        if (_containsVowelBefore(_w.length - 2)) _replace('s', '');
    }
  }

  void _step1b() {
    final suffix = _longest(const [
      'eedly',
      'eed',
      'ingly',
      'edly',
      'ing',
      'ed',
    ]);
    if (suffix == null) return;
    final stemLength = _w.length - suffix.length;
    final before = _w.sublist(0, stemLength).join();
    if (suffix == 'eed' || suffix == 'eedly') {
      // proceed, exceed and succeed are not past tenses.
      if (_inR1(suffix) && !const {'proc', 'exc', 'succ'}.contains(before)) {
        _replace(suffix, 'ee');
      }
      return;
    }
    if (suffix == 'ing') {
      // dying -> die, and inning, outing, herring, evening stay whole.
      if (stemLength == 2 && before.endsWith('y') && !_isVowel(0)) {
        _replace('ying', 'ie');
        return;
      }
      if (const {
        'inn',
        'out',
        'cann',
        'herr',
        'earr',
        'even',
      }.contains(before)) {
        return;
      }
    }
    if (!_containsVowelBefore(stemLength)) return;
    _replace(suffix, '');
    if (_endsWith('at') || _endsWith('bl') || _endsWith('iz')) {
      _w.add('e');
    } else if (_endsWithDouble()) {
      // hopp -> hop, but add, egg and off keep their double.
      final onlyVowel = _w.length == 3 && 'aeo'.contains(_w[0]);
      if (!onlyVowel) _w.removeLast();
    } else if (_isShort) {
      _w.add('e');
    }
  }

  bool _endsWithDouble() {
    if (_w.length < 2) return false;
    final pair = _w[_w.length - 2] + _w[_w.length - 1];
    return const {
      'bb',
      'dd',
      'ff',
      'gg',
      'mm',
      'nn',
      'pp',
      'rr',
      'tt',
    }.contains(pair);
  }

  void _step1c() {
    if (_w.length > 2 &&
        (_w.last == 'y' || _w.last == 'Y') &&
        !_isVowel(_w.length - 2)) {
      _w[_w.length - 1] = 'i';
    }
  }

  static const _step2Suffixes = {
    'tional': 'tion',
    'enci': 'ence',
    'anci': 'ance',
    'abli': 'able',
    'entli': 'ent',
    'izer': 'ize',
    'ization': 'ize',
    'ational': 'ate',
    'ation': 'ate',
    'ator': 'ate',
    'alism': 'al',
    'aliti': 'al',
    'alli': 'al',
    'fulness': 'ful',
    'ousli': 'ous',
    'ousness': 'ous',
    'iveness': 'ive',
    'iviti': 'ive',
    'biliti': 'ble',
    'bli': 'ble',
    'ogist': 'og',
    'fulli': 'ful',
    'lessli': 'less',
  };

  void _step2() {
    final suffix = _longest([..._step2Suffixes.keys, 'ogi', 'li']);
    if (suffix == null || !_inR1(suffix)) return;
    switch (suffix) {
      case 'ogi':
        if (_w.length > 3 && _w[_w.length - 4] == 'l') _replace('ogi', 'og');
      case 'li':
        if (_w.length > 2 && 'cdeghkmnrt'.contains(_w[_w.length - 3])) {
          _replace('li', '');
        }
      default:
        _replace(suffix, _step2Suffixes[suffix]!);
    }
  }

  static const _step3Suffixes = {
    'tional': 'tion',
    'ational': 'ate',
    'alize': 'al',
    'icate': 'ic',
    'iciti': 'ic',
    'ical': 'ic',
    'ful': '',
    'ness': '',
  };

  void _step3() {
    final suffix = _longest([..._step3Suffixes.keys, 'ative']);
    if (suffix == null || !_inR1(suffix)) return;
    if (suffix == 'ative') {
      if (_inR2(suffix)) _replace(suffix, '');
    } else {
      _replace(suffix, _step3Suffixes[suffix]!);
    }
  }

  void _step4() {
    final suffix = _longest(const [
      'al',
      'ance',
      'ence',
      'er',
      'ic',
      'able',
      'ible',
      'ant',
      'ement',
      'ment',
      'ent',
      'ism',
      'ate',
      'iti',
      'ous',
      'ive',
      'ize',
      'ion',
    ]);
    if (suffix == null || !_inR2(suffix)) return;
    if (suffix == 'ion') {
      if (_w.length > 3) {
        final before = _w[_w.length - 4];
        if (before == 's' || before == 't') _replace(suffix, '');
      }
    } else {
      _replace(suffix, '');
    }
  }

  void _step5() {
    if (_w.isEmpty) return;
    if (_w.last == 'e') {
      final before = _w.length - 1;
      if (before >= _r2 ||
          (before >= _r1 && !_endsInShortSyllable(_w.length - 1))) {
        _w.removeLast();
      }
    } else if (_w.last == 'l' &&
        _w.length - 1 >= _r2 &&
        _w.length > 1 &&
        _w[_w.length - 2] == 'l') {
      _w.removeLast();
    }
  }
}
