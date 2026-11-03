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

  group('describeCapture', () {
    test('says what is in a capture that has no probe', () {
      final text = describeCapture(
        PcapCapture([
          const CapturedPacket(
            timeUs: 1000000,
            length: 80,
            dstPort: 53,
            dnsQuestion: 'connectivitycheck.gstatic.com',
          ),
          const CapturedPacket(timeUs: 3500000, length: 60),
          const CapturedPacket(
            timeUs: 4000000,
            length: 80,
            dstPort: 53,
            dnsQuestion: 'connectivitycheck.gstatic.com',
          ),
        ], linkType: 1),
      );
      expect(text, contains('3 packets over 3.0 s'));
      expect(text, contains('link type 1'));
      expect(
        text,
        contains('1 distinct DNS question: connectivitycheck.gstatic.com'),
      );
    });

    test('says so when a capture is empty or has no DNS at all', () {
      expect(
        describeCapture(PcapCapture(const [], linkType: 1)),
        'the capture holds no packets',
      );
      final noDns = describeCapture(
        PcapCapture(const [CapturedPacket(timeUs: 1, length: 60)], linkType: 1),
      );
      expect(noDns, contains('0 distinct DNS questions'));
      // No names, so no ": name, name" list after the count.
      expect(noDns, isNot(contains(':')));
    });

    test('lists at most maxNames names and marks the rest', () {
      final many = PcapCapture([
        for (var i = 0; i < 12; i++)
          CapturedPacket(
            timeUs: 1000000 + i,
            length: 80,
            dstPort: 53,
            dnsQuestion: 'host$i.example.com',
          ),
      ], linkType: 1);
      final text = describeCapture(many, maxNames: 3);
      expect(text, contains('12 distinct DNS questions'));
      expect(
        text,
        contains(
          'host0.example.com, host1.example.com, host2.example.com, ...',
        ),
      );
      expect(text, isNot(contains('host3.example.com')));
    });
  });
}
