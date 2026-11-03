import 'package:flutter_test/flutter_test.dart';

import '../../tool/acceptance/pcap.dart';
import '../../tool/acceptance/privacy.dart';
import 'pcap_builder.dart';

const _s = 1000000;
const _t0 = 1762000000 * _s;

(int, List<int>) _dnsQuery(int at, String name) =>
    (at, ipv4Frame(guestIp, '10.0.2.3', 17, udp(40000, 53, dnsQuery(name))));

(int, List<int>) _dnsAnswer(int at, String name, String address) => (
  at,
  ipv4Frame(
    '10.0.2.3',
    guestIp,
    17,
    udp(53, 40000, dnsResponse(name, address)),
  ),
);

(int, List<int>) _hello(int at, String host, String address) =>
    (at, ipv4Frame(guestIp, address, 6, tcp(41000, 443, clientHello(host))));

(int, List<int>) _http(int at, String host, String address) =>
    (at, ipv4Frame(guestIp, address, 6, tcp(41000, 80, httpGet(host, '/'))));

PcapAudit _audit(
  List<(int, List<int>)> frames, {
  Set<String> allowed = const {},
  List<String> markers = const [],
  List<TimeWindow> offline = const [],
  bool withControl = true,
}) => auditPcap(
  parsePcap(pcapFile(frames)),
  session: const TimeWindow(_t0 + 100 * _s, _t0 + 200 * _s),
  control: withControl ? const TimeWindow(_t0, _t0 + 50 * _s) : null,
  allowedHosts: allowed,
  markers: markers,
  offline: offline,
);

void main() {
  group('auditPcap', () {
    test('passes a session that only repeats the OS baseline', () {
      final audit = _audit([
        _dnsQuery(_t0 + 10 * _s, 'connectivitycheck.gstatic.com'),
        _dnsQuery(_t0 + 120 * _s, 'connectivitycheck.gstatic.com'),
        _hello(_t0 + 130 * _s, 'play.googleapis.com', '142.250.0.1'),
        _http(_t0 + 140 * _s, 'connectivitycheck.gstatic.com', '142.250.0.2'),
      ]);

      expect(audit.pass, isTrue, reason: audit.toJson().toString());
      expect(audit.sessionPackets, 3);
      expect(audit.totalPackets, 4);
    });

    test('flags a name that appears only in the session', () {
      final audit = _audit([
        _dnsQuery(_t0 + 10 * _s, 'connectivitycheck.gstatic.com'),
        _dnsQuery(_t0 + 120 * _s, 'tracker.example.net'),
        _hello(_t0 + 121 * _s, 'tracker.example.net', '203.0.113.7'),
      ]);

      expect(audit.pass, isFalse);
      expect(audit.unexpectedNames, ['tracker.example.net']);
    });

    test('lets an allow-listed host through, wildcard or exact', () {
      final frames = [
        _hello(_t0 + 120 * _s, 'api.loremark.app', '203.0.113.7'),
        _hello(_t0 + 121 * _s, 'eu.ai.example.com', '203.0.113.8'),
      ];

      expect(_audit(frames).unexpectedNames, hasLength(2));
      expect(
        _audit(frames, allowed: {'api.loremark.app', '*.ai.example.com'}).pass,
        isTrue,
      );
    });

    test('uses names the control window saw as baseline too', () {
      final frames = [
        _hello(_t0 + 10 * _s, 'vendor-telemetry.example.org', '198.51.100.1'),
        _hello(_t0 + 120 * _s, 'vendor-telemetry.example.org', '198.51.100.1'),
      ];

      expect(_audit(frames).pass, isTrue);
      expect(_audit(frames, withControl: false).pass, isFalse);
    });

    test('allow-list permits HTTPS destinations, never plaintext HTTP', () {
      final audit = _audit(
        [
          _dnsAnswer(_t0 + 110 * _s, 'api.loremark.app', '203.0.113.7'),
          _http(_t0 + 120 * _s, 'api.loremark.app', '203.0.113.7'),
          (
            _t0 + 121 * _s,
            ipv4Frame(guestIp, '203.0.113.7', 6, tcp(41000, 80, [1, 2, 3])),
          ),
        ],
        allowed: {'api.loremark.app'},
      );
      expect(audit.unexpectedNames, isEmpty);
      expect(audit.plaintextHttp, ['203.0.113.7:80', 'api.loremark.app:80']);
      expect(audit.pass, isFalse);
    });

    test('ignores packets outside the session window', () {
      final audit = _audit([
        _hello(_t0 + 60 * _s, 'before.example.org', '198.51.100.2'),
        _hello(_t0 + 300 * _s, 'after.example.org', '198.51.100.3'),
      ]);

      expect(audit.pass, isTrue);
      expect(audit.sessionPackets, 0);
    });

    test(
      'flags plaintext HTTP to a stranger, with or without a Host header',
      () {
        final audit = _audit([
          _http(_t0 + 120 * _s, 'files.example.org', '198.51.100.9'),
          (
            _t0 + 121 * _s,
            ipv4Frame(guestIp, '198.51.100.10', 6, tcp(41000, 80, [1, 2, 3])),
          ),
        ]);

        expect(audit.pass, isFalse);
        expect(audit.plaintextHttp, [
          '198.51.100.10:80',
          'files.example.org:80',
        ]);
      },
    );

    test(
      'accepts plaintext HTTP to an address a baseline name resolved to',
      () {
        final audit = _audit([
          _dnsAnswer(
            _t0 + 5 * _s,
            'connectivitycheck.gstatic.com',
            '172.217.0.3',
          ),
          (
            _t0 + 120 * _s,
            ipv4Frame(guestIp, '172.217.0.3', 6, tcp(41000, 80, [1, 2, 3])),
          ),
        ]);

        expect(audit.plaintextHttp, isEmpty);
        expect(audit.pass, isTrue);
      },
    );

    test('flags QUIC to an unknown destination but not to a baseline one', () {
      (int, List<int>) quic(int at, String address) => (
        at,
        ipv4Frame(guestIp, address, 17, udp(50000, 443, List.filled(40, 1))),
      );

      final stranger = _audit([quic(_t0 + 120 * _s, '203.0.113.50')]);
      expect(stranger.opaqueDestinations, ['203.0.113.50:443 (QUIC)']);

      final known = _audit([
        quic(_t0 + 10 * _s, '203.0.113.60'),
        quic(_t0 + 120 * _s, '203.0.113.60'),
      ]);
      expect(known.opaqueDestinations, isEmpty);
    });

    test('finds a planted marker phrase in plaintext, and only then', () {
      const marker = 'LOREMARK-MARKER-c3-s403-abc';
      final leak = (
        _t0 + 130 * _s,
        ipv4Frame(
          guestIp,
          '10.0.2.2',
          6,
          tcp(41000, 9000, 'POST /x HTTP/1.1\r\n\r\n$marker'.codeUnits),
        ),
      );

      expect(_audit([leak], markers: [marker]).markerHits, [marker]);
      expect(
        _audit([leak], markers: ['LOREMARK-MARKER-c9']).markerHits,
        isEmpty,
      );
    });

    test('flags routable packets sent while airplane mode was on', () {
      final frames = [
        _dnsQuery(_t0 + 150 * _s, 'connectivitycheck.gstatic.com'),
        (
          _t0 + 151 * _s,
          ipv4Frame(guestIp, '198.51.100.77', 17, udp(1, 2, [1])),
        ),
        (
          _t0 + 152 * _s,
          ipv4Frame(guestIp, '224.0.0.251', 17, udp(5353, 5353, [1])),
        ),
        (
          _t0 + 180 * _s,
          ipv4Frame(guestIp, '198.51.100.78', 17, udp(1, 2, [1])),
        ),
      ];
      final audit = _audit(
        frames,
        offline: const [TimeWindow(_t0 + 140 * _s, _t0 + 160 * _s)],
      );

      // The query goes to the emulator's DNS, mDNS is multicast, and the last
      // packet is after the window: only the middle one counts.
      expect(audit.offlineLeaks, ['198.51.100.77:2']);
      expect(audit.pass, isFalse);
    });
  });

  group('hostMatches', () {
    test('matches exactly or by wildcard subdomain, ignoring case', () {
      expect(hostMatches('Example.com', 'example.COM'), isTrue);
      expect(hostMatches('*.example.com', 'a.b.example.com'), isTrue);
      expect(hostMatches('*.example.com', 'example.com'), isTrue);
      expect(hostMatches('*.example.com', 'notexample.com'), isFalse);
      expect(hostMatches('example.com', 'a.example.com'), isFalse);
    });
  });

  group('parseNetstats', () {
    const dump = '''
  BPF map content:
    mCookieTagMap:
      cookie=8677 tag=0x407 uid=10145
    mAppUidStatsMap:
      uid rxBytes rxPackets txBytes txPackets
      10165 51609 62 8235 52
      10216 100 2 40 1
      1000 11117 76 1487 13

    mStatsMapA:
      ifaceIndex cookie tag uid
''';

    test('reads the per-UID table and stops at the next section', () {
      final snapshot = parseNetstats(dump)!;

      expect(snapshot.byUid.keys, [10165, 10216, 1000]);
      expect(snapshot.trafficOf(10216).txBytes, 40);
      expect(snapshot.trafficOf(10216).rxPackets, 2);
    });

    test('treats an absent UID as zero traffic', () {
      expect(parseNetstats(dump)!.trafficOf(99999).isZero, isTrue);
    });

    test('returns null when the device prints no such table', () {
      expect(parseNetstats('Active interfaces:\n  iface=wlan0'), isNull);
      expect(parseNetstats(''), isNull);
      expect(parseNetstats('mAppUidStatsMap:\n permission denied'), isNull);
      expect(parseNetstats('mAppUidStatsMap:\n uid bytes packets'), isNull);
      expect(
        parseNetstats(
          dump.replaceFirst('10165 51609 62 8235 52', '10165 unavailable'),
        ),
        isNull,
      );
    });

    test('subtracts two readings', () {
      const before = UidTraffic(txBytes: 10, txPackets: 1, rxBytes: 5);
      const after = UidTraffic(txBytes: 10, txPackets: 1, rxBytes: 5);

      expect((after - before).isZero, isTrue);
      expect((const UidTraffic(txBytes: 14) - before).txBytes, 4);
    });
  });
}
