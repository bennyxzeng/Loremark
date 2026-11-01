import 'dart:convert';

import 'pcap.dart';

/// Bytes an app UID moved over the network, from `dumpsys netstats detail`.
class UidTraffic {
  const UidTraffic({
    this.rxBytes = 0,
    this.rxPackets = 0,
    this.txBytes = 0,
    this.txPackets = 0,
  });

  final int rxBytes;
  final int rxPackets;
  final int txBytes;
  final int txPackets;

  UidTraffic operator -(UidTraffic other) => UidTraffic(
    rxBytes: rxBytes - other.rxBytes,
    rxPackets: rxPackets - other.rxPackets,
    txBytes: txBytes - other.txBytes,
    txPackets: txPackets - other.txPackets,
  );

  bool get isZero =>
      rxBytes == 0 && rxPackets == 0 && txBytes == 0 && txPackets == 0;

  Map<String, int> toJson() => {
    'rxBytes': rxBytes,
    'rxPackets': rxPackets,
    'txBytes': txBytes,
    'txPackets': txPackets,
  };
}

/// One reading of the kernel's per-UID counters.
class NetstatsSnapshot {
  const NetstatsSnapshot(this.byUid);

  /// Every UID that has moved a byte since boot. A UID that never touched
  /// the network is absent, which counts as zero.
  final Map<int, UidTraffic> byUid;

  UidTraffic trafficOf(int uid) => byUid[uid] ?? const UidTraffic();
}

/// Reads the `mAppUidStatsMap:` table of `dumpsys netstats detail`, or returns
/// null if the output has no such table (a different Android version), so the
/// audit can report "not measured" instead of a false zero.
///
/// The table is `uid rxBytes rxPackets txBytes txPackets`, one UID per line;
/// loopback is not counted, so the app's in-process asset server and the Dart
/// VM service never show up here.
NetstatsSnapshot? parseNetstats(String dump) {
  final lines = const LineSplitter().convert(dump);
  final header = lines.indexWhere((l) => l.trim() == 'mAppUidStatsMap:');
  if (header < 0) return null;
  final byUid = <int, UidTraffic>{};
  final row = RegExp(r'^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$');
  for (final line in lines.skip(header + 1)) {
    final match = row.firstMatch(line);
    if (match == null) {
      // Column titles come first; the table ends at the next section.
      if (line.contains('rxBytes') || line.trim().isEmpty) continue;
      break;
    }
    final n = [for (var i = 1; i <= 5; i++) int.parse(match.group(i)!)];
    byUid[n[0]] = UidTraffic(
      rxBytes: n[1],
      rxPackets: n[2],
      txBytes: n[3],
      txPackets: n[4],
    );
  }
  return NetstatsSnapshot(byUid);
}

/// Hosts the OS contacts on its own on a google_apis emulator, whether or not
/// our app runs (connectivity checks, time sync, Play services). The audit
/// adds whatever a control window without the app shows, but these cover
/// traffic that was quiet during the control window.
///
/// A leading `*.` matches any subdomain.
const defaultOsBaselineHosts = [
  'connectivitycheck.gstatic.com',
  'www.google.com',
  '*.googleapis.com',
  '*.gstatic.com',
  '*.google.com',
  'time.android.com',
  '*.local',
  '*.arpa',
];

/// Whether [host] equals [pattern] or, for `*.x`, is a subdomain of x.
bool hostMatches(String pattern, String host) {
  final h = host.toLowerCase();
  final p = pattern.toLowerCase();
  if (p.startsWith('*.')) {
    return h.endsWith(p.substring(1)) || h == p.substring(2);
  }
  return h == p;
}

bool _inAny(Iterable<String> patterns, String host) =>
    patterns.any((pattern) => hostMatches(pattern, host));

/// What the pcap policy check found in one session window.
class PcapAudit {
  const PcapAudit({
    required this.totalPackets,
    required this.sessionPackets,
    required this.sessionNames,
    required this.baselineNames,
    required this.unexpectedNames,
    required this.plaintextHttp,
    required this.opaqueDestinations,
    required this.markerHits,
    required this.offlineLeaks,
  });

  final int totalPackets;
  final int sessionPackets;

  /// Every DNS question, TLS server name and HTTP host in the session window.
  final Set<String> sessionNames;

  /// What the OS does with no app involved: built-in list plus control window.
  final Set<String> baselineNames;

  /// Session names that are neither baseline nor allowed.
  final List<String> unexpectedNames;

  /// Plaintext HTTP to anything but a baseline destination.
  final List<String> plaintextHttp;

  /// TLS or QUIC flows to a non-baseline address that revealed no name.
  final List<String> opaqueDestinations;

  /// Marker phrases found in the raw capture.
  final List<String> markerHits;

  /// Routable packets sent while airplane mode was on.
  final List<String> offlineLeaks;

  bool get pass =>
      unexpectedNames.isEmpty &&
      plaintextHttp.isEmpty &&
      opaqueDestinations.isEmpty &&
      markerHits.isEmpty &&
      offlineLeaks.isEmpty;

  Map<String, dynamic> toJson() => {
    'totalPackets': totalPackets,
    'sessionPackets': sessionPackets,
    'sessionNames': sessionNames.toList()..sort(),
    'baselineNames': baselineNames.toList()..sort(),
    'unexpectedNames': unexpectedNames,
    'plaintextHttp': plaintextHttp,
    'opaqueDestinations': opaqueDestinations,
    'markerHits': markerHits,
    'offlineLeaks': offlineLeaks,
    'pass': pass,
  };
}

/// A time window in microseconds since the Unix epoch.
class TimeWindow {
  const TimeWindow(this.startUs, this.endUs);

  final int startUs;
  final int endUs;

  bool contains(int us) => us >= startUs && us <= endUs;
}

/// Applies the privacy policy to [capture].
///
/// The capture is the whole guest NIC, with no way to tell which app sent a
/// packet, so the policy is about destinations, not about our app alone:
/// - every name in the [session] window, not in the OS baseline and not in
///   [allowedHosts], is a finding ([allowedHosts] is empty until the app talks
///   to a backend);
/// - plaintext HTTP is a finding unless it goes to a baseline host, or to an
///   address a baseline name resolved to;
/// - [markers] (phrases planted in the generated book) must not appear in any
///   packet;
/// - nothing routable may leave the guest in the [offline] windows.
///
/// The baseline is [osBaseline] plus every name and address in the [control]
/// window, recorded with the app stopped. The authoritative "the app sent
/// nothing" check is the netstats counters; this is the destination policy.
PcapAudit auditPcap(
  PcapCapture capture, {
  required TimeWindow session,
  TimeWindow? control,
  Set<String> allowedHosts = const {},
  List<String> osBaseline = defaultOsBaselineHosts,
  List<String> markers = const [],
  List<TimeWindow> offline = const [],
  String guestIp = '10.0.2.15',
}) {
  final packets = capture.packets;

  // Which address belongs to which name, over the whole capture.
  final nameOfAddress = <String, Set<String>>{};
  for (final packet in packets) {
    for (final answer in packet.dnsAnswers) {
      nameOfAddress.putIfAbsent(answer.address, () => {}).add(answer.name);
    }
  }

  Set<String> namesIn(Iterable<CapturedPacket> window) => {
    for (final p in window) ...[
      if (p.dnsQuestion != null && p.dstPort == 53) p.dnsQuestion!,
      ?p.sni,
      ?p.httpHost,
    ],
  };

  final sessionPackets = packets
      .where((p) => session.contains(p.timeUs))
      .toList();
  final controlPackets = control == null
      ? const <CapturedPacket>[]
      : packets.where((p) => control.contains(p.timeUs)).toList();

  final baselineNames = {...osBaseline, ...namesIn(controlPackets)};
  final baselineAddresses = {
    for (final p in controlPackets)
      if (p.srcIp == guestIp && p.dstIp != null) p.dstIp!,
  };
  final sessionNames = namesIn(sessionPackets);

  final unexpected = [
    for (final name in sessionNames.toList()..sort())
      if (!_inAny(baselineNames, name) && !_inAny(allowedHosts, name)) name,
  ];

  // A destination is baseline when its address was in the control window or a
  // baseline name resolved to it.
  bool baselineDestination(CapturedPacket p) {
    final address = p.dstIp;
    if (address == null) return false;
    if (baselineAddresses.contains(address)) return true;
    return (nameOfAddress[address] ?? const {}).any(
      (name) => _inAny(baselineNames, name) || _inAny(allowedHosts, name),
    );
  }

  final plaintext = <String>{};
  final opaque = <String>{};
  for (final p in sessionPackets) {
    if (p.srcIp != guestIp) continue;
    if (p.isPlaintextHttp && p.protocol == 'tcp') {
      final host = p.httpHost;
      final ok = host != null
          ? _inAny(baselineNames, host) || _inAny(allowedHosts, host)
          : baselineDestination(p);
      if (!ok) plaintext.add('${host ?? p.dstIp}:${p.dstPort}');
    }
    // A TLS handshake or QUIC packet that named nothing, to a stranger.
    final tlsHello = p.protocol == 'tcp' && p.sniSplit;
    final quic = p.protocol == 'udp' && p.dstPort == 443;
    if ((tlsHello || quic) && !baselineDestination(p)) {
      opaque.add('${p.dstIp}:${p.dstPort} (${quic ? 'QUIC' : 'split hello'})');
    }
  }

  final markerHits = <String>[];
  for (final marker in markers) {
    final needle = utf8.encode(marker);
    final hit = sessionPackets.any((p) {
      final payload = p.payload;
      return payload != null && containsBytes(payload, needle);
    });
    if (hit) markerHits.add(marker);
  }

  final leaks = <String>{};
  for (final p in packets) {
    if (p.srcIp != guestIp || p.dstIp == null) continue;
    if (!offline.any((w) => w.contains(p.timeUs))) continue;
    if (_isRoutable(p.dstIp!)) leaks.add('${p.dstIp}:${p.dstPort}');
  }

  return PcapAudit(
    totalPackets: packets.length,
    sessionPackets: sessionPackets.length,
    sessionNames: sessionNames,
    baselineNames: baselineNames,
    unexpectedNames: unexpected,
    plaintextHttp: plaintext.toList()..sort(),
    opaqueDestinations: opaque.toList()..sort(),
    markerHits: markerHits,
    offlineLeaks: leaks.toList()..sort(),
  );
}

/// Whether [address] could leave the local network: not multicast, broadcast,
/// link-local or the emulator's own gateway and DNS.
bool _isRoutable(String address) {
  if (address.contains(':')) {
    final lower = address.toLowerCase();
    return !(lower.startsWith('ff') ||
        lower.startsWith('fe80') ||
        lower == '0:0:0:0:0:0:0:1');
  }
  final parts = address.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.contains(null)) return false;
  final a = parts[0]!;
  final b = parts[1]!;
  if (a >= 224) return false; // multicast and broadcast
  if (a == 169 && b == 254) return false;
  if (a == 10 && b == 0 && parts[2] == 2) return false; // emulator network
  return true;
}
