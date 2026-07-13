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
import 'package:grid_runtime/grid_runtime.dart';

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

/// The DISCOVERY circuit's node paths (`discovery.dart`) — nested one level under
/// `spec_review`, BETWEEN the readiness ladder and `specify`. `anchors` is the
/// circuit's only dep-free step, and the cursor key the migration guard
/// classifies the CURRENT (shape-5) circuit on.
const String kAnchorsNode = 'spec_review/discovery/anchors';
const String kDiscoveryRouteNode = 'spec_review/discovery/discovery-route';

/// The three READ-ONLY explorer lenses — the only agents this circuit spawns.
const List<String> kDiscoveryLensNodes = [
  'spec_review/discovery/explore-code',
  'spec_review/discovery/explore-decision',
  'spec_review/discovery/explore-prior-art',
];

/// The discovery circuit's five nodes.
const Set<String> kDiscoveryNodes = {
  kAnchorsNode,
  ...kDiscoveryLensNodes,
  kDiscoveryRouteNode,
};

/// The spec circuit's whole CHEAP HEAD — the readiness ladder + the discovery
/// circuit — everything UPSTREAM of `specify`. Splat into a `completed` set to
/// fast-forward a suite to the point where `specify` is again the first agent to
/// spawn.
///
/// Carrying the DISCOVERY keys is what also keeps such a session on the CURRENT
/// circuit shape: a cursor holding `spec_review/specify` with NO
/// `spec_review/discovery/anchors` is a PRE-DISCOVERY survivor, which
/// `CodeCircuitResolver` correctly roots on the FROZEN pre-discovery circuit
/// (`circuit_migration.dart`) — so a suite that fast-forwards `specify` WITHOUT
/// them would silently drive the frozen shape instead of the live one.
const Set<String> kSpecHeadNodes = {
  ...kReadinessLadderNodes,
  ...kDiscoveryNodes,
};

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

/// A [SessionProjection] whose whole CHEAP SPEC HEAD is already COMPLETE — the
/// readiness ladder (grade A) AND the discovery circuit — the cold-start
/// fast-forward for a suite that projects sessions DIRECTLY onto the joined
/// snapshot (rather than adopting a session BEAD, for which [ladderDoneSession]
/// is the equivalent).
///
/// An already-complete step never mounts, so neither the ladder nor the three
/// discovery explorers ever run and `specify` is again the first AGENT to spawn —
/// leaving such a suite's focus (which is DOWNSTREAM of the head) exactly where
/// it was.
SessionProjection ladderDoneProjection({
  required String workBeadId,
  required String sessionId,
}) => SessionProjection(
  workBeadId: workBeadId,
  sessionId: sessionId,
  cursor: {
    for (final step in kSpecHeadNodes)
      '$workBeadId/$step': const NodeCursor(state: StepState.complete),
  },
  results: {
    for (final entry in kReadinessGradeA.entries)
      '$workBeadId/${entry.key}': {'grade': entry.value},
  },
);

/// A session whose whole CHEAP SPEC HEAD is already COMPLETE — the readiness
/// ladder (grade A) AND the discovery circuit — and NOTHING else: the cold-start
/// fast-forward a suite whose focus is DOWNSTREAM of the head pushes right after
/// its first `work.push`, so `specify` is again the first agent to spawn.
///
/// It ALSO keeps the session on the CURRENT circuit shape — see [kSpecHeadNodes]
/// for why dropping the discovery keys would silently drive the FROZEN
/// pre-discovery circuit instead.
Bead ladderDoneSession({
  String id = 'tgdog-sess1',
  String workBeadId = 'tg-1',
}) => committeeSession(
  id: id,
  workBeadId: workBeadId,
  completed: kSpecHeadNodes,
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

/// EVERY spec-phase node complete — the whole CHEAP HEAD ([kSpecHeadNodes]: the
/// readiness ladder + the discovery circuit) INCLUDED, so a fast-forwarded
/// session also stays on the CURRENT circuit shape (a cursor without the
/// discovery keys is a PRE-DISCOVERY survivor, which the migration guard roots on
/// the FROZEN circuit). Prepend this to a `completed` set (with [kSpecGradesAllA]
/// as grades) to FAST-FORWARD a test past the spec phase via cursor adoption (the
/// cursor is data; already-complete steps never mount), so the code-committee
/// choreography stays the test's focus. The spec phase's own fan-out/gate proofs
/// live in `spec_stage_acceptance_test.dart`; the ladder's own in
/// `acceptance/readiness_acceptance_test.dart`; the discovery circuit's own in
/// `acceptance/discovery_acceptance_test.dart`.
const Set<String> kSpecPhaseNodes = {
  ...kSpecHeadNodes,
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

/// The landing PREPARATION circuit's own node paths (`tg-rm5`), relative to the
/// work bead — `land/rebase` → `land/revalidate`. (`land` at the `code` circuit
/// level is a [SubCircuitStep] over `landing`, not a leaf.) The PR is no longer a
/// step here: `land/land` is GONE (M5 D-4a).
const String kRebaseNode = 'land/rebase';
const String kRevalidateNode = 'land/revalidate';

/// The ROOT circuit's TERMINAL node — the flat route whose advance ACTUATES the
/// substation's bound `DeliveryMethod`. It replaced `land/land`, and it is a
/// ROOT-level step (a sub-circuit tail could never deliver: `isDeliveryTerminal`
/// is false at a [SubCircuitStep]).
const String kDeliverNode = kDeliverStep;

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

/// A [GitRunner] with canned per-subcommand answers (Fakes, not mocks) — the
/// describe pass's branch-delta reads (bead `pow-8dx`): `git log` returns [log],
/// `git diff --stat` a fixed one-file stat, and `git diff` returns [diff] with
/// [diffOk] deciding whether the read succeeded at all.
///
/// EVERY OTHER call — `status`/`add`/`commit`/`push`/`fetch`, the source-control
/// half — succeeds with EMPTY output, i.e. a CLEAN tree and a clean push. That
/// matters when this same runner also backs a [GitSourceControl]: the land step's
/// residue gate probes `git status --porcelain`, and a fake that echoed the
/// canned diff there would read as uncommitted residue and Gate the land.
class CannedGitRunner implements GitRunner {
  /// Creates the runner over its canned log/diff answers.
  CannedGitRunner({this.log = '', this.diff = '', this.diffOk = true});

  /// The `git log --format=…%x00` body (NUL-separated commit records).
  final String log;

  /// The `git diff origin/<base>...HEAD` body.
  final String diff;

  /// Whether the `git diff` read succeeds (false ⇒ a non-zero git).
  final bool diffOk;

  /// Every argv, in call order.
  final List<List<String>> calls = [];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add(List.unmodifiable(args));
    if (args.first == 'log') return GitRunResult(exitCode: 0, output: log);
    if (args.first == 'diff') {
      if (args.contains('--stat')) {
        return const GitRunResult(exitCode: 0, output: ' lib/x.dart | 2 +-');
      }
      return GitRunResult(exitCode: diffOk ? 0 : 128, output: diff);
    }
    return const GitRunResult(exitCode: 0, output: '');
  }
}

/// An [InferenceRunner] recording its invocation and returning [output] (Fakes,
/// not mocks) — the describe pass's one-shot inference seam (bead `pow-8dx`).
/// The offline suite ALWAYS injects one of these; a real `claude` is never
/// reached.
class FakeInferenceRunner implements InferenceRunner {
  /// Creates the runner over the canned model [output] and run outcome [ok].
  FakeInferenceRunner({this.output = '', this.ok = true});

  /// The stdout the fake `claude` returns (the model's answer).
  final String output;

  /// Whether the run exited clean.
  final bool ok;

  /// Every rendered invocation, in call order.
  final List<RuntimeConfig> calls = [];

  @override
  Future<InferenceResult> run(RuntimeConfig config) async {
    calls.add(config);
    return InferenceResult(ok: ok, output: output);
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
