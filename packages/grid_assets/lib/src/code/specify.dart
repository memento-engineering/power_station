/// The SPECIFY stage + the spec-readiness committee (bead `pow-6ao`).
///
/// The corrected model (Nico, 2026-07-10): specify is a station ASSET — pure
/// agentic work AFTER discovery — that mounts as a stage in the PER-BEAD
/// WORKTREE upstream of the build stage, with its own committee review. The
/// `code` circuit's drive loop is
///
///   [intake → readiness → readiness-route] → [specify agent → SPEC committee →
///   advance | RESPEC | escalate] → [build agent → CODE committee gate → land]
///
/// The READINESS LADDER at the head (bead `pow-q7n`, `readiness.dart`) is the
/// CHEAP pre-specify lens: a deterministic intake contract (zero agents) then ONE
/// agent grading the BEAD itself. A bead that is not spec-ready is HELD for
/// refinement there, so no specify agent and no 4-critic committee ever runs on
/// it. It is UPSTREAM of `specify` and therefore OUTSIDE the auto-respec
/// invalidated closure.
///
/// with `specify` FOLDED INTO the spec circuit as the route's sibling (bead
/// `pow-ui8`): [kCodeCircuit] (`code_capabilities.dart`) drops in `spec_review`
/// as its head [SubCircuitStep], and `agent`'s `dependsOn: {'spec_review'}`
/// resolves through the engine's existing one-hop terminal resolution to
/// `<bead>/spec_review/route`'s positive terminal, so only a spec that passes its
/// committee reaches the build. An ESCALATION parks the bead in the SAME `gated`
/// state the code committee uses (the `type=gate` bead + the `<bead>#rN` rework
/// re-key).
///
/// **The stage** ([SpecifyCapability]): an architect-equivalent harness ride —
/// the resolved agent (claude by default, ADR-0008 Decision 10) runs in the
/// bead's worktree and writes the implementation-ready spec INTO the bead via
/// the bd CLI: testable `--acceptance` checkboxes; a `--design` body carrying
/// `## Implementation Plan` (literal Dart code / exact file paths / exact
/// `dart test` commands / conventional-commit messages), `## Touches`, a
/// MANDATORY `## ADR Alignment` (grep the SUBSTATION's `docs/adr/` and
/// `docs/decisions/` registers and cite load-bearing clauses), and
/// a `## Validation Plan` mapped 1:1 to acceptance; plus the `validation_plan`
/// metadata command the CODE committee's gating lane later runs. Before it
/// exits it re-validates the drafted spec against the LIVE worktree (grep
/// callers/tests of every touched symbol + the sibling cross-check) to catch
/// drift from work that shipped while it wrote.
///
/// **The committee** ([kSpecReviewCircuit]): REUSES the pluggable machine
/// `committee.dart` ships — a [Circuit] over rubric ids, prose fed by the same
/// [RubricSource] (the Packaged-AI-Asset loader, D-9), verdicts through the
/// same transport stack, grades joined by the same [RouteCapability] matrix.
/// The lanes are the spec-readiness pack (ported from a deprecated skills
/// reference, every rubric body REWRITTEN for the station/memento context —
/// Dart tooling, the substation ADR-0000 register, this committee's own
/// circuit + loader, memento terminology, the station status model):
///  - `spec-validation` — the GATING lane ([SpecValidationCapability]): a
///    deterministic STRUCTURAL check over the spec the bead carries (the
///    spec-side mirror of `code-validation`'s runner-not-agent posture). A
///    placeholder or section-less spec grades F — a hard block via the route —
///    so a spec-less bead can never silently reach the build.
///  - `coherence` / `adr-alignment` / `acceptance-testability` /
///    `plan-completeness` — four LLM critics ([SpecCriticCapability]), each
///    riding the resolved harness with ONLY its own rubric (anti-anchoring),
///    grading the bead's SPEC (never a diff — there is no code yet) and
///    verifying its claims against the live worktree.
///
/// A FIXABLE fail (an actionable critic `D`/`E` carrying a rationale, under the
/// round cap) AUTO-RESPECS with NO human in the loop (beads `pow-7nm` +
/// `pow-ui8`, `respec.dart`): the route writes the failing lanes' rationales into
/// the worktree ledger and stamps an invalidating `grade: 'F'` on its own
/// result; the route declares a `validates` edge onto its `specify` SIBLING, so
/// the engine DERIVES the wave and re-keys the whole spec sub-DAG INSIDE the
/// live session (no gate bead, no session re-mint) and the next specify ride
/// reads that ledger back as its correction guidance. A structural `F`, a critic `F`, a
/// rationale-less fail, or the round cap still flares to a human [Gate].
///
/// **Freshness posture**: the committee grades the ambient [Bead] the engine
/// re-provides after specify's bd mutation lands — the same bd-watch →
/// diff → reconcile loop that made the bead ready in the first place. Every
/// capability here reads that ambient state at entry and trusts it (the
/// tg-83y posture, `committee.dart`); the fail direction is SAFE by
/// construction — a stale or empty spec grades F and gates (a false PARK a
/// human unwinds), never a false advance to the build.
library;

import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;

import '../agent/agent_domain.dart';
import '../agent/agent_harness.dart';
import '../agent/environment_registry.dart';
import '../agent/site_binding.dart';
import '../agent/usage_report.dart';
import 'committee.dart';
import 'decision_register.dart';
import 'discovery.dart';
import 'readiness.dart';
import 'respec.dart';

/// The spec committee's gating rubric id — a deterministic structural check
/// whose grade `F` is a hard block, decided by the route's matrix (the
/// spec-side mirror of [kGatingRubric]).
const String kSpecGatingRubric = 'spec-validation';

/// The four LLM spec-critic rubric ids (each graded in isolation by a harness
/// critic; anti-anchoring) — the spec-readiness pack's judgement lanes.
const List<String> kSpecLlmRubrics = [
  'coherence',
  'adr-alignment',
  'acceptance-testability',
  'plan-completeness',
];

/// Every spec-committee rubric id, in declaration order (the gating lane
/// first) — the spec-side mirror of [kCommitteeRubrics].
const List<String> kSpecCommitteeRubrics = [
  kSpecGatingRubric,
  ...kSpecLlmRubrics,
];

/// A structurally WHOLE spec — the acceptance half of the exemplar the specify
/// brief ships. Round-tripped through [specStructuralFindings] in test: what the
/// architect is told to copy is PROVEN to pass the gate that grades it.
const String kSpecExemplarAcceptance = '''
- [ ] `Heartbeat` parses a well-formed peer frame
- [ ] A malformed peer frame is refused LOUDLY (throws, never returns null)''';

/// The design half of that exemplar — one complete step in the ordinal-heading
/// shape, all four sections, every element the four LLM lanes look for.
const String kSpecExemplarDesign = '''
## Implementation Plan

### Step 1 — Add the `Heartbeat` frame

Create `packages/grid_assets/lib/src/bus/heartbeat.dart`:

```dart
/// One peer heartbeat frame.
class Heartbeat {
  /// Creates a heartbeat from [peerId].
  const Heartbeat(this.peerId);

  /// Parses [frame] — throws [FormatException] on a malformed frame (LOUD;
  /// never a null return).
  factory Heartbeat.parse(String frame) => frame.isEmpty
      ? throw const FormatException('empty heartbeat frame')
      : Heartbeat(frame);

  /// The peer that sent it.
  final String peerId;
}
```

Test: `cd packages/grid_assets && dart test test/heartbeat_test.dart` → expect
`All tests passed!`.
Commit: `feat(bus): add the peer heartbeat frame`

## Touches
- `packages/grid_assets/lib/src/bus/heartbeat.dart` — created;
  `lib/src/bus/heartbeat.dart:Heartbeat`

Re-validated against the live tree: `Heartbeat` has no caller yet and no sibling
bead adds one.

## ADR Alignment
No ADR applies — verified via grep on `heartbeat`, `bus`, `frame`.

## Validation Plan
- [ ] `Heartbeat` parses a well-formed peer frame → `cd packages/grid_assets && dart test test/heartbeat_test.dart` → `All tests passed!`
- [ ] A malformed peer frame is refused LOUDLY → `cd packages/grid_assets && dart test test/heartbeat_test.dart` → `All tests passed!`''';

/// Result key carrying the acceptance text authored by the specify step.
const String kCarriedSpecAcceptanceKey = 'specAcceptance';

/// Result key carrying the design text authored by the specify step.
const String kCarriedSpecDesignKey = 'specDesign';

/// The exact complete specification authored by one specify-step execution.
class CarriedSpec {
  /// Creates a carried specification.
  const CarriedSpec({required this.acceptance, required this.design});

  /// The exact acceptance text written to the work bead.
  final String acceptance;

  /// The exact design text written to the work bead.
  final String design;

  /// Parses the final harness result, returning null unless both fields exist.
  static CarriedSpec? tryParse(String? text) {
    if (text == null) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final acceptance = decoded['acceptance'];
      final design = decoded['design'];
      if (acceptance is! String ||
          acceptance.trim().isEmpty ||
          design is! String ||
          design.trim().isEmpty) {
        return null;
      }
      return CarriedSpec(acceptance: acceptance, design: design);
    } catch (_) {
      return null;
    }
  }

  /// Renders the pair into the existing string-valued step result payload.
  Map<String, String> toResultFields() => {
    kCarriedSpecAcceptanceKey: acceptance,
    kCarriedSpecDesignKey: design,
  };
}

/// Selects the complete current-wave spec, falling back to the mounted bead.
Bead? specForStructuralValidation({
  required Bead? fallback,
  required Map<String, String> specifyResult,
}) {
  final acceptance = specifyResult[kCarriedSpecAcceptanceKey];
  final design = specifyResult[kCarriedSpecDesignKey];
  if (acceptance == null ||
      acceptance.trim().isEmpty ||
      design == null ||
      design.trim().isEmpty) {
    return fallback;
  }
  if (fallback == null) return null;
  return fallback.copyWith(acceptanceCriteria: acceptance, design: design);
}

/// [kSpecPlaceholderTokens] as one backticked line — the brief names EVERY token
/// the fence bans.
final String _bannedTokenLine = kSpecPlaceholderTokens
    .map((token) => '`$token`')
    .join(', ');

/// The EXACT structural contract the deterministic `spec-validation` lane
/// enforces ([specStructuralFindings]), in the words the specify agent reads.
/// [buildSpecifyBrief] renders it VERBATIM, so the gate's contract and the
/// architect's instructions are literally ONE string.
///
/// Bead `pow-77g`: `pow-kzx`'s plan was graded **A** by `plan-completeness` and
/// **F** here, for lacking a step FORMAT the brief never named. A gate whose
/// contract the brief does not state is a trap. The round-trip fence in test —
/// the exemplar below PASSES [specStructuralFindings] — is what keeps the two
/// honest as either side moves.
final String kSpecStructuralContract =
    '''
### The structural contract (a DETERMINISTIC gate, run before any critic reads your spec)

`spec-validation` is not a critic and holds no opinion: it greps the bead you
write and hard-blocks the build on any miss. It checks EXACTLY this, and nothing
else:

1. **Acceptance** carries at least one `- [ ]` checkbox line.
2. **The design carries all four `## ` headings**, spelled exactly:
   `## Implementation Plan`, `## Touches`, `## ADR Alignment`,
   `## Validation Plan`.
3. **`## Implementation Plan` carries NUMBERED steps.** Every step opens with an
   ordinal — an ordered-list item (`1. …` / `1) …`) or an ordinal heading
   (`### Step 1 — …` / `### 1. …`). A bulleted or prose-only plan has no ordinal
   and FAILS however complete it is. Steps carrying fenced code read best as
   `### Step N — …` headings.
4. **`## Validation Plan` carries at least one `- ` item.**
5. **No placeholder token in PROSE.** These exact tokens, case-insensitively:
   $_bannedTokenLine.

Headings and ordinals are read from PROSE, and so are those tokens: markdown
QUOTATION is exempt (fenced blocks, `inline code` spans, `>` blockquote lines).
A token you QUOTE as evidence — a comment your plan deletes, a gate note cited
verbatim — points at work rather than deferring it, so backtick any banned token
you must name. The same cuts the other way: a `## Touches` heading that exists
only inside a code block is evidence, not a section.

Below is a COMPLETE spec that passes this gate. Copy its SHAPE.

`````markdown
$kSpecExemplarAcceptance

$kSpecExemplarDesign
`````''';

/// The spec-readiness committee circuit (id `spec_review`) — the READINESS
/// LADDER (bead `pow-q7n`: `intake` → `readiness` → `readiness-route`, the cheap
/// pre-specify lens) → SPECIFY (the architect harness ride) → a hygiene step
/// ([ClearCritiqueCapability], shared with the code committee so a round's
/// verdict files are always round-fresh) → the deterministic gating lane + four
/// LLM critics fanned out in parallel → a `route` join running the SPEC matrix
/// ([SpecRouteCapability], bead `pow-7nm`) — advance | AUTO-RESPEC | escalate —
/// over the spec grades.
///
/// **The ladder is the CHEAP head (bead `pow-q7n`, `readiness.dart`)**: it is
/// deliberately UPSTREAM of `specify` and so OUTSIDE the invalidated closure
/// below — a
/// respec rewrites the SPEC, not the BEAD, and re-grading an unchanged bead every
/// round would burn the very agents the lens exists to save.
///
/// **The DISCOVERY circuit is the second head (`discovery.dart`)**: a nested
/// [SubCircuitStep] between the ladder and `specify` — a deterministic gather
/// (rubrics, resolved anchors, prior art) plus three READ-ONLY cheap-tier
/// explorers, terminating in a CITE-THE-OFFENCE gate. `specify` `dependsOn` it,
/// so a bead that contradicts a ratified decision WITHOUT acknowledging the
/// departure spawns NO architect and NO committee, and a clean bead reaches the
/// architect with a curated dossier instead of a bare worktree. It is upstream of
/// `specify` for the same reason the ladder is, and stays out of the
/// invalidated closure.
///
/// **`specify` is FOLDED IN as the route's SIBLING (bead `pow-ui8`)** — it was a
/// step of the PARENT `code` circuit. A backward-motion edge may only name a
/// step of the SOURCE's OWN circuit, so the RESPEC arm can only invalidate
/// `specify` if `specify` lives HERE. The fold is what makes the auto-respec
/// loop ACTUATE with no human and no session re-mint: the route declares
/// `validates: specify` and stamps an `F`, the engine derives the invalidated
/// closure (`specify` ∪ its transitive dependents ∪ the route itself) and mints
/// a successor incarnation per node, keyed reconcile disposes the old
/// incarnations, and the committee re-runs VIRGIN in the SAME worktree with the
/// ledger's correction guidance in the next specify brief.
///
/// EVERY lane is transitively downstream of `specify` (the hygiene step depends
/// on it, and every lane depends on the hygiene step), so the invalidated
/// closure is the whole circuit FROM `specify` DOWN — the readiness ladder above
/// it is an ANCESTOR, not a dependent, and stays complete across the derived
/// wave (which is exactly why `specify`'s new dep is still satisfied when the
/// wave re-keys it). So the route can never re-decide over a previous round's
/// grades, and a round's verdict files are made fresh by the successor re-key
/// with [ClearCritiqueCapability]'s wipe as the belt behind it.
/// `spec_committee_test.dart` fences the closure with the engine's own
/// `transitiveDependents` predicate.
///
/// No `pin-diff` here: the review subject is the bead's OWN spec (its
/// acceptance + design fields), not a code delta — there is no diff to pin
/// before the build stage has run.
///
/// Reentrant: composed at the same `CircuitScope` seam as `code_review`, so
/// the `code` circuit drops it in as the `spec_review` [SubCircuitStep] with
/// zero engine changes.
const Circuit kSpecReviewCircuit = Circuit(
  id: 'spec_review',
  terminalStepId: 'route',
  steps: [
    // The SPEC-READINESS INTAKE LENS (bead `pow-q7n`) — the cheap ladder, ahead
    // of everything expensive. `intake` is deterministic (zero agents) and gates
    // a non-driveable / brief-less bead outright; `readiness` is ONE agent
    // grading the BEAD; `readiness-route` holds it or lets it drive. All three
    // are UPSTREAM of `specify`, so they are NOT in the auto-respec closure.
    CapabilityStep(stepId: kIntakeStep, capabilityId: kIntakeStep),
    CapabilityStep(
      stepId: kReadinessStep,
      capabilityId: kReadinessStep,
      params: {'rubric': kReadinessRubric},
      dependsOn: {kIntakeStep},
    ),
    CapabilityStep(
      stepId: kReadinessRouteStep,
      capabilityId: kReadinessRouteStep,
      params: {'lane': kReadinessStep},
      dependsOn: {kReadinessStep},
    ),
    // The DISCOVERY circuit (`discovery.dart`) — the nested read-only gather +
    // the cite-the-offence violation gate. `specify` dependsOn it, so an
    // unacknowledged offender spawns NO architect; the engine's one-hop terminal
    // resolution resolves the dep to
    // `<bead>/spec_review/discovery/discovery-route`'s positive terminal.
    // It is UPSTREAM of `specify` and therefore OUTSIDE the auto-respec
    // closure: a respec rewrites the SPEC, not the bead, so re-running three
    // explorers per round would burn the very agents this circuit exists to save
    // (the A17(9) posture).
    SubCircuitStep(
      stepId: kDiscoveryCircuitId,
      circuitId: kDiscoveryCircuitId,
      dependsOn: {kReadinessRouteStep},
    ),
    CapabilityStep(
      stepId: kSpecifyStep,
      capabilityId: kSpecifyStep,
      dependsOn: {kDiscoveryCircuitId},
    ),
    CapabilityStep(
      stepId: kClearCritiqueStep,
      capabilityId: kClearCritiqueStep,
      dependsOn: {kSpecifyStep},
    ),
    CapabilityStep(
      stepId: kSpecGatingRubric,
      capabilityId: kSpecGatingRubric,
      dependsOn: {kClearCritiqueStep},
    ),
    CapabilityStep(
      stepId: 'coherence',
      capabilityId: 'spec-critic',
      params: {'rubric': 'coherence'},
      dependsOn: {kClearCritiqueStep},
    ),
    CapabilityStep(
      stepId: 'adr-alignment',
      capabilityId: 'spec-critic',
      params: {'rubric': 'adr-alignment'},
      dependsOn: {kClearCritiqueStep},
    ),
    CapabilityStep(
      stepId: 'acceptance-testability',
      capabilityId: 'spec-critic',
      params: {'rubric': 'acceptance-testability'},
      dependsOn: {kClearCritiqueStep},
    ),
    CapabilityStep(
      stepId: 'plan-completeness',
      capabilityId: 'spec-critic',
      params: {'rubric': 'plan-completeness'},
      dependsOn: {kClearCritiqueStep},
    ),
    CapabilityStep(
      stepId: 'route',
      // The SPEC route (bead `pow-7nm`) — the three-way matrix (advance |
      // RESPEC | escalate), NOT the code committee's binary [RouteCapability].
      // The stepId stays `route` (the circuit's terminal), so no node path moves.
      capabilityId: 'spec-route',
      dependsOn: {
        kSpecGatingRubric,
        'coherence',
        'adr-alignment',
        'acceptance-testability',
        'plan-completeness',
      },
      params: {
        'critics':
            'spec-validation,coherence,adr-alignment,'
            'acceptance-testability,plan-completeness',
        'gating': kSpecGatingRubric,
        // The DECLARATIVE backward-motion edge. The route does not REPORT a
        // rewind — the engine refuses a reported one outright. It stamps
        // `grade: 'F'` on its own result and the engine DERIVES the wave off
        // this edge: `specify` ∪ its transitive dependents ∪ this route are
        // invalidated and re-mint as successor incarnations. The target MUST be
        // a sibling of THIS circuit (which is why `specify` is folded in here);
        // a dangling name mints no edge at all, so the committee suite fences
        // that the named step exists.
        kValidatesParamKey: kSpecifyStep,
      },
    ),
  ],
);

/// The SPECIFY capability — spawns the architect-equivalent agent in the
/// bead's workspace, parameterized over the AMBIENT agent scope exactly like
/// [AgentCapability] (ADR-0008 Decision 10): it reads the work [Bead], the
/// [Workspace], the station's [AgentConfig] default, and the
/// [AgentHarnessRegistry] with the effect verb, resolves the effective config
/// through the ladder, and delegates the INVOCATION to the resolved harness.
///
/// The architect is an ARCHITECT-role spawner ([AgentRole.architect], bead
/// `pow-t1w`). It writes the spec two independent builds must converge on, so
/// it rides the FRONTIER tier ([kFrontierModelDefault], `opus`) by default.
/// An unarmed architect inherits the BUILD environment in
/// [resolveAgentConfig], preserving existing station armings. Auto-respec
/// re-enters this same capability and therefore rides the same role.
///
/// The POLICY stays here: [buildSpecifyBrief] renders the full bead (a
/// title-only brief starves the agent, A36) + the spec-writing contract — the
/// agent writes the spec INTO the bead via the bd CLI (`--acceptance`, the
/// four-section `--design`, the `validation_plan` metadata command), runs the
/// pre-convene re-validation against the live tree, and NEVER touches the
/// code: this stage is read-only on the worktree (no commit, no push, no PR —
/// the build stage owns the tree). No pub linkage is materialized here
/// (unlike [AgentCapability]): the stage greps and reads; it runs no Dart
/// tooling, so `grid.dart` linkage stays the build spawn's job.
class SpecifyCapability extends ProcessCapability {
  /// Creates the specify capability.
  ///
  /// [runnerFor] is the bd subprocess seam used only for the durable read-back;
  /// production composes [ProcessBdRunner], while tests inject a fake
  /// [BdRunner].
  const SpecifyCapability({
    BdRunner Function(String workspaceRoot) runnerFor = _processRunnerFor,
  }) : _runnerFor = runnerFor;

  final BdRunner Function(String workspaceRoot) _runnerFor;

  static BdRunner _processRunnerFor(String workspaceRoot) =>
      ProcessBdRunner(workspaceRoot: workspaceRoot);

  @override
  CompletionContract get completionContract =>
      CompletionContract.artifactDurability;

  @override
  Future<GateOutcome> probeCompletionArtifact(
    TreeContext context,
    StepArgs args,
  ) async {
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (workspace == null) return GateOutcome.probeError;
    try {
      final queried = await BdCliService(
        _runnerFor(workspace.workspaceDir),
      ).query('id=${args.beadId}');
      if (args.cancel.isCancelled) return GateOutcome.probeError;
      final matches = queried
          .where((candidate) => candidate.id == args.beadId)
          .toList(growable: false);
      if (matches.isEmpty) return GateOutcome.present;
      if (matches.length != 1) return GateOutcome.probeError;
      final durable = matches.single;
      return durable.acceptanceCriteria.trim().isNotEmpty &&
              durable.design.trim().isNotEmpty
          ? GateOutcome.clear
          : GateOutcome.present;
    } on Object {
      return GateOutcome.probeError;
    }
  }

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) {
    // Read the ambient values at ENTRY (synchronously, while mounted).
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (bead == null || workspace == null) {
      throw StateError(
        'SpecifyCapability requires the ambient Bead + Workspace '
        '(WorkBead/SessionScope mount them)',
      );
    }
    final ambient =
        context.getInheritedSeedOfExactType<AgentConfig>() ??
        const AgentConfig();
    final registry =
        context.getInheritedSeedOfExactType<EnvironmentRegistry>() ??
        buildBuiltinEnvironmentRegistry();
    final siteBinding =
        context.getInheritedSeedOfExactType<SiteBinding>() ?? SiteBinding.none;
    final config = resolveAgentConfig(
      role: AgentRole.architect,
      ambient: ambient,
      beadMetadata: bead.metadata,
      stepParams: args.params,
      registry: registry,
    );
    final environment = registry.resolve(config.harness);
    // The AUTO-RESPEC guidance (bead `pow-7nm`): on a rework round the spec
    // route left the failing lanes' rationales in the worktree ledger — the one
    // channel that survives the session re-mint (the SiblingView it graded
    // through does not). Absent (a first round, or an offline/dry-run worktree
    // that was never materialized) ⇒ a plain first-round brief.
    final workspaceDir = workspace.workspaceDir;
    final live = Directory(workspaceDir).existsSync();
    final guidance = live
        ? readRespecLedger(workspaceDir, expectedSessionRoot: args.beadId)
        : null;
    // The DISCOVERY dossier (`discovery.dart`) — the curated context the gather
    // circuit left in the worktree. Absent (offline, or a session on a frozen
    // pre-discovery shape) ⇒ a brief byte-identical to the pre-discovery one.
    final dossier = live ? readDiscoveryDossier(workspaceDir) : null;
    return spawnFor(
      environment: environment,
      model: config.params['model'],
      endpoint: siteBinding.endpointFor(
        name: config.harness,
        environment: environment,
      ),
      brief: buildSpecifyBrief(
        bead,
        workspace,
        guidance: guidance,
        dossier: dossier,
      ),
      workspace: workspace,
      // CAPTURE-ONLY usage telemetry (FT-2), same as the build agent.
      usageOut: usageReportPath(args.nodePath),
    );
  }

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };

  /// The CAPTURE-ONLY usage telemetry (FT-2) — identical posture to
  /// [AgentCapability.result]: an absent/malformed envelope yields no fields,
  /// NEVER a throw.
  @override
  Future<Map<String, String>?> result(
    TreeContext context,
    StepArgs args,
  ) async {
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (workspace == null) return null;
    final fields = <String, String>{
      ...readUsageFields(workspace.workspaceDir, args.nodePath),
      ...?CarriedSpec.tryParse(
        readEnvelopeResultText(workspace.workspaceDir, args.nodePath),
      )?.toResultFields(),
    };
    return fields.isEmpty ? null : fields;
  }
}

/// Assembles the specify agent's full-bead brief + the spec-writing working
/// agreement (exposed for unit tests). Mirrors [buildAgentBrief]'s shape —
/// the full bead renders first (A36), the agreement carries the stage policy
/// — but the contract is the ARCHITECT's, not the builder's: write the spec
/// into the bead, verify it against the live tree, touch no code.
///
/// **AUTO-RESPEC (bead `pow-7nm`)**: when [guidance] is present this is a
/// REWRITE, not a fresh spec — the previous round's spec was rejected and the
/// ledger carries the failing lanes' rationales VERBATIM. They render as a
/// `## Correction guidance` block between the bead and the job contract, so the
/// re-specify agent corrects against the committee's own words with no human in
/// the loop. Absent ⇒ the brief is byte-identical to the pre-pow-7nm one.
///
/// Q3′ (Track E): the only paths interpolated are the ambient [Workspace]'s
/// (`workspaceDir`/`branch`); bead reads are content + the bead ID (a
/// reference, never a path). The ledger contributes rubric ids, grades and
/// critic prose — never a path.
AgentBrief buildSpecifyBrief(
  Bead bead,
  Workspace workspace, {
  RespecLedger? guidance,
  DiscoveryDossier? dossier,
}) {
  final title = bead.title.isNotEmpty ? bead.title : 'work bead ${bead.id}';
  final substation = bead.metadata['rig'];
  final id = bead.id;
  final registerListCommand = localDecisionRegisterListCommand();
  final registerGrepCommand = localDecisionRegisterGrepCommand(
    r'<keyword1>\|<keyword2>\|<keyword3>',
  );
  final t = StringBuffer()
    ..writeln('# Specify: $title')
    ..writeln()
    ..writeln(
      substation is String && substation.isNotEmpty
          ? 'Bead `$id` (substation `$substation`).'
          : 'Bead `$id`.',
    );
  void section(String heading, String body) {
    if (body.trim().isEmpty) return;
    t
      ..writeln()
      ..writeln('## $heading')
      ..writeln(body.trim());
  }

  section('Task', bead.description);
  section('Design', bead.design);
  section('Acceptance criteria', bead.acceptanceCriteria);
  section('Notes', bead.notes);
  if (guidance != null) {
    t
      ..writeln()
      ..write(renderRespecGuidance(guidance));
  }
  // The DISCOVERY dossier (`discovery.dart`) — the gather's curated context: the
  // rubrics this spec will be GRADED by, the bead's resolved anchors, the prior
  // art, what the explorers found, the flags to answer, and any departure the
  // bead declared (which the architect must carry into `## ADR Alignment`).
  if (dossier != null) {
    t
      ..writeln()
      ..write(renderDiscoveryDossier(dossier));
  }
  t
    ..writeln()
    ..writeln('## Your job — the SPECIFY stage')
    ..writeln(
      'You are the specify stage of this bead\'s circuit — the ARCHITECT, not '
      'the builder. The build agent runs AFTER you in this same worktree with '
      'ONLY the bead as its brief, so the spec you write into the bead is '
      'everything the builder gets. A spec-readiness committee grades your '
      'spec before any build runs; a placeholder, ADR-misaligned, or '
      'non-testable spec is F-gated back for rework. Write the spec so '
      'concrete that two independent builds of it converge on the same '
      'change.',
    )
    ..writeln()
    ..writeln(
      'Explore the worktree first — read the code your plan will touch. Then '
      'write the spec INTO bead `$id` via the bd CLI (the only sanctioned '
      'mutation path; always pass `--actor specify`):',
    )
    ..writeln()
    ..writeln('### 1. Acceptance criteria')
    ..writeln('`bd update $id --actor specify --acceptance \'<criteria>\'`')
    ..writeln(
      '- One testable criterion per checkbox line (`- [ ] ...`), ordered '
      'most-critical first, error/edge cases included.',
    )
    ..writeln(
      '- Every criterion must be independently verifiable by an exact command '
      'or test — if you cannot name the `dart test` (or shell) check that '
      'proves it, it is not a criterion. No vague claims ("works well", '
      '"is fast").',
    )
    ..writeln()
    ..writeln('### 2. The spec body')
    ..writeln(
      '`bd update $id --actor specify --design \'<spec>\'` — carrying EXACTLY '
      'these four sections:',
    )
    ..writeln()
    ..writeln(
      '**## Implementation Plan** — numbered steps a builder with zero '
      'context can follow. EVERY step carries all four elements: the literal '
      'Dart code to write (a real code block, not pseudo-code, honoring the '
      'memento house set — freezed sealed unions consumed with exhaustive '
      '`switch`, Fakes not mocks, no `print` in lib code); the exact file '
      'path from the repo root (backticked); the exact test command with '
      'expected output (`dart test test/<file>_test.dart` → expect PASS); and '
      'a conventional-commit message. When the plan touches genesis_tree / '
      'grid code, spec it to the D-H doctrine (ADR-0008): watch deps in '
      '`build` via `dependOn*`; no public synchronous accessor over '
      '`StateNotifier` state; config = VALUES in the tree, impls = DI; guards '
      'LOUD or GONE. No placeholders: the structural contract below enumerates '
      'every banned token, and a spec that defers its own content is F-gated.',
    )
    ..writeln()
    ..writeln(
      '**## Touches** — every file the plan creates or modifies, and every '
      'public symbol it adds or exposes (`lib/src/<file>.dart:SymbolName`). '
      'Sibling beads cross-check shared state against this section.',
    )
    ..writeln()
    ..writeln(
      '**## ADR Alignment** — MANDATORY. Grep the substation\'s ADR register '
      'FIRST, from the worktree root. Run `$registerListCommand`, then '
      '`$registerGrepCommand` with 3-6 keywords from the bead\'s title and '
      'touched surfaces. Both commands search `docs/adr/` and '
      '`docs/decisions/`; a missing directory is absent, not an error. Cite a '
      'legacy ADR by file path plus ADR or `A<n>` clause. Cite a '
      '`docs/decisions/` entry as `<repo>#<slug>`, for example '
      '`the_grid#admission-authority-boundary`; a migrated entry may also '
      'preserve its old citation in `register.legacy-id`. The legacy '
      'register\'s ADR-0000 is the living AI-decision register — its pending '
      '`A<n>` amendments bind too. Quote each load-bearing decision and say '
      'how the plan aligns. If grep returns nothing relevant, write exactly: '
      'No ADR applies — verified via grep on `<keywords>`.',
    )
    ..writeln()
    ..writeln(
      '**## Validation Plan** — one item per acceptance criterion, mapped '
      '1:1: `- [ ] <criterion> → \'<exact command>\' → <expected output>`. No '
      'gaps — every criterion has its validation, every validation names its '
      'criterion.',
    )
    ..writeln()
    ..writeln(kSpecStructuralContract)
    ..writeln()
    ..writeln('### 3. The machine gate')
    ..writeln(
      '`bd update $id --actor specify --set-metadata validation_plan=\'<one '
      'shell command line>\'` (e.g. `cd packages/<pack> && dart analyze && '
      'dart test`). After the build, the code committee\'s gating lane runs '
      'EXACTLY this command in the worktree and hard-blocks on non-zero — '
      'make it the one line that proves this bead\'s change.',
    )
    ..writeln()
    ..writeln('## Pre-convene re-validation (before you exit)')
    ..writeln(
      'The plan was written from your read of the tree; sibling work may have '
      'shipped since. Re-validate the drafted spec against the LIVE worktree:',
    )
    ..writeln(
      '- for every symbol in ## Touches (added, renamed, or deleted), grep '
      'its callers and tests — `grep -rn "<symbol>" . --include=\'*.dart\'` — '
      'and cross-check the hits against the plan: any caller or test file the '
      'plan does not already migrate is DRIFT; add the missing migration '
      'step;',
    )
    ..writeln(
      '- sibling cross-check: if the bead has a parent or siblings (`bd dep '
      'list $id`), read their Touches — a symbol your plan consumes that a '
      'sibling adds needs an explicit dependency (`bd dep add $id '
      '<sibling-id>`) or a restructured, self-contained plan. Do not proceed '
      'until one is true.',
    )
    ..writeln(
      'Then record the outcome as the LAST line of ## Touches: '
      '`Re-validated against the live tree: <one-line summary>` (update the '
      'design field again if re-validation changed the plan).',
    )
    ..writeln(
      'After all three sanctioned `bd update --actor specify` mutations and '
      'the live-tree re-validation succeed, your final response must be '
      'exactly one JSON object: {"acceptance":"<the exact value passed to '
      '--acceptance>","design":"<the exact value passed to --design>"}. Emit '
      'no Markdown fence and no surrounding prose.',
    );

  final agreement = StringBuffer()
    ..writeln(
      '- Work ONLY inside this worktree (${workspace.workspaceDir}); it is on '
      'branch `${workspace.branch}`, a throwaway branch the_grid provisioned '
      'for this bead.',
    )
    ..writeln(
      '- This stage is READ-ONLY on the tree: do NOT edit, commit, or push '
      'code, and do NOT open a pull request — you write the SPEC; the build '
      'stage writes the code.',
    )
    ..writeln(
      '- Every bead mutation goes through the bd CLI with `--actor specify` — '
      'never SQL, never files under `.beads/`.',
    )
    ..writeln(
      '- Do NOT transition the bead\'s status and do NOT close it — the '
      'circuit advances it.',
    )
    ..writeln(
      '- After all three sanctioned `bd update --actor specify` mutations and '
      'the live-tree re-validation succeed, your final response must be '
      'exactly one JSON object: {"acceptance":"<the exact value passed to '
      '--acceptance>","design":"<the exact value passed to --design>"}. Emit '
      'no Markdown fence and no surrounding prose.',
    )
    ..write(
      '- When the spec (acceptance + the four-section design + the '
      '`validation_plan` metadata) is written and re-validated, you are done; '
      'exit.',
    );
  return AgentBrief(task: t.toString(), workingAgreement: agreement.toString());
}

/// One SPEC critic, in isolation — the spec committee's LLM lane. Subclasses
/// [CriticCapability] to inherit the ENTIRE verdict-transport stack unchanged
/// (canonical file → round-fresh stray → result-envelope → fail-closed F,
/// each with the `nodePath` + `round` freshness stamps and a named `transport`;
/// plus the FT-2 usage merge): one transport stack serves both committees, so a
/// hardening landed for the code critics (gate-integrity #3/#4, tg-291)
/// automatically holds here. Only the SPAWN differs — it is a GRADE-role spawner
/// ([AgentRole.grade], bead `pow-edp`), like its superclass, so absent an
/// override it grades on the MID tier ([kMidModelDefault], `sonnet`); and a spec
/// critic is always an agent (there is no `sh -c` validation-runner flavor; the
/// spec gate is [SpecValidationCapability]) and its prompt is
/// [buildSpecCriticPrompt]: the review subject is the bead's SPEC, never a
/// pinned diff (no code exists yet).
class SpecCriticCapability extends CriticCapability {
  /// Creates the spec critic, optionally over a rubric source (D-9 wires
  /// the Packaged-AI-Asset loader; absent ⇒ an inline placeholder so the
  /// circuit is testable with no real assets).
  const SpecCriticCapability({super.rubrics, super.verdictTextReader});

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) {
    // Read the ambient values at ENTRY (synchronously, while mounted).
    final rubric = args.params['rubric'] ?? '';
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (bead == null || workspace == null) {
      throw StateError(
        'SpecCriticCapability requires the ambient Bead + Workspace '
        '(WorkBead/SessionScope mount them)',
      );
    }
    final ambient =
        context.getInheritedSeedOfExactType<AgentConfig>() ??
        const AgentConfig();
    final registry =
        context.getInheritedSeedOfExactType<EnvironmentRegistry>() ??
        buildBuiltinEnvironmentRegistry();
    final siteBinding =
        context.getInheritedSeedOfExactType<SiteBinding>() ?? SiteBinding.none;
    final config = resolveAgentConfig(
      role: AgentRole.grade,
      ambient: ambient,
      beadMetadata: bead.metadata,
      stepParams: args.params,
      registry: registry,
    );
    final environment = registry.resolve(config.harness);
    return spawnFor(
      environment: environment,
      model: config.params['model'],
      endpoint: siteBinding.endpointFor(
        name: config.harness,
        environment: environment,
      ),
      brief: AgentBrief(
        task:
            buildSpecCriticPrompt(
              bead,
              rubric,
              args.nodePath,
              workspace.workspaceDir,
              round: verdictRound(args),
            ) +
            criticRepairInstruction(
              workspaceDir: workspace.workspaceDir,
              rubric: rubric,
              nodePath: args.nodePath,
              round: verdictRound(args),
            ),
      ),
      workspace: workspace,
      usageOut: usageReportPath(args.nodePath),
    );
  }

  /// The rubric prose embedded in a spec critic's prompt — the inherited
  /// injected source (D-9), or an inline placeholder so the circuit is
  /// testable with no assets.
  String _rubricText(String rubric) =>
      rubricSource?.call(rubric) ??
      '(rubric `$rubric` — the Packaged-AI-Asset loader supplies the bands)';

  /// Assembles the spec critic's prompt for [rubric] over the work [bead] —
  /// names ONLY its own rubric (anti-anchoring), carries the full bead (whose
  /// Acceptance criteria + Design fields ARE the spec under review), and
  /// instructs a single A–F grade written as a verdict JSON.
  ///
  /// Carries the SAME hardening as [CriticCapability.buildCriticPrompt]: the
  /// verdict JSON's `nodePath` FRESHNESS STAMP (gate-integrity #3 — a rework
  /// round reuses the workspace directory), plus the ROUND stamp (A15(5)
  /// alt-A), sourced from the engine-injected session circuit round via
  /// [verdictRound], which fences a stale verdict across an auto-respec wave
  /// (the node path does not move); the workspace-derived ABSOLUTE
  /// canonical write path (gate-integrity #4 — cwd-invariant), and the
  /// file-write instruction as the LAST thing the prompt says (tg-291 —
  /// recency). What differs is the SCOPE: the review subject is the bead's
  /// spec — there is no pinned diff and no code to grade — and the critic is
  /// told to VERIFY the spec's claims (named files/symbols, ADR citations)
  /// against the live worktree it is standing in rather than take the spec's
  /// word.
  ///
  /// Exposed for unit tests.
  String buildSpecCriticPrompt(
    Bead bead,
    String rubric,
    String nodePath,
    String workspaceDir, {
    required int round,
  }) {
    final path = p.join(workspaceDir, '.grid', 'critique', '$rubric.json');
    final registerListCommand = localDecisionRegisterListCommand();
    final registerGrepCommand = localDecisionRegisterGrepCommand(
      r'<keyword1>\|<keyword2>\|<keyword3>',
    );
    final b = StringBuffer()
      ..writeln('# Spec review — rubric: `$rubric`')
      ..writeln()
      ..writeln(
        'You are ONE critic in an adversarial spec-readiness committee. The '
        'bead has NOT been built yet: you are grading its SPEC — the '
        'Acceptance criteria and Design fields below (the implementation '
        'plan, touches, ADR alignment, and validation plan) — never a code '
        'diff. Review ONLY against the `$rubric` rubric below — do not weigh '
        'any other concern.',
      )
      ..writeln()
      ..writeln('## Rubric: $rubric')
      ..writeln(_rubricText(rubric))
      ..write(specBeadBlock(bead))
      ..writeln()
      ..writeln('## Verify against the live tree')
      ..writeln(
        'You are standing in the bead\'s worktree. Verify the spec\'s claims '
        'against the REAL tree before grading: grep/read the files and '
        'symbols the plan names (a named symbol that neither resolves nor is '
        'announced as new is a finding, not a style nit). Run '
        '`$registerListCommand`, then `$registerGrepCommand`. Both commands '
        'search `docs/adr/` and `docs/decisions/`; a missing directory is '
        'absent, not an error. Cite a legacy ADR by file path plus ADR or '
        '`A<n>` clause. Cite a `docs/decisions/` entry as `<repo>#<slug>`, for '
        'example `the_grid#admission-authority-boundary`; a migrated entry may '
        'also preserve its old citation in `register.legacy-id`. Check the '
        'decisions the spec cites — or should have cited. A claim you cannot '
        'verify grades down; do not take the spec\'s word for the world.',
      )
      ..writeln()
      ..writeln('## Your verdict')
      ..writeln(
        'Grade the spec A (best) through F (worst) against `$rubric` ONLY. '
        'Your verdict is JSON of this exact shape:',
      )
      ..writeln(
        verdictJsonTemplate(rubric: rubric, nodePath: nodePath, round: round),
      )
      ..writeln()
      ..writeln(kVerdictStampInstruction)
      ..writeln()
      ..writeln(verdictWriteInstruction(path));
    return b.toString();
  }
}

/// Renders the full work bead into the spec-review prompt block — the same
/// title/task/design/acceptance/notes rendering the code committee embeds,
/// re-labeled so the critic knows the Acceptance criteria + Design sections
/// ARE the artifact under review.
String specBeadBlock(Bead bead) {
  final title = bead.title.isNotEmpty ? bead.title : 'work bead ${bead.id}';
  final b = StringBuffer()
    ..writeln()
    ..writeln(
      '## The work bead (its Acceptance criteria + Design ARE the spec)',
    )
    ..writeln('`${bead.id}` — $title');
  void section(String heading, String body) {
    if (body.trim().isEmpty) return;
    b
      ..writeln()
      ..writeln('### $heading')
      ..writeln(body.trim());
  }

  section('Task', bead.description);
  section('Design', bead.design);
  section('Acceptance criteria', bead.acceptanceCriteria);
  section('Notes', bead.notes);
  return b.toString();
}

/// The GATING spec lane — a deterministic STRUCTURAL check over the spec the
/// ambient [Bead] carries (the spec-side mirror of the code committee's
/// `code-validation` posture: a validation RUNNER, not an agent — no LLM
/// judgement in this lane). It always COMPLETES with a grade in its [Ok]
/// payload (A iff the structure is whole, else F with the findings as
/// rationale), leaving the route as the single decision point — exactly the
/// gating-lane contract `committee.dart` established.
///
/// **The invariant it protects (LOUD-or-gone)**: a bead may only reach the
/// build stage carrying a structurally complete, placeholder-free spec —
/// testable `- [ ]` acceptance checkboxes and a design with all four sections
/// (`## Implementation Plan` with ordinal-led steps, `## Touches`,
/// `## ADR Alignment`, `## Validation Plan` with at least one item), free of
/// the [kSpecPlaceholderTokens]. A bead with no spec at all — the pre-specify
/// state — grades F, so the specify stage can never be silently skipped.
/// Fail-closed: a missing ambient bead grades F too.
///
/// Every rule it enforces is STATED to the agent it judges: the specify brief
/// renders [kSpecStructuralContract] verbatim, and the exemplar that contract
/// ships is round-tripped through [specStructuralFindings] in test (bead
/// `pow-77g` — a gate whose contract the brief does not state is a trap, and
/// this one had F'd an A-graded plan for a step FORMAT nobody named).
///
/// The placeholder fence reads the spec's PROSE only: markdown quotation
/// contexts — fenced ``` blocks, inline `code` spans, `>` blockquote lines —
/// are stripped before matching, so a spec that QUOTES a banned token as
/// evidence (a `// TODO` comment the plan deletes, an ADR clause or gate note
/// cited verbatim) is pointing at work, not deferring it, and never parks. The
/// same strip governs the STRUCTURE check — a `## ` heading or a step ordinal
/// quoted inside a fence is evidence, not structure.
///
/// What the structure check does NOT judge — whether the criteria are truly
/// testable, the plan truly complete, the ADR citations truly load-bearing —
/// is exactly what the four LLM lanes own.
class SpecValidationCapability extends ServiceCapability {
  /// Creates the spec-validation gate.
  const SpecValidationCapability();

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    final round = verdictRound(args);
    final entryBead = context.getInheritedSeedOfExactType<Bead>();
    final siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    final bead = specForStructuralValidation(
      fallback: entryBead,
      specifyResult: siblings.resultOf(
        '${parentPath(args.nodePath)}/$kSpecifyStep',
      ),
    );
    if (bead == null) {
      return Ok({
        'grade': 'F',
        'transport': 'structural',
        'rationale': 'no ambient work bead to validate — fail-closed',
        kVerdictRoundKey: '$round',
      });
    }
    final findings = specStructuralFindings(bead);
    if (findings.isEmpty) {
      return Ok({
        'grade': 'A',
        'transport': 'structural',
        kVerdictRoundKey: '$round',
      });
    }
    return Ok({
      'grade': 'F',
      'transport': 'structural',
      'rationale': findings.join('; '),
      kVerdictRoundKey: '$round',
    });
  }
}

/// The placeholder tokens that anchor an automatic structural F — a spec that
/// defers its own content is not implementation-ready.
///
/// This list is the ONE source: [_placeholderPatterns] compiles it (single
/// words on word boundaries, so an identifier that merely CONTAINS the letters
/// never trips; the phrases verbatim, all case-insensitive) and
/// [kSpecStructuralContract] enumerates it to the specify agent — so the fence
/// can never ban a token the brief never named. Before bead `pow-77g` the brief
/// named three of these seven, and the four it omitted are ordinary English an
/// architect writes without thinking: a good plan parked on a rule nobody
/// stated.
const List<String> kSpecPlaceholderTokens = [
  'TBD',
  'TODO',
  'implement later',
  'fill in later',
  'as needed',
  'appropriate error handling',
  'similar to step',
];

/// [kSpecPlaceholderTokens] compiled — single words word-bounded, phrases
/// verbatim, all case-insensitive. Matched against [proseOnly] output, so a
/// token inside a markdown quotation context (quoted code, a cited clause) is
/// evidence, not deferral, and never trips.
final List<RegExp> _placeholderPatterns = [
  for (final token in kSpecPlaceholderTokens)
    RegExp(
      token.contains(' ')
          ? RegExp.escape(token)
          : '\\b${RegExp.escape(token)}\\b',
      caseSensitive: false,
    ),
];

/// A NUMBERED step's opening line inside `## Implementation Plan` — the two
/// shapes a real plan takes, BOTH carrying an explicit ordinal:
///
///  * an ordered-list item — `1. …` / `1) …`
///  * an ordinal heading or bold lead-in — `### Step 1 — …`, `### 1. …`,
///    `**Step 1:** …`
///
/// The heading form is what a plan with a fenced Dart block per step must take
/// (a `1.` list item has to indent every following block to stay inside the
/// item) and it is what the specify agent writes when left to itself: bead
/// `pow-kzx`'s 1226-line plan, graded **A** by the `plan-completeness` critic,
/// carried `### Step 1 — …` headings and not one `1.`-led line, and F'd here on
/// FORMAT alone (bead `pow-77g`).
///
/// Recognizing it is not a loosening — the ordinal is still MANDATORY, so a
/// bulleted or prose-only plan (steps neither ordered nor addressable) still
/// fails LOUD. In a heading or bold lead-in a bare ordinal IS the step number,
/// so no trailing `.`/`)` is required there; in running prose one is, which is
/// why `2026-07-11 …` and `3.5x faster` do not match.
final RegExp _numberedStep = RegExp(
  r'^[ \t]*(?:'
  r'\d+[.)]\s' // 1. …  /  1) …
  r'|#{1,6}[ \t]*(?:step[ \t]*)?\d+\b' // ### Step 1 — …  /  ### 1. …
  r'|\*\*[ \t]*(?:step[ \t]*)?\d+\b' // **Step 1:** …  /  **1.** …
  r')',
  multiLine: true,
  caseSensitive: false,
);

/// The structural findings for [bead]'s spec — empty iff the spec is whole.
/// Pure and exposed for unit tests; [SpecValidationCapability] grades A iff
/// this returns empty. Each finding names what is missing (guards LOUD), so
/// the route's gate reason — and the rework round's operator — never has to
/// diff the spec by hand.
List<String> specStructuralFindings(Bead bead) {
  final findings = <String>[];
  final acceptance = bead.acceptanceCriteria;
  final design = bead.design;
  if (acceptance.trim().isEmpty) {
    findings.add('acceptance: empty');
  }
  if (design.trim().isEmpty) {
    findings.add('design: empty');
  }
  // The SHAPE is read from PROSE, the same way the placeholder fence is
  // (A13(10)): a `## ` heading or a step ordinal quoted inside a fenced block —
  // this pack's own specs quote all four headings verbatim — is evidence, not
  // structure.
  final structure = proseOnly(design);

  // Testable acceptance: at least one `- [ ]` checkbox criterion.
  if (!RegExp(
    r'^\s*-\s*\[[ xX]\]\s*\S',
    multiLine: true,
  ).hasMatch(acceptance)) {
    findings.add('acceptance: no testable `- [ ]` checkbox criteria');
  }

  // The four design sections.
  final planAt = structure.indexOf('## Implementation Plan');
  if (planAt < 0) {
    findings.add('design: no `## Implementation Plan` section');
  } else if (!_numberedStep.hasMatch(sectionBodyAt(structure, planAt))) {
    findings.add(
      'design: `## Implementation Plan` has no numbered steps — every step '
      'must open with an ordinal (`1.` / `1)` list items, or `### Step 1 — …` '
      'headings)',
    );
  }
  if (!structure.contains('## Touches')) {
    findings.add('design: no `## Touches` section');
  }
  if (!structure.contains('## ADR Alignment')) {
    findings.add('design: no `## ADR Alignment` section');
  }
  final validationAt = structure.indexOf('## Validation Plan');
  if (validationAt < 0) {
    findings.add('design: no `## Validation Plan` section');
  } else {
    final body = sectionBodyAt(structure, validationAt);
    if (!RegExp(r'^\s*-\s*\S', multiLine: true).hasMatch(body)) {
      findings.add('design: `## Validation Plan` has no items');
    }
  }

  // Placeholder tokens anywhere in the spec's PROSE — quotation contexts
  // (quoted code, cited clauses) are evidence, not deferral, and never trip.
  final prose = proseOnly('$acceptance\n$design');
  for (final pattern in _placeholderPatterns) {
    final match = pattern.firstMatch(prose);
    if (match != null) {
      findings.add(
        'placeholder: "${match.group(0)}" — not implementation-ready',
      );
    }
  }
  return findings;
}

/// [spec] with its markdown QUOTATION contexts blanked — fenced ``` blocks,
/// `>` blockquote lines, then inline `code` spans (in that order, so a fence's
/// own backticks are never re-paired as inline spans). Quoted material is what
/// a spec points AT (code carrying a `// TODO` the plan deletes, an ADR clause
/// cited verbatim), not a commitment the author defers, so the placeholder
/// fence never reads it. Each region is replaced by a TWO-space seam: wide
/// enough that stripping can only ever break a token across it, never splice
/// one together (every banned phrase joins its words with a single space).
/// An unterminated fence is left as-is (its content stays scannable —
/// fail-closed), and inline spans never cross a newline.
///
/// PUBLIC because the DOCS committee (`docs_committee.dart`) reads headings
/// from PROSE by the same rule — one definition, two readers.
String proseOnly(String spec) {
  final prose = StringBuffer();
  final fenceLines = RegExp(r'^[ \t]*(`{3,})([^`\r\n]*)\r?$', multiLine: true);
  var copiedThrough = 0;
  int? openerAt;
  int? openerLength;

  for (final fence in fenceLines.allMatches(spec)) {
    final runLength = fence.group(1)!.length;
    if (openerAt == null) {
      openerAt = fence.start;
      openerLength = runLength;
      continue;
    }
    final suffix = fence.group(2)!;
    if (runLength < openerLength! || suffix.trim().isNotEmpty) continue;

    prose
      ..write(spec.substring(copiedThrough, openerAt))
      ..write('  ');
    copiedThrough = fence.end;
    openerAt = null;
    openerLength = null;
  }
  prose.write(spec.substring(copiedThrough));

  return prose
      .toString()
      .replaceAll(RegExp(r'^[ \t]*>.*$', multiLine: true), '  ')
      .replaceAll(RegExp(r'`[^`\n]*`'), '  ');
}

/// The body of the section whose `## ` heading starts at [headingAt] — the
/// text after the heading line up to the next `## ` heading (or the end).
///
/// PUBLIC for the same reason as [proseOnly]: `changeShapeOf` reads the bead's
/// `## Touches` body with it.
String sectionBodyAt(String design, int headingAt) {
  final afterHeading = design.indexOf('\n', headingAt);
  if (afterHeading < 0) return '';
  final next = design.indexOf('\n## ', afterHeading);
  return design.substring(afterHeading, next < 0 ? design.length : next);
}
