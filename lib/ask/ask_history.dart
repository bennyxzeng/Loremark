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
  /// A record only; it doesn't decide what is sent.
  final TextPosition limit;
  final DateTime askedAt;

  /// Whether the answer was cut off before it finished.
  final bool cutOff;

  AskTurn get turn => AskTurn(question: question, answer: answer);

  Map<String, dynamic> toJson() => {
    'question': question,
    'answer': answer,
    'limit': limit.toJson(),
    'askedAt': askedAt.toUtc().toIso8601String(),
    if (cutOff) 'cutOff': true,
  };
}

/// The most exchanges kept in one conversation; older ones are dropped.
const maxKeptExchanges = 200;

/// One conversation about a book, as saved. Never empty.
class AskConversation {
  AskConversation(this.id, List<AskExchange> exchanges)
    : assert(exchanges.isNotEmpty),
      exchanges = List.unmodifiable(exchanges);

  final String id;

  /// Oldest first.
  final List<AskExchange> exchanges;

  /// Its first question.
  String get title => exchanges.first.question;

  /// When its last question was asked.
  DateTime get updatedAt => exchanges.last.askedAt;

  int get length => exchanges.length;
}

/// Each book's Ask conversations, kept on the device next to the library as
/// `chats/<book id>/<conversation id>.json`.
///
/// They are the reader's own record, so losing one loses nothing of the book:
/// a file that can't be read is an empty conversation.
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

  /// An id for a conversation started at [now].
  static String newId(DateTime now) => 'c${now.microsecondsSinceEpoch}';

  /// The folder of [bookId]'s conversations. A path separator or `..` never
  /// reaches the disk.
  Directory folder(String bookId) {
    _check(bookId, 'bookId');
    return Directory('${root.path}/chats/$bookId');
  }

  /// The file of conversation [id] about [bookId].
  File file(String bookId, String id) {
    _check(id, 'id');
    return File('${folder(bookId).path}/$id.json');
  }

  /// Where the one conversation a book had before there could be several was
  /// kept.
  File _singleFile(String bookId) => File('${folder(bookId).path}.json');

  static void _check(String id, String name) {
    if (!_validId.hasMatch(id)) {
      throw ArgumentError.value(id, name, 'Not a valid id');
    }
  }

  /// The conversations about [bookId], the latest first. Files that can't be
  /// read are left out.
  Future<List<AskConversation>> list(String bookId) async {
    await _moveSingleFile(bookId);
    final dir = folder(bookId);
    final conversations = <AskConversation>[];
    try {
      await for (final entity in dir.list()) {
        final name = entity.uri.pathSegments.last;
        if (entity is! File || !name.endsWith('.json')) continue;
        final id = name.substring(0, name.length - '.json'.length);
        if (!_validId.hasMatch(id)) continue;
        final exchanges = await _read(entity);
        if (exchanges.isEmpty) continue;
        conversations.add(AskConversation(id, exchanges));
      }
    } on FileSystemException {
      return [];
    }
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  /// Conversation [id] about [bookId], oldest first; empty if there is none
  /// or it can't be read.
  Future<List<AskExchange>> load(String bookId, String id) =>
      _read(file(bookId, id));

  /// Writes [exchanges] as conversation [id] about [bookId], keeping the
  /// latest [maxKeptExchanges]. A crash mid-write leaves the old file or the
  /// new one.
  Future<void> save(String bookId, String id, List<AskExchange> exchanges) =>
      _write(file(bookId, id), exchanges);

  /// Forgets conversation [id] about [bookId].
  Future<void> delete(String bookId, String id) async {
    final target = file(bookId, id);
    if (await target.exists()) await target.delete();
  }

  /// Forgets every conversation about [bookId].
  Future<void> deleteBook(String bookId) async {
    final dir = folder(bookId);
    if (await dir.exists()) await dir.delete(recursive: true);
    final single = _singleFile(bookId);
    if (await single.exists()) await single.delete();
  }

  /// Moves the book's one conversation from before there could be several
  /// into its folder, as a conversation of its own. One that can't be read is
  /// left where it is.
  Future<void> _moveSingleFile(String bookId) async {
    final single = _singleFile(bookId);
    if (!await single.exists()) return;
    final exchanges = await _read(single);
    if (exchanges.isEmpty) return;
    final target = file(bookId, newId(exchanges.first.askedAt));
    await target.parent.create(recursive: true);
    await single.rename(target.path);
  }

  Future<List<AskExchange>> _read(File file) async {
    try {
      final json = jsonDecode(await file.readAsString());
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

  Future<void> _write(File target, List<AskExchange> exchanges) async {
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
}
