import 'package:loremark/story_map/card_sounds.dart';

/// Records what would have played, without touching the audio system.
class FakeCardSounds extends CardSounds {
  final played = <CardSound>[];
  int stops = 0;
  bool _enabled = true;

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) {
    _enabled = value;
    notifyListeners();
  }

  @override
  void prepare() {}

  @override
  void play(CardSound sound) {
    if (_enabled) played.add(sound);
  }

  @override
  void stop() => stops++;
}
