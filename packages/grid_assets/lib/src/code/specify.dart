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
/// MANDATORY `## ADR Alignment` (query the ROSTER UNION of every mounted
/// substation's register via `decisions index` and cite load-bearing
/// clauses), and
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
///  - `coherence` / `decision-alignment` / `acceptance-testability` /
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

import '../agent/acp_session_adapter.dart';
import '../agent/agent_domain.dart';
import '../agent/agent_environment.dart';
import '../agent/agent_harness.dart';
import '../agent/agent_session.dart';
import '../agent/environment_registry.dart';
import '../agent/model_tier.dart';
import '../agent/seat_environments.dart';
import '../agent/site_binding.dart';
import '../agent/typed_environment.dart';
import '../agent/usage_report.dart';
import '../assets/overlay_materializer.dart' show kDefaultOverlayRunner;
import 'committee.dart';
import 'committee_selection.dart';
import 'conventional_commit.dart' show lintConventionalSubject;
import 'decision_register.dart';
import 'discovery.dart';
// The pack's ONE citation-path reader. `docs_committee.dart` imports this
// library in turn — the same two-way seam `committee.dart` already has here.
import 'docs_committee.dart' show normalizeCitedPath;
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
  'decision-alignment',
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
///
/// Every criterion is an ADDRESSABLE record ([kAcceptanceRecordForm]), because
/// the id is what [kValidationRecordForm] maps onto.
const String kSpecExemplarAcceptance = '''
- [ ] AC-1 — `Heartbeat.parse` returns a frame for a well-formed peer line
- [ ] AC-2 — `Heartbeat.parse` throws `FormatException` on an empty frame''';

/// The design half of that exemplar — one complete step in the ordinal-heading
/// shape, all four sections, every element the four LLM lanes look for, and
/// every RECORD form the deterministic gate parses.
///
/// The step carries the five labeled fields ([kStepFieldLabels]) and NO fenced
/// implementation block: a code block is optional EVIDENCE, and an exemplar
/// that shipped one taught the opposite.
String specExemplarDesign({String runner = kDefaultOverlayRunner}) =>
    '''
## Implementation Plan

### Step 1 — Add the `Heartbeat` frame

Paths: `packages/grid_assets/lib/src/bus/heartbeat.dart`, `packages/grid_assets/test/heartbeat_test.dart`
Change: a `Heartbeat` value carrying `peerId`, with a `Heartbeat.parse` factory
that refuses an empty frame LOUDLY — it throws `FormatException` and never
returns null. One probe per acceptance id covers the two paths.
Test: `cd packages/grid_assets && dart test test/heartbeat_test.dart`
Expect: `All tests passed!`
Commit: `feat(bus): add the peer heartbeat frame`

## Touches
- `packages/grid_assets/lib/src/bus/heartbeat.dart` — created; `Heartbeat`, `Heartbeat.parse`
- `packages/grid_assets/test/heartbeat_test.dart` — created; one probe per acceptance id

Re-validated against the live tree: `Heartbeat` has no caller yet and no sibling
bead adds one.

## ADR Alignment
${noGoverningDecisionSentence(runner: runner)} Queried: `power_station/packages/grid_assets/lib/src/bus/heartbeat.dart`, `power_station/packages/grid_assets/test/heartbeat_test.dart`.

## Validation Plan
- [ ] AC-1 → `cd packages/grid_assets && dart test test/heartbeat_test.dart` → `All tests passed!`
- [ ] AC-2 → `cd packages/grid_assets && dart test test/heartbeat_test.dart` → `All tests passed!`''';

/// The DEFAULT-runner rendering of [specExemplarDesign] — the exemplar the
/// structural round-trip fence grades.
final String kSpecExemplarDesign = specExemplarDesign();

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

/// [kStepFieldLabels] as one backticked line — the brief names EVERY labeled
/// line a step must carry, in the order the parser reads them, so the gate can
/// never require a field the brief did not teach.
final String _stepFieldLabelLine = kStepFieldLabels
    .map((label) => '`$label:`')
    .join(', ');

/// The PHASE boundary, in one sentence, written into the brief
/// ([kSpecStructuralContract]), the packaged `spec-validation` rubric and the
/// decision that ratified the grammar alike — so no surface can read the record
/// rules as live while another reads them as measured.
const String _specContractShadowBoundary =
    'Record-contract findings are shadow-only until an explicit activation '
    'ruling; the five presence and placeholder checks remain the live A/F '
    'gate, and all five committee lanes remain unconditional.';

/// The EXACT structural contract taught to the specify agent, in the words it
/// reads. Items 1–5 are enforced by [specStructuralFindings]; items 6–10 are
/// parsed by [parseSpecContract] in shadow measurement only. [buildSpecifyBrief]
/// renders this string VERBATIM, so neither phase can hide a rule from the
/// architect.
///
/// The shipped exemplar is round-tripped through both readings in test: it
/// passes [specStructuralFindings] and parses without a record finding.
String specStructuralContract({String runner = kDefaultOverlayRunner}) =>
    '''
### The structural contract (a DETERMINISTIC gate, run before any critic reads your spec)

`spec-validation` is not a critic and holds no opinion. Its live A/F result is
the five presence and placeholder checks in items 1–5:

1. **Acceptance** carries at least one `- [ ]` checkbox line.
2. **The design carries all four `## ` headings**, spelled exactly:
   `## Implementation Plan`, `## Touches`, `## ADR Alignment`,
   `## Validation Plan` — each OPENING ITS OWN LINE. A heading NAMED inside a
   sentence ("the machine gate is the fast subset — see `## Validation Plan`")
   is a MENTION: it neither satisfies this rule nor displaces the real section
   further down. Backtick any heading you name in running prose.
3. **`## Implementation Plan` carries NUMBERED steps.** Every step opens with an
   ordinal — an ordered-list item (`1. …` / `1) …`) or an ordinal heading
   (`### Step 1 — …` / `### 1. …`). A bulleted or prose-only plan has no ordinal
   and FAILS however complete it is. Steps carrying fenced code read best as
   `### Step N — …` headings.
4. **`## Validation Plan` carries at least one `- ` item.**
5. **No placeholder token in PROSE.** These exact tokens, case-insensitively:
   $_bannedTokenLine.

$_specContractShadowBoundary

Items 6–10 are the strict record grammar measured over the retained corpus by
`spec_contract_shadow.dart`; they do not affect `SpecValidationCapability`'s
grade before that ruling:

6. **Every acceptance criterion is an ADDRESSABLE record**:
   `$kAcceptanceRecordForm` — ids UNIQUE and CONTIGUOUS from `AC-1`. The id is
   what the validation plan maps onto.
7. **Every implementation step carries five LABELED lines**, each opening its
   own line: $_stepFieldLabelLine. `Change:` states the BEHAVIOUR and INVARIANT
   a zero-context builder must produce; a fenced code block beside it is
   optional EVIDENCE, never a required field. `Paths:` cites backticked
   REPO-RELATIVE paths (no leading `/`, no `..`); `Commit:` is a
   conventional-commit subject. The step opener is `$kStepRecordForm`, and the
   ordinal-list openers rule 3 names still count.
8. **Every `## Touches` item is** `$kTouchRecordForm` — exactly ONE
   repo-relative backticked path and one disposition word.
9. **Every `## ADR Alignment` item is** `$kDecisionRecordForm`, whose citation
   resolves as `<repo>#<slug>`, a `docs/decisions/` or `docs/adr/` path, or a
   legacy `ADR-<nnnn>` id. The section is NEVER silent about the lookup: when
   the roster union is empty for every queried surface, write
   "${noGoverningDecisionSentence(runner: runner)}"; when the lookup FAILED or
   exited non-zero, write "${failedDecisionLookupSentence(runner: runner)}" — an
   unknown union is not an empty one, and a crashed index is never graded clean.
10. **Every `## Validation Plan` item is** `$kValidationRecordForm`, exactly
   ONCE for every acceptance id and NEVER for an id no criterion declares.

Headings and ordinals are read from PROSE, and so are those tokens: markdown
QUOTATION is exempt (fenced blocks, `inline code` spans, `>` blockquote lines).
A token you QUOTE as evidence — a comment your plan deletes, a gate note cited
verbatim — points at work rather than deferring it, so backtick any banned token
you must name. The same cuts the other way: a `## Touches` heading that exists
only inside a code block is evidence, not a section.

Below is a COMPLETE spec that passes the live gate and parses clean under the
shadow grammar. Copy its SHAPE.

`````markdown
$kSpecExemplarAcceptance

${specExemplarDesign(runner: runner)}
`````''';

/// The DEFAULT-runner rendering of [specStructuralContract].
final String kSpecStructuralContract = specStructuralContract();

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
    // The DECISION lane
    // (`power_station#the-spec-decision-lane-queries-the-roster-union`): it
    // queries the composing station's ROSTER-MODE `decisions index` — the
    // UNION of every mounted substation's register — not this repo's
    // `docs/adr/`. Step id and rubric id MUST stay equal: the route joins a
    // lane by reading `.grid/critique/<id>.json` at `<parent>/<id>`. A
    // survivor mid-`spec_review` finds no cursor key here, which the frontier
    // reads as `pending`: the lane simply re-runs, and a read-only critic
    // re-grading is harmless (A16 guards spec-phase RE-ENTRY for a bead
    // already mid-BUILD, which this cannot cause). The FROZEN shapes in
    // `circuit_migration.dart` keep the superseded lane's literal ids and its
    // local-only rubric, and retire with that file.
    CapabilityStep(
      stepId: 'decision-alignment',
      capabilityId: 'spec-critic',
      params: {'rubric': 'decision-alignment'},
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
    // The SHADOW committee selector (bead `pow-1nl.1.1`) — a NON-AUTHORITATIVE
    // sibling of the spec lanes. It joins on the hygiene wipe alone (the same
    // round-freshness dependency every lane has) and NOTHING joins on it, so
    // the route decides over the full committee exactly as before. It reads the
    // round-stamped discovery artifacts, never `.grid/critique`.
    CapabilityStep(
      stepId: kCommitteeSelectionStep,
      capabilityId: kCommitteeSelectionStep,
      dependsOn: {kClearCritiqueStep},
      params: {
        kCommitteeSelectionStageParam: 'spec_review',
        kCommitteeFullRubricsParam:
            'spec-validation,coherence,decision-alignment,'
            'acceptance-testability,plan-completeness',
        kCommitteeGatingRubricsParam: kSpecGatingRubric,
      },
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
        'decision-alignment',
        'acceptance-testability',
        'plan-completeness',
      },
      params: {
        'critics':
            'spec-validation,coherence,decision-alignment,'
            'acceptance-testability,plan-completeness',
        'gating': kSpecGatingRubric,
        // The stage the SHADOW receipt is filed under (bead `pow-1nl.1.1`);
        // this route's matrix never reads it.
        kCommitteeSelectionStageParam: 'spec_review',
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
/// The spec author declares the **FRONTIER tier** ([AgentTier.frontier]): it
/// writes the spec two independent builds must converge on, so it rides
/// [kFrontierModelDefault] (`opus`) by default. Its ENVIRONMENT comes from the
/// [SpecAgentEnvironment] seat (ADR-0006 D2/D5, bead `pow-n6n.4`), which folded
/// `pow-t1w`'s architect role. Auto-respec re-enters this same capability and
/// therefore rides the same seat.
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
/// One resolved specify spawn — the ambient values read with the effect verb at
/// the spawn edge (ADR-0008 D3), shared by `spawn` and `createSession`.
typedef _ResolvedSpecifyRun = ({
  AgentEnvironment environment,
  Workspace workspace,
  AgentBrief brief,
  String? model,
  Uri? endpoint,
});

class SpecifyCapability extends ProcessCapability {
  /// Creates the specify capability.
  ///
  /// [runnerFor] is the bd subprocess seam used only for the durable read-back;
  /// production composes [ProcessBdRunner], while tests inject a fake
  /// [BdRunner].
  ///
  /// [sessionAdapters] and [steers] are the CHANNEL seams — this seat is armed
  /// on a channel harness as readily as the build seat is (bead `pow-39tl`), so
  /// it carries the same two injected collaborators.
  ///
  /// [decisionRunner] is the COMPOSING STATION's verb, threaded into every
  /// decision-lookup line the brief renders (`buildCodeRegistry` binds it from
  /// `overlayArgs['runner']`). Absent ⇒ the first-party [kDefaultOverlayRunner].
  const SpecifyCapability({
    BdRunner Function(String workspaceRoot) runnerFor = _processRunnerFor,
    AgentSessionAdapterRegistry sessionAdapters = kBuiltinAgentSessionAdapters,
    AgentSteerSource steers = const NoAgentSteerSource(),
    String decisionRunner = kDefaultOverlayRunner,
  }) : _runnerFor = runnerFor,
       _sessionAdapters = sessionAdapters,
       _steers = steers,
       _decisionRunner = decisionRunner;

  final BdRunner Function(String workspaceRoot) _runnerFor;
  final AgentSessionAdapterRegistry _sessionAdapters;
  final AgentSteerSource _steers;
  final String _decisionRunner;

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

  /// Reads the ambient values at ENTRY (synchronously, while mounted) and
  /// renders this incarnation's environment, brief, model and endpoint — shared
  /// by [spawn] and [createSession], so the argv leg and the channel leg can
  /// never disagree about what this seat resolved.
  ///
  /// GUARD, LOUD: a missing ambient [Bead]/[Workspace] throws, which
  /// `ProcessAllocation` routes to supervision as a per-work `Failed`.
  _ResolvedSpecifyRun _resolveRun(TreeContext context, StepArgs args) {
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
      tier: AgentTier.frontier,
      ambient: ambient,
      beadMetadata: bead.metadata,
      stepParams: args.params,
      registry: registry,
      // Rung 4.5 - the SPEC seat (ADR-0006 D2). Read with the effect verb at the
      // spawn edge; null (nothing mounted, or nothing preferred present) simply
      // falls to the ambient harness below.
      typedEnvironment: resolveEnvironment<SpecAgentEnvironment>(context),
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
    return (
      environment: environment,
      workspace: workspace,
      brief: buildSpecifyBrief(
        bead,
        workspace,
        guidance: guidance,
        dossier: dossier,
        runner: _decisionRunner,
      ),
      model: config.params['model'],
      endpoint: siteBinding.endpointFor(
        name: config.harness,
        environment: environment,
      ),
    );
  }

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) {
    final run = _resolveRun(context, args);
    // HARNESS-NEUTRAL (bead `pow-39tl`): a channel environment launches through
    // its session adapter and receives the brief over the protocol; an argv
    // environment renders it into argv. Calling `spawnFor` directly is what
    // spawned an ACP server as a one-turn process with an EMPTY prompt segment
    // (`PromptMode.none`), so the brief was never delivered and the seat made
    // no forward progress past discovery.
    return spawnThroughSessionAdapter(
      adapters: _sessionAdapters,
      environment: run.environment,
      brief: run.brief,
      workspace: run.workspace,
      model: run.model,
      endpoint: run.endpoint,
      // CAPTURE-ONLY usage telemetry (FT-2), same as the build agent.
      usageOut: usageReportPath(args.nodePath),
    );
  }

  /// The CHANNEL leg of the same seat. Null for an argv environment (the
  /// engine's one-turn dispatch owns it, including the artifact fence).
  ///
  /// The completion contract this capability DECLARES is re-applied here,
  /// because the engine's dispatcher fence is unreachable on the session path —
  /// see [ArtifactFencedSession]. This stage also stays READ-ONLY on the tree
  /// (A13(6)): unlike [AgentCapability.createSession] it materializes no pub
  /// linkage and no station overlay — the architect greps and writes the bead.
  @override
  ProcessSession? createSession({
    required RuntimeProvider runtime,
    required String name,
    required String attemptId,
    required String instanceFence,
    required TreeContext context,
    required StepArgs args,
  }) {
    final run = _resolveRun(context, args);
    final adapterId = run.environment.sessionAdapter;
    if (adapterId == null) return null;
    return ArtifactFencedSession(
      inner: AgentSession(
        runtime: runtime,
        name: name,
        adapter: _sessionAdapters.require(adapterId),
        brief: run.brief,
        commands: _steers.watch(args.beadId),
        attemptId: attemptId,
        instanceFence: instanceFence,
      ),
      probe: () => probeCompletionArtifact(context, args),
      resultFields: () => result(context, args),
      verb: kSpecifyStep,
      adapter: adapterId,
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
    // The spec seat is the codex-armed one: without the ambient price table
    // its cost is null and the lane leaves the spend report entirely.
    final prices =
        (context.getInheritedSeedOfExactType<AgentConfig>() ??
                const AgentConfig())
            .modelPrices;
    final fields = <String, String>{
      ...readUsageFields(
        workspace.workspaceDir,
        args.nodePath,
        modelPrices: prices,
        flare: context
            .getInheritedSeedOfExactType<ServiceBundle>()
            ?.transport
            ?.flare,
      ),
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
  String runner = kDefaultOverlayRunner,
}) {
  final title = bead.title.isNotEmpty ? bead.title : 'work bead ${bead.id}';
  final substation = bead.metadata['rig'];
  final id = bead.id;
  final lookupBlock = rosterDecisionLookupBlock(
    rosterQualifiedSurfaces(
      design: bead.design,
      substation: substation is String ? substation : '',
    ),
    runner: runner,
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
      'context can follow. EVERY step opens with an ordinal and carries the '
      'five labeled lines the structural contract names '
      '($_stepFieldLabelLine). `Paths:` is the exact file path from the repo '
      'root (backticked); `Change:` states the BEHAVIOUR and INVARIANT the '
      'builder must produce, in the memento house set (freezed sealed unions '
      'consumed with exhaustive `switch`, Fakes not mocks, no `print` in lib '
      'code); `Test:` is the exact test command and `Expect:` its expected '
      'output (`dart test test/<file>_test.dart` → expect PASS); `Commit:` is '
      'a conventional-commit message. A fenced Dart block beside `Change:` is '
      'optional EVIDENCE where the exact text matters — write one when it '
      'earns its space, never as a required field. When the plan touches '
      'genesis_tree / grid code, spec it to the D-H doctrine (ADR-0008): '
      'watch deps in `build` via `dependOn*`; no public synchronous accessor '
      'over `StateNotifier` state; config = VALUES in the tree, impls = DI; '
      'guards LOUD or GONE. No placeholders: the structural contract below '
      'enumerates every banned token, and a spec that defers its own content '
      'is F-gated.',
    )
    ..writeln()
    ..writeln(
      '**## Touches** — one item per file the plan creates or modifies, in '
      'the record form: `$kTouchRecordForm`. EXACTLY one repo-relative '
      'backticked path per item, then what happens to it, then the public '
      'symbols it adds or exposes as bare backticked names (`Heartbeat`, '
      '`Heartbeat.parse`) — a second path in the same item is a second item. '
      'Sibling beads cross-check shared state against this section.',
    )
    ..writeln()
    ..writeln(
      '**## ADR Alignment** — MANDATORY. ${decisionLookupRule(runner: runner)} '
      'For the surfaces this bead already names that is:',
    )
    ..writeln()
    ..writeln('```sh')
    ..writeln(lookupBlock)
    ..writeln('```')
    ..writeln()
    ..writeln(
      'Re-run the block over the FINAL `## Touches` you write. '
      '$kDecisionWriteRule '
      'Quote each load-bearing decision and say how the plan aligns. The '
      'section is NEVER silent about the lookup itself: if the union is empty '
      'for every queried surface, write exactly: '
      '${noGoverningDecisionSentence(runner: runner)} If the lookup FAILED '
      'or exited non-zero, that is NOT an empty union — write exactly: '
      '${failedDecisionLookupSentence(runner: runner)}',
    )
    ..writeln()
    ..writeln(
      '**## Validation Plan** — one item per acceptance criterion, mapped '
      '1:1 BY ID: `$kValidationRecordForm`. No gaps and no strays — every '
      'criterion is validated exactly once, and no item names an id no '
      'criterion declares.',
    )
    ..writeln()
    ..writeln(specStructuralContract(runner: runner))
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
/// automatically holds here. Only the SPAWN differs — it declares the MID tier
/// ([AgentTier.mid]), like its superclass, so absent an override it grades on
/// [kMidModelDefault] (`sonnet`); and a spec
/// critic is always an agent (there is no `sh -c` validation-runner flavor; the
/// spec gate is [SpecValidationCapability]) and its prompt is
/// [buildSpecCriticPrompt]: the review subject is the bead's SPEC, never a
/// pinned diff (no code exists yet).
class SpecCriticCapability extends CriticCapability {
  /// Creates the spec critic, optionally over a rubric source (D-9 wires
  /// the Packaged-AI-Asset loader; absent ⇒ an inline placeholder so the
  /// circuit is testable with no real assets).
  ///
  /// [decisionRunner] is the COMPOSING STATION's verb, threaded into every
  /// decision-lookup line this prompt renders (`buildCodeRegistry` binds it from
  /// `overlayArgs['runner']`, and binds the injected rubric source's own
  /// `{{runner}}` hole from the same value). Absent ⇒ [kDefaultOverlayRunner].
  const SpecCriticCapability({
    super.rubrics,
    super.verdictTextReader,
    String decisionRunner = kDefaultOverlayRunner,
  }) : _decisionRunner = decisionRunner;

  final String _decisionRunner;

  /// The SPEC family IS held to the owner column (bead `pow-hxme`, ADR-0000
  /// A37): its route decides on ownership, and [buildSpecCriticPrompt] teaches
  /// it below.
  @override
  bool get requiresVerdictOwner => true;

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
    // Same incarnation stamp as the code committee: the spec lanes are where
    // contaminated rounds have been observed in live review sessions.
    recordCriticIncarnation(
      workspaceDir: workspace.workspaceDir,
      rubric: rubric,
    );
    final ambient =
        context.getInheritedSeedOfExactType<AgentConfig>() ??
        const AgentConfig();
    final registry =
        context.getInheritedSeedOfExactType<EnvironmentRegistry>() ??
        buildBuiltinEnvironmentRegistry();
    final siteBinding =
        context.getInheritedSeedOfExactType<SiteBinding>() ?? SiteBinding.none;
    final config = resolveAgentConfig(
      tier: AgentTier.mid,
      ambient: ambient,
      beadMetadata: bead.metadata,
      stepParams: args.params,
      registry: registry,
      typedEnvironment: CriticAgentEnvironment.of(
        context,
        lane: CriticLane(rubric),
      ),
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
    final rig = bead.metadata['rig'];
    final lookupBlock = rosterDecisionLookupBlock(
      rosterQualifiedSurfaces(
        design: bead.design,
        substation: rig is String ? rig : '',
      ),
      runner: _decisionRunner,
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
        'announced as new is a finding, not a style nit). '
        '${decisionLookupRule(runner: _decisionRunner)}',
      )
      ..writeln()
      ..writeln('```sh')
      ..writeln(lookupBlock)
      ..writeln('```')
      ..writeln()
      ..writeln(
        '$kDecisionWriteRule '
        'A spec that appends an `A<n>` amendment to ADR-0000 has DEPARTED '
        'from that rule — say so under `decision-alignment`. Check the '
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
        verdictJsonTemplate(
          rubric: rubric,
          nodePath: nodePath,
          round: round,
          owner: true,
          refinement: true,
        ),
      )
      ..writeln()
      ..writeln(kVerdictStampInstruction)
      ..writeln()
      ..writeln(kVerdictOwnerInstruction)
      ..writeln()
      ..writeln(kVerdictRefinementInstruction)
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
/// **Shadow measurement, not a second live gate level:** [parseSpecContract]
/// reads the line-oriented records into [SpecContract] and returns typed,
/// source-located findings without repair. Those findings are consumed by
/// `spec_contract_shadow.dart`; they do not enter this capability's grade
/// before an explicit activation ruling. All four semantic critics remain
/// unconditional because test proof, plan coherence, and decision
/// interpretation remain inference.
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
/// What the structure check does NOT judge — whether a named command actually
/// PROVES its criterion, whether the plan is COHERENT, whether a resolvable
/// decision is INTERPRETED correctly — is exactly what the four LLM lanes own.
/// Structure and referential integrity are represented and measured in code but
/// do not route in this phase; the residue is inference, and reading a `Test:`
/// line is not the same as knowing it can fail.
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
///
/// The three ordinals are CAPTURED (and nothing else changed) so
/// [parseSpecContract] can read a step's number without a second grammar: the
/// accepted language is byte-for-byte the one already ratified, because WHICH
/// openers count is settled and only what a step CONTAINS is newly graded.
final RegExp _numberedStep = RegExp(
  r'^[ \t]*(?:'
  r'(\d+)[.)]\s' // 1. …  /  1) …
  r'|#{1,6}[ \t]*(?:step[ \t]*)?(\d+)\b' // ### Step 1 — …  /  ### 1. …
  r'|\*\*[ \t]*(?:step[ \t]*)?(\d+)\b' // **Step 1:** …  /  **1.** …
  r')',
  multiLine: true,
  caseSensitive: false,
);

/// The LIVE structural findings for [bead]'s spec — empty iff the five
/// presence and placeholder checks pass. Pure and exposed for unit tests;
/// [SpecValidationCapability] grades A iff this returns empty. Each finding
/// names what is missing (guards LOUD), and every existing finding string is
/// byte-unchanged.
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
  final hasCheckboxes = RegExp(
    r'^\s*-\s*\[[ xX]\]\s*\S',
    multiLine: true,
  ).hasMatch(acceptance);
  if (!hasCheckboxes) {
    findings.add('acceptance: no testable `- [ ]` checkbox criteria');
  }

  // The four design sections. Each heading is resolved at a LINE START
  // ([headingOffset]): a sentence that NAMES `## Validation Plan` is a MENTION,
  // and a mention neither satisfies the gate nor displaces the real section
  // further down (bead `pow-o3ti`).
  final planAt = headingOffset(structure, '## Implementation Plan');
  final hasNumberedSteps =
      planAt >= 0 && _numberedStep.hasMatch(sectionBodyAt(structure, planAt));
  if (planAt < 0) {
    findings.add('design: no `## Implementation Plan` section');
  } else if (!hasNumberedSteps) {
    findings.add(
      'design: `## Implementation Plan` has no numbered steps — every step '
      'must open with an ordinal (`1.` / `1)` list items, or `### Step 1 — …` '
      'headings)',
    );
  }
  final touchesAt = headingOffset(structure, '## Touches');
  if (touchesAt < 0) {
    findings.add('design: no `## Touches` section');
  }
  final decisionsAt = headingOffset(structure, '## ADR Alignment');
  if (decisionsAt < 0) {
    findings.add('design: no `## ADR Alignment` section');
  }
  final validationAt = headingOffset(structure, '## Validation Plan');
  final hasValidationItems =
      validationAt >= 0 &&
      RegExp(
        r'^\s*-\s*\S',
        multiLine: true,
      ).hasMatch(sectionBodyAt(structure, validationAt));
  if (validationAt < 0) {
    findings.add('design: no `## Validation Plan` section');
  } else if (!hasValidationItems) {
    findings.add('design: `## Validation Plan` has no items');
  }

  // Record-contract findings are SHADOW ONLY until an explicit activation
  // ruling. `parseSpecContract` is invoked by `spec_contract_shadow.dart`, not
  // appended to this live A/F list.

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
/// LINE-COUNT PRESERVING, and that is a NAMED invariant: `proseOnly(s)` has
/// exactly as many lines as `s`. Every seam gives back the newlines it blanked
/// (the blockquote and inline-span strips are single-line replacements; the
/// fence strip pads explicitly), so an offset into the stripped text maps to
/// the AUTHORED line and [parseSpecContract] can name the line a record is on.
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
      ..write('  ')
      // LINE-COUNT PRESERVING: the blanked region gives back the newlines it
      // swallowed, so an offset into the stripped text maps to the AUTHORED
      // line and a record finding can name it. The two-space seam still LEADS,
      // so stripping can only break a token across it, never splice one
      // together.
      ..write(
        '\n' * '\n'.allMatches(spec.substring(openerAt, fence.end)).length,
      );
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

/// The section whose `## ` heading starts at [headingAt]: its [start] offset in
/// [design] and its [body] — the text after the heading line up to the next
/// `## ` heading (or the end).
///
/// The SOURCE-LOCATED form of [sectionBodyAt], which is now one line over it.
/// [parseSpecContract] needs the offset to turn a body-local match into the
/// document line a record is authored on, without recomputing the body's start.
({int start, String body}) sectionAt(String design, int headingAt) {
  final afterHeading = design.indexOf('\n', headingAt);
  if (afterHeading < 0) return (start: design.length, body: '');
  final next = design.indexOf('\n## ', afterHeading);
  final end = next < 0 ? design.length : next;
  return (start: afterHeading, body: design.substring(afterHeading, end));
}

/// The body of the section whose `## ` heading starts at [headingAt] — the
/// text after the heading line up to the next `## ` heading (or the end).
///
/// PUBLIC for the same reason as [proseOnly]: `changeShapeOf` reads the bead's
/// `## Touches` body with it.
String sectionBodyAt(String design, int headingAt) =>
    sectionAt(design, headingAt).body;

/// The 1-based line of [offset] in [text] — the ONE line-number reckoning, so
/// every [SpecContractFinding] counts the same way, and the only place a line
/// number is computed.
int lineOf(String text, int offset) =>
    1 + '\n'.allMatches(text.substring(0, offset.clamp(0, text.length))).length;

/// The offset of the heading LINE that opens [heading]'s section in [design],
/// or `-1` when there is none — the LAST match when several exist.
///
/// A heading is markdown STRUCTURE, so it is resolved at a LINE START. A
/// substring search is not, and that is the defect this replaces: it takes a
/// prose SENTENCE that NAMES the heading (`... the full house gate (see ##
/// Validation Plan).`) for the section itself, anchors [sectionBodyAt] at that
/// sentence, reads the following paragraph as the body, and hard-blocks a whole
/// spec on `has no items` while the real section, further down, carries ten
/// (bead `pow-o3ti`, receipt space-3ds 2026-09-03).
///
/// LAST, not first. Callers pass [proseOnly] output, so a heading quoted in a
/// TERMINATED fence, a `>` blockquote or an inline span is already blanked; what
/// survives is an UNTERMINATED fence, whose tail [proseOnly] leaves scannable by
/// design. This pack's own specs quote the four canonical headings inside their
/// `## Implementation Plan`, ABOVE the sections they name, so taking the LAST
/// line-anchored match is what keeps a quotation from displacing the authored
/// section in exactly the case that survives the strip.
///
/// As permissive as the `indexOf` it replaces on every axis but two: the line
/// start, and 0-3 spaces of indentation (4+ is an indented code block, i.e.
/// quotation). Any level `##`…`######` still resolves (a substring search for
/// `## X` matches inside `### X` today, and a spec that writes `### Touches`
/// must not newly park), as does any trailing text on the heading line
/// (`## Validation Plan (1:1)`) and any spacing after the hashes.
///
/// PUBLIC for the same reason as [proseOnly] and [sectionBodyAt]: the code
/// committee's declaration headings resolve through this one definition too.
int headingOffset(String design, String heading) {
  final title = heading.replaceFirst(RegExp(r'^#+[ \t]*'), '');
  final matches = RegExp(
    r'^[ \t]{0,3}#{2,6}[ \t]*' + RegExp.escape(title),
    multiLine: true,
  ).allMatches(design).toList();
  return matches.isEmpty ? -1 : matches.last.start;
}

// ---------------------------------------------------------------------------
// The RECORD grammar — the deterministic contract one level below the
// section-PRESENCE checks above.
//
// The record FORMS are constants because [kSpecStructuralContract] interpolates
// them and the parser's doc comments quote them: one edit moves the brief and
// the gate together, which is the "a gate whose contract the brief does not
// state is a trap" rule applied to the new rules.
// ---------------------------------------------------------------------------

/// The acceptance-criterion record form — an addressable, stable id per
/// criterion, so the validation plan can map onto it BY NAME.
const String kAcceptanceRecordForm = '- [ ] AC-<n> — <criterion>';

/// The implementation-step record form. The ordinal-LIST openers already
/// accepted (`1. …` / `1) …` / `**Step 1:** …`) still parse as steps; this is
/// the shape the brief TEACHES, because a step carrying a fenced block must
/// take it.
const String kStepRecordForm = '### Step <n> — <title>';

/// The labeled lines every implementation step carries, in brief order.
///
/// `Change:` states the BEHAVIOUR/INVARIANT the builder must produce. A fenced
/// code block is optional EVIDENCE beside it, never a required field: making
/// the architect pre-write the implementation duplicates the most expensive
/// output in the circuit and bloats every later context.
const List<String> kStepFieldLabels = [
  'Paths',
  'Change',
  'Test',
  'Expect',
  'Commit',
];

/// The `## Touches` record form — one repo-relative backticked path, one
/// disposition, then the symbols the item adds or exposes.
const String kTouchRecordForm =
    '- `<repo-relative/path>` — <created|modified|deleted|renamed>; <symbols>';

/// The `## ADR Alignment` record form. RESOLUTION is deterministic (the
/// citation is an identity the roster index can answer, and the disposition is
/// a declared word); INTERPRETATION stays the `decision-alignment` lane's.
const String kDecisionRecordForm =
    '- `<repo>#<slug>` — <applied|extended|updated|superseded>: <clause>';

/// The `## Validation Plan` record form — the restatement is optional; the id
/// is what carries the mapping.
const String kValidationRecordForm =
    '- [ ] AC-<n>[ — <restatement>] → `<command>` → <expected>';

/// What a `## Touches` item declares happened to its path.
enum TouchDisposition {
  /// The path is created by this bead.
  created,

  /// The path exists and this bead edits it.
  modified,

  /// The path is removed by this bead.
  deleted,

  /// The path is moved or renamed by this bead.
  renamed,
}

/// What a `## ADR Alignment` item declares about its cited decision.
enum DecisionDisposition {
  /// The plan implements the decision as recorded.
  applied,

  /// The plan extends the decision without contradicting it.
  extended,

  /// The plan records a change to the decision.
  updated,

  /// The plan replaces the decision with a new entry.
  superseded,
}

/// What a spec's `## ADR Alignment` section declares about the roster LOOKUP
/// itself — the distinction
/// `power_station#the-spec-decision-lane-queries-the-roster-union` (3) makes
/// load-bearing: "An empty union is a real result; a CRASHED lookup is not. A
/// lookup that fails or exits non-zero must be reported verbatim and never
/// graded clean."
///
/// The grammar therefore types all three outcomes rather than collapsing a
/// crash into a vacuous citation-less section: an empty union and an unknown
/// union are different results, and only one of them means "nothing governs
/// these surfaces".
enum DecisionLookupNarrative {
  /// The section cites recorded decisions and makes no claim about the lookup.
  cited,

  /// The union was EMPTY for every queried surface
  /// ([kNoGoverningDecisionPrefix]) — a real result.
  emptyUnion,

  /// The lookup FAILED and the section reports it verbatim
  /// ([kFailedDecisionLookupPrefix]). Citations are not REQUIRED — the union is
  /// UNKNOWN, not empty — but the section is never silent about why.
  failedLookup,
}

/// One `- [ ] AC-<n> — <criterion>` record.
class AcceptanceCriterion {
  /// Creates a criterion record.
  const AcceptanceCriterion({
    required this.id,
    required this.text,
    required this.line,
  });

  /// The `<n>` in `AC-<n>`.
  final int id;

  /// The criterion prose after the separator.
  final String text;

  /// The 1-based line of the record in the acceptance field.
  final int line;
}

/// One implementation-step record and its five labeled fields.
class ImplementationStep {
  /// Creates a step record.
  const ImplementationStep({
    required this.ordinal,
    required this.title,
    required this.paths,
    required this.change,
    required this.testCommand,
    required this.expected,
    required this.commit,
    required this.line,
  });

  /// The step's ordinal, as written.
  final int ordinal;

  /// The title after the ordinal, `''` when the opener carries none.
  final String title;

  /// The repo-relative paths the `Paths:` field cites, in document order.
  final List<String> paths;

  /// The behaviour/invariant the step must produce.
  final String change;

  /// The `Test:` command.
  final String testCommand;

  /// The `Expect:` output.
  final String expected;

  /// The `Commit:` conventional-commit subject.
  final String commit;

  /// The 1-based line of the step's opener in the design field.
  final int line;
}

/// One `## Touches` record.
class Touch {
  /// Creates a touch record.
  const Touch({
    required this.path,
    required this.symbols,
    required this.disposition,
    required this.line,
  });

  /// The repo-relative path.
  final String path;

  /// The rest of the item after the disposition — the symbols it names.
  final String symbols;

  /// What the bead does to [path].
  final TouchDisposition disposition;

  /// The 1-based line of the record in the design field.
  final int line;
}

/// One `## ADR Alignment` record.
class DecisionCitation {
  /// Creates a citation record.
  const DecisionCitation({
    required this.reference,
    required this.disposition,
    required this.line,
  });

  /// The resolvable identity — `<repo>#<slug>`, a `docs/decisions/` or
  /// `docs/adr/` path, or a legacy `ADR-<nnnn>` id.
  final String reference;

  /// What the plan does with the decision.
  final DecisionDisposition disposition;

  /// The 1-based line of the record in the design field.
  final int line;
}

/// One `## Validation Plan` record.
class ValidationMapping {
  /// Creates a validation record.
  const ValidationMapping({
    required this.criterionId,
    required this.command,
    required this.expected,
    required this.line,
  });

  /// The `<n>` of the `AC-<n>` this item validates.
  final int criterionId;

  /// The exact command.
  final String command;

  /// The expected output.
  final String expected;

  /// The 1-based line of the record in the design field.
  final int line;
}

/// The typed projection of ONE spec's line-oriented records.
///
/// Only what the documented grammar RECOGNIZED lands here: a malformed record
/// contributes a [SpecContractFinding] and NOTHING to these lists, so no
/// downstream check ever reads a guessed value.
class SpecContract {
  /// Creates a contract projection.
  const SpecContract({
    required this.criteria,
    required this.steps,
    required this.touches,
    required this.citations,
    required this.decisionNarrative,
    required this.validations,
  });

  /// The acceptance records, in document order.
  final List<AcceptanceCriterion> criteria;

  /// The implementation-step records, in document order.
  final List<ImplementationStep> steps;

  /// The `## Touches` records, in document order.
  final List<Touch> touches;

  /// The `## ADR Alignment` records, in document order.
  final List<DecisionCitation> citations;

  /// What the `## ADR Alignment` section declares about the roster lookup —
  /// citations, an EMPTY union, or a FAILED one.
  final DecisionLookupNarrative decisionNarrative;

  /// The `## Validation Plan` records, in document order.
  final List<ValidationMapping> validations;
}

/// The spec sections [parseSpecContract] reads — the cascade's currency.
enum SpecContractSection {
  /// The bead's acceptance field.
  acceptance,

  /// `## Implementation Plan`.
  plan,

  /// `## Touches`.
  touches,

  /// `## ADR Alignment`.
  decisions,

  /// `## Validation Plan`.
  validation,
}

/// Every rule [parseSpecContract] can report — one rule, one finding, so a
/// single-rule fixture mutation fails with a single precise message.
enum SpecContractRule {
  /// A `- [ ]` acceptance line that is not [kAcceptanceRecordForm].
  acceptanceRecord,

  /// Two acceptance records declaring the same id.
  acceptanceIdDuplicate,

  /// The acceptance ids are not exactly `1..N`.
  acceptanceIdNotContiguous,

  /// A step opener carrying no title.
  stepTitle,

  /// A step missing one of [kStepFieldLabels].
  stepField,

  /// A `Paths:` field citing no repo-relative backticked path.
  stepPath,

  /// A `Commit:` field that is not a conventional-commit subject.
  stepCommit,

  /// A `## Touches` item without one repo-relative path and a disposition.
  touchRecord,

  /// A `## ADR Alignment` item without a resolvable citation + disposition.
  decisionRecord,

  /// A `## ADR Alignment` section that cites nothing and declares NEITHER an
  /// empty union NOR a failed lookup — a silent section, which is the one
  /// reading the roster-union decision forbids.
  decisionSectionSilent,

  /// A `## Validation Plan` item that is not [kValidationRecordForm].
  validationRecord,

  /// A validation item naming an id no acceptance record declares.
  validationUnknownCriterion,

  /// A criterion with no validation item, or one mapped more than once.
  validationCoverage,
}

/// One source-located deviation from the documented grammar.
class SpecContractFinding {
  /// Creates a finding.
  const SpecContractFinding({
    required this.rule,
    required this.field,
    required this.line,
    required this.message,
  });

  /// The rule this finding reports.
  final SpecContractRule rule;

  /// The bead field the line is in — `acceptance` or `design`.
  final String field;

  /// The 1-based line in [field].
  final int line;

  /// The LOUD message naming what is wrong and the form that is required.
  final String message;

  /// A stable human-readable rendering for shadow evidence, tests, and a future
  /// explicit activation ruling.
  String render() => '$field line $line: $message';
}

/// [raw] as a REPO-RELATIVE path, or null when it is not one.
///
/// Composes [normalizeCitedPath] — the pack's ONE citation-path reader — and
/// adds the two guards repo-relativity needs and citation does not: an ABSOLUTE
/// path and any `..` segment are refused.
String? repoRelativePathOf(String raw) {
  final cited = normalizeCitedPath(raw);
  if (cited == null) return null;
  if (cited.startsWith('/')) return null;
  if (cited.split('/').contains('..')) return null;
  return cited;
}

/// Whether [raw] is a citation identity the roster index can ANSWER: the
/// canonical `<repo>#<slug>`, a `docs/decisions/` or `docs/adr/` path, or a
/// legacy `ADR-<nnnn>` id (which a migrated entry still resolves by).
///
/// RESOLUTION only — whether the clause is READ correctly is the
/// `decision-alignment` lane's judgement, never this parser's.
bool isResolvableDecisionReference(String raw) {
  final token = raw.trim();
  if (RegExp(r'^[A-Za-z0-9_.-]+#[a-z0-9][a-z0-9-]*$').hasMatch(token)) {
    return true;
  }
  if (RegExp(r'^ADR-\d{4}\b').hasMatch(token)) return true;
  final path = repoRelativePathOf(token);
  return path != null &&
      (path.startsWith('docs/decisions/') || path.startsWith('docs/adr/'));
}

/// The separator a record may put between its id and its text.
const String _recordSeparator = r'(?:—|–|-|:)';

/// [kAcceptanceRecordForm], as a per-LINE matcher.
final RegExp _acceptanceRecord = RegExp(
  r'^[ \t]*-[ \t]*\[[ xX]\][ \t]*AC-(\d+)[ \t]*' +
      _recordSeparator +
      r'[ \t]*(\S.*)$',
);

/// Any `- [ ]` checkbox line — the SUPERSET [_acceptanceRecord] and
/// [_validationRecord] must match, so a checkbox that is not a record is a
/// named deviation rather than a silent omission.
final RegExp _checkboxLine = RegExp(r'^[ \t]*-[ \t]*\[[ xX]\][ \t]*(\S.*)$');

/// Any `- ` list item — the superset the section record forms must match.
final RegExp _listItem = RegExp(r'^[ \t]*-[ \t]+(\S.*)$');

/// [kValidationRecordForm], as a per-LINE matcher. `->` is taken for `→`, so
/// an ASCII keyboard is never a structural F.
final RegExp _validationRecord = RegExp(
  r'^[ \t]*-[ \t]*\[[ xX]\][ \t]*AC-(\d+)[ \t]*(?:' +
      _recordSeparator +
      r'[^\n]*?)?(?:→|->)[ \t]*`([^`\n]+)`[ \t]*(?:→|->)[ \t]*(\S.*)$',
);

/// A markdown inline `code` span.
final RegExp _backtickedSpan = RegExp(r'`([^`\n]+)`');

/// The `<label>:` line opening a step field — an optional `- ` bullet and
/// optional `**` bold are accepted decoration.
RegExp _stepFieldLine(String label) => RegExp(
  '^[ \\t]*(?:[-*][ \\t]*)?(?:\\*\\*)?${RegExp.escape(label)}(?:\\*\\*)?'
  '[ \\t]*:[ \\t]*',
);

/// Every step field label as one alternation — a field's VALUE ends where the
/// next label begins.
final RegExp _anyStepFieldLine = RegExp(
  '^[ \\t]*(?:[-*][ \\t]*)?(?:\\*\\*)?(?:${kStepFieldLabels.join('|')})'
  '(?:\\*\\*)?[ \\t]*:',
);

/// A markdown heading line — a field value never runs through one.
final RegExp _headingLine = RegExp(r'^[ \t]{0,3}#{1,6}[ \t]');

/// The disposition word a `## Touches` item declares.
final RegExp _touchDisposition = RegExp(
  r'\b(created|modified|deleted|renamed)\b',
  caseSensitive: false,
);

/// The disposition word a `## ADR Alignment` item declares.
final RegExp _decisionDisposition = RegExp(
  r'\b(applied|extended|updated|superseded)\b',
  caseSensitive: false,
);

/// One authored line the record grammar can SEE: its 1-based [line] in the
/// bead field and its RAW [text].
typedef _AuthoredLine = ({int line, String text});

/// The authored lines of `[from, to]` that the grammar SEES.
///
/// A line is invisible exactly when its [proseOnly] counterpart is blank —
/// i.e. it is markdown QUOTATION (a fenced block, a `>` blockquote, a line
/// that is nothing but `code` spans). That is the SAME rule the section-
/// presence checks read structure by, and it works line-for-line only because
/// [proseOnly] preserves the line count. The record's own text comes from the
/// RAW field, so a backticked command or path survives to be parsed.
List<_AuthoredLine> _authoredLines(
  List<String> raw,
  List<String> prose,
  int from,
  int to,
) => [
  for (var i = from < 1 ? 1 : from; i <= to && i <= raw.length; i++)
    if (prose[i - 1].trim().isNotEmpty) (line: i, text: raw[i - 1]),
];

/// The `- ` list ITEMS of [lines].
///
/// Each item is its opening line joined with every CONTIGUOUS following line
/// that is not itself a list item or a heading, because a markdown list item
/// INCLUDES its continuation: a record wrapped over two lines is one record,
/// and reading only its first line would report a disposition the author did
/// write. The item keeps its OPENING line number, which is where a reader
/// looks for it.
List<_AuthoredLine> _listItems(List<_AuthoredLine> lines) {
  final items = <_AuthoredLine>[];
  for (var i = 0; i < lines.length; i++) {
    if (!_listItem.hasMatch(lines[i].text)) continue;
    final text = StringBuffer(lines[i].text);
    var previous = lines[i].line;
    for (var j = i + 1; j < lines.length; j++) {
      if (lines[j].line != previous + 1) break;
      if (_listItem.hasMatch(lines[j].text)) break;
      if (_headingLine.hasMatch(lines[j].text)) break;
      text.write(' ${lines[j].text.trim()}');
      previous = lines[j].line;
    }
    items.add((line: lines[i].line, text: text.toString()));
  }
  return items;
}

/// The 1-based, inclusive line range of [heading]'s section BODY in [prose],
/// or null when the section is absent.
({int from, int to})? _sectionLineRange(String prose, String heading) {
  final at = headingOffset(prose, heading);
  if (at < 0) return null;
  final section = sectionAt(prose, at);
  return (
    from: lineOf(prose, section.start) + 1,
    to: lineOf(prose, section.start + section.body.length),
  );
}

/// The value of the `<label>:` field inside a step's [slice], or null when the
/// step carries no such label.
///
/// The value is the label line's remainder plus every CONTIGUOUS following line
/// that is not another label, a step opener, or a heading — contiguity is what
/// makes a blank line (or a fenced block, which is invisible here) end the
/// field. `Commit:` is the one exception and takes its own line only: a
/// conventional-commit SUBJECT is one line by definition.
String? _stepFieldValue(List<_AuthoredLine> slice, String label) {
  final opener = _stepFieldLine(label);
  for (var i = 0; i < slice.length; i++) {
    final match = opener.firstMatch(slice[i].text);
    if (match == null) continue;
    final value = StringBuffer(slice[i].text.substring(match.end));
    if (label != 'Commit') {
      var previous = slice[i].line;
      for (var j = i + 1; j < slice.length; j++) {
        final next = slice[j];
        if (next.line != previous + 1) break;
        if (_anyStepFieldLine.hasMatch(next.text)) break;
        if (_numberedStep.hasMatch(next.text)) break;
        if (_headingLine.hasMatch(next.text)) break;
        value.write('\n${next.text}');
        previous = next.line;
      }
    }
    return value.toString().trim();
  }
  return null;
}

/// Projects [acceptance] + [design] — the bead's RAW fields — into a
/// [SpecContract], appending every deviation from the documented grammar to the
/// returned findings.
///
/// TOTAL: it never throws and never repairs. A record that does not match its
/// documented form contributes a finding and NOTHING to the projection, so a
/// guess can never reach a cross-record check.
///
/// [only] narrows the parse to a chosen set of sections. That cascade is what
/// keeps one defect to one finding: an acceptance field with no checkboxes at
/// all is already [specStructuralFindings]' own live finding, and re-reading it
/// as a dozen malformed records would bury it. The shadow measurement parses
/// whole, because it counts migration cost rather than grading a bead.
({SpecContract contract, List<SpecContractFinding> findings})
parseSpecContract({
  required String acceptance,
  required String design,
  Set<SpecContractSection> only = const {
    SpecContractSection.acceptance,
    SpecContractSection.plan,
    SpecContractSection.touches,
    SpecContractSection.decisions,
    SpecContractSection.validation,
  },
}) {
  final findings = <SpecContractFinding>[];
  final criteria = <AcceptanceCriterion>[];
  final steps = <ImplementationStep>[];
  final touches = <Touch>[];
  final citations = <DecisionCitation>[];
  final validations = <ValidationMapping>[];
  var narrative = DecisionLookupNarrative.cited;

  void report(SpecContractRule rule, String field, int line, String message) =>
      findings.add(
        SpecContractFinding(
          rule: rule,
          field: field,
          line: line,
          message: message,
        ),
      );

  // ---- acceptance: `- [ ] AC-<n> — <criterion>` ---------------------------
  var acceptanceRecordsClean = true;
  if (only.contains(SpecContractSection.acceptance)) {
    final raw = acceptance.split('\n');
    final prose = proseOnly(acceptance).split('\n');
    final seen = <int, int>{};
    for (final entry in _authoredLines(raw, prose, 1, raw.length)) {
      if (!_checkboxLine.hasMatch(entry.text)) continue;
      final match = _acceptanceRecord.firstMatch(entry.text);
      if (match == null) {
        acceptanceRecordsClean = false;
        report(
          SpecContractRule.acceptanceRecord,
          'acceptance',
          entry.line,
          'not the `$kAcceptanceRecordForm` record form — every criterion '
              'carries an addressable id the validation plan maps onto',
        );
        continue;
      }
      final id = int.parse(match.group(1)!);
      if (seen.containsKey(id)) {
        acceptanceRecordsClean = false;
        report(
          SpecContractRule.acceptanceIdDuplicate,
          'acceptance',
          entry.line,
          'AC-$id is already declared on line ${seen[id]} — ids are UNIQUE, '
              'or the validation mapping is ambiguous',
        );
        continue;
      }
      seen[id] = entry.line;
      criteria.add(
        AcceptanceCriterion(
          id: id,
          text: match.group(2)!.trim(),
          line: entry.line,
        ),
      );
    }
    // Contiguity is only MEANINGFUL once every record parsed: a malformed
    // criterion leaves a hole in the id set, and reporting that hole as a
    // second defect would bury the one the architect actually has to fix.
    final ids = criteria.map((criterion) => criterion.id).toList()..sort();
    final expected = [for (var i = 1; i <= criteria.length; i++) i];
    if (acceptanceRecordsClean &&
        criteria.isNotEmpty &&
        '$ids' != '$expected') {
      acceptanceRecordsClean = false;
      report(
        SpecContractRule.acceptanceIdNotContiguous,
        'acceptance',
        criteria.first.line,
        'the acceptance ids are $ids — they must be CONTIGUOUS from AC-1, '
            'i.e. $expected',
      );
    }
  }

  final designRaw = design.split('\n');
  final designProse = proseOnly(design);
  final designProseLines = designProse.split('\n');

  // ---- `## Implementation Plan`: ordinal openers + five labeled fields ----
  final planRange = only.contains(SpecContractSection.plan)
      ? _sectionLineRange(designProse, '## Implementation Plan')
      : null;
  if (planRange != null) {
    final body = _authoredLines(
      designRaw,
      designProseLines,
      planRange.from,
      planRange.to,
    );
    final openers = [
      for (var i = 0; i < body.length; i++)
        if (_numberedStep.hasMatch(body[i].text)) i,
    ];
    for (var k = 0; k < openers.length; k++) {
      final slice = body.sublist(
        openers[k],
        k + 1 < openers.length ? openers[k + 1] : body.length,
      );
      final opener = slice.first;
      final match = _numberedStep.firstMatch(opener.text)!;
      final ordinal = int.parse(
        (match.group(1) ?? match.group(2) ?? match.group(3))!,
      );
      final title = opener.text
          .substring(match.end)
          .replaceFirst(RegExp(r'^[\s—–\-:.)*]+'), '')
          .trim();
      if (title.isEmpty) {
        report(
          SpecContractRule.stepTitle,
          'design',
          opener.line,
          'step $ordinal carries no title — the opener is `$kStepRecordForm`',
        );
      }
      final values = {
        for (final label in kStepFieldLabels)
          label: _stepFieldValue(slice, label),
      };
      final missing = [
        for (final label in kStepFieldLabels)
          if ((values[label] ?? '').isEmpty) label,
      ];
      if (missing.isNotEmpty) {
        report(
          SpecContractRule.stepField,
          'design',
          opener.line,
          'step $ordinal is missing ${missing.map((l) => '`$l:`').join(', ')} '
              '— every step carries '
              '${kStepFieldLabels.map((l) => '`$l:`').join(', ')} on its own '
              'line',
        );
      }
      final paths = [
        for (final span in _backtickedSpan.allMatches(values['Paths'] ?? ''))
          if (repoRelativePathOf(span.group(1)!) case final path?) path,
      ];
      if ((values['Paths'] ?? '').isNotEmpty && paths.isEmpty) {
        report(
          SpecContractRule.stepPath,
          'design',
          opener.line,
          'step $ordinal cites no repo-relative backticked path in `Paths:` '
              '— no leading `/`, no `..`',
        );
      }
      final commit = (values['Commit'] ?? '').replaceAll('`', '').trim();
      final violations = commit.isEmpty
          ? const <String>[]
          : lintConventionalSubject(commit);
      if (violations.isNotEmpty) {
        report(
          SpecContractRule.stepCommit,
          'design',
          opener.line,
          'step $ordinal\'s `Commit:` is not a conventional-commit subject: '
              '${violations.join('; ')}',
        );
      }
      steps.add(
        ImplementationStep(
          ordinal: ordinal,
          title: title,
          paths: paths,
          change: values['Change'] ?? '',
          testCommand: values['Test'] ?? '',
          expected: values['Expect'] ?? '',
          commit: commit,
          line: opener.line,
        ),
      );
    }
  }

  // ---- `## Touches`: one repo-relative path + one disposition per item ----
  final touchRange = only.contains(SpecContractSection.touches)
      ? _sectionLineRange(designProse, '## Touches')
      : null;
  if (touchRange != null) {
    for (final entry in _listItems(
      _authoredLines(
        designRaw,
        designProseLines,
        touchRange.from,
        touchRange.to,
      ),
    )) {
      final paths = [
        for (final span in _backtickedSpan.allMatches(entry.text))
          if (repoRelativePathOf(span.group(1)!) case final path?) path,
      ];
      final disposition = _touchDisposition.firstMatch(entry.text);
      if (paths.length != 1 || disposition == null) {
        report(
          SpecContractRule.touchRecord,
          'design',
          entry.line,
          'not the `$kTouchRecordForm` record form — exactly ONE '
              'repo-relative backticked path and one disposition word',
        );
        continue;
      }
      touches.add(
        Touch(
          path: paths.single,
          symbols: entry.text.substring(disposition.end).trim(),
          disposition: TouchDisposition.values.byName(
            disposition.group(1)!.toLowerCase(),
          ),
          line: entry.line,
        ),
      );
    }
  }

  // ---- `## ADR Alignment`: a resolvable citation, or a NAMED lookup --------
  final decisionRange = only.contains(SpecContractSection.decisions)
      ? _sectionLineRange(designProse, '## ADR Alignment')
      : null;
  if (decisionRange != null) {
    final body = _authoredLines(
      designRaw,
      designProseLines,
      decisionRange.from,
      decisionRange.to,
    );
    final prose = body.map((entry) => entry.text).join('\n');
    // A CRASHED lookup is read FIRST: a section reporting one may also quote
    // whatever local register it could still read, and reading that as an
    // empty union is the exact failure the roster-union decision forbids.
    if (prose.contains(kFailedDecisionLookupPrefix)) {
      narrative = DecisionLookupNarrative.failedLookup;
    } else if (prose.contains(kNoGoverningDecisionPrefix)) {
      narrative = DecisionLookupNarrative.emptyUnion;
    }
    final items = _listItems(body);
    if (narrative != DecisionLookupNarrative.emptyUnion) {
      for (final entry in items) {
        final tokens = [
          for (final span in _backtickedSpan.allMatches(entry.text))
            span.group(1)!,
          ...entry.text.split(RegExp(r'[\s,;`]+')),
        ];
        final reference = tokens
            .where(isResolvableDecisionReference)
            .firstOrNull;
        final disposition = _decisionDisposition.firstMatch(entry.text);
        if (reference == null || disposition == null) {
          report(
            SpecContractRule.decisionRecord,
            'design',
            entry.line,
            'not the `$kDecisionRecordForm` record form — a citation the '
                'roster index can RESOLVE plus a disposition word',
          );
          continue;
        }
        citations.add(
          DecisionCitation(
            reference: reference.trim(),
            disposition: DecisionDisposition.values.byName(
              disposition.group(1)!.toLowerCase(),
            ),
            line: entry.line,
          ),
        );
      }
    }
    // SILENT means the section says nothing about the lookup AT ALL. A
    // resolvable identity anywhere in its prose is a statement — it may be
    // outside the record form (and rule 9 is what says so), but calling such
    // a section "cites nothing" would be a finding whose own message is false.
    final citesSomething = [
      for (final span in _backtickedSpan.allMatches(prose)) span.group(1)!,
      ...prose.split(RegExp(r'[\s,;`]+')),
    ].any(isResolvableDecisionReference);
    if (narrative == DecisionLookupNarrative.cited &&
        items.isEmpty &&
        !citesSomething) {
      report(
        SpecContractRule.decisionSectionSilent,
        'design',
        decisionRange.from - 1,
        '`## ADR Alignment` cites nothing and declares neither outcome — say '
            '"$kNoGoverningDecisionPrefix …" when the union is EMPTY, or '
            '"$kFailedDecisionLookupPrefix …" and the verbatim output when the '
            'lookup CRASHED; an unknown union is not an empty one',
      );
    }
  }

  // ---- `## Validation Plan`: `AC-<n> → command → expected`, 1:1 -----------
  final validationRange = only.contains(SpecContractSection.validation)
      ? _sectionLineRange(designProse, '## Validation Plan')
      : null;
  var validationRecordsClean = true;
  if (validationRange != null) {
    for (final entry in _authoredLines(
      designRaw,
      designProseLines,
      validationRange.from,
      validationRange.to,
    )) {
      if (!_checkboxLine.hasMatch(entry.text)) continue;
      final match = _validationRecord.firstMatch(entry.text);
      if (match == null) {
        validationRecordsClean = false;
        report(
          SpecContractRule.validationRecord,
          'design',
          entry.line,
          'not the `$kValidationRecordForm` record form — the id is what '
              'carries the mapping',
        );
        continue;
      }
      validations.add(
        ValidationMapping(
          criterionId: int.parse(match.group(1)!),
          command: match.group(2)!.trim(),
          expected: match.group(3)!.trim(),
          line: entry.line,
        ),
      );
    }
  }

  // ---- the 1:1 mapping, only once BOTH ends parsed clean -------------------
  final bothEndsParsed =
      only.contains(SpecContractSection.acceptance) &&
      validationRange != null &&
      acceptanceRecordsClean &&
      validationRecordsClean;
  var mappingClean = true;
  if (bothEndsParsed) {
    final declared = {for (final criterion in criteria) criterion.id};
    for (final mapping in validations) {
      if (declared.contains(mapping.criterionId)) continue;
      mappingClean = false;
      report(
        SpecContractRule.validationUnknownCriterion,
        'design',
        mapping.line,
        'AC-${mapping.criterionId} is not declared by any acceptance '
            'criterion — a validation item never names an unknown id',
      );
    }
  }
  if (bothEndsParsed && mappingClean) {
    for (final criterion in criteria) {
      final mapped = validations
          .where((mapping) => mapping.criterionId == criterion.id)
          .toList();
      if (mapped.isEmpty) {
        report(
          SpecContractRule.validationCoverage,
          'acceptance',
          criterion.line,
          'AC-${criterion.id} has no `## Validation Plan` item — every '
              'criterion is validated EXACTLY once',
        );
      } else if (mapped.length > 1) {
        report(
          SpecContractRule.validationCoverage,
          'design',
          mapped[1].line,
          'AC-${criterion.id} is validated ${mapped.length} times (first on '
              'line ${mapped.first.line}) — every criterion is validated '
              'EXACTLY once',
        );
      }
    }
  }

  return (
    contract: SpecContract(
      criteria: criteria,
      steps: steps,
      touches: touches,
      citations: citations,
      decisionNarrative: narrative,
      validations: validations,
    ),
    findings: findings,
  );
}
