import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/story_model/story_model.dart';
import 'package:loremark/story_model/story_model_loader.dart';
import 'package:loremark/story_model/story_snapshot.dart';

// Checks the real demo data the Story Map ships with, read from disk.
void main() {
  final model = StoryModel.fromJson(
    jsonDecode(File(demoStoryModelAsset).readAsStringSync())
        as Map<String, dynamic>,
  );
  final chapter1 = model.sections.firstWhere((s) => s.chapterNumber == 1);
  final chapter2 = model.sections.firstWhere((s) => s.chapterNumber == 2);

  String? idOf(String name) => model.names
      .where((record) => record.payload.text == name)
      .firstOrNull
      ?.payload
      .entityId;

  test('Shin is still Undertaker in chapter 1', () {
    final shin = idOf('Shinei Nouzen')!;
    expect(StorySnapshot(model, chapter1).displayName(shin), 'Undertaker');
    expect(StorySnapshot(model, chapter2).displayName(shin), 'Shinei Nouzen');
  });

  test('characters from chapter 2 are hidden in chapter 1', () {
    final raiden = idOf('Raiden')!;
    final known = StorySnapshot(model, chapter1).knownEntities;
    expect([for (final e in known) e.id], isNot(contains(raiden)));
    expect([
      for (final e in StorySnapshot(model, chapter2).knownEntities) e.id,
    ], contains(raiden));
  });
}
