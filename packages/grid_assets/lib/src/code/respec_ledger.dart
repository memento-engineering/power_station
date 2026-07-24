/// The auto-respec ROUND LEDGER — the shared read/write seam for the durable
/// guidance file the spec route leaves in the bead's worktree (bead `pow-7nm`;
/// extracted from `respec.dart` by bead `pow-96s`).
///
/// **Why a separate library.** ADR-0000 A27(7)(a)'s follow-up made the ledger's
/// `round` field the verdict-round source for EVERY critic family: the round a
/// critic stamps into its verdict JSON (`committee.dart`'s `roundOf` /
/// `verdictJsonTemplate`) and the round `_verdictFromFile` verifies are now the
/// SAME counter the spec route bounds its auto-respec loop with. That makes the
/// ledger a dependency of BOTH `committee.dart` (the reader side) and
/// `respec.dart` (the writer side) — and `respec.dart` already imports
/// `committee.dart`, so homing the ledger here is what lets `committee.dart`
/// read it without an import cycle and without a second JSON parser.
///
/// The ledger lives at [respecLedgerPath] — a sibling of (never inside)
/// `.grid/critique/`, which `ClearCritiqueCapability` wipes at the start of
/// every committee round; the ledger must outlive that wipe. It does NOT
/// outlive the SESSION: `IntakeCapability` (the spec circuit's once-per-session
/// head, upstream of the auto-respec closure) clears it, so a fresh session
/// over a reused worktree starts the round counter at zero — a prior session's
/// rounds are never counted (bead `pow-96s`).
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
/// (`SpecifyCapability`'s guidance, `committee.dart`'s `roundOf`).
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

/// The auto-respec ROUND LEDGER — the round number plus every failing lane,
/// written into the bead's worktree by `SpecRouteCapability` and read back by
/// `SpecifyCapability` on the NEXT round. It is BOTH channels: the correction
/// GUIDANCE the next brief embeds, and the round COUNTER `SpecRouteCapability`
/// reads back to apply its cap. The `round` it carries is what the next brief
/// renders ("RESPEC round N of 2") — and, per ADR-0000 A27(7)(a)'s follow-up
/// (bead `pow-96s`), the round every critic family stamps into its verdict
/// (`committee.dart`'s `roundOf`), so the writer and the freshness fence can
/// never drift apart.
class RespecLedger {
  /// Creates a ledger for [round] over the failing [lanes].
  const RespecLedger({required this.round, required this.lanes});

  /// The auto-respec round this ledger opens (1-based; capped at
  /// `kMaxRespecRounds`).
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
    if (round is! int || round < 1) return null;
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
/// Best-effort by design: a corrupt ledger degrades to "no prior round" (the
/// next specify ride simply gets no correction guidance and the round counter
/// restarts) — it can never throw into a spawn or a route.
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
