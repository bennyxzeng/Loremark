/// Every threshold the reading insights use, in one place.
///
/// Most values are design choices, not research constants: nobody has
/// published validated thresholds for confusion in e-books. The ones with a
/// source say so. KOReader's statistics plugin and Readest (both AGPL, so only
/// the ideas are used) clamp a page's reading time to two minutes and drop
/// flip-throughs; Brysbaert (2019) gives the reference reading speeds.
class InsightsConfig {
  const InsightsConfig({
    this.minDwell = const Duration(seconds: 3),
    this.maxDwell = const Duration(seconds: 120),
    this.mergeWindow = const Duration(milliseconds: 300),
    this.sampleMinUnits = 40,
    this.sampleMinUnitsPerMinute = 60,
    this.sampleMaxUnitsPerMinute = 900,
    this.paceWindow = 40,
    this.paceTrimFraction = 0.1,
    this.paceShrinkage = 6,
    this.paceFloorUnitsPerMinute = 80,
    this.paceCeilingUnitsPerMinute = 600,
    this.minSamplesToShow = 6,
    this.minPoolSamplesToShow = 20,
    this.poolWindow = 100,
    this.keptSamples = 200,
    this.defaultLatinUnitsPerMinute = 230,
    this.defaultCjkUnitsPerMinute = 400,
    this.cjkMajority = 0.5,
    this.defaultPageUnits = 200,
    this.defaultCjkPageUnits = 450,
    this.pageUnitsWindow = 50,
    this.minPageUnitSamples = 5,
    this.swipeJumpFactor = 1.5,
    this.buttonJumpFactor = 4,
    this.sessionGap = const Duration(minutes: 10),
    this.backgroundSessionBreak = const Duration(minutes: 5),
    this.streakDayMinutes = 5,
    this.minVisit = const Duration(seconds: 4),
    this.spanOverlap = 0.5,
    this.rereadVisits = 3,
    this.rereadBackArrivals = 2,
    this.rereadWindow = const Duration(minutes: 20),
    this.warmUpGrace = const Duration(seconds: 90),
    this.warmUpGracePages = 2,
    this.stallZ = 3.5,
    this.stallSigmaFloor = 0.15,
    this.stallMinDwell = const Duration(seconds: 60),
    this.stallMaxDwell = const Duration(seconds: 240),
    this.stallDwellFactor = 3,
    this.stallLookback = const Duration(seconds: 20),
    this.stallBaselineWindow = 100,
    this.stallMinBaseline = 30,
    this.bounceCount = 2,
    this.bounceWindow = const Duration(minutes: 30),
    this.bounceSectionSlack = 1,
    this.bounceBackPages = 2,
    this.searchBurstCount = 3,
    this.searchBurstWindow = const Duration(minutes: 5),
    this.dedupWindow = const Duration(hours: 24),
    this.nudgeCooldown = const Duration(minutes: 30),
    this.nudgeCooldownPages = 25,
    this.nudgesPerSession = 2,
    this.nudgesPerDay = 4,
    this.dismissSuppression = const Duration(minutes: 60),
    this.dismissalsPerSession = 2,
    this.nudgeNearPages = 2,
    this.nudgeMovedOnPages = 3,
    this.nudgeWarmUp = const Duration(minutes: 2),
    this.nudgeAfterBackground = const Duration(seconds: 30),
    this.nudgeCandidateTtl = const Duration(minutes: 3),
    this.nudgeNeighbourhood = const Duration(minutes: 10),
    this.compactBytes = 1024 * 1024,
    this.compactLines = 15000,
    this.keepRawDays = 60,
    this.hardCapBytes = 4 * 1024 * 1024,
    this.hardCapRawDays = 14,
  });

  // Dwell: how long a page was on screen.

  /// A page shown for less than this was flipped through and doesn't count
  /// (Readest 3 s, KOReader 5 s).
  final Duration minDwell;

  /// A longer dwell is clamped to this, so a slow page still counts as read
  /// but a phone left on the table doesn't (KOReader and Readest, 120 s).
  final Duration maxDwell;

  /// Two positions closer together than this are one page turn: a finished
  /// section followed by the first page of the next.
  final Duration mergeWindow;

  // Pace: units per minute, where a unit is a word or a CJK character.

  /// Pages shorter than this (title pages, last stubs) don't give a sample.
  final int sampleMinUnits;
  final double sampleMinUnitsPerMinute;

  /// Faster than this is skimming or flicking, slower is an interruption.
  final double sampleMaxUnitsPerMinute;

  /// The estimate uses the newest samples of this book.
  final int paceWindow;

  /// The slowest share of the window is dropped as probable interruptions.
  final double paceTrimFraction;

  /// Weight of the prior, in samples, when blending it with the reader's own.
  final double paceShrinkage;
  final double paceFloorUnitsPerMinute;
  final double paceCeilingUnitsPerMinute;

  /// Minutes are shown once this book has this many samples (Readest uses 5)...
  final int minSamplesToShow;

  /// ...or the reader's other books have this many.
  final int minPoolSamplesToShow;

  /// Samples from other books that make up the prior.
  final int poolWindow;

  /// Samples kept in memory per book.
  final int keptSamples;

  /// Reference speeds for the cold start: Brysbaert (2019) measured 238 wpm
  /// for English non-fiction and 260 for fiction, and 260 wpm for Chinese at
  /// about 1.55 characters a word. Phones show little text per page and
  /// readers stop to think, so both sit a little under.
  final double defaultLatinUnitsPerMinute;
  final double defaultCjkUnitsPerMinute;

  /// A book counts characters, not words, when more than this share of its
  /// units are CJK characters.
  final double cjkMajority;

  // Pages: how far one turn moves.

  /// The page length assumed before enough turns are seen.
  final double defaultPageUnits;
  final double defaultCjkPageUnits;
  final int pageUnitsWindow;
  final int minPageUnitSamples;

  /// A swipe or other unexplained move longer than this many pages is a jump.
  final double swipeJumpFactor;

  /// The page buttons only count as a jump beyond this many pages, so a
  /// larger font doesn't turn every page into one.
  final double buttonJumpFactor;

  // Sessions and days.

  /// Silence longer than this ends a session. Our dwell cap is two minutes,
  /// so any longer silence is not reading; ten minutes keeps a tea break in
  /// one session. Google Analytics uses 30, a Play Books statistics script 5.
  final Duration sessionGap;

  /// Time in the background at least this long ends a session. A shorter
  /// trip, such as pulling down the notification shade, continues it.
  final Duration backgroundSessionBreak;

  /// Minutes of reading that make a day count towards the streak.
  final int streakDayMinutes;

  // Confusion detection.

  /// A view shown for less than this is a glance, not a visit.
  final Duration minVisit;

  /// Two views are the same span if they overlap by this share of the
  /// shorter one.
  final double spanOverlap;

  /// R1: a span visited this many times within [rereadWindow], at least
  /// [rereadBackArrivals] of them by going back to it.
  final int rereadVisits;
  final int rereadBackArrivals;
  final Duration rereadWindow;

  /// R1: going back to the page before the resume point in this time after
  /// opening is everyone regaining context, not confusion.
  final Duration warmUpGrace;
  final double warmUpGracePages;

  /// R2: a long dwell is a stall when its modified z-score on ln(seconds per
  /// unit) is at least [stallZ] (Iglewicz and Hoaglin 3.5, Leys et al. 2.5),
  /// [stallDwellFactor] times the usual page, within the dwell bounds, and
  /// followed by looking back within [stallLookback].
  final double stallZ;

  /// Keeps a near-constant reader from making z explode: 0.15 is about 16%.
  final double stallSigmaFloor;
  final Duration stallMinDwell;
  final Duration stallMaxDwell;
  final double stallDwellFactor;
  final Duration stallLookback;
  final int stallBaselineWindow;
  final int stallMinBaseline;

  /// R3: [bounceCount] trips back to the same earlier section (give or take
  /// [bounceSectionSlack]) and forward again within [bounceWindow]. A move
  /// back of more than [bounceBackPages] pages across a section boundary
  /// counts as a trip like a contents jump.
  final int bounceCount;
  final Duration bounceWindow;
  final int bounceSectionSlack;
  final double bounceBackPages;

  /// R4: this many searches within [searchBurstWindow].
  final int searchBurstCount;
  final Duration searchBurstWindow;

  /// A span emits at most one signal per rule in this time.
  final Duration dedupWindow;

  // Nudge policy.

  /// After a nudge, none for this long and this many forward pages,
  /// whichever is later.
  final Duration nudgeCooldown;
  final int nudgeCooldownPages;
  final int nudgesPerSession;
  final int nudgesPerDay;

  /// Dismissing a nudge holds back the next ones this long; this many
  /// dismissals in a row in a session stop nudges for the session.
  final Duration dismissSuppression;
  final int dismissalsPerSession;

  /// A nudge only shows while the reader is within this many pages of the
  /// passage, and is dropped once they are [nudgeMovedOnPages] past it.
  final double nudgeNearPages;
  final double nudgeMovedOnPages;

  /// No nudge this soon after a session starts, or after the app came back
  /// from the background.
  final Duration nudgeWarmUp;
  final Duration nudgeAfterBackground;

  /// A nudge that can't show yet is dropped after this long: it would be
  /// about a passage the reader has left.
  final Duration nudgeCandidateTtl;

  /// A medium signal nudges only with another signal this close in time (or
  /// on the same passage).
  final Duration nudgeNeighbourhood;

  // Log compaction.
  final int compactBytes;
  final int compactLines;
  final int keepRawDays;
  final int hardCapBytes;
  final int hardCapRawDays;
}
