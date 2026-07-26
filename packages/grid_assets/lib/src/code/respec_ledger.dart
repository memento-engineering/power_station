/// The auto-respec ROUND LEDGER — the shared read/write seam for the durable
/// guidance file the spec route leaves in the bead's worktree (bead `pow-7nm`;
/// extracted from `respec.dart` by bead `pow-96s`).
///
/// The ledger remains separate from verdict transport because it is correction
/// guidance and provenance, not a freshness-round authority.
///
/// The ledger lives at [respecLedgerPath] — a sibling of (never inside)
/// `.grid/critique/`, which `ClearCritiqueCapability` wipes at the start of
/// every committee round; the ledger must outlive that wipe. It does NOT
/// outlive the SESSION: `IntakeCapability` (the spec circuit's once-per-session
/// head, upstream of the auto-respec closure) clears it, so a fresh session
/// over a reused worktree never inherits prior correction guidance.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The workspace-relative directory the respec guidance ledger lives in —
/// deliberately NOT under `.grid/critique/` (which `ClearCritiqueCapability`
/// wipes at the start of every committee round; the ledger must outlive that
/// wipe — though never the session: `IntakeCapability` resets it).
const String kRespecSpecDir = '.grid/spec';

/// The absolute path of the respec guidance ledger under [workspaceDir] —
/// derived identically by `SpecRouteCapability` (the writer) and its readers
/// (`SpecifyCapability`'s guidance).
String respecLedgerPath(String workspaceDir) =>
    p.join(workspaceDir, kRespecSpecDir, 'respec.json');

/// One FAILING committee lane, as the re-specify agent must see it: the rubric
/// that rejected the spec, the grade it gave, and its RATIONALE verbatim (the
/// "recommendation" the bead requires reach the next brief).
class RespecLane {
  /// Creates a failing lane record.
  const RespecLane({
    required this.rubric,
    required this.grade,
    required this.rationale,
  });

  /// The rubric id that failed (`coherence`, `plan-completeness`, …).
  final String rubric;

  /// The letter grade it returned (`D`/`E` — an `F` is never respec-fixable).
  final String grade;

  /// The critic's own rationale — the correction guidance, verbatim.
  final String rationale;

  /// The wire shape (hand-rolled — this pack carries no `json_serializable`).
  Map<String, Object?> toJson() => {
    'rubric': rubric,
    'grade': grade,
    'rationale': rationale,
  };

  /// Decodes one lane; a non-map / field-less entry yields null (best-effort — a
  /// corrupt ledger degrades to "no guidance", never a throw).
  static RespecLane? fromJson(Object? json) {
    if (json is! Map) return null;
    final rubric = (json['rubric'] as String?)?.trim() ?? '';
    final grade = (json['grade'] as String?)?.trim().toUpperCase() ?? '';
    final rationale = (json['rationale'] as String?)?.trim() ?? '';
    if (rubric.isEmpty || grade.isEmpty || rationale.isEmpty) return null;
    return RespecLane(rubric: rubric, grade: grade, rationale: rationale);
  }
}

/// The auto-respec guidance ledger — the circuit round plus every failing lane,
/// written into the bead's worktree by `SpecRouteCapability` and read back by
/// `SpecifyCapability` on the next round. The `round` field mirrors the circuit
/// round for the guidance brief; `grid.round` remains the sole authority.
class RespecLedger {
  /// Creates a ledger for [round] over the failing [lanes].
  const RespecLedger({required this.round, required this.lanes});

  /// The session circuit round mirrored for guidance and provenance.
  ///
  /// This field is never a round authority; verdict writers and joins consume
  /// the engine-injected `grid.round` parameter.
  final int round;

  /// Every FIXABLE failing lane, in committee (`critics` param) order.
  final List<RespecLane> lanes;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'version': 1,
    'round': round,
    'lanes': [for (final lane in lanes) lane.toJson()],
  };

  /// Decodes a ledger; null for anything unreadable (no round, no lanes, bad
  /// JSON) — the caller then treats it as "no prior round".
  static RespecLedger? fromJson(Object? json) {
    if (json is! Map) return null;
    final round = json['round'];
    if (round is! int || round < 0) return null;
    final raw = json['lanes'];
    if (raw is! List) return null;
    final lanes = [
      for (final entry in raw)
        if (RespecLane.fromJson(entry) case final lane?) lane,
    ];
    if (lanes.isEmpty) return null;
    return RespecLedger(round: round, lanes: lanes);
  }
}

/// The ledger at [workspaceDir], or null when there is none / it is unreadable.
/// Best-effort by design: a corrupt ledger degrades to no correction guidance;
/// it can never throw into a spawn or a route.
RespecLedger? readRespecLedger(String workspaceDir) {
  final file = File(respecLedgerPath(workspaceDir));
  if (!file.existsSync()) return null;
  try {
    return RespecLedger.fromJson(jsonDecode(file.readAsStringSync()));
  } catch (_) {
    return null;
  }
}

/// Writes [ledger] into [workspaceDir]. THROWS on a write that cannot land — the
/// caller (`SpecRouteCapability`) turns that into a LOUD `RouteFailure`: a
/// respec whose guidance never reaches the next brief would re-specify blind and
/// re-park, which is precisely the toil this bead removes (guards LOUD or GONE).
void writeRespecLedger(String workspaceDir, RespecLedger ledger) =>
    File(respecLedgerPath(workspaceDir))
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(ledger.toJson()));

/// Deletes the ledger at [workspaceDir] — called on EVERY terminal verdict that
/// hands the bead on: an ADVANCE (the spec is ready) and an ESCALATE (a human now
/// rules). Both exits SPEND the counter, so a LATER rework round can never
/// re-inject a stale spec correction into a fresh specify brief, and a re-armed
/// route after a gate resolve can never re-flare off a consumed round.
/// ALSO called by `IntakeCapability` at the head of every session (bead
/// `pow-96s`): the counter is SESSION-scoped — a fresh session over a reused
/// worktree starts at round zero rather than inheriting a prior session's
/// rounds. Best-effort: a delete that fails never gates an otherwise-passing
/// spec.
void clearRespecLedger(String workspaceDir) {
  try {
    final file = File(respecLedgerPath(workspaceDir));
    if (file.existsSync()) file.deleteSync();
  } catch (_) {
    // Hygiene only — a stale ledger is re-overwritten by the next respec anyway.
  }
}
