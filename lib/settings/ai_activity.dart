import 'package:flutter/foundation.dart';

/// Counts the AI tasks in flight anywhere in the app: Story Map updates and
/// Ask answers.
///
/// Each task holds on to the API key it started with, so the active key can't
/// change while [busy]: a task would carry on, and keep spending, on a key the
/// reader thinks they have switched away from.
class AiActivity extends ChangeNotifier {
  AiActivity();

  /// The app's tracker. Tests make their own.
  static final instance = AiActivity();

  int _running = 0;

  /// Whether any AI task is running.
  bool get busy => _running > 0;

  /// Marks a task as started, and returns what to call once it has ended.
  /// Calling that more than once does nothing.
  ///
  /// Call it before the task's first `await`, where it reads the key, so that
  /// there is no moment in which the key is held but the task isn't counted.
  VoidCallback begin() {
    _running++;
    if (_running == 1) notifyListeners();
    var ended = false;
    return () {
      if (ended) return;
      ended = true;
      _running--;
      if (_running == 0) notifyListeners();
    };
  }
}
