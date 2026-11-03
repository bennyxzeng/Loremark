import 'dart:convert';
import 'dart:typed_data';

/// A pure-Dart reader for the classic libpcap files that `emulator -tcpdump`
/// writes, with just enough protocol decoding for the privacy audit: IPv4 and
/// IPv6, TCP and UDP, DNS names and TLS ClientHello server names.
///
/// It never throws on a damaged packet: a field that doesn't parse stays null,
/// and a truncated last record (the emulator is still writing) is dropped.
/// Blind spots, which is why the audit also reads the app's netstats: QUIC and
/// ECH hide the server name, DNS over TLS hides the lookups, and a ClientHello
/// split over several TCP segments is reported with [CapturedPacket.sniSplit]
/// instead of reassembled.

/// One captured frame.
class CapturedPacket {
  const CapturedPacket({
    required this.timeUs,
    required this.length,
    this.srcIp,
    this.dstIp,
    this.protocol,
    this.srcPort,
    this.dstPort,
    this.payload,
    this.dnsQuestion,
    this.dnsAnswers = const [],
    this.sni,
    this.sniSplit = false,
    this.httpRequestLine,
    this.httpHost,
    this.isHttpResponse = false,
  });

  /// Capture time in microseconds since the Unix epoch.
  final int timeUs;

  /// Bytes on the wire (`orig_len`).
  final int length;

  /// Null for frames that aren't IP, such as ARP.
  final String? srcIp;
  final String? dstIp;

  /// `tcp`, `udp`, `icmp`, or `other` for IP; null otherwise.
  final String? protocol;
  final int? srcPort;
  final int? dstPort;

  /// The TCP or UDP payload, null if there is none.
  final Uint8List? payload;

  /// The first name asked in a DNS message on port 53.
  final String? dnsQuestion;

  /// Address records of a DNS response.
  final List<DnsAnswer> dnsAnswers;

  /// The TLS server name of a ClientHello.
  final String? sni;

  /// A ClientHello that doesn't fit its TCP segment, so no name was read.
  final bool sniSplit;

  /// The request line of a plaintext HTTP request (`GET /x HTTP/1.1`).
  final String? httpRequestLine;
  final String? httpHost;

  /// A plaintext `HTTP/1.x` status line.
  final bool isHttpResponse;

  /// Whether this carries plaintext HTTP in either direction.
  bool get isPlaintextHttp =>
      httpRequestLine != null ||
      isHttpResponse ||
      (protocol == 'tcp' && (dstPort == 80 && (payload?.isNotEmpty ?? false)));
}

/// A name-to-address mapping from a DNS response.
class DnsAnswer {
  const DnsAnswer(this.name, this.address);

  final String name;
  final String address;
}

/// A parsed capture.
class PcapCapture {
  const PcapCapture(this.packets, {required this.linkType});

  final List<CapturedPacket> packets;
  final int linkType;
}

/// Parses classic pcap [bytes].
///
/// Throws a [FormatException] for anything that is not a classic pcap file with
/// an Ethernet (1) or raw IP (101) link layer, such as pcapng, so a changed
/// emulator format fails loudly instead of reading as "no traffic".
PcapCapture parsePcap(Uint8List bytes) {
  if (bytes.length < 24) {
    throw const FormatException('pcap: shorter than the 24-byte header');
  }
  final data = ByteData.sublistView(bytes);
  final Endian endian;
  var nanoseconds = false;
  switch (data.getUint32(0, Endian.big)) {
    case 0xd4c3b2a1:
      endian = Endian.little;
    case 0xa1b2c3d4:
      endian = Endian.big;
    case 0x4d3cb2a1:
      endian = Endian.little;
      nanoseconds = true;
    case 0xa1b23c4d:
      endian = Endian.big;
      nanoseconds = true;
    case 0x0a0d0d0a:
      throw const FormatException('pcap: pcapng is not supported');
    default:
      throw const FormatException('pcap: unknown magic number');
  }
  final linkType = data.getUint32(20, endian);
  if (linkType != 1 && linkType != 101) {
    throw FormatException('pcap: unsupported link type $linkType');
  }

  final packets = <CapturedPacket>[];
  var offset = 24;
  while (offset + 16 <= bytes.length) {
    final seconds = data.getUint32(offset, endian);
    final fraction = data.getUint32(offset + 4, endian);
    final included = data.getUint32(offset + 8, endian);
    final original = data.getUint32(offset + 12, endian);
    final start = offset + 16;
    // The emulator is still writing: drop the half record at the end.
    if (included > 0x40000 || start + included > bytes.length) break;
    offset = start + included;
    final timeUs =
        seconds * 1000000 + (nanoseconds ? fraction ~/ 1000 : fraction);
    packets.add(
      _decodeFrame(
        Uint8List.sublistView(bytes, start, start + included),
        timeUs,
        original,
        linkType,
      ),
    );
  }
  return PcapCapture(packets, linkType: linkType);
}

CapturedPacket _decodeFrame(
  Uint8List frame,
  int timeUs,
  int length,
  int linkType,
) {
  CapturedPacket opaque() => CapturedPacket(timeUs: timeUs, length: length);
  var p = 0;
  var etherType = 0;
  if (linkType == 1) {
    if (frame.length < 14) return opaque();
    etherType = (frame[12] << 8) | frame[13];
    p = 14;
    // 802.1Q tag.
    if (etherType == 0x8100 && frame.length >= 18) {
      etherType = (frame[16] << 8) | frame[17];
      p = 18;
    }
  } else if (frame.isNotEmpty) {
    etherType = frame[0] >> 4 == 6 ? 0x86dd : 0x0800;
  }

  String src;
  String dst;
  int protocol;
  if (etherType == 0x0800 && frame.length >= p + 20) {
    final headerLength = (frame[p] & 0xf) * 4;
    if (headerLength < 20 || frame.length < p + headerLength) return opaque();
    protocol = frame[p + 9];
    src = frame.sublist(p + 12, p + 16).join('.');
    dst = frame.sublist(p + 16, p + 20).join('.');
    final fragmentOffset = ((frame[p + 6] & 0x1f) << 8) | frame[p + 7];
    p += headerLength;
    // Later fragments carry no transport header.
    if (fragmentOffset != 0) {
      return CapturedPacket(
        timeUs: timeUs,
        length: length,
        srcIp: src,
        dstIp: dst,
        protocol: 'other',
      );
    }
  } else if (etherType == 0x86dd && frame.length >= p + 40) {
    protocol = frame[p + 6];
    src = _ipv6(frame, p + 8);
    dst = _ipv6(frame, p + 24);
    p += 40;
    // Skip hop-by-hop, routing, fragment, destination options and AH.
    var guard = 0;
    while ((protocol == 0 ||
            protocol == 43 ||
            protocol == 44 ||
            protocol == 60 ||
            protocol == 51) &&
        guard++ < 8) {
      if (frame.length < p + 8) return opaque();
      final next = frame[p];
      final extension = switch (protocol) {
        44 => 8,
        51 => (frame[p + 1] + 2) * 4,
        _ => (frame[p + 1] + 1) * 8,
      };
      protocol = next;
      p += extension;
    }
  } else {
    return opaque();
  }

  CapturedPacket ip(String name, {int? sp, int? dp, Uint8List? payload}) =>
      CapturedPacket(
        timeUs: timeUs,
        length: length,
        srcIp: src,
        dstIp: dst,
        protocol: name,
        srcPort: sp,
        dstPort: dp,
        payload: payload,
      );

  if (protocol == 1 || protocol == 58) return ip('icmp');
  if (protocol != 6 && protocol != 17) return ip('other');
  if (frame.length < p + 8) return ip(protocol == 6 ? 'tcp' : 'udp');

  final sp = (frame[p] << 8) | frame[p + 1];
  final dp = (frame[p + 2] << 8) | frame[p + 3];
  final int payloadStart;
  if (protocol == 6) {
    if (frame.length < p + 20) return ip('tcp', sp: sp, dp: dp);
    payloadStart = p + (frame[p + 12] >> 4) * 4;
  } else {
    payloadStart = p + 8;
  }
  final payload = payloadStart < frame.length
      ? Uint8List.sublistView(frame, payloadStart)
      : null;

  String? question;
  var answers = const <DnsAnswer>[];
  String? sni;
  var sniSplit = false;
  String? requestLine;
  String? host;
  var isResponse = false;
  if (payload != null) {
    if (protocol == 17 && (sp == 53 || dp == 53)) {
      final dns = parseDns(payload);
      question = dns?.question;
      answers = dns?.answers ?? const [];
    } else if (protocol == 6) {
      final hello = extractSni(payload);
      sni = hello.name;
      sniSplit = hello.split;
      final http = parseHttp(payload);
      requestLine = http?.requestLine;
      host = http?.host;
      isResponse = http?.isResponse ?? false;
    }
  }
  return CapturedPacket(
    timeUs: timeUs,
    length: length,
    srcIp: src,
    dstIp: dst,
    protocol: protocol == 6 ? 'tcp' : 'udp',
    srcPort: sp,
    dstPort: dp,
    payload: payload,
    dnsQuestion: question,
    dnsAnswers: answers,
    sni: sni,
    sniSplit: sniSplit,
    httpRequestLine: requestLine,
    httpHost: host,
    isHttpResponse: isResponse,
  );
}

String _ipv6(Uint8List f, int o) {
  final groups = <String>[];
  for (var i = 0; i < 16; i += 2) {
    groups.add(((f[o + i] << 8) | f[o + i + 1]).toRadixString(16));
  }
  return groups.join(':');
}

/// The question and address answers of a DNS message.
class DnsMessage {
  const DnsMessage(this.question, this.answers);

  final String? question;
  final List<DnsAnswer> answers;
}

/// Decodes a DNS message, or returns null if it is malformed.
///
/// Reads the first question and the A and AAAA answers. Compression pointers
/// are followed for answer names (they are how responses repeat the question),
/// with a hop limit against loops.
DnsMessage? parseDns(Uint8List message) {
  if (message.length < 12) return null;
  final questions = (message[4] << 8) | message[5];
  final answerCount = (message[6] << 8) | message[7];
  if (questions == 0) return null;
  try {
    var p = 12;
    String? firstQuestion;
    for (var i = 0; i < questions; i++) {
      final name = _dnsName(message, p);
      if (name == null) return null;
      firstQuestion ??= name.value;
      p = name.next + 4;
    }
    final answers = <DnsAnswer>[];
    for (var i = 0; i < answerCount; i++) {
      final name = _dnsName(message, p);
      if (name == null) break;
      p = name.next;
      if (p + 10 > message.length) break;
      final type = (message[p] << 8) | message[p + 1];
      final length = (message[p + 8] << 8) | message[p + 9];
      p += 10;
      if (p + length > message.length) break;
      if (type == 1 && length == 4) {
        answers.add(DnsAnswer(name.value, message.sublist(p, p + 4).join('.')));
      } else if (type == 28 && length == 16) {
        answers.add(DnsAnswer(name.value, _ipv6(message, p)));
      }
      p += length;
    }
    return DnsMessage(firstQuestion, answers);
  } on RangeError {
    return null;
  }
}

/// A decoded name and the offset just past it in the message.
class _DnsName {
  const _DnsName(this.value, this.next);

  final String value;
  final int next;
}

_DnsName? _dnsName(Uint8List m, int start) {
  final labels = <String>[];
  var p = start;
  int? after;
  var hops = 0;
  while (true) {
    if (p >= m.length) return null;
    final length = m[p];
    if (length == 0) {
      after ??= p + 1;
      break;
    }
    if (length & 0xc0 == 0xc0) {
      if (p + 1 >= m.length || hops++ > 8) return null;
      after ??= p + 2;
      p = ((length & 0x3f) << 8) | m[p + 1];
      continue;
    }
    if (length & 0xc0 != 0 || p + 1 + length > m.length) return null;
    labels.add(
      ascii.decode(m.sublist(p + 1, p + 1 + length), allowInvalid: true),
    );
    p += 1 + length;
  }
  if (labels.isEmpty) return null;
  return _DnsName(labels.join('.').toLowerCase(), after);
}

/// What [extractSni] found in a TCP payload.
class SniResult {
  const SniResult(this.name, {this.split = false});

  final String? name;

  /// The payload starts a ClientHello that continues in another segment.
  final bool split;
}

/// Reads the server name from a TLS ClientHello at the start of [payload]
/// (RFC 6066, `server_name` extension 0).
///
/// Returns no name for anything else. Every read is bounds-checked, since a
/// capture can contain arbitrary bytes.
SniResult extractSni(Uint8List payload) {
  const none = SniResult(null);
  // Record: type 0x16 (handshake), version 03 xx, length(2); handshake:
  // type 0x01 (ClientHello), length(3).
  if (payload.length < 9 || payload[0] != 0x16 || payload[1] != 0x03) {
    return none;
  }
  if (payload[5] != 0x01) return none;
  final recordLength = (payload[3] << 8) | payload[4];
  if (payload.length < 5 + recordLength) {
    return const SniResult(null, split: true);
  }
  try {
    var p = 5 + 4 + 2 + 32; // record + handshake headers, version, random
    p += 1 + payload[p]; // session id
    p += 2 + ((payload[p] << 8) | payload[p + 1]); // cipher suites
    p += 1 + payload[p]; // compression methods
    final extensionsEnd = p + 2 + ((payload[p] << 8) | payload[p + 1]);
    p += 2;
    while (p + 4 <= extensionsEnd) {
      final type = (payload[p] << 8) | payload[p + 1];
      final length = (payload[p + 2] << 8) | payload[p + 3];
      if (type == 0) {
        // server_name_list length(2), name_type(1) = 0, host_name length(2).
        if (payload[p + 6] != 0) return none;
        final hostLength = (payload[p + 7] << 8) | payload[p + 8];
        final host = payload.sublist(p + 9, p + 9 + hostLength);
        return SniResult(ascii.decode(host, allowInvalid: true).toLowerCase());
      }
      p += 4 + length;
    }
  } on RangeError {
    return none;
  }
  return none;
}

/// A plaintext HTTP message start.
class HttpStart {
  const HttpStart({this.requestLine, this.host, this.isResponse = false});

  final String? requestLine;
  final String? host;
  final bool isResponse;
}

const _httpVerbs = ['GET ', 'POST ', 'PUT ', 'HEAD ', 'DELETE ', 'OPTIONS '];

/// Recognises a plaintext HTTP/1.x request or response at the start of
/// [payload], on any port.
HttpStart? parseHttp(Uint8List payload) {
  final head = ascii.decode(
    payload.sublist(0, payload.length < 512 ? payload.length : 512),
    allowInvalid: true,
  );
  if (head.startsWith('HTTP/1.')) return const HttpStart(isResponse: true);
  if (!_httpVerbs.any(head.startsWith)) return null;
  final lines = const LineSplitter().convert(head);
  if (!lines.first.contains(' HTTP/1.')) return null;
  String? host;
  for (final line in lines.skip(1)) {
    if (line.toLowerCase().startsWith('host:')) {
      host = line.substring(5).trim().toLowerCase();
      break;
    }
  }
  return HttpStart(requestLine: lines.first, host: host);
}

/// Whether [haystack] contains [needle] as raw bytes.
bool containsBytes(Uint8List haystack, List<int> needle) {
  if (needle.isEmpty) return true;
  final last = haystack.length - needle.length;
  for (var i = 0; i <= last; i++) {
    var j = 0;
    while (j < needle.length && haystack[i + j] == needle[j]) {
      j++;
    }
    if (j == needle.length) return true;
  }
  return false;
}
