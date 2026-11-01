import 'dart:convert';

import 'metrics.dart';
import 'privacy.dart';

/// The spec's reliability target: "force-quit the app 20 times mid-chapter.
/// The system should reopen within one page of the last position every time."
const requiredForceQuits = 20;

/// One force-quit (or offline, or open-from-library) trial.
class TrialResult {
  const TrialResult({
    required this.index,
    required this.kind,
    required this.pageTurns,
    required this.pass,
    required this.durationMs,
    this.before,
    this.last,
    this.saved,
    this.restored,
    this.restoredDistance,
    this.savedDistance,
    this.note,
  });

  final int index;

  /// `force-stop`, `kill-9`, `offline` or `open-from-library`.
  final String kind;
  final int pageTurns;
  final bool pass;
  final int durationMs;

  /// Where the reader settled after the trial's launch.
  final PagePosition? before;

  /// The last page shown before the kill.
  final PagePosition? last;

  /// The saved file read after the kill, as a page.
  final PagePosition? saved;

  /// Where the reader settled after the relaunch.
  final PagePosition? restored;

  /// Page turns between [last] and [restored]; null if not comparable.
  final int? restoredDistance;

  /// Page turns between [last] and [saved].
  final int? savedDistance;
  final String? note;

  Map<String, dynamic> toJson() => {
    'index': index,
    'kind': kind,
    'pageTurns': pageTurns,
    'pass': pass,
    'durationMs': durationMs,
    'before': before?.toJson(),
    'last': last?.toJson(),
    'saved': saved?.toJson(),
    'restored': restored?.toJson(),
    'restoredDistance': restoredDistance,
    'savedDistance': savedDistance,
    'note': note,
  };
}

/// The privacy audit: the app UID's network counters, and the pcap policy
/// check when a capture was given.
class PrivacyResult {
  const PrivacyResult({
    required this.uid,
    required this.before,
    required this.after,
    required this.uidsSeen,
    this.audit,
    this.pcapNote,
    this.captureRequired = false,
  });

  final int? uid;
  final UidTraffic? before;
  final UidTraffic? after;

  /// UIDs in the counters table, to show the table was readable and not empty.
  final int uidsSeen;
  final PcapAudit? audit;

  /// Why there is no pcap result, when there isn't.
  final String? pcapNote;
  final bool captureRequired;

  bool get measured => before != null && after != null;

  UidTraffic? get delta => measured ? after! - before! : null;

  /// True when the app moved no bytes over the network during the session.
  bool get netstatsPass => delta?.isZero ?? false;

  /// A capture was supplied (or required) but couldn't be shown to cover the
  /// session, so it proves nothing either way. The per-UID counters stay the
  /// gate: on the Windows emulator `-tcpdump` misses some guest DNS lookups,
  /// so an unverified capture must not fail a run, and must never pass one.
  bool get captureInconclusive => captureRequired && audit == null;

  bool get pass => netstatsPass && (audit?.pass ?? true);

  Map<String, dynamic> toJson() => {
    'appUid': uid,
    'netstatsMeasured': measured,
    'netstatsBefore': before?.toJson(),
    'netstatsAfter': after?.toJson(),
    'netstatsDelta': delta?.toJson(),
    'netstatsPass': netstatsPass,
    'uidsSeen': uidsSeen,
    'pcap': audit?.toJson(),
    'pcapNote': pcapNote,
    'captureRequired': captureRequired,
    'captureInconclusive': captureInconclusive,
    'pass': pass,
  };
}

/// Everything one harness run measured.
class AcceptanceReport {
  const AcceptanceReport({
    required this.startedAt,
    required this.device,
    required this.seed,
    required this.forceQuits,
    this.openFromLibrary,
    this.offline,
    this.privacy,
    this.notes = const [],
    this.requiredTrials = requiredForceQuits,
  });

  final DateTime startedAt;

  /// Model, Android version, build type, screen size.
  final Map<String, String> device;
  final int seed;
  final List<TrialResult> forceQuits;
  final TrialResult? openFromLibrary;
  final TrialResult? offline;
  final PrivacyResult? privacy;
  final List<String> notes;
  final int requiredTrials;

  int get forceQuitPasses => forceQuits.where((t) => t.pass).length;

  bool get forceQuitPass =>
      forceQuits.isNotEmpty && forceQuitPasses == forceQuits.length;

  /// A run with fewer trials than the spec asks for proves less than the spec.
  bool get forceQuitComplete => forceQuits.length >= requiredTrials;

  bool get pass =>
      forceQuitPass &&
      (openFromLibrary?.pass ?? true) &&
      (offline?.pass ?? true) &&
      (privacy?.pass ?? true);

  Map<String, dynamic> toJson() => {
    'startedAt': startedAt.toUtc().toIso8601String(),
    'device': device,
    'seed': seed,
    'pass': pass,
    'forceQuit': {
      'required': requiredTrials,
      'trials': forceQuits.length,
      'passed': forceQuitPasses,
      'complete': forceQuitComplete,
      'pass': forceQuitPass,
      'results': [for (final t in forceQuits) t.toJson()],
    },
    'openFromLibrary': openFromLibrary?.toJson(),
    'offline': offline?.toJson(),
    'privacy': privacy?.toJson(),
    'notes': notes,
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  String toMarkdown() {
    final out = StringBuffer()
      ..writeln('# Loremark acceptance checks')
      ..writeln()
      ..writeln(
        '**${!pass
            ? 'FAIL'
            : forceQuitComplete
            ? 'PASS'
            : 'INCOMPLETE'}** · ${startedAt.toUtc().toIso8601String()} '
        '· seed $seed',
      )
      ..writeln();
    if (device.isNotEmpty) {
      out
        ..writeln(device.entries.map((e) => '${e.key}: ${e.value}').join(' · '))
        ..writeln();
    }

    out
      ..writeln('## Summary')
      ..writeln()
      ..writeln('| Check | Result | Detail |')
      ..writeln('|---|---|---|')
      ..writeln(
        '| Force-quit, back within one page | ${_mark(forceQuitPass && forceQuitComplete, partial: forceQuitPass)} '
        '| $forceQuitPasses of ${forceQuits.length} within one page '
        '(spec: $requiredTrials of $requiredTrials)'
        '${forceQuitComplete ? '' : ', **fewer trials than the spec**'} |',
      );
    final open = openFromLibrary;
    if (open != null) {
      out.writeln(
        '| Open the book from the library | ${_mark(open.pass)} | ${open.note ?? ''} |',
      );
    }
    final off = offline;
    if (off != null) {
      out.writeln(
        '| Offline reading (airplane mode) | ${_mark(off.pass)} '
        '| ${off.pageTurns} page turns, ${off.note ?? ''} |',
      );
    }
    final p = privacy;
    if (p != null) {
      final d = p.delta;
      out.writeln(
        '| App network traffic (UID ${p.uid}) | ${_mark(p.netstatsPass)} '
        '| ${d == null ? 'not measured' : '${d.txBytes} B sent, ${d.rxBytes} B received'} |',
      );
      final audit = p.audit;
      out.writeln(
        '| Capture policy (HTTPS, hosts, markers) | '
        '${audit == null ? (p.captureInconclusive ? 'INCONCLUSIVE' : 'n/a') : _mark(audit.pass)} '
        '| ${audit == null ? p.pcapNote ?? 'no capture given' : _auditDetail(audit)} |',
      );
    }

    out
      ..writeln()
      ..writeln('## Force-quit trials')
      ..writeln()
      ..writeln(
        '| # | Kill | Turns | Last shown | Saved | Restored | Off by (restored / saved) | Result | ms |',
      )
      ..writeln('|--:|---|--:|---|---|---|---|---|--:|');
    for (final t in forceQuits) {
      out.writeln(_row(t));
    }
    if (open != null || off != null) {
      out
        ..writeln()
        ..writeln('## Other trials')
        ..writeln()
        ..writeln(
          '| # | Kind | Turns | Last shown | Saved | Restored | Off by | Result | ms |',
        )
        ..writeln('|--:|---|--:|---|---|---|---|---|--:|');
      if (open != null) out.writeln(_row(open));
      if (off != null) out.writeln(_row(off));
    }
    if (p != null) {
      out
        ..writeln()
        ..writeln('## Privacy detail')
        ..writeln()
        ..writeln(
          '- App UID: ${p.uid}; ${p.uidsSeen} UIDs in the counter table.',
        )
        ..writeln('- Before: ${_traffic(p.before)}')
        ..writeln('- After: ${_traffic(p.after)}');
      final audit = p.audit;
      if (audit == null) {
        out.writeln('- Capture: ${p.pcapNote ?? 'none'}');
      } else {
        out
          ..writeln(
            '- Capture: ${audit.totalPackets} packets, ${audit.sessionPackets} in the session window.',
          )
          ..writeln(
            '- Names in the session: ${_list(audit.sessionNames.toList()..sort())}',
          )
          ..writeln('- Unexpected names: ${_list(audit.unexpectedNames)}')
          ..writeln('- Plaintext HTTP: ${_list(audit.plaintextHttp)}')
          ..writeln(
            '- Unnamed destinations: ${_list(audit.opaqueDestinations)}',
          )
          ..writeln('- Marker phrases found: ${_list(audit.markerHits)}')
          ..writeln(
            '- Routable packets while offline: ${_list(audit.offlineLeaks)}',
          );
      }
    }
    if (notes.isNotEmpty) {
      out
        ..writeln()
        ..writeln('## Notes')
        ..writeln();
      for (final note in notes) {
        out.writeln('- $note');
      }
    }
    return out.toString();
  }
}

String _mark(bool pass, {bool partial = false}) =>
    pass ? 'PASS' : (partial ? 'INCOMPLETE' : 'FAIL');

String _auditDetail(PcapAudit a) =>
    '${a.sessionPackets} packets in the session; '
    '${a.unexpectedNames.length} unexpected names, '
    '${a.plaintextHttp.length} plaintext HTTP, '
    '${a.markerHits.length} marker hits';

String _list(List<String> items) => items.isEmpty ? 'none' : items.join(', ');

String _traffic(UidTraffic? t) => t == null
    ? 'not measured'
    : 'tx ${t.txBytes} B / ${t.txPackets} pkts, rx ${t.rxBytes} B / ${t.rxPackets} pkts';

String _position(PagePosition? p) => p == null ? '-' : p.toString();

String _row(TrialResult t) {
  final off = t.restored == null
      ? '-'
      : '${t.restoredDistance ?? '?'} / ${t.savedDistance ?? '-'}';
  final note = t.note == null ? '' : ' ${t.note!.replaceAll('|', '/')}';
  return '| ${t.index} | ${t.kind} | ${t.pageTurns} | ${_position(t.last)} '
      '| ${_position(t.saved)} | ${_position(t.restored)} | $off '
      '| ${t.pass ? 'pass' : '**FAIL**'}$note | ${t.durationMs} |';
}
