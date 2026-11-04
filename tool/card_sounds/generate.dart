// Synthesizes the character card's reveal sounds into assets/sounds/.
//
// Everything is generated here, so the sounds carry no third-party license and
// can be retuned. The output is the same on every run.
//
// Run from the repo root: dart run tool/card_sounds/generate.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _sampleRate = 44100;
const _tau = 2 * math.pi;

void main() {
  final sounds = {
    'charge_short': _normalized(_charge(0.5), 0.35),
    'charge_long': _normalized(_charge(0.95), 0.35),
    'burst_low': _normalized(_burstLow(), 0.56),
    'burst_high': _normalized(_burstHigh(), 0.84),
    'flip': _normalized(_flip(), 0.25),
    // A pentatonic climb, so the stars read as one rising phrase.
    'star_1': _normalized(_star(1046.50), 0.4),
    'star_2': _normalized(_star(1174.66), 0.4),
    'star_3': _normalized(_star(1318.51), 0.4),
    'star_4': _normalized(_star(1567.98), 0.4),
    'star_5': _normalized(_star(1760.00), 0.4),
  };

  final directory = Directory('assets/sounds')..createSync(recursive: true);
  for (final MapEntry(key: name, value: samples) in sounds.entries) {
    File('${directory.path}/$name.wav').writeAsBytesSync(_wav(samples));
    stdout.writeln(
      '$name: ${(samples.length / _sampleRate).toStringAsFixed(2)} s',
    );
  }
}

Float64List _silence(double seconds) =>
    Float64List((seconds * _sampleRate).round());

/// A rising shimmer: gliding partials with a quickening flutter over noise.
Float64List _charge(double seconds) {
  final out = _silence(seconds);
  final random = math.Random(1);
  const partials = [(1.0, 1.0), (1.5, 0.5), (2.0, 0.6), (3.0, 0.3), (4.0, 0.2)];
  final phases = List.filled(partials.length, 0.0);
  var flutterPhase = 0.0;
  var low = 0.0;
  for (var i = 0; i < out.length; i++) {
    final t = i / out.length;
    final base = 220 * math.pow(4, t);
    flutterPhase += _tau * (8 + 22 * t) / _sampleRate;
    final flutter = 0.75 + 0.25 * math.sin(flutterPhase);
    var tone = 0.0;
    for (final (index, (ratio, level)) in partials.indexed) {
      phases[index] += _tau * base * ratio / _sampleRate;
      tone += level * math.sin(phases[index]);
    }
    // One-pole low-pass whose cutoff opens as the charge builds.
    low += (0.02 + 0.25 * t) * (random.nextDouble() * 2 - 1 - low);
    final swell = math.pow(t, 1.5).toDouble();
    out[i] = swell * (tone * flutter * 0.6 + low * 0.8);
  }
  return _faded(out, inSeconds: 0.01, outSeconds: 0.015);
}

/// A small two-note chime for low-star cards.
Float64List _burstLow() {
  final out = _silence(1.0);
  _bell(out, 0, 659.25, 1.0, 0.55);
  _bell(out, 0.02, 987.77, 0.7, 0.45);
  return out;
}

/// An impact, a wide chord and a tail of sparkles for high-star cards.
Float64List _burstHigh() {
  final out = _silence(2.2);
  final random = math.Random(2);

  // The impact: a pitch-dropping thump and a very short crack of noise.
  var phase = 0.0;
  for (var i = 0; i < out.length; i++) {
    final t = i / _sampleRate;
    phase += _tau * (40 + 45 * math.exp(-t * 18)) / _sampleRate;
    out[i] += 1.1 * math.exp(-t * 9) * math.sin(phase);
    if (t < 0.04) {
      out[i] += 0.5 * (1 - t / 0.04) * (random.nextDouble() * 2 - 1);
    }
  }

  // A bright add9 chord, with detuned pairs for width.
  const chord = [261.63, 392.00, 523.25, 659.25, 783.99, 1174.66];
  for (final (index, note) in chord.indexed) {
    final level = 0.32 - index * 0.025;
    _bell(out, 0.005, note, level, 1.5);
    _bell(out, 0.005, note * 1.004, level * 0.7, 1.3);
  }

  // Sparkles that thin out and fade across the tail.
  for (var i = 0; i < 44; i++) {
    final at = 0.1 + 1.75 * math.pow(random.nextDouble(), 1.4);
    final level = 0.16 * (1 - at / 2.0);
    _bell(out, at, 1500 + random.nextDouble() * 3500, level, 0.09);
  }
  return out;
}

/// A short whoosh, like a card turning over.
Float64List _flip() {
  final out = _silence(0.22);
  final random = math.Random(3);
  var low = 0.0;
  var lower = 0.0;
  for (var i = 0; i < out.length; i++) {
    final t = i / out.length;
    final cutoff = 0.05 + 0.4 * t;
    final noise = random.nextDouble() * 2 - 1;
    low += cutoff * (noise - low);
    lower += 0.03 * (low - lower);
    final swell = math.pow(math.sin(math.pi * t), 2).toDouble();
    // Subtracting the slower filter keeps only the band in between.
    out[i] = swell * (low - lower);
  }
  return out;
}

/// A quick ding.
Float64List _star(double frequency) {
  final out = _silence(0.35);
  _bell(out, 0, frequency, 1.0, 0.16);
  return out;
}

/// Adds a struck tone at [at] seconds that decays with [decay] seconds.
void _bell(
  Float64List out,
  double at,
  double frequency,
  double level,
  double decay,
) {
  const partials = [(1.0, 1.0, 1.0), (2.0, 0.4, 0.6), (2.76, 0.22, 0.4)];
  final start = (at * _sampleRate).round();
  for (var i = start; i < out.length; i++) {
    final t = (i - start) / _sampleRate;
    final attack = math.min(1.0, t / 0.002);
    for (final (ratio, partLevel, decayScale) in partials) {
      out[i] +=
          level *
          partLevel *
          attack *
          math.exp(-t / (decay * decayScale)) *
          math.sin(_tau * frequency * ratio * t);
    }
  }
}

/// Short fades at both ends, so playback never clicks.
Float64List _faded(
  Float64List samples, {
  double inSeconds = 0.002,
  double outSeconds = 0.01,
}) {
  final fadeIn = (inSeconds * _sampleRate).round();
  final fadeOut = (outSeconds * _sampleRate).round();
  for (var i = 0; i < fadeIn && i < samples.length; i++) {
    samples[i] *= i / fadeIn;
  }
  for (var i = 0; i < fadeOut && i < samples.length; i++) {
    samples[samples.length - 1 - i] *= i / fadeOut;
  }
  return samples;
}

/// Scales [samples] so the loudest one reaches [peak].
Float64List _normalized(Float64List samples, double peak) {
  final faded = _faded(samples);
  final loudest = faded.fold<double>(
    0,
    (max, sample) => math.max(max, sample.abs()),
  );
  for (var i = 0; i < faded.length; i++) {
    faded[i] *= peak / loudest;
  }
  return faded;
}

/// Encodes mono 16-bit PCM as a WAV file.
Uint8List _wav(Float64List samples) {
  final dataSize = samples.length * 2;
  final bytes = ByteData(44 + dataSize);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataSize, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, _sampleRate, Endian.little);
  bytes.setUint32(28, _sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataSize, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final value = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    bytes.setInt16(44 + i * 2, value, Endian.little);
  }
  return bytes.buffer.asUint8List();
}
