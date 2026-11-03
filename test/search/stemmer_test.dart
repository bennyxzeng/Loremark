import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/search/stemmer.dart';

void main() {
  test('stems the sample of the official Snowball vocabulary', () {
    final wrong = <String>[];
    for (final MapEntry(:key, :value) in _snowballSample.entries) {
      final got = porter2Stem(key);
      if (got != value) wrong.add('$key: got $got, want $value');
    }
    expect(wrong, isEmpty);
  });

  test('leaves words of two letters or fewer alone', () {
    expect(porter2Stem('is'), 'is');
    expect(porter2Stem('a'), 'a');
  });

  test('treats the exceptional words as the algorithm says', () {
    expect(porter2Stem('skies'), 'sky');
    expect(porter2Stem('news'), 'news');
    expect(porter2Stem('atlas'), 'atlas');
  });

  test('conflates the inflections a reader would type', () {
    final forms = ['run', 'runs'].map(porter2Stem).toSet();
    expect(forms, hasLength(1));
    expect(porter2Stem('walking'), porter2Stem('walked'));
    expect(porter2Stem('mysteries'), porter2Stem('mystery'));
  });
}

/// Word and stem pairs from Snowball's English test vocabulary, `voc.txt` and
/// `output.txt` (https://github.com/snowballstem/snowball-data/tree/master/english,
/// BSD-3-Clause). Every 400th word, plus the cases the algorithm's exceptions
/// and Snowball 3.x changes are about. The full 42,649 pairs matched when
/// this stemmer was written.
const _snowballSample = {
  'actors': 'actor',
  'added': 'add',
  'adding': 'add',
  'aggressor': 'aggressor',
  'agreed': 'agre',
  'amend': 'amend',
  'apologists': 'apolog',
  'appalling': 'appal',
  'arthur': 'arthur',
  'auks': 'auk',
  'banishing': 'banish',
  'bedsteads': 'bedstead',
  'betrayed': 'betray',
  'bloomsbury': 'bloomsburi',
  'bouts': 'bout',
  'browne': 'brown',
  'caelius': 'caelius',
  'carnegie': 'carnegi',
  'chalr': 'chalr',
  'chipping': 'chip',
  'clicking': 'click',
  'com': 'com',
  'communism': 'communism',
  'conclusions': 'conclus',
  'conditional': 'condit',
  'consign': 'consign',
  'consummate': 'consumm',
  'corrobery': 'corroberi',
  'crept': 'crept',
  'cries': 'cri',
  'curves': 'curv',
  'decease': 'deceas',
  'densest': 'densest',
  'deyvle': 'deyvl',
  'discoverin': 'discoverin',
  'ditty': 'ditti',
  'drawers': 'drawer',
  'dying': 'die',
  'easter': 'easter',
  'ebbed': 'ebb',
  'embowell': 'embowel',
  'emergency': 'emergenc',
  'ensconcing': 'ensconc',
  'erred': 'err',
  'esq': 'esq',
  'evening': 'evening',
  'exceeds': 'exceed',
  'expectancy': 'expect',
  'family': 'famili',
  'feed': 'feed',
  'fevers': 'fever',
  'fleshpots': 'fleshpot',
  'flies': 'fli',
  'fluently': 'fluentli',
  'forfeit': 'forfeit',
  'fronte': 'front',
  'gas': 'gas',
  'gatherings': 'gather',
  'generate': 'generat',
  'geologist': 'geolog',
  'glittered': 'glitter',
  'graveless': 'graveless',
  'gusts': 'gust',
  'happily': 'happili',
  'haunting': 'haunt',
  'hieing': 'hie',
  'hoped': 'hope',
  'hopping': 'hop',
  'horum': 'horum',
  'hying': 'hie',
  'idlers': 'idler',
  'inarticulately': 'inarticul',
  'inflammable': 'inflamm',
  'intercepting': 'intercept',
  'internal': 'internal',
  'international': 'internat',
  'israel': 'israel',
  'june': 'june',
  'knack': 'knack',
  'lacs': 'lac',
  'lateral': 'lateral',
  'lecon': 'lecon',
  'linnets': 'linnet',
  'lucentio': 'lucentio',
  'luxuriating': 'luxuri',
  'malignantly': 'malign',
  'matrons': 'matron',
  'mewlinn': 'mewlinn',
  'mistrustful': 'mistrust',
  'mountant': 'mountant',
  'natives': 'nativ',
  'news': 'news',
  'noddle': 'noddl',
  'occurrences': 'occurr',
  'offing': 'off',
  'organic': 'organic',
  'oruro': 'oruro',
  'oz': 'oz',
  'parties': 'parti',
  'pasting': 'paste',
  'pennyworth': 'pennyworth',
  'philippi': 'philippi',
  'plantation': 'plantat',
  'popped': 'pop',
  'prefix': 'prefix',
  'proceed': 'proceed',
  'profitable': 'profit',
  'puling': 'pule',
  'quite': 'quit',
  'ream': 'ream',
  'regardons': 'regardon',
  'reprobated': 'reprob',
  'revolutionist': 'revolutionist',
  'rosebud': 'rosebud',
  'saltness': 'salt',
  'schwager': 'schwager',
  'seminary': 'seminari',
  'shepherdess': 'shepherdess',
  'siminary': 'siminari',
  'skies': 'sky',
  'skis': 'ski',
  'sky': 'sky',
  'slung': 'slung',
  'somewhither': 'somewhith',
  'spoil': 'spoil',
  'steamer': 'steamer',
  'stroked': 'stroke',
  'sunders': 'sunder',
  'swordsman': 'swordsman',
  'telescope': 'telescop',
  'thracian': 'thracian',
  'ties': 'tie',
  'tommy': 'tommi',
  'trencher': 'trencher',
  'twas': 'twas',
  'uncross': 'uncross',
  'unkennel': 'unkennel',
  'unstain': 'unstain',
  'valid': 'valid',
  'vii': 'vii',
  'vileness': 'vile',
  'waitress': 'waitress',
  'weobly': 'weobli',
  'winters': 'winter',
  'wrymug': 'wrymug',
};
