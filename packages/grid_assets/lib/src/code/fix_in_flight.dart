/// The FIX-IN-FLIGHT carry (bead `pow-bhm`; policy Nico-ratified 2026-07-18,
/// interactive session) — the ONE actionable finding a committee round
/// ADVANCED with.
///
/// The ratified clause: "A SINGLE D advances, with that lane's finding attached
/// VERBATIM to the build brief as a binding fix-in-flight item; the code
/// committee re-checks it at review. Every catch keeps its value; single-finding
/// rounds stop burning a full respec cycle."
///
/// The channel is a WORKTREE FILE for the same reason the respec ledger is
/// (A14(5)): the build agent runs in a LATER step of the same session
/// (`kCodeCircuit` orders `spec_review` before `agent` before `review`), and the
/// `SiblingView` the route graded through is not addressable from a spawn edge.
/// It is a SIBLING of (never inside) `.grid/critique/`, which
/// `ClearCritiqueCapability` wipes every round, and `IntakeCapability` clears it
/// at the head of every session — so a reused worktree never inherits a prior
/// session's carry. (A34(2) is the placement precedent: a marker inside the
/// swept dir is deleted by a mid-wave sweep and the fix degrades silently.)
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'respec_ledger.dart';

/// The absolute path of the carry under [workspaceDir].
String fixInFlightPath(String workspaceDir) =>
    p.join(workspaceDir, kRespecSpecDir, 'fix-in-flight.json');

/// ONE committee finding the round advanced WITH — BINDING on the build.
class FixInFlight {
  /// Creates the carry over [lane], stamped with its [sessionRoot] + [round].
  const FixInFlight({
    required this.sessionRoot,
    required this.round,
    required this.lane,
  });

  /// The round-zero work-bead root that owns this session (provenance only —
  /// [readFixInFlight] does not fence on it, because `IntakeCapability` clears
  /// the carry at the head of every session).
  final String sessionRoot;

  /// The circuit round the finding was graded in (provenance).
  final int round;

  /// The failing lane, its grade, and its rationale VERBATIM. Reuses
  /// [RespecLane] rather than minting a second lane record — the respec ledger
  /// already owns that concept, and this pack grades conceptual duplication.
  final RespecLane lane;

  /// The wire shape (hand-rolled — this pack carries no `json_serializable`).
  Map<String, Object?> toJson() => {
    'version': 1,
    'sessionRoot': sessionRoot,
    'round': round,
    'lane': lane.toJson(),
  };

  /// Decodes a carry; null for anything unreadable (the [readRespecLedger]
  /// posture — a corrupt carry degrades to "no carry", never a throw).
  static FixInFlight? fromJson(Object? json) {
    if (json is! Map) return null;
    final sessionRoot = (json['sessionRoot'] as String?)?.trim() ?? '';
    final round = json['round'];
    final lane = RespecLane.fromJson(json['lane']);
    if (sessionRoot.isEmpty || round is! int || round < 0 || lane == null) {
      return null;
    }
    return FixInFlight(sessionRoot: sessionRoot, round: round, lane: lane);
  }
}

/// The carry at [workspaceDir], or null when there is none / it is unreadable.
FixInFlight? readFixInFlight(String workspaceDir) {
  final file = File(fixInFlightPath(workspaceDir));
  if (!file.existsSync()) return null;
  try {
    return FixInFlight.fromJson(jsonDecode(file.readAsStringSync()));
  } catch (_) {
    return null;
  }
}

/// Writes [carry] into [workspaceDir]. THROWS on a write that cannot land — the
/// caller turns that into a LOUD `RouteFailure`. The guard protects a NAMED
/// invariant (guards LOUD or GONE): the build brief reads the FILE, so an
/// advance whose carry never landed would build a spec with its one known
/// defect silently dropped — exactly the "every catch keeps its value" clause
/// the ratified policy turns on.
void writeFixInFlight(String workspaceDir, FixInFlight carry) =>
    File(fixInFlightPath(workspaceDir))
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(carry.toJson()));

/// Deletes the carry at [workspaceDir] — every exit that does NOT advance with
/// a finding, plus `IntakeCapability`'s session-head hygiene. Best-effort: a
/// delete that fails never gates an otherwise-passing spec.
void clearFixInFlight(String workspaceDir) {
  try {
    final file = File(fixInFlightPath(workspaceDir));
    if (file.existsSync()) file.deleteSync();
  } catch (_) {
    // Hygiene only — the next advance overwrites it anyway.
  }
}

/// The BINDING block the BUILD agent's brief embeds: the finding verbatim, and
/// what the builder owes it.
String renderFixInFlightGuidance(FixInFlight carry) =>
    (StringBuffer()
          ..writeln('## Fix in flight — BINDING (READ THIS FIRST)')
          ..writeln()
          ..writeln(
            'The spec-readiness committee ADVANCED this spec carrying ONE open '
            'finding rather than burning a respec round on it. The finding is '
            'BINDING on your build: close it IN FLIGHT, in the same change. The '
            'code committee RE-CHECKS it at review — a commit that leaves it '
            'open is graded against it.',
          )
          ..writeln()
          ..writeln('### `${carry.lane.rubric}` — grade ${carry.lane.grade}')
          ..writeln(carry.lane.rationale))
        .toString();

/// The RE-CHECK block every CODE-critic prompt embeds while a carry is live —
/// the same finding, addressed to the reviewer.
String renderFixInFlightRecheck(FixInFlight carry) =>
    (StringBuffer()
          ..writeln('## Fix in flight — the spec committee\'s carried finding')
          ..writeln(
            'The spec-readiness committee advanced this bead\'s spec carrying '
            'ONE open finding, BINDING on the build you are reviewing. If it '
            'falls inside YOUR rubric, grade whether the diff actually closed '
            'it; if it does not, ignore it — you are blind to the other lanes\' '
            'concerns.',
          )
          ..writeln()
          ..writeln('### `${carry.lane.rubric}` — grade ${carry.lane.grade}')
          ..writeln(carry.lane.rationale))
        .toString();
