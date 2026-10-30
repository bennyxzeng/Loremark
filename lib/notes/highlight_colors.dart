import 'package:flutter/material.dart';

import 'note.dart';

/// This extension gives each highlight color the name and swatch shown in the app.
/// Ex. HighlightColor.blue.label is 'Blue' and its swatch is a light blue.
extension HighlightColorDisplay on HighlightColor {
  /// This is the name of the color shown to the reader. (Ex. 'Yellow')
  String get label => switch (this) {
    HighlightColor.yellow => 'Yellow',
    HighlightColor.green => 'Green',
    HighlightColor.blue => 'Blue',
    HighlightColor.pink => 'Pink',
  };

  /// This is the color used to draw the highlight.
  Color get swatch => switch (this) {
    HighlightColor.yellow => const Color(0xFFF5D76E),
    HighlightColor.green => const Color(0xFFA8D5A2),
    HighlightColor.blue => const Color(0xFF9CC3E6),
    HighlightColor.pink => const Color(0xFFF2A7C3),
  };
}
