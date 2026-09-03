// Code-asset test support — the helpers that reference the moved `code`
// opinions (`kCodeCircuit`/`buildCodeRegistry`), which do NOT belong in the
// engine's testing lib. Re-exports `package:grid_engine/testing.dart` so a
// moved test gets the SAME shared engine fakes (a drop-in for the old
// `support/engine_fakes.dart`), plus the `code` resolver below. Pure-Dart: no
// live tg/gc/claude/git/network.
//
// **The molecule model (tg-eli phase 2).** Per-node circuit progress is no
// longer a flat cursor on the session bead — it lives on each node's OWN
// `type=step` bead ([MoleculeStepKeys], re-exported from
// `package:grid_engine/testing.dart`). [stepBead]/[stepBeads] mint that shape
// directly; [committeeSession] is the molecule-faithful session+steps
// fast-forward built on top of them ([kAllCodeCircuitNodes] is the `code`
// circuit's whole flat node universe, so a live mount always finds a staged
// step bead for whatever it is about to reach); [ladderDoneSession] is the
// cheap-head-complete convenience over it. [settle] is the shared bounded
// wait helper; it grants REAL wall clock per round because the molecule
// mint's pour crosses the filesystem below the fake runner seam.
export 'package:grid_engine/testing.dart';

import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
// Imported (not just re-exported) so this library can USE the shared fakes
// (`stateSubstation`, etc.) in its own committee helpers.
import 'package:grid_engine/testing.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart' show pumpEventQueue;

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

/// A fake bd query source for [SpecifyCapability]'s durable spec read-back.
final class SpecifyReadbackBdRunner implements BdRunner {
  SpecifyReadbackBdRunner({this.beads = const [], this.error, this.result});

  final List<Bead> beads;
  final Object? error;
  final BdResult? result;
  final List<List<String>> calls = <List<String>>[];
  final List<String?> stdins = <String?>[];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List<String>.unmodifiable(args));
    stdins.add(stdin);
    final forcedError = error;
    if (forcedError != null) throw forcedError;
    final forcedResult = result;
    if (forcedResult != null) return forcedResult;
    return BdResult(
      exitCode: 0,
      stdout: jsonEncode({
        'schema_version': 1,
        'data': [for (final bead in beads) bead.toJson()],
      }),
      stderr: '',
    );
  }
}

/// A work bead whose authored spec is durably non-empty.
Bead durableSpecifiedBead(String id) => workBead(id).copyWith(
  acceptanceCriteria: kSpecExemplarAcceptance,
  design: kSpecExemplarDesign,
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

/// A MOLECULE session bead + its `type=step` beads, whole CHEAP SPEC HEAD
/// already COMPLETE — the readiness ladder (grade A) AND the discovery circuit
/// — and every OTHER `code`-circuit node staged `pending`: the cold-start
/// fast-forward a suite whose focus is DOWNSTREAM of the head pushes right after
/// its first `work.push`, so `specify` is again the first agent to spawn.
///
/// It ALSO keeps the session on the CURRENT circuit shape — see [kSpecHeadNodes]
/// for why dropping the discovery keys would silently drive the FROZEN
/// pre-discovery circuit instead.
///
/// Same return shape as [committeeSession] (which this is built on): the
/// molecule-stamped session bead first, then one `type=step` bead per staged
/// node — splat the whole list into a pushed [GraphSnapshot]'s `beads`.
List<Bead> ladderDoneSession({
  String id = 'tgdog-sess1',
  String workBeadId = 'tg-1',
}) => committeeSession(
  id: id,
  workBeadId: workBeadId,
  completed: kSpecHeadNodes,
  grades: kReadinessGradeA,
);
/// The LOCAL-ONLY register tokens the spec path no longer renders — the shell
/// shape a `for register in docs/adr docs/decisions` grep is built from.
///
/// Shared by every suite that fences the roster-mode lookup: a revert to a
/// local register read reintroduces at least one of them.
const List<String> kLocalOnlyTokens = [
  'for register in docs/adr docs/decisions',
  r'[ ! -d "$register" ]',
  '-exec grep -li',
];

const String kSpecClearCritiqueNode = 'spec_review/clear-critique';
const String kSpecGateNode = 'spec_review/spec-validation';
const List<String> kSpecCriticNodes = [
  'spec_review/coherence',
  'spec_review/decision-alignment',
  'spec_review/acceptance-testability',
  'spec_review/plan-completeness',
];
const String kSpecRouteNode = 'spec_review/route';
const String kAgentNode = 'agent';
const String kClearCritiqueNode = 'review/clear-critique';
const String kPinDiffNode = 'review/pin-diff';
const List<String> kCriticNodes = [
  'review/code-validation',
  'review/declared-tests-present',
  'review/spec-adherence',
  'review/regression-risk',
  'review/test-coverage',
];
const List<String> kProcessCriticNodes = [
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
  'spec_review/decision-alignment',
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

/// The `code_review` sub-circuit's whole node set (`committee.dart`):
/// `clear-critique` (gate-integrity #3) → `pin-diff` → the four critics (in
/// parallel) → `route`. Pair with [kLandingNodes] + [kSpecPhaseNodes] to build
/// [kAllCodeCircuitNodes].
const Set<String> kCodeReviewNodes = {
  kClearCritiqueNode,
  kPinDiffNode,
  ...kCriticNodes,
  kRouteNode,
};

/// The `landing` sub-circuit's whole node set (`tg-rm5`, `landing.dart`):
/// `rebase` → `revalidate`.
const Set<String> kLandingNodes = {kRebaseNode, kRevalidateNode};

/// The `code` circuit's ENTIRE flat node-path universe, in circuit declaration
/// order: [kSpecPhaseNodes] (the whole `spec_review` sub-circuit, itself
/// [kSpecHeadNodes] + `specify` + the spec committee) → [kAgentNode] →
/// [kCodeReviewNodes] → [kLandingNodes] → [kDeliverNode].
///
/// A live molecule mount needs a `type=step` bead staged for EVERY node it
/// might ever reach — `CapabilityHost._stepBeadId` refuses LOUD when
/// `InheritedCircuit.beadIdByNodePath` lacks the node it is about to MOUNT —
/// so this is the default universe [committeeSession] pours one step bead per
/// (an `omit` argument narrows it for a suite staging a deliberately-partial,
/// frozen-shape survivor).
const Set<String> kAllCodeCircuitNodes = {
  ...kSpecPhaseNodes,
  kAgentNode,
  ...kCodeReviewNodes,
  ...kLandingNodes,
  kDeliverNode,
};

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

/// A `type=step` bead at [relativePath] (relative to [workBeadId]) for
/// [sessionId] — the molecule model's per-node durable state (tg-eli phase 2:
/// `grid.step.*` on the step's OWN bead; the retired flat `grid.cursor.*`
/// never projects again, `session_bead.dart`). The id shape
/// (`'{sessionId}-{path, dashes for slashes}'`) and metadata shape mirror
/// the_grid's own
/// `molecule/molecule_join_test.dart` `_stepBead` fixture, and are the SAME
/// shape `invariant_4_a37_pristine_source_test.dart`'s local `_stepBead`
/// builder used before this helper was promoted here.
///
/// `CapabilityHost._stepBeadId` refuses LOUD (a contained, per-work supervised
/// failure — never a crash) when `InheritedCircuit.beadIdByNodePath` has no
/// entry for the node it is about to mount, so EVERY node a live circuit will
/// ever spawn — not just the already-`complete` ones — needs its OWN step bead
/// staged in the state snapshot BEFORE that mount, hence [state] defaults to
/// [StepState.pending] rather than [StepState.complete].
///
/// [capability] is the `grid.step.capability` value recorded on the bead —
/// audit-only (the actual routing resolves the capability from the LIVE
/// `Circuit` definition, never from this metadata field), so the default
/// (`'agent'`) is fine for every node; override it only if a test asserts on
/// the recorded value itself.
Bead stepBead(
  String relativePath, {
  required String sessionId,
  required String workBeadId,
  StepState state = StepState.pending,
  String capability = 'agent',
}) => Bead(
  id: '$sessionId-${relativePath.replaceAll('/', '-')}',
  issueType: GridIssueTypes.step,
  status: BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    MoleculeStepKeys.stepId: relativePath.split('/').last,
    MoleculeStepKeys.capability: capability,
    MoleculeStepKeys.kind: StepKind.job.name,
    MoleculeStepKeys.path: '$workBeadId/$relativePath',
    MoleculeStepKeys.session: sessionId,
    MoleculeStepKeys.state: state.name,
  },
);

/// One [stepBead] per relative node path in [paths], all owned by
/// [sessionId] — the fast-forward fixture: an already-[StepState.complete]
/// step's OWN bead is what keeps `CapabilityHost` from ever re-mounting it
/// (`projectMoleculeCursor` reads `grid.step.state` per STEP bead now, never a
/// session-level cursor) — the molecule-model replacement for the retired flat
/// `completed:` cursor set this suite used to push directly on the session
/// bead.
Iterable<Bead> stepBeads(
  Set<String> paths, {
  required String sessionId,
  required String workBeadId,
  StepState state = StepState.complete,
  String capability = 'agent',
}) => paths.map(
  (path) => stepBead(
    path,
    sessionId: sessionId,
    workBeadId: workBeadId,
    state: state,
    capability: capability,
  ),
);

/// A MOLECULE-minted STATE session for the COMMITTEE-wired `code` circuit (M5
/// Track E / tg-eli phase 2) — the session bead ([sessionBead], stamped
/// `grid.session.model=molecule`) PLUS one `type=step` bead per node in
/// `code`'s whole flat universe ([kAllCodeCircuitNodes], narrowed by [omit]):
/// a node in [completed] stages [StepState.complete], a node in [gated] stages
/// [StepState.gated] (a molecule-faithful reading of "parked at a human
/// gate" — `StepState` already carries that value natively, D-7), and every
/// other staged node is [StepState.pending] (the honest "nothing has run yet"
/// default — never silently promoted to `complete`, or a live circuit's real
/// completions would be shadowed).
///
/// [grades]/[results] attach each entry (relative nodePath → letter / full
/// payload) under `grid.result.*` on the SESSION bead — unchanged from the
/// flat model (R1: `ResultKeys` reused verbatim, only its HOST bead moved for
/// results recorded live; a fast-forward that PRE-seeds a grade still stages it
/// here) — so a mounted `route` reads its siblings' grades through the
/// threaded `SiblingView` (D-5). [results] merges AFTER [grades], so a path in
/// both wins there. [closed] marks the session terminal.
///
/// **The omission escape hatch.** [omit] drops nodes out of the staged
/// universe ENTIRELY — no step bead at all, not even `pending` — for a suite
/// that fast-forwards onto a deliberately-partial, frozen circuit shape (e.g.
/// the migration guard's pre-fold survivor, which must present with NO
/// `spec_review/discovery/*` key so the resolver roots the FROZEN circuit
/// instead of silently driving the live one). [completed]/[gated] must name
/// only STAGED (non-omitted) nodes — asserted.
///
/// Returns the full staged set: the molecule-stamped session bead FIRST, then
/// one step bead per staged node — splat the whole list into a pushed
/// [GraphSnapshot]'s `beads`.
List<Bead> committeeSession({
  String id = 'tgdog-sess1',
  String workBeadId = 'tg-1',
  Set<String> completed = const {},
  Set<String> gated = const {},
  Map<String, String> grades = const {},
  Map<String, Map<String, String>> results = const {},
  bool closed = false,
  Set<String> omit = const {},
}) {
  final staged = kAllCodeCircuitNodes.difference(omit);
  assert(
    completed.every(staged.contains),
    'committeeSession: a completed node must be staged, not omitted: '
    '${completed.difference(staged)}',
  );
  assert(
    gated.every(staged.contains),
    'committeeSession: a gated node must be staged, not omitted: '
    '${gated.difference(staged)}',
  );
  return [
    sessionBead(
      id: id,
      workBeadId: workBeadId,
      closed: closed,
      metadata: {
        SessionBeadKeys.model: kSessionModelMolecule,
        for (final entry in grades.entries)
          ...nodeResultMetadata('$workBeadId/${entry.key}', {
            'grade': entry.value,
          }),
        for (final entry in results.entries)
          ...nodeResultMetadata('$workBeadId/${entry.key}', entry.value),
      },
    ),
    for (final node in staged)
      stepBead(
        node,
        sessionId: id,
        workBeadId: workBeadId,
        state: gated.contains(node)
            ? StepState.gated
            : completed.contains(node)
            ? StepState.complete
            : StepState.pending,
      ),
  ];
}

/// Waits until [condition] holds, or [maxPumps] bounded rounds have run
/// (default 20). Each round drains the Dart event queue AND, when the
/// condition is still unsatisfied, sleeps a REAL [ioSlice] (default 1ms).
///
/// The real slice is the load-bearing half, not the pump (bead `pow-d26`). A
/// molecule mint's POUR crosses the actual filesystem BELOW the fake
/// `BdRunner` seam: `BdCliService.applyGraph` writes the graph-apply plan to a
/// temp file (`Directory.systemTemp.createTemp` → `File.writeAsString` →
/// `Directory.delete`) around the runner call, so a fake runner does not make
/// the pour offline. `pumpEventQueue` advances event-loop TURNS and grants
/// only microseconds of wall clock, so it can never wait out an OS completion
/// — and to a plateau-based fixed-point wrapper an in-flight filesystem call
/// looks exactly like quiescence. That is why raising the pump budget alone
/// never fixed the ~25%-per-run acceptance wedge, and why this helper now
/// yields real time instead.
///
/// [condition] is evaluated EXACTLY ONCE per round, at the TOP of the round —
/// so an already-satisfied condition costs one check and no sleep, and a
/// never-satisfied one costs exactly [maxPumps] checks. That one-check-per-
/// round rate is what the private `_settle` fixed-point wrappers in the
/// acceptance suites count their `stableRounds` plateau in.
///
/// Still bounded, so a genuine regression FAILS (its [condition] stays false
/// through [maxPumps] rounds) instead of hanging.
Future<void> settle(
  bool Function() condition, {
  int maxPumps = 20,
  Duration ioSlice = const Duration(milliseconds: 1),
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (condition()) return;
    await pumpEventQueue();
    await Future<void>.delayed(ioSlice);
  }
}

/// The metadata map of ONE recorded chokepoint call ([argv]) — decoded from
/// the legacy single `--metadata '<json>'` flag when present, else assembled
/// from the repeated op-shaped `--set-metadata key=value` pairs
/// `BdCliService` emits since the atomic server-side metadata merges
/// (tg-u7b5, the_grid #174 — shipped in the 0.3.0-rc.3 wave). Empty when the
/// call carries neither shape. The per-argv sibling of the shared
/// `RecordingBdRunner.metadataOfUpdate` (same dual-shape parse, same
/// first-`=` split so embedded equals signs survive), kept separate so the
/// acceptance probes can filter calls by TARGET id before parsing.
Map<String, dynamic> callMetadata(List<String> argv) {
  final i = argv.indexOf('--metadata');
  if (i != -1 && i + 1 < argv.length) {
    return jsonDecode(argv[i + 1]) as Map<String, dynamic>;
  }
  final merged = <String, dynamic>{};
  for (var j = 0; j + 1 < argv.length; j++) {
    if (argv[j] == '--set-metadata') {
      final pair = argv[j + 1];
      final eq = pair.indexOf('=');
      if (eq > 0) merged[pair.substring(0, eq)] = pair.substring(eq + 1);
    }
  }
  return merged;
}
