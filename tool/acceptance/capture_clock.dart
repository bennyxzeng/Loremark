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
