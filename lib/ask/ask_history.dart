import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../reading/text_position.dart';
import 'ask_engine.dart';

/// A question asked in Ask and the answer it got.
class AskExchange {
  const AskExchange({
    required this.question,
    required this.answer,
    required this.limit,
    required this.askedAt,
    this.cutOff = false,
  });

  /// Reads an exchange saved by [toJson]. Throws a [FormatException] if it
  /// isn't one.
  factory AskExchange.fromJson(Map<String, dynamic> json) {
    final question = json['question'];
    final answer = json['answer'];
    final limit = json['limit'];
    final askedAt = DateTime.tryParse('${json['askedAt']}');
    if (question is! String ||
        answer is! String ||
        limit is! Map<String, dynamic> ||
        askedAt == null) {
      throw FormatException('Invalid AskExchange: $json');
    }
    return AskExchange(
      question: question,
      answer: answer,
      limit: TextPosition.fromJson(limit),
      askedAt: askedAt,
      cutOff: json['cutOff'] == true,
    );
  }

  final String question;

  /// With only citations of paragraphs that were real when it was answered.
  final String answer;

  /// How far the reader had read when it was asked: see `AskReach.limit`.
  final TextPosition limit;
  final DateTime askedAt;

  /// Whether the answer was cut off before it finished.
  final bool cutOff;

  AskTurn get turn => AskTurn(question: question, answer: answer, limit: limit);

  Map<String, dynamic> toJson() => {
    'question': question,
    'answer': answer,
    'limit': limit.toJson(),
    'askedAt': askedAt.toUtc().toIso8601String(),
    if (cutOff) 'cutOff': true,
  };
}

/// The most exchanges kept for a book; older ones are dropped.
const maxKeptExchanges = 200;

/// Each book's Ask conversation, kept on the device next to the library as
/// `chats/<book id>.json`.
///
/// It is the reader's own record, so losing it loses nothing of the book: a
/// file that can't be read is an empty conversation.
class AskHistoryStore {
  AskHistoryStore(this.root);

  /// The store in the library folder of the app's support directory.
  static Future<AskHistoryStore> open() async {
    final support = await getApplicationSupportDirectory();
    return AskHistoryStore(Directory('${support.path}/library'));
  }

  /// The library folder, the same one `BookRepository` uses.
  final Directory root;

  static final _validId = RegExp(r'^[A-Za-z0-9_-]+$');

  /// The file for [bookId]. A path separator or `..` never reaches the disk.
  File file(String bookId) {
    if (!_validId.hasMatch(bookId)) {
      throw ArgumentError.value(bookId, 'bookId', 'Not a valid book id');
    }
    return File('${root.path}/chats/$bookId.json');
  }

  /// The conversation about [bookId], oldest first; empty if there is none or
  /// it can't be read.
  Future<List<AskExchange>> load(String bookId) async {
    try {
      final json = jsonDecode(await file(bookId).readAsString());
      if (json is! Map<String, dynamic> || json['version'] != 1) return [];
      return [
        for (final item in json['exchanges'] as List)
          AskExchange.fromJson(item as Map<String, dynamic>),
      ];
    } on FileSystemException {
      return [];
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  }

  /// Writes [exchanges] as the conversation about [bookId], keeping the latest
  /// [maxKeptExchanges]. A crash mid-write leaves the old file or the new one.
  Future<void> save(String bookId, List<AskExchange> exchanges) async {
    final target = file(bookId);
    await target.parent.create(recursive: true);
    final kept = exchanges.length > maxKeptExchanges
        ? exchanges.sublist(exchanges.length - maxKeptExchanges)
        : exchanges;
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'version': 1,
        'exchanges': [for (final exchange in kept) exchange.toJson()],
      }),
      flush: true,
    );
    await temp.rename(target.path);
  }

  /// Forgets the conversation about [bookId].
  Future<void> delete(String bookId) async {
    final target = file(bookId);
    if (await target.exists()) await target.delete();
  }
}
