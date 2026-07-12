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
/// (folded in so the spec route's `Rewind` can name it as a sibling).
const String kSpecifyNode = 'spec_review/specify';
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

/// EVERY spec-phase node complete — prepend this to a `completed` set (with
/// [kSpecGradesAllA] as grades) to FAST-FORWARD a test past the spec phase via
/// cursor adoption (the cursor is data; already-complete steps never mount),
/// so the code-committee choreography stays the test's focus. The spec phase's
/// own fan-out/gate proofs live in `spec_stage_acceptance_test.dart`.
const Set<String> kSpecPhaseNodes = {
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
/// [kSpecPhaseNodes].
final Map<String, String> kSpecGradesAllA = {
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
