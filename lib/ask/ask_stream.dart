import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../story_update/story_api_client.dart';
import '../story_update/story_book.dart' show JsonMap;

/// How long a reply may go quiet before Ask gives up on it. A model can think
/// for a while before its first word.
const askIdleTimeout = Duration(minutes: 3);

/// A reply as it streams in.
class AskHttpReply {
  /// [_close] drops the connection.
  AskHttpReply(this.statusCode, this.body, [this._close]);

  final int statusCode;

  /// The body, decoded, as it arrives.
  final Stream<String> body;
  final void Function()? _close;

  /// Drops the connection. Safe to call more than once.
  void close() => _close?.call();
}

/// Sends a request and starts reading its reply; tests replace the network.
typedef AskHttpPost = Future<AskHttpReply> Function(
  Uri url,
  Map<String, String> headers,
  String body,
);

/// Posts over the network. Throws a [TimeoutException] or an [IOException] if
/// there is no reply.
Future<AskHttpReply> postAskRequest(
  Uri url,
  Map<String, String> headers,
  String body,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client.postUrl(url);
    headers.forEach(request.headers.set);
    request.add(utf8.encode(body));
    final response = await request.close().timeout(askIdleTimeout);
    return AskHttpReply(
      response.statusCode,
      response.transform(utf8.decoder),
      () => client.close(force: true),
    );
  } on Object {
    client.close(force: true);
    rethrow;
  }
}

/// Stops a question that is under way: the request being read is dropped, and
/// no other is sent.
class AskCancel {
  bool _cancelled = false;
  void Function()? _close;

  bool get cancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _close?.call();
  }

  void _attach(void Function() close) {
    _close = close;
    if (_cancelled) close();
  }
}

/// A function the model asked to call.
class AskToolCall {
  const AskToolCall(this.callId, this.name, this.arguments);

  final String callId;
  final String name;

  /// JSON, as the model wrote it.
  final String arguments;
}

/// How one request ended.
class AskRound {
  AskRound(this.status, {this.error});

  /// `completed`, `incomplete`, `failed`, `refusal`, `api_error` or
  /// `cancelled`.
  final String status;

  /// `category` and `message`, never anything from the request's headers.
  final JsonMap? error;

  /// The response's output items, to send back with the tools' answers.
  List<JsonMap> output = const [];

  /// The functions the model asked to call, in order.
  List<AskToolCall> calls = const [];

  /// The final answer's text, if it gave one.
  String text = '';
  JsonMap? usage;
}

/// The data of each server-sent event in [chunks], decoded. An event that
/// isn't a JSON object is skipped.
///
/// A plain transformer rather than a generator, so a reader that stops partway
/// cancels it at once.
Stream<JsonMap> serverSentEvents(Stream<String> chunks) {
  final data = StringBuffer();
  var pending = false;
  void emit(EventSink<JsonMap> sink) {
    final text = data.toString();
    data.clear();
    pending = false;
    try {
      final decoded = jsonDecode(text);
      if (decoded is JsonMap) sink.add(decoded);
    } on FormatException {
      // Skipped: see above.
    }
  }

  return chunks
      .transform(const LineSplitter())
      .transform(
        StreamTransformer<String, JsonMap>.fromHandlers(
          handleData: (line, sink) {
            if (line.isEmpty) {
              if (pending) emit(sink);
              return;
            }
            // `event:` repeats the data's own `type`; `id:`, `retry:` and
            // comments don't matter here.
            if (!line.startsWith('data:')) return;
            var value = line.substring(5);
            if (value.startsWith(' ')) value = value.substring(1);
            if (pending) data.write('\n');
            data.write(value);
            pending = true;
          },
          handleDone: (sink) {
            if (pending) emit(sink);
            sink.close();
          },
        ),
      );
}

/// Sends one streamed request to the Responses API at [url] and reads it to
/// the end. Words of the final answer go to [onText] as they arrive.
///
/// Never retries and never throws: every way it can end is an [AskRound].
Future<AskRound> streamAskRound({
  required String url,
  required String apiKey,
  required String body,
  AskHttpPost post = postAskRequest,
  void Function(String delta)? onText,
  AskCancel? cancel,
}) async {
  if (cancel?.cancelled ?? false) return AskRound('cancelled');
  final AskHttpReply reply;
  try {
    reply = await post(Uri.parse(url), {
      HttpHeaders.authorizationHeader: 'Bearer $apiKey',
      HttpHeaders.contentTypeHeader: 'application/json',
      HttpHeaders.acceptHeader: 'text/event-stream',
    }, body);
  } on TimeoutException {
    return _failure('timeout', 'The request timed out');
  } on IOException catch (error) {
    if (cancel?.cancelled ?? false) return AskRound('cancelled');
    return _failure('network', '${error.runtimeType}');
  } on FormatException {
    // The error's message can quote a header's value, which is the key.
    return _failure(
      'invalid_request',
      'The request or its reply was not valid',
    );
  }
  // Ends the round once, however it ends, and lets go of the connection. The
  // stream's cancel isn't awaited: nothing more is wanted from it.
  final done = Completer<AskRound>();
  StreamSubscription<Object?>? subscription;
  Timer? idle;
  void end(AskRound round) {
    if (done.isCompleted) return;
    done.complete(round);
    idle?.cancel();
    unawaited(subscription?.cancel());
    reply.close();
  }

  // Gives up if the reply goes quiet for too long. Restarted by every event,
  // so a long answer that keeps coming is never cut off.
  void stillTalking() {
    idle?.cancel();
    idle = Timer(
      askIdleTimeout,
      () => end(_failure('timeout', 'The reply went quiet')),
    );
  }

  cancel?._attach(() => end(AskRound('cancelled')));
  if (done.isCompleted) return done.future;
  stillTalking();

  void failed(Object error) => end(switch (error) {
    IOException() => _failure('network', '${error.runtimeType}'),
    FormatException() => _failure(
      'invalid_response_body',
      'The reply is not text',
    ),
    _ => _failure('network', '${error.runtimeType}'),
  });

  if (reply.statusCode < 200 || reply.statusCode >= 300) {
    final text = StringBuffer();
    subscription = reply.body.listen(
      (chunk) {
        stillTalking();
        text.write(chunk);
      },
      onError: failed,
      onDone: () => end(
        AskRound(
          'api_error',
          error: storyApiError(
            reply.statusCode,
            redactStoryKey(text.toString(), apiKey),
          ).error,
        ),
      ),
      cancelOnError: true,
    );
    return done.future;
  }

  final hidden = <Object?>{};
  subscription = serverSentEvents(reply.body).listen(
    (event) {
      stillTalking();
      switch (event['type']) {
        case 'response.output_item.added':
          // Commentary before a tool call isn't the answer.
          final item = event['item'];
          if (item is Map &&
              item['type'] == 'message' &&
              item['phase'] != null &&
              item['phase'] != 'final_answer') {
            hidden.add(item['id']);
          }
        case 'response.output_text.delta':
          final delta = event['delta'];
          if (delta is String && !hidden.contains(event['item_id'])) {
            onText?.call(delta);
          }
        case 'response.completed' || 'response.incomplete' || 'response.failed':
          final response = event['response'];
          end(
            response is JsonMap
                ? _finish(response, apiKey)
                : _failure(
                    'invalid_response_body',
                    'The last event has no response',
                  ),
          );
        case 'error':
          end(
            AskRound(
              'failed',
              error: {
                'category': 'stream_error',
                'message': redactStoryKey(
                  '${event['message'] ?? event['code'] ?? 'The reply failed'}',
                  apiKey,
                ),
              },
            ),
          );
      }
    },
    onError: failed,
    onDone: () =>
        end(_failure('network', 'The reply stopped before it finished')),
    cancelOnError: true,
  );
  return done.future;
}

AskRound _failure(String category, String message) =>
    AskRound('api_error', error: {'category': category, 'message': message});

/// Reads the full response the last event carries.
AskRound _finish(JsonMap response, String apiKey) {
  try {
    final status = response['status'];
    final output = [
      for (final item in (response['output'] as List?) ?? const [])
        item as JsonMap,
    ];
    final (texts, refusals) = finalMessageParts(response);
    final AskRound round;
    if (response['error'] != null || status == 'failed') {
      round = AskRound(
        'failed',
        error: {
          'category': 'response_failed',
          'message': redactStoryKey(
            '${response['error'] ?? 'The response failed'}',
            apiKey,
          ),
        },
      );
    } else if (refusals.isNotEmpty) {
      round = AskRound(
        'refusal',
        error: {'category': 'refusal', 'message': refusals.join('\n')},
      );
    } else if (status == 'incomplete') {
      round = AskRound(
        'incomplete',
        error: {
          'category': 'incomplete',
          'message': '${response['incomplete_details']}',
        },
      );
    } else {
      round = AskRound('completed');
    }
    return round
      ..output = output
      ..calls = [
        for (final item in output)
          if (item['type'] == 'function_call')
            AskToolCall(
              item['call_id'] as String,
              item['name'] as String,
              (item['arguments'] as String?) ?? '{}',
            ),
      ]
      ..text = texts.join()
      ..usage = response['usage'] as JsonMap?;
  } on TypeError {
    return _failure(
      'invalid_response_body',
      'The response is not in the expected form',
    );
  }
}
