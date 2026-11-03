import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/acceptance/pcap.dart';
import 'pcap_builder.dart';

const _t0 = 1762000000 * 1000000;

void main() {
  group('parsePcap', () {
    test(
      'reads the emulator format: little-endian, microseconds, Ethernet',
      () {
        final capture = parsePcap(
          pcapFile([
            (
              _t0 + 250,
              ipv4Frame(
                guestIp,
                '10.0.2.3',
                17,
                udp(40000, 53, dnsQuery('example.com')),
              ),
            ),
          ]),
        );

        expect(capture.linkType, 1);
        expect(capture.packets, hasLength(1));
        final packet = capture.packets.single;
        expect(packet.timeUs, _t0 + 250);
        expect(packet.srcIp, guestIp);
        expect(packet.dstIp, '10.0.2.3');
        expect(packet.protocol, 'udp');
        expect(packet.dstPort, 53);
      },
    );

    test('reads the big-endian and nanosecond variants', () {
      final frame = ipv4Frame(guestIp, '1.2.3.4', 17, udp(1, 2, [9]));
      for (final (big, nano) in [(true, false), (false, true), (true, true)]) {
        final capture = parsePcap(
          pcapFile([(_t0 + 123456, frame)], bigEndian: big, nanoseconds: nano),
        );
        expect(capture.packets.single.timeUs, _t0 + 123456);
        expect(capture.packets.single.dstIp, '1.2.3.4');
      }
    });

    test('drops a truncated last record instead of failing', () {
      final frame = ipv4Frame(guestIp, '1.2.3.4', 17, udp(1, 2, [9]));
      final capture = parsePcap(
        pcapFile([(_t0, frame), (_t0 + 1, frame)], truncateBy: 5),
      );

      expect(capture.packets, hasLength(1));
    });

    test('accepts a header-only file', () {
      expect(parsePcap(pcapFile(const [])).packets, isEmpty);
    });

    test('rejects pcapng, unknown magic and other link layers loudly', () {
      final pcapng = Uint8List(32)..setAll(0, [0x0a, 0x0d, 0x0d, 0x0a]);
      expect(() => parsePcap(pcapng), throwsFormatException);
      expect(() => parsePcap(Uint8List(32)), throwsFormatException);
      expect(() => parsePcap(Uint8List(10)), throwsFormatException);
      expect(
        () => parsePcap(pcapFile(const [], linkType: 113)),
        throwsFormatException,
      );
    });

    test('keeps a non-IP frame (ARP) as an opaque packet', () {
      final arp = [...List.filled(12, 0xff), 0x08, 0x06, ...List.filled(28, 0)];
      final capture = parsePcap(pcapFile([(_t0, arp)]));

      expect(capture.packets.single.protocol, isNull);
      expect(capture.packets.single.srcIp, isNull);
    });

    test('survives garbage frames without throwing', () {
      final garbage = [
        [1, 2, 3],
        List.filled(14, 0),
        [...List.filled(12, 0), 0x08, 0x00, 0x45], // IPv4 header cut off
        [...List.filled(12, 0), 0x86, 0xdd, ...List.filled(10, 0)],
      ];
      final capture = parsePcap(
        pcapFile([
          for (var i = 0; i < garbage.length; i++) (_t0 + i, garbage[i]),
        ]),
      );

      expect(capture.packets, hasLength(garbage.length));
    });

    test('reads raw IP captures (link type 101)', () {
      final ipOnly = ipv4Frame(
        guestIp,
        '9.9.9.9',
        6,
        tcp(1, 80, [1]),
      ).sublist(14);
      final capture = parsePcap(pcapFile([(_t0, ipOnly)], linkType: 101));

      expect(capture.packets.single.dstIp, '9.9.9.9');
      expect(capture.packets.single.protocol, 'tcp');
    });

    test('reads IPv6 UDP behind an extension header', () {
      final payload = udp(5000, 53, dnsQuery('v6.example.org'));
      final frame = [
        ...List.filled(12, 0), 0x86, 0xdd,
        0x60, 0, 0, 0, 0, payload.length + 8, 0, 64, // next header: hop-by-hop
        ...List.generate(16, (i) => i == 15 ? 1 : 0), // src ::1
        ...List.generate(16, (i) => i == 0 ? 0x20 : (i == 15 ? 2 : 0)),
        17, 0, 1, 4, 0, 0, 0, 0, // hop-by-hop header (8 bytes) then UDP
        ...payload,
      ];
      final capture = parsePcap(pcapFile([(_t0, frame)]));
      final packet = capture.packets.single;

      expect(packet.protocol, 'udp');
      expect(packet.dstPort, 53);
      expect(packet.dnsQuestion, 'v6.example.org');
      expect(packet.dstIp, startsWith('2000:'));
    });

    test('ignores the transport header of later IPv4 fragments', () {
      final frame = ipv4Frame(
        guestIp,
        '1.2.3.4',
        17,
        List.filled(30, 0xab),
        fragmentField: 5,
      );
      final packet = parsePcap(pcapFile([(_t0, frame)])).packets.single;

      expect(packet.protocol, 'other');
      expect(packet.dstPort, isNull);
    });
  });

  group('DNS', () {
    test('extracts the queried name, lowercased', () {
      final frame = ipv4Frame(
        guestIp,
        '10.0.2.3',
        17,
        udp(33333, 53, dnsQuery('Connectivitycheck.GStatic.com')),
      );
      final packet = parsePcap(pcapFile([(_t0, frame)])).packets.single;

      expect(packet.dnsQuestion, 'connectivitycheck.gstatic.com');
    });

    test('maps names to addresses from a response with a compressed name', () {
      final frame = ipv4Frame(
        '10.0.2.3',
        guestIp,
        17,
        udp(53, 33333, dnsResponse('api.example.com', '93.184.216.34')),
      );
      final packet = parsePcap(pcapFile([(_t0, frame)])).packets.single;

      expect(packet.dnsQuestion, 'api.example.com');
      expect(packet.dnsAnswers.single.name, 'api.example.com');
      expect(packet.dnsAnswers.single.address, '93.184.216.34');
    });

    test('returns null for malformed messages', () {
      expect(parseDns(Uint8List(5)), isNull);
      // A pointer loop must not hang.
      final loop = Uint8List.fromList([
        0,
        1,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0xc0,
        0x0c,
        0,
        1,
        0,
        1,
      ]);
      expect(parseDns(loop), isNull);
      // A label that claims more bytes than exist.
      final long = Uint8List.fromList([
        0,
        1,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        60,
        65,
        66,
      ]);
      expect(parseDns(long), isNull);
    });
  });

  group('TLS SNI', () {
    test('extracts the server name of a ClientHello', () {
      final frame = ipv4Frame(
        guestIp,
        '142.250.1.1',
        6,
        tcp(41000, 443, clientHello('Api.Example.com')),
      );
      final packet = parsePcap(pcapFile([(_t0, frame)])).packets.single;

      expect(packet.sni, 'api.example.com');
      expect(packet.sniSplit, isFalse);
      expect(packet.isPlaintextHttp, isFalse);
    });

    test('flags a ClientHello split over segments instead of guessing', () {
      final hello = Uint8List.fromList(clientHello('example.com'));
      final firstSegment = Uint8List.sublistView(hello, 0, 40);

      final result = extractSni(firstSegment);

      expect(result.name, isNull);
      expect(result.split, isTrue);
    });

    test('returns nothing for other TLS records and cut-off hellos', () {
      final application = Uint8List.fromList([0x17, 3, 3, 0, 5, 1, 2, 3, 4, 5]);
      expect(extractSni(application).name, isNull);
      expect(extractSni(Uint8List(3)).name, isNull);

      // Cut inside the extensions but with an honest record length.
      final hello = clientHello('example.com');
      final cut = Uint8List.fromList(hello.sublist(0, hello.length - 8));
      cut[3] = (cut.length - 5) >> 8;
      cut[4] = (cut.length - 5) & 0xff;
      expect(extractSni(cut).name, isNull);
    });
  });

  group('plaintext HTTP', () {
    test('finds a request line and the Host header on any port', () {
      final frame = ipv4Frame(
        guestIp,
        '203.0.113.9',
        6,
        tcp(41000, 8080, httpGet('Plain.Example.com', '/book.epub')),
      );
      final packet = parsePcap(pcapFile([(_t0, frame)])).packets.single;

      expect(packet.httpRequestLine, 'GET /book.epub HTTP/1.1');
      expect(packet.httpHost, 'plain.example.com');
      expect(packet.isPlaintextHttp, isTrue);
    });

    test('counts any payload to port 80 as plaintext', () {
      final frame = ipv4Frame(
        guestIp,
        '203.0.113.9',
        6,
        tcp(41000, 80, [1, 2, 3]),
      );
      final packet = parsePcap(pcapFile([(_t0, frame)])).packets.single;

      expect(packet.isPlaintextHttp, isTrue);
    });

    test('does not mistake a TLS payload on 443 for HTTP', () {
      final frame = ipv4Frame(
        guestIp,
        '203.0.113.9',
        6,
        tcp(41000, 443, [0x17, 3, 3, 0, 1, 9]),
      );
      final packet = parsePcap(pcapFile([(_t0, frame)])).packets.single;

      expect(packet.isPlaintextHttp, isFalse);
    });

    test('recognises a response status line', () {
      expect(
        parseHttp(Uint8List.fromList('HTTP/1.1 200 OK\r\n'.codeUnits))
            ?.isResponse,
        isTrue,
      );
      expect(
        parseHttp(Uint8List.fromList('GETTING started'.codeUnits)),
        isNull,
      );
      expect(parseHttp(Uint8List(0)), isNull);
    });
  });

  test('containsBytes finds a phrase anywhere and rejects near misses', () {
    final data = Uint8List.fromList('xxLOREMARK-MARKER-c3yy'.codeUnits);

    expect(containsBytes(data, 'LOREMARK-MARKER-c3'.codeUnits), isTrue);
    expect(containsBytes(data, 'LOREMARK-MARKER-c4'.codeUnits), isFalse);
    expect(containsBytes(Uint8List(2), 'abc'.codeUnits), isFalse);
  });
}
