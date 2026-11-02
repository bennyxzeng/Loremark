import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'search_index.dart';
import 'tokenizer.dart';

/// Bump when the layout below changes, so older files are rebuilt.
const searchIndexFormatVersion = 2;

const _magic = [0x4C, 0x4D, 0x53, 0x49]; // "LMSI"

/// The bytes to save for [index]: the layout below, gzipped. gzip's CRC-32
/// catches a truncated or damaged file when it is read back, so no checksum
/// of our own is needed.
///
/// The layout, with every number a varint (7 bits per byte, low first):
///
/// ```
/// "LMSI"  formatVersion  headerLength  header(JSON: bookId, tokenizer, stemmer)
/// sectionCount  { linear(1 byte)  [textLength  text(UTF-8)] }*
/// paragraphCount  { tokenCount }*
/// termCount  { termLength  term(UTF-8) }*
/// { postingCount  { paragraphId - previous  frequency }* }*   one per term
/// ```
///
/// The section texts are in the file so opening a book's search never has to
/// unzip and parse the EPUB again; paragraphs are found again by splitting
/// them, which is cheap and can't disagree with the text.
Uint8List encodeSearchIndex(SearchIndex index) {
  final data = index.toData();
  final out = _Writer();
  out.bytes(_magic);
  out.varint(searchIndexFormatVersion);
  out.string(
    jsonEncode({
      'bookId': data.bookId,
      'tokenizer': tokenizerVersion,
      'stemmer': data.stemmed ? 'en' : 'none',
    }),
  );
  out.varint(data.sectionTexts.length);
  for (var i = 0; i < data.sectionTexts.length; i++) {
    out.byte(data.linear[i] ? 1 : 0);
    if (data.linear[i]) out.string(data.sectionTexts[i]);
  }
  out.varint(data.tokenCounts.length);
  for (final count in data.tokenCounts) {
    out.varint(count);
  }
  out.varint(data.terms.length);
  for (final term in data.terms) {
    out.string(term);
  }
  for (var t = 0; t < data.terms.length; t++) {
    final start = data.termStarts[t];
    final end = data.termStarts[t + 1];
    out.varint((end - start) >> 1);
    var previous = 0;
    for (var i = start; i < end; i += 2) {
      out.varint(data.postings[i] - previous);
      previous = data.postings[i];
      out.varint(data.postings[i + 1]);
    }
  }
  return Uint8List.fromList(gzip.encode(out.takeBytes()));
}

/// The index that [encodeSearchIndex] wrote.
///
/// Throws a [FormatException] if the bytes are damaged or truncated, were
/// written by another format or tokenizer version, or belong to a book other
/// than [bookId]; the caller then rebuilds. Never answers from an index
/// whose paragraph ids might not match the book.
SearchIndex decodeSearchIndex(Uint8List bytes, {required String bookId}) {
  final Uint8List plain;
  try {
    plain = Uint8List.fromList(gzip.decode(bytes));
  } on Object catch (error) {
    throw FormatException('Not a readable search index: $error');
  }
  try {
    return _read(_Reader(plain), bookId);
  } on FormatException {
    rethrow;
  } on Object catch (error) {
    // A range error from a length that points outside the data.
    throw FormatException('Damaged search index: $error');
  }
}

SearchIndex _read(_Reader input, String bookId) {
  for (final byte in _magic) {
    if (input.byte() != byte) throw const FormatException('Bad magic');
  }
  if (input.varint() != searchIndexFormatVersion) {
    throw const FormatException('Another search index format version');
  }
  final header = jsonDecode(input.string());
  if (header is! Map<String, dynamic>) {
    throw const FormatException('Bad header');
  }
  if (header['bookId'] != bookId) {
    throw const FormatException('The index is for another book');
  }
  if (header['tokenizer'] != tokenizerVersion) {
    throw const FormatException('Another tokenizer version');
  }
  final stemmer = header['stemmer'];
  if (stemmer != 'en' && stemmer != 'none') {
    throw const FormatException('Unknown stemmer');
  }

  final sectionCount = input.count();
  final texts = <String>[];
  final linear = <bool>[];
  for (var i = 0; i < sectionCount; i++) {
    final isLinear = input.byte() == 1;
    linear.add(isLinear);
    texts.add(isLinear ? input.string() : '');
  }
  final paragraphCount = input.count();
  final tokenCounts = Int32List(paragraphCount);
  for (var i = 0; i < paragraphCount; i++) {
    tokenCounts[i] = input.varint();
  }
  final termCount = input.count();
  final terms = [for (var i = 0; i < termCount; i++) input.string()];
  final starts = Int32List(termCount + 1);
  var postings = Int32List(1024);
  var used = 0;
  for (var t = 0; t < termCount; t++) {
    starts[t] = used;
    final count = input.count();
    if (used + count * 2 > postings.length) {
      final grown = Int32List(
        (postings.length * 2).clamp(used + count * 2, 1 << 30),
      )..setRange(0, used, postings);
      postings = grown;
    }
    var id = 0;
    for (var i = 0; i < count; i++) {
      id += input.varint();
      postings[used++] = id;
      postings[used++] = input.varint();
    }
  }
  starts[termCount] = used;
  if (!input.atEnd) throw const FormatException('Extra data');
  return SearchIndex.fromData(
    SearchIndexData(
      bookId: bookId,
      stemmed: stemmer == 'en',
      sectionTexts: texts,
      linear: linear,
      tokenCounts: tokenCounts,
      terms: terms,
      termStarts: starts,
      postings: Int32List.sublistView(postings, 0, used),
    ),
  );
}

class _Writer {
  var _buffer = Uint8List(1 << 16);
  var _length = 0;

  void _ensure(int extra) {
    if (_length + extra <= _buffer.length) return;
    var size = _buffer.length * 2;
    while (size < _length + extra) {
      size *= 2;
    }
    _buffer = Uint8List(size)..setRange(0, _length, _buffer);
  }

  void byte(int value) {
    _ensure(1);
    _buffer[_length++] = value;
  }

  void bytes(List<int> values) {
    _ensure(values.length);
    _buffer.setRange(_length, _length + values.length, values);
    _length += values.length;
  }

  void varint(int value) {
    assert(value >= 0);
    _ensure(10);
    while (value >= 0x80) {
      _buffer[_length++] = (value & 0x7F) | 0x80;
      value >>= 7;
    }
    _buffer[_length++] = value;
  }

  void string(String value) {
    final encoded = utf8.encode(value);
    varint(encoded.length);
    bytes(encoded);
  }

  Uint8List takeBytes() => Uint8List.sublistView(_buffer, 0, _length);
}

class _Reader {
  _Reader(this._bytes);

  final Uint8List _bytes;
  var _at = 0;

  bool get atEnd => _at == _bytes.length;

  int byte() {
    if (_at >= _bytes.length) throw const FormatException('Truncated');
    return _bytes[_at++];
  }

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final next = byte();
      result |= (next & 0x7F) << shift;
      if (next < 0x80) return result;
      shift += 7;
      if (shift > 56) throw const FormatException('Bad number');
    }
  }

  /// A length or count, which can't exceed what is left to read, so a
  /// damaged number can't make a huge allocation.
  int count() {
    final value = varint();
    if (value > _bytes.length) throw const FormatException('Bad count');
    return value;
  }

  String string() {
    final length = count();
    if (_at + length > _bytes.length) {
      throw const FormatException('Truncated');
    }
    final value = utf8.decode(_bytes.sublist(_at, _at + length));
    _at += length;
    return value;
  }
}
