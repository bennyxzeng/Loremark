import 'dart:convert';
import 'dart:typed_data';

/// Builds small classic pcap files for the parser and audit tests, so no
/// capture from a real device has to live in the repo.

/// The guest address the emulator uses.
const guestIp = '10.0.2.15';

List<int> _ipv4(String address) => address.split('.').map(int.parse).toList();

List<int> _u16(int value) => [(value >> 8) & 0xff, value & 0xff];

/// An Ethernet frame holding an IPv4 packet with [protocol] and [payload].
List<int> ipv4Frame(
  String src,
  String dst,
  int protocol,
  List<int> payload, {
  int fragmentField = 0,
}) {
  final total = 20 + payload.length;
  return [
    ...List.filled(6, 0x52), // destination MAC
    ...List.filled(6, 0x54), // source MAC
    0x08, 0x00, // IPv4
    0x45, 0x00, ..._u16(total), ..._u16(1), ..._u16(fragmentField),
    64, protocol, 0, 0, ..._ipv4(src), ..._ipv4(dst),
    ...payload,
  ];
}

List<int> udp(int srcPort, int dstPort, List<int> payload) => [
  ..._u16(srcPort),
  ..._u16(dstPort),
  ..._u16(8 + payload.length),
  0,
  0,
  ...payload,
];

List<int> tcp(int srcPort, int dstPort, List<int> payload) => [
  ..._u16(srcPort),
  ..._u16(dstPort),
  0, 0, 0, 1, 0, 0, 0, 1, // sequence and acknowledgement numbers
  0x50, 0x18, // 20-byte header, PSH+ACK
  0xff, 0xff, 0, 0, 0, 0,
  ...payload,
];

List<int> _dnsName(String name) => [
  for (final label in name.split('.')) ...[
    label.length,
    ...ascii.encode(label),
  ],
  0,
];

/// A DNS query for [name] (type A).
List<int> dnsQuery(String name, {int id = 0x1234}) => [
  ..._u16(id),
  0x01,
  0x00,
  0,
  1,
  0,
  0,
  0,
  0,
  0,
  0,
  ..._dnsName(name),
  0,
  1,
  0,
  1,
];

/// A DNS response for [name] with one A record for [address], using a
/// compression pointer for the answer name as real resolvers do.
List<int> dnsResponse(String name, String address, {int id = 0x1234}) => [
  ..._u16(id), 0x81, 0x80, 0, 1, 0, 1, 0, 0, 0, 0,
  ..._dnsName(name), 0, 1, 0, 1,
  0xc0, 0x0c, // pointer to the question name
  0, 1, 0, 1, 0, 0, 0, 60, 0, 4, ..._ipv4(address),
];

/// A TLS 1.2 ClientHello record with a `server_name` extension for [host].
List<int> clientHello(String host) {
  final name = ascii.encode(host);
  final serverName = [
    ..._u16(name.length + 3),
    0,
    ..._u16(name.length),
    ...name,
  ];
  final extension = [0, 0, ..._u16(serverName.length), ...serverName];
  final body = [
    0x03, 0x03, // version
    ...List.filled(32, 7), // random
    0, // session id length
    0, 4, 0x13, 0x01, 0xc0, 0x2f, // two cipher suites
    1, 0, // compression: null
    ..._u16(extension.length), ...extension,
  ];
  final handshake = [0x01, 0, ..._u16(body.length), ...body];
  return [0x16, 0x03, 0x01, ..._u16(handshake.length), ...handshake];
}

/// A plaintext HTTP request.
List<int> httpGet(String host, String path) =>
    ascii.encode('GET $path HTTP/1.1\r\nHost: $host\r\n\r\n');

/// A classic pcap holding [frames] as `(timeUs, frame)` pairs.
///
/// [bigEndian] writes the 0xa1b2c3d4 variant, [nanoseconds] the 0xa1b23c4d
/// one; by default it is the emulator's little-endian microsecond file.
Uint8List pcapFile(
  List<(int, List<int>)> frames, {
  bool bigEndian = false,
  bool nanoseconds = false,
  int linkType = 1,
  int truncateBy = 0,
}) {
  final endian = bigEndian ? Endian.big : Endian.little;
  final out = BytesBuilder();
  void u32(int v) {
    final b = ByteData(4)..setUint32(0, v, endian);
    out.add(b.buffer.asUint8List());
  }

  void u16(int v) {
    final b = ByteData(2)..setUint16(0, v, endian);
    out.add(b.buffer.asUint8List());
  }

  u32(nanoseconds ? 0xa1b23c4d : 0xa1b2c3d4);
  u16(2);
  u16(4);
  u32(0);
  u32(0);
  u32(65536);
  u32(linkType);
  for (final (timeUs, frame) in frames) {
    u32(timeUs ~/ 1000000);
    final fraction = timeUs % 1000000;
    u32(nanoseconds ? fraction * 1000 : fraction);
    u32(frame.length);
    u32(frame.length);
    out.add(frame);
  }
  final bytes = out.toBytes();
  return truncateBy == 0
      ? bytes
      : Uint8List.sublistView(bytes, 0, bytes.length - truncateBy);
}
