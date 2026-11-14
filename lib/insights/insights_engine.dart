import '../reader/reader_position.dart';
import 'book_units.dart';
import 'confusion_detector.dart';
import 'insights_config.dart';
import 'nudge_policy.dart';
import 'reading_insights.dart';
import 'reading_log.dart';
import 'reading_timeline.dart';
import 'view_tracker.dart';

/// Everything computed from a book's log, fed one record at a time.
///
/// The app feeds it as the reader reads, and opening a book feeds it the
/// whole saved log through the same [add], so what the reader sees after a
/// restart is what they would have seen had the app stayed open. It holds no
/// state a log can't rebuild.
class InsightsEngine {
  InsightsEngine({
    required this.units,
    this.config = const InsightsConfig(),
    List<PaceSample> pool = const [],
    bool hintsEnabled = true,
  }) : tracker = ViewTracker(units, config),
       timeline = ReadingTimeline(config),
       detector = ConfusionDetector(
         units: units,
         config: config,
         externalBaseline: pool,
       ),
       policy = NudgePolicy(
         units: units,
         config: config,
         hintsEnabled: hintsEnabled,
       );

  final BookUnits units;
  final InsightsConfig config;
  final ViewTracker tracker;
  final ReadingTimeline timeline;
  final ConfusionDetector detector;
  final NudgePolicy policy;

  /// Takes the next record and returns the confusion signals it caused.
  List<ConfusionSignal> add(LogRecord record) {
    if (record is DayRecord) {
      timeline.addDay(record);
      return const [];
    }
    final events = tracker.add(record);
    events.forEach(timeline.onEvent);
    final signals = detector.processEvents(events);
    policy.process(events, signals);
    return signals;
  }

  /// Feeds a saved log, without the signals it would have shown.
  void replay(Iterable<LogRecord> records) {
    for (final record in records) {
      add(record);
    }
    policy.endReplay();
  }

  ReaderPosition? get furthest => tracker.furthest;
}
