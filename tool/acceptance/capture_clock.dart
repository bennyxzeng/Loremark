import 'pcap.dart';
import 'privacy.dart';

/// A unique DNS lookup made by adb, with the host times around the command.
/// Matching both probes also proves that a supplied capture covers this run.
class CaptureProbe {
  const CaptureProbe(this.name, this.beforeUs, this.afterUs);

  final String name;
  final int beforeUs;
  final int afterUs;

  int offsetIn(PcapCapture capture) {
    final queries = capture.packets.where(
      (p) => p.dstPort == 53 && p.dnsQuestion == name,
    );
    if (queries.isEmpty) {
      throw FormatException('Capture has no fresh DNS probe $name');
    }
    return queries.first.timeUs - (beforeUs + afterUs) ~/ 2;
  }
}

/// One line saying what a capture holds, for the report when the capture cannot
/// be verified: how many packets, over what link type, and which DNS names were
/// asked. This is what tells "the probe never reached the capture" from "the
/// capture is empty" without needing the file.
String describeCapture(PcapCapture capture, {int maxNames = 8}) {
  final packets = capture.packets;
  if (packets.isEmpty) return 'the capture holds no packets';
  final names = <String>[];
  for (final p in packets) {
    final name = p.dnsQuestion;
    if (p.dstPort == 53 && name != null && !names.contains(name)) {
      names.add(name);
    }
  }
  final spanSeconds = (packets.last.timeUs - packets.first.timeUs) / 1e6;
  final shown = names.take(maxNames).join(', ');
  return '${packets.length} packets over ${spanSeconds.toStringAsFixed(1)} s '
      '(link type ${capture.linkType}); ${names.length} distinct DNS '
      'question${names.length == 1 ? '' : 's'}'
      '${names.isEmpty ? '' : ': $shown${names.length > maxNames ? ', ...' : ''}'}';
}

/// QEMU captures on Windows can have a different clock from the host (an
/// observed eight-hour offset). Calibrate from traffic, never from timezone.
/// Reject a missing probe or a changing clock instead of auditing no packets.
int captureClockOffset(
  PcapCapture capture,
  CaptureProbe start,
  CaptureProbe end,
) {
  final first = start.offsetIn(capture);
  final last = end.offsetIn(capture);
  final uncertainty =
      (start.afterUs - start.beforeUs + end.afterUs - end.beforeUs) ~/ 2;
  if ((first - last).abs() > uncertainty + 2000000) {
    throw const FormatException('Capture clock changed during the run');
  }
  return (first + last) ~/ 2;
}

TimeWindow shiftWindow(TimeWindow window, int offsetUs) =>
    TimeWindow(window.startUs + offsetUs, window.endUs + offsetUs);
