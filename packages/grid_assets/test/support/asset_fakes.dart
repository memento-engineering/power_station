// Code-asset test support — the helpers that reference the moved `code`
// opinions (`kCodeCircuit`/`buildCodeRegistry`), which do NOT belong in the
// engine's testing lib. Re-exports `package:grid_engine/testing.dart` so a
// moved test gets the SAME shared engine fakes (a drop-in for the old
// `support/engine_fakes.dart`), plus the `code` resolver below. Pure-Dart: no
// live tg/gc/claude/git/network.
export 'package:grid_engine/testing.dart';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
// Imported (not just re-exported) so this library can USE the shared fakes
// (`stateSubstation`, etc.) in its own committee helpers.
import 'package:grid_engine/testing.dart';
import 'package:grid_assets/grid_assets.dart';

/// The live `code` resolver for the integrated acceptance tests — the SAME
/// migration-aware resolver the production composition mounts (bead `pow-3p4`):
/// fresh work and any session carrying a FOLDED cursor root the current
/// [kCodeCircuit]; an adopted OLD-shape in-flight session (a pre-fold cursor)
/// roots the frozen shape it was minted under, so a bounce never re-enters
/// `specify`. Pair it with [buildCodeRegistry] as the ambient
/// `CapabilityRegistry`.
const SessionResolver kCodeResolver = CodeCircuitResolver(kCodeCircuit);

/// The committee-wired `code` circuit's node paths (relative to the work bead),
/// in declaration order — the `spec_review/<lane>` spec committee, `specify`
/// INCLUDED (beads `pow-6ao` + `pow-ui8`) → `agent` → `review/clear-critique`
/// (gate-integrity #3) → `review/pin-diff` (scope-pinning, bead `pow-6wo`) → the
/// four `review/<critic>` lanes → `review/route` → `land`. The drive helpers +
/// acceptance tests key the cursor off these.
///
/// The specify stage's node path is INSIDE the spec circuit as of bead `pow-ui8`
/// (folded in so the spec route's `Rewind` can name it as a sibling), and the
/// spec circuit's HEAD is the readiness ladder as of bead `pow-q7n`.
const String kSpecifyNode = 'spec_review/specify';

/// The spec-readiness INTAKE ladder's node paths (bead `pow-q7n`) — the CHEAP
/// head of the spec circuit, UPSTREAM of `specify` (so NOT in the auto-respec
/// rewind set). `intake` is the spec circuit's only dep-free step.
const String kIntakeNode = 'spec_review/intake';
const String kReadinessNode = 'spec_review/readiness';
const String kReadinessRouteNode = 'spec_review/readiness-route';

/// The ladder's three node paths. Splat into a `completed` set (with
/// [kReadinessGradeA]) to FAST-FORWARD a suite past the ladder by cursor
/// adoption — an already-complete step never mounts.
const Set<String> kReadinessLadderNodes = {
  kIntakeNode,
  kReadinessNode,
  kReadinessRouteNode,
};

/// The readiness lane's PASS grade — pair with [kReadinessLadderNodes].
final Map<String, String> kReadinessGradeA = {kReadinessNode: 'A'};

/// A ready WORK bead that PASSES the INTAKE CONTRACT (bead `pow-q7n`): a
/// driveable type AND a non-empty description — the two things
/// [IntakeCapability] requires before ANY agent may run.
///
/// The engine's shared [bead] fake predates the intake contract and carries an
/// EMPTY description, which `intakeFindings` correctly HOLDS (a bead with no
/// brief cannot be specified by anyone). So a suite that drives a bead through
/// the LIVE circuit head — i.e. one that MINTS its session, leaving `intake` to
/// actually mount and run — must push THIS, not the bare fake. A suite that
/// instead ADOPTS a ladder-complete session ([ladderDoneSession]) never mounts
/// `intake` at all, and may keep using [bead].
Bead workBead(String id) => bead(id).copyWith(
  description:
      'A real brief: drive this bead through the `code` circuit. Non-empty on '
      'purpose — the intake contract (bead `pow-q7n`) HOLDS a bead that carries '
      'no brief for an architect to plan against.',
);

/// A [SessionProjection] whose READINESS LADDER is already COMPLETE (grade A) —
/// the cold-start fast-forward for a suite that projects sessions DIRECTLY onto
/// the joined snapshot (rather than adopting a session BEAD, for which
/// [ladderDoneSession] is the equivalent).
///
/// An already-complete step never mounts, so `intake`/`readiness` never run and
/// `specify` is again the first AGENT to spawn — leaving such a suite's focus
/// (which is DOWNSTREAM of the ladder) exactly where it was.
SessionProjection ladderDoneProjection({
  required String workBeadId,
  required String sessionId,
}) => SessionProjection(
  workBeadId: workBeadId,
  sessionId: sessionId,
  cursor: {
    for (final step in kReadinessLadderNodes)
      '$workBeadId/$step': const NodeCursor(state: StepState.complete),
  },
  results: {
    for (final entry in kReadinessGradeA.entries)
      '$workBeadId/${entry.key}': {'grade': entry.value},
  },
);

/// A session whose READINESS LADDER is already COMPLETE (grade A) and NOTHING
/// else — the cold-start fast-forward a suite whose focus is DOWNSTREAM of the
/// ladder pushes right after its first `work.push`, so `specify` is again the
/// first agent to spawn.
///
/// It ALSO keeps the session on the CURRENT (laddered) circuit shape: a cursor
/// carrying `spec_review/specify` but NO `spec_review/intake` key is a
/// PRE-LADDER survivor, which `CodeCircuitResolver` correctly roots on the
/// FROZEN pre-ladder circuit (`circuit_migration.dart`) — so a suite that
/// fast-forwards `specify` WITHOUT the ladder keys would silently drive the
/// frozen shape instead of the live one.
Bead ladderDoneSession({
  String id = 'tgdog-sess1',
  String workBeadId = 'tg-1',
}) => committeeSession(
  id: id,
  workBeadId: workBeadId,
  completed: kReadinessLadderNodes,
  grades: kReadinessGradeA,
);
const String kSpecClearCritiqueNode = 'spec_review/clear-critique';
const String kSpecGateNode = 'spec_review/spec-validation';
const List<String> kSpecCriticNodes = [
  'spec_review/coherence',
  'spec_review/adr-alignment',
  'spec_review/acceptance-testability',
  'spec_review/plan-completeness',
];
const String kSpecRouteNode = 'spec_review/route';
const String kAgentNode = 'agent';
const String kClearCritiqueNode = 'review/clear-critique';
const String kPinDiffNode = 'review/pin-diff';
const List<String> kCriticNodes = [
  'review/code-validation',
  'review/spec-adherence',
  'review/regression-risk',
  'review/test-coverage',
];
const String kRouteNode = 'review/route';

/// EVERY spec-phase node complete — the READINESS LADDER (bead `pow-q7n`)
/// INCLUDED, so a fast-forwarded session also stays on the CURRENT circuit shape
/// (a cursor without the ladder keys is a PRE-LADDER survivor, which the
/// migration guard roots on the FROZEN circuit). Prepend this to a `completed`
/// set (with [kSpecGradesAllA] as grades) to FAST-FORWARD a test past the spec
/// phase via cursor adoption (the cursor is data; already-complete steps never
/// mount), so the code-committee choreography stays the test's focus. The spec
/// phase's own fan-out/gate proofs live in `spec_stage_acceptance_test.dart`;
/// the ladder's own live in `acceptance/readiness_acceptance_test.dart`.
const Set<String> kSpecPhaseNodes = {
  ...kReadinessLadderNodes,
  kSpecifyNode,
  kSpecClearCritiqueNode,
  kSpecGateNode,
  'spec_review/coherence',
  'spec_review/adr-alignment',
  'spec_review/acceptance-testability',
  'spec_review/plan-completeness',
  kSpecRouteNode,
};

/// All-pass spec grades (the happy spec committee) — pair with
/// [kSpecPhaseNodes]. Carries the readiness lane's own `A` (bead `pow-q7n`), so
/// a suite that fast-forwards the spec phase also fast-forwards the ladder.
final Map<String, String> kSpecGradesAllA = {
  ...kReadinessGradeA,
  kSpecGateNode: 'A',
  for (final n in kSpecCriticNodes) n: 'A',
};

/// The landing circuit's own node paths (`tg-rm5`), relative to the work bead
/// — `land/rebase` → `land/revalidate` → `land/land` (the innermost
/// `LandCapability`, since `land` at the `code` circuit level is itself a
/// [SubCircuitStep] over `landing`, not a leaf).
const String kRebaseNode = 'land/rebase';
const String kRevalidateNode = 'land/revalidate';
const String kLandNode = 'land/land';

/// A recording [ShellRunner] (the `revalidate` seam, `tg-rm5`): records every
/// (workingDirectory, command) call and returns a configurable [exitCode] (0
/// ⇒ ok) — mirrors [RecordingGitRunner]'s shape/posture (Fakes, not mocks).
class RecordingShellRunner implements ShellRunner {
  /// Every (workingDirectory, command) call, in call order.
  final List<({String workingDirectory, String command})> calls = [];

  /// The exit code the next runs return (0 ⇒ `ok`). Settable so a test can
  /// make revalidate fail (Gate).
  int exitCode = 0;

  @override
  Future<ShellRunResult> run({
    required String workingDirectory,
    required String command,
  }) async {
    calls.add((workingDirectory: workingDirectory, command: command));
    return ShellRunResult(exitCode: exitCode, output: '');
  }
}

/// A STATE session bead for the COMMITTEE-wired `code` circuit (M5 Track E):
/// marks each relative path in [completed] `complete` in the per-node cursor AND
/// attaches each grade in [grades] (relative nodePath → letter) under
/// `grid.result.*` — so a mounted `route` reads its siblings' grades through the
/// threaded `SiblingView` (D-5). [closed] marks the session terminal.
///
/// Paths are RELATIVE to [workBeadId] (e.g. `'review/route'`); the helper prefixes
/// the bead id, matching the engine's `<beadId>/<...>` cursor keying.
Bead committeeSession({
  String id = 'tgdog-sess1',
  String workBeadId = 'tg-1',
  Set<String> completed = const {},
  Set<String> gated = const {},
  Map<String, String> grades = const {},
  // FULL result payloads (relative nodePath → payload), for a lane that must
  // carry more than a bare grade (bead `pow-7nm`: the spec route reads each
  // critic's `rationale` to build the respec guidance). Merged AFTER [grades],
  // so a path in both wins here.
  Map<String, Map<String, String>> results = const {},
  bool closed = false,
}) => Bead(
  id: id,
  issueType: IssueType.session,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    SessionBeadKeys.workBead: workBeadId,
    for (final step in completed)
      ...nodeStateMetadata('$workBeadId/$step', StepState.complete),
    for (final step in gated)
      ...nodeStateMetadata('$workBeadId/$step', StepState.gated),
    for (final entry in grades.entries)
      ...nodeResultMetadata('$workBeadId/${entry.key}', {'grade': entry.value}),
    for (final entry in results.entries)
      ...nodeResultMetadata('$workBeadId/${entry.key}', entry.value),
  },
);
