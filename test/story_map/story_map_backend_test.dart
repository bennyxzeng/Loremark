import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/library/book.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/reader/reading_position_store.dart';
import 'package:loremark/settings/ai_settings.dart';
import 'package:loremark/story_map/story_map_backend.dart';
import 'package:loremark/story_update/story_api_client.dart';
import 'package:loremark/story_update/story_book.dart';
import 'package:loremark/story_update/story_model_choice.dart';

import '../story_update/golden.dart';

// The path the Update button really takes, from the bundled prompt through to
// the store on disk, with only the provider stood in for.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  final golden = readValidationGolden();
  final chapter1Delta = (golden['first'] as JsonMap)['candidate'];

  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('story_backend_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => temp.path,
        );
  });
  tearDownAll(() => temp.deleteSync(recursive: true));

  test('builds a map and reads it back', () async {
    final epub = File('$goldenDir/story.epub');
    final book = Book(
      id: StoryBook.open(epub.readAsBytesSync()).sha256Hash,
      title: 'Synthetic Story',
      author: null,
      epubPath: epub.path,
      coverPath: null,
      importedAt: DateTime.utc(2026),
    );
    late String sent;
    final backend = DeviceStoryMapBackend(
      post: (url, headers, body) async {
        sent = body;
        return StoryHttpResponse(
          200,
          jsonEncode({
            'status': 'completed',
            'output': [
              {
                'type': 'message',
                'content': [
                  {'type': 'output_text', 'text': jsonEncode(chapter1Delta)},
                ],
              },
            ],
          }),
        );
      },
    );

    expect(await backend.loadModel(book), isNull);
    final status = await backend.inspect(book);
    expect(status.isNewStore, isTrue);

    final outcome = await backend.update(
      book,
      credentials: const AiCredentials(
        provider: AiProvider.deepseek,
        apiKey: 'sk-test',
      ),
      model: StoryModelChoice.deepseekFlash,
      effort: StoryEffort.low,
      checkQuotes: false,
      startSectionId: 'section-002',
    );
    expect(outcome.status, 'committed', reason: '${outcome.issues}');
    // The real prompt and schema came out of the app's bundle.
    final body = jsonDecode(sent) as JsonMap;
    expect(
      ((body['input'] as List)[0] as JsonMap)['content'],
      startsWith('You build a cumulative story model'),
    );
    expect(body['reasoning'], {'effort': 'low'});

    final model = (await backend.loadModel(book))!;
    expect(model.sections.single.id, 'section-002');
    expect(model.sections.single.quotesChecked, isFalse);
    expect((await backend.inspect(book)).nextSectionId, 'section-003');

    // Nothing read yet: not even this section counts as finished.
    expect(await backend.finishedSections(book, model.sections), 0);
    final positions = await ReadingPositionStore.open();
    await positions.save(book.id, const ReaderPosition(1, 1));
    expect(await backend.finishedSections(book, model.sections), 1);
  });
}
