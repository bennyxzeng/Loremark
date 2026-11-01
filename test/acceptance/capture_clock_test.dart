import 'package:flutter_test/flutter_test.dart';

import '../../tool/acceptance/capture_clock.dart';
import '../../tool/acceptance/pcap.dart';
import '../../tool/acceptance/privacy.dart';

void main() {
  const start = CaptureProbe('start.example.com', 1000000, 1200000);
  const end = CaptureProbe('end.example.com', 10000000, 10200000);
  const eightHours = 8 * 3600 * 1000000;

  PcapCapture capture({bool missingEnd = false, int drift = 0}) => PcapCapture([
    const CapturedPacket(
      timeUs: eightHours + 1100000,
      length: 80,
      dstPort: 53,
      dnsQuestion: 'start.example.com',
    ),
    if (!missingEnd)
      CapturedPacket(
        timeUs: eightHours + 10100000 + drift,
        length: 80,
        dstPort: 53,
        dnsQuestion: 'end.example.com',
      ),
  ], linkType: 1);

  test('calibrates real capture timestamps rather than guessing timezone', () {
    final offset = captureClockOffset(capture(), start, end);
    expect(offset, eightHours);
    final window = shiftWindow(const TimeWindow(2000000, 9000000), offset);
    expect(window.startUs, eightHours + 2000000);
    expect(window.endUs, eightHours + 9000000);
  });

  test('rejects a stale capture even when it contains other packets', () {
    expect(
      () => captureClockOffset(capture(missingEnd: true), start, end),
      throwsFormatException,
    );
  });

  test('rejects a capture whose clock changed during the run', () {
    expect(
      () => captureClockOffset(capture(drift: 5000000), start, end),
      throwsFormatException,
    );
  });
}
