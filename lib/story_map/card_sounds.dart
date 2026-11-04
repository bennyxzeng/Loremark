import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The sounds of a card reveal, from `assets/sounds/`. They are synthesized by
/// `tool/card_sounds/generate.dart`.
enum CardSound {
  chargeShort('charge_short'),
  chargeLong('charge_long'),
  burstLow('burst_low'),
  burstHigh('burst_high'),
  flip('flip'),
  star1('star_1'),
  star2('star_2'),
  star3('star_3'),
  star4('star_4'),
  star5('star_5');

  const CardSound(this.file);

  final String file;

  /// The sound of lighting the [number]th star, from 1 to 5.
  static CardSound star(int number) => values.byName('star$number');
}

/// Plays card sounds, and remembers whether the reader wants them.
abstract class CardSounds extends ChangeNotifier {
  bool get enabled;

  set enabled(bool value);

  /// Gets ready to play. Cards call this as they open, so that nothing touches
  /// the audio system until a card is actually shown.
  void prepare();

  void play(CardSound sound);

  /// Silences whatever is playing, as when a reveal is skipped.
  void stop();
}

/// Whether card sounds are on, kept in a small file on the device.
class CardSoundPreference {
  CardSoundPreference(this.file);

  /// The preference in the app's support directory.
  static Future<CardSoundPreference> open() async {
    final support = await getApplicationSupportDirectory();
    return CardSoundPreference(File('${support.path}/card_sounds.json'));
  }

  final File file;

  /// Whether sounds are on. They are unless the reader turned them off, so a
  /// missing or damaged file counts as on.
  Future<bool> load() async {
    try {
      final json = jsonDecode(await file.readAsString());
      return json is! Map || json['enabled'] != false;
    } on Object {
      return true;
    }
  }

  Future<void> save({required bool enabled}) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({'enabled': enabled}));
  }
}

/// [CardSounds] on the device's audio system.
///
/// Sound is a bonus here, so a failure only means silence.
class AudioCardSounds extends CardSounds {
  /// A cue this late would land on top of the ones after it, so it is dropped.
  static const _tooLate = Duration(milliseconds: 250);

  /// Follows the silent switch and leaves the reader's music playing.
  static final _context = AudioContext(
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.game,
      audioFocus: AndroidAudioFocus.none,
    ),
  );

  final _players = <CardSound, AudioPlayer>{};
  CardSoundPreference? _preference;
  Future<void>? _ready;
  bool _enabled = true;
  bool _disposed = false;

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    notifyListeners();
    if (!value) stop();
    _preference?.save(enabled: value).ignore();
  }

  @override
  void prepare() => _ready ??= _load();

  Future<void> _load() async {
    try {
      final preference = await CardSoundPreference.open();
      _preference = preference;
      final saved = await preference.load();
      if (!_disposed && saved != _enabled) {
        _enabled = saved;
        notifyListeners();
      }
      for (final sound in CardSound.values) {
        if (_disposed) return;
        final player = AudioPlayer();
        _players[sound] = player;
        await player.setAudioContext(_context);
        await player.setPlayerMode(PlayerMode.lowLatency);
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource('sounds/${sound.file}.wav'));
      }
    } on Object catch (error) {
      debugPrint('Card sounds are unavailable: $error');
    }
  }

  @override
  void play(CardSound sound) {
    prepare();
    final asked = DateTime.now();
    _ready!
        .then((_) async {
          if (_disposed || !_enabled) return;
          if (DateTime.now().difference(asked) > _tooLate) return;
          final player = _players[sound];
          if (player == null) return;
          await player.stop();
          await player.resume();
        })
        .catchError(_ignore);
  }

  @override
  void stop() {
    for (final player in _players.values) {
      player.stop().catchError(_ignore);
    }
  }

  static void _ignore(Object error) {
    debugPrint('A card sound failed: $error');
  }

  @override
  void dispose() {
    _disposed = true;
    for (final player in _players.values) {
      player.dispose().catchError(_ignore);
    }
    super.dispose();
  }
}
