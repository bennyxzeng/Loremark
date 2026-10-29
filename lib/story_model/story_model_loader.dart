import 'dart:convert';

import 'package:flutter/services.dart';

import 'story_model.dart';

/// The story model the demo Story Map shows (86—EIGHTY-SIX, Vol. 1).
const demoStoryModelAsset =
    'tools/story_model_lab/stores/86v1/story_model.json';

/// Loads and parses a `story_model.json` bundled as an asset.
Future<StoryModel> loadStoryModel(String asset, {AssetBundle? bundle}) async {
  // Decoded here rather than with loadString, which moves large files to a
  // background isolate that widget tests never let finish.
  final data = await (bundle ?? rootBundle).load(asset);
  final text = utf8.decode(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  return StoryModel.fromJson(jsonDecode(text) as Map<String, dynamic>);
}
