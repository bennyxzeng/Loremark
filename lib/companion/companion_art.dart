import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'companion_director.dart';

/// How much of the companion shows.
enum CompanionFrame {
  /// All of her, head to boots.
  full,

  /// Head and shoulders, with the raised hand.
  bust,
}

/// The companion's pictures, made by `tool/companion/build_companion.py`: a
/// body with holes where the eyes, mouth and hand go, and the pictures that
/// fill them.
///
/// A pose is pasted together at the pictures' own size, at whole pixels, and
/// then shown scaled as one picture. Scaling the parts separately would
/// smooth each hole's edge on its own and leave a faint seam around it.
class CompanionArt {
  CompanionArt._(this._body, this._layers, this._frames);

  static const _folder = 'assets/companion';

  static Future<CompanionArt>? _loading;

  /// The pictures, loaded once and kept. A failed load is tried again next
  /// time.
  static Future<CompanionArt> load() async {
    final loading = _loading ??= _load();
    try {
      return await loading;
    } catch (_) {
      if (identical(_loading, loading)) _loading = null;
      rethrow;
    }
  }

  static Future<CompanionArt> _load() async {
    final manifest = jsonDecode(
      await rootBundle.loadString('$_folder/companion.json'),
    ) as Map<String, Object?>;
    final layers = manifest['layers']! as Map<String, Object?>;
    final frames = manifest['frames']! as Map<String, Object?>;

    Future<ui.Image> picture(String file) async {
      final data = await rootBundle.load('$_folder/$file');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    }

    Future<_Layer> layer(String name) async {
      final spec = layers[name]! as Map<String, Object?>;
      final files = spec['files']! as Map<String, Object?>;
      return _Layer(
        ui.Offset(
          (spec['x']! as num).toDouble(),
          (spec['y']! as num).toDouble(),
        ),
        {
          for (final MapEntry(:key, :value) in files.entries)
            key: await picture(value! as String),
        },
      );
    }

    ui.Rect frame(CompanionFrame which) {
      final [left, top, width, height] = [
        for (final value in frames[which.name]! as List<Object?>)
          (value! as num).toDouble(),
      ];
      return ui.Rect.fromLTWH(left, top, width, height);
    }

    return CompanionArt._(
      await picture(manifest['base']! as String),
      {
        for (final name in const ['eyes', 'mouth', 'hand'])
          name: await layer(name),
      },
      {for (final which in CompanionFrame.values) which: frame(which)},
    );
  }

  final ui.Image _body;
  final Map<String, _Layer> _layers;
  final Map<CompanionFrame, ui.Rect> _frames;

  /// Pictures pasted lately, newest last, so a mouth going back and forth
  /// doesn't paste the same few again and again.
  final _pasted =
      <
        (CompanionFrame, CompanionEyes, CompanionMouth, CompanionHand),
        ui.Image
      >{};

  static const _kept = 8;

  /// Width over height of [frame].
  double aspectRatio(CompanionFrame frame) =>
      _frames[frame]!.width / _frames[frame]!.height;

  /// [pose] in [frame]. The caller owns the image returned and disposes it.
  ui.Image picture(CompanionPose pose, CompanionFrame frame) {
    final key = (frame, pose.eyes, pose.mouth, pose.hand);
    final kept = _pasted.remove(key);
    final image = kept ?? _paste(pose, _frames[frame]!);
    _pasted[key] = image;
    while (_pasted.length > _kept) {
      final oldest = _pasted.keys.first;
      _pasted.remove(oldest)!.dispose();
    }
    return image.clone();
  }

  ui.Image _paste(CompanionPose pose, ui.Rect frame) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..translate(-frame.left, -frame.top);
    final paint = ui.Paint();
    canvas.drawImage(_body, ui.Offset.zero, paint);
    for (final (name, state) in [
      ('eyes', pose.eyes.name),
      ('mouth', pose.mouth.name),
      ('hand', pose.hand.name),
    ]) {
      final layer = _layers[name]!;
      canvas.drawImage(layer.pictures[state]!, layer.offset, paint);
    }
    final picture = recorder.endRecording();
    try {
      return picture.toImageSync(frame.width.round(), frame.height.round());
    } finally {
      picture.dispose();
    }
  }
}

class _Layer {
  const _Layer(this.offset, this.pictures);

  final ui.Offset offset;
  final Map<String, ui.Image> pictures;
}
