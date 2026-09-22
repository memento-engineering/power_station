/// The SPEC-READINESS INTAKE LENS (bead `pow-q7n`) — the CHEAP pre-specify
/// ladder at the head of [kSpecReviewCircuit].
///
/// **The gap.** The 2026-07-11 opus wide run proved the coarse backlog is not
/// spec-ready: 4 of 7 beads gated at `spec_review` on real decision-alignment /
/// coherence findings, because their COARSE descriptions produced weak specs.
/// ~42 opus agents discovered that AT the spec committee — downstream of the
/// most expensive fan-out in the circuit. The bar this lens applies is NOT "is
/// there a spec" (that is the committee's, `specify.dart`); it is: **does the
/// BEAD carry enough — a clear scope, an acceptance shape, its cited
/// constraints, a DECIDED approach — that `specify` will PLAUSIBLY produce a
/// spec the committee passes?** A bead that does not is HELD for refinement.
///
/// **The ladder, cheapest first** (each tier withholds the next):
///  1. [IntakeCapability] — the INTAKE CONTRACT, deterministic, ZERO agents: a
///     driveable [IssueType] + a non-empty description. It [Escalate]s directly
///     (the [PinDiffCapability] posture, ADR-0000 A9: a pre-lane step whose hold
///     withholds the lanes), so a `decision`/`epic` bead — or an empty brief —
///     never spawns ANY agent.
///  2. [ReadinessCriticCapability] — the JUDGEMENT, ONE agent, riding the
///     SHARED verdict transport ([CriticCapability], ADR-0000 A13(3)) with the
///     `bead-readiness` rubric.
///  3. [ReadinessRouteCapability] — the decision point AND the lane's JOIN:
///     `A`–`C` ⇒ drive; `D`–`F` ⇒ HOLD. An ABSENT lane result is NEITHER — it
///     is a join state the route WAITS on, and a lane that finished without
///     publishing one fails the route LOUDLY instead of minting a hold.
///
/// **Tier 1 is DELIBERATELY NARROW.** It asserts only what a machine can be
/// RIGHT about: a type the station drives, and a brief that exists. It applies
/// NO placeholder fence and NO length floor to the human-written
/// [Bead.description] — ADR-0000 A13(10)'s fence is for the fields the specify
/// AGENT writes to a known contract (`acceptanceCriteria`/`design`), and turning
/// it on a human's prose would park a terse-but-real chore bead, or one that
/// merely mentions a placeholder marker it intends to delete. Measured over the
/// live backlog (2026-07-12), no scalar signal separates the wide run's 4 gated
/// beads from its 3 passing ones without ALSO holding the beads the governor
/// ranked to drive. Determinism is confined to the tier where a hold is never
/// wrong; the coarse/ready call is the agent's.
///
/// **Tier 1's type gate is load-bearing.** grid_engine narrows to
/// [driveableTypes] only under RESIDENT arming
/// (`WorkList._isDispatchableWork` = `isCore && (!resident || isDriveable)`), and
/// `SubstationConfig.resident` defaults to FALSE — so a non-resident station
/// mounts and DRIVES an `epic`/`decision`/`spike`/`story`/`milestone` bead today.
/// This is the circuit-level contract that holds in both arming modes.
///
/// **The HOLD is an [Escalate], honestly.** The station has ONE park primitive
/// (ADR-0000 A13(1) reuses `gated` rather than minting a state — and an escalate
/// with no bound `EscalationHandler` falls to the engine's default `HumanGate`,
/// which parks exactly there), so mechanically a hold parks the bead exactly as a
/// spec escalation does. What makes it a REFINEMENT ASK and not a ruling is its
/// CONTENT: [renderIntakeHold] /
/// [renderRefinementAsk] name every finding and the lens's rationale verbatim,
/// addressed to the governor's refine lever. It carries NO machine-actionable
/// token — ADR-0000 A15(3) deleted exactly such a prefix on the grounds that "a
/// machine-actionable gate prefix nothing reads is a doc that lies".
///
/// **The lens is NOT in the invalidated closure.** Every readiness step is
/// UPSTREAM of `specify`, so the auto-respec wave (beads `pow-7nm`/`pow-ui8` —
/// derived from the spec route's `validates` edge, which invalidates `specify` ∪
/// its transitive dependents ∪ the route) never re-runs it:
/// a respec round rewrites the SPEC, not the BEAD, so re-grading the bead would
/// burn an agent per round to re-derive the same verdict. `spec_committee_test`
/// fences this with the engine's own `transitiveDependents` predicate.
///
/// **The bounce is guarded.** The ladder is a FOURTH `code`-circuit head shape;
/// `circuit_migration.dart` (bead `pow-3p4`, EXTENDED here) roots the frozen
/// pre-ladder circuit for an in-flight survivor, so this ladder never mounts —
/// and never spawns its agent — for a session minted before it existed.
library;

import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;

import '../agent/agent_domain.dart';
import '../agent/agent_environment.dart';
import '../agent/agent_harness.dart';
import '../agent/environment_registry.dart';
import '../agent/model_tier.dart';
import '../agent/seat_environments.dart';
import '../agent/site_binding.dart';
import '../agent/usage_report.dart';
import '../assets/overlay_materializer.dart' show kDefaultOverlayRunner;
import 'committee.dart';
import 'decision_register.dart';
import 'fix_in_flight.dart';
import 'refinement_flag.dart';
import 'respec_ledger.dart';
import 'route_failure.dart';

/// The deterministic intake-contract step id (the ladder's head — zero agents).
const String kIntakeStep = 'intake';

/// The cheap judgement lane's step id (ONE agent).
const String kReadinessStep = 'readiness';

/// The readiness decision point's step id (zero agents).
const String kReadinessRouteStep = 'readiness-route';

/// The readiness lane's rubric id (`extension/rubrics/bead-readiness.md`).
///
/// Named `bead-readiness`, NOT `spec-readiness`: the committee `specify.dart`
/// already ships IS "the spec-readiness committee" (bead `pow-6ao`) and grades
/// the SPEC. This lens grades the BEAD, upstream of it — one word keeps the two
/// legible in a prompt, a verdict path, and a gate reason.
const String kReadinessRubric = 'bead-readiness';

/// The INTAKE-CONTRACT findings for [bead] — empty iff the bead may reach the
/// readiness lane. Pure and exposed for unit tests; [IntakeCapability] gates iff
/// this returns non-empty. Each finding NAMES what is missing (guards LOUD), so
/// a held bead's refinement ask never makes a governor diff the bead by hand.
///
/// Driveability is grid_engine's [IssueTypeDriveability.isDriveable] over its
/// [driveableTypes] — the SINGLE source of truth (`driveable_work.dart`, already
/// consumed by `WorkList`). This pack declares no second list: two definitions of
/// "driveable" would drift and produce a park nobody intended.
///
/// It checks NOTHING ELSE. No placeholder fence, no length floor — see the
/// library doc: those are judgements, and judgement is the lens's (tier 2) job.
List<String> intakeFindings(Bead bead) {
  final findings = <String>[];

  if (!bead.issueType.isDriveable) {
    findings.add(
      'type: `${bead.issueType.wire}` is not a driveable type '
      '(${driveableTypes.map((t) => t.wire).join(' | ')}) — this bead wants a '
      'ruling or a decomposition, not a coding agent',
    );
  }
  if (bead.description.trim().isEmpty) {
    findings.add(
      'description: EMPTY — the bead carries no brief for an architect to plan '
      'against',
    );
  }
  return findings;
}

/// The readiness ladder's verdict. Sealed: consumed with an exhaustive `switch`.
sealed class ReadinessVerdict {
  const ReadinessVerdict();
}

/// The bead is READY — `specify` may run. [grade] is the lane's own `A`–`C`.
final class ReadinessDrive extends ReadinessVerdict {
  /// Creates a drive verdict carrying the lane's [grade] (provenance, FT-2).
  const ReadinessDrive(this.grade);

  /// The readiness lane's letter grade (`A`, `B` or `C`).
  final String grade;
}

/// The bead is NOT ready — HOLD it for refinement. [rule] names the arm that
/// fired (`not-ready` / `no-verdict`); [reason] is the refinement ask recorded
/// on the parked gate bead.
final class ReadinessHold extends ReadinessVerdict {
  /// Creates a hold.
  const ReadinessHold({required this.rule, required this.reason});

  /// The matrix arm that fired.
  final String rule;

  /// The refinement ask (the gate reason).
  final String reason;
}

/// NO verdict has been published for this round — a JOIN state, NOT a
/// judgement. The lane has said nothing yet: its result may simply not be
/// VISIBLE to the route, and its artifact may not be on disk, at the instant
/// the route looked.
///
/// This arm is the correction recorded as
/// `power_station#readiness-route-joins-on-a-published-verdict-never-on-absence`:
/// absence is never routed, so [ReadinessRouteCapability] WAITS on it and
/// re-reads, and a lane that FINISHED without publishing fails the route
/// loudly. The no-free-pass invariant is untouched — absence still never
/// advances a bead — but it no longer mints a human gate on a verdict that was
/// merely late.
final class ReadinessAbsent extends ReadinessVerdict {
  /// Creates the absent-result arm.
  const ReadinessAbsent();
}

/// The readiness MATRIX (pure — zero I/O; the whole decision, unit-testable).
///
///  1. a MISSING/blank [grade] ⇒ [ReadinessAbsent] — the lane published
///     NOTHING this round, so there is nothing to route over. Absence is a
///     join state, not a verdict: the caller waits for the lane to publish and
///     re-reads, and only a lane that FINISHED silent is a failure. The fail
///     direction stays SAFE by construction (ADR-0000 A13(7)): absence never
///     ADVANCES — what it stopped doing is minting a governor gate that names
///     no finding.
///  2. `A`/`B`/`C` ⇒ [ReadinessDrive] — the bead is specifiable.
///  3. anything else (`D`/`E`/`F`, or an off-ladder letter) ⇒ [ReadinessHold]
///     (`not-ready`) carrying the lens's [rationale] VERBATIM as the ask. A
///     PRESENT failing grade is the ONLY hold this ladder mints.
///
/// There is no auto-fix arm (unlike the spec route's RESPEC, `respec.dart`): a
/// respec re-runs an AGENT that can rewrite the spec, but nothing in this circuit
/// rewrites the BEAD — refining it is the governor's lever, so the only honest
/// not-ready outcome is a hold.
ReadinessVerdict decideReadiness({
  required String? grade,
  required String rationale,
}) {
  final raw = grade?.trim() ?? '';
  if (raw.isEmpty) return const ReadinessAbsent();
  final letter = raw.toUpperCase();
  if (letter == 'A' || letter == 'B' || letter == 'C') {
    return ReadinessDrive(letter);
  }
  return ReadinessHold(
    rule: 'not-ready',
    reason: renderRefinementAsk(grade: letter, rationale: rationale.trim()),
  );
}

/// The REFINEMENT ASK a not-ready bead parks with — the hold's whole point. The
/// lens's [rationale] rides VERBATIM (it is the governor's working material, not
/// a summary), under a line that says plainly what was NOT spent: no specify
/// agent, no spec committee.
String renderRefinementAsk({required String grade, required String rationale}) {
  final b = StringBuffer()
    ..writeln(
      'SPEC-READINESS HOLD (grade $grade) — this bead is not ready to specify, '
      'so NO specify agent and NO spec committee ran. It is HELD for '
      'refinement, not rejected.',
    )
    ..writeln()
    ..writeln('## What the `$kReadinessRubric` lens found')
    ..writeln(
      rationale.isEmpty
          ? '(the lens graded $grade but returned no rationale — refine against '
                'the rubric bands: scope, acceptance shape, cited constraints, '
                'a decided approach)'
          : rationale,
    )
    ..writeln()
    ..writeln('## The bar')
    ..writeln(
      'Not "is there a spec" — that is the spec committee, downstream. It is: '
      'does this bead carry enough that `specify` will PLAUSIBLY produce a spec '
      'the committee passes? A clear scope; an acceptance shape; the '
      'constraints and ADRs it must honor; and a DECIDED approach — not an open '
      'question the architect would have to guess at. Refine the bead and '
      're-arm it.',
    );
  return b.toString();
}

/// The INTAKE-CONTRACT hold's reason — every deterministic finding, named.
String renderIntakeHold(Bead bead, List<String> findings) {
  final b = StringBuffer()
    ..writeln(
      'INTAKE HOLD — bead `${bead.id}` does not meet the intake contract, so NO '
      'agent ran at all (not even the readiness lens). It is HELD for '
      'refinement, not rejected.',
    )
    ..writeln()
    ..writeln('## Findings');
  for (final finding in findings) {
    b.writeln('- $finding');
  }
  b
    ..writeln()
    ..writeln(
      'Fix every finding above and re-arm the bead. A bead only drives when it '
      'is a coding job (${driveableTypes.map((t) => t.wire).join(' | ')}) '
      'carrying a real brief.',
    );
  return b.toString();
}

/// TIER 1 — the deterministic INTAKE CONTRACT (zero agents), the ladder's head.
///
/// **The invariant it protects (LOUD-or-gone)**: a bead may only reach an AGENT
/// carrying a driveable type and a real brief. It [Escalate]s directly rather
/// than grading into a route — the [PinDiffCapability] posture (ADR-0000 A9): a
/// pre-lane step whose HOLD withholds the lanes is the whole point when the
/// saving IS the un-spawned agent. Fail-closed: a missing ambient bead holds too.
///
/// It also owns the readiness lane's ROUND-FRESHNESS. [ClearCritiqueCapability]
/// wipes `.grid/critique/` only DOWNSTREAM of `specify` (that dependency is
/// load-bearing for the spec lanes — ADR-0000 A15(5)), so on a `grid rework`
/// round, which re-runs this whole circuit in the SAME worktree, the readiness
/// lane would otherwise read the PREVIOUS round's `bead-readiness.json` (the
/// verdict's `nodePath` stamp cannot fence it: A15(5) — no re-key, so the path
/// is byte-identical across rounds). This step runs exactly once per round,
/// immediately before the lane, so its wipe is that lane's guarantee. Two wipes,
/// two lane-sets, neither weakened. Best-effort, same posture as
/// [ClearCritiqueCapability]: a wipe that throws never gates the round.
///
/// It also clears prior-session respec guidance. The session circuit round is
/// supplied independently by the engine under `grid.round`.
class IntakeCapability extends RouteCapability {
  /// Creates the intake lens, optionally over an injected [clearer] (tests
  /// inject a no-op so the offline suite never touches a real filesystem at a
  /// synthetic workspace path — Fakes, not mocks); defaults to [clearDirectory].
  const IntakeCapability({DirectoryClearer? clearer}) : _clearer = clearer;

  final DirectoryClearer? _clearer;

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async {
    // Read the ambient values at ENTRY (while mounted); the check below is pure
    // over the captured value.
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (bead == null) {
      return const Escalate(
        'INTAKE HOLD — no ambient work bead to check (fail-closed): a bead '
        'reaches an agent only on a verdict that SAYS it is driveable.',
      );
    }
    if (workspace != null) {
      try {
        (_clearer ?? clearDirectory)(critiqueDirPath(workspace.workspaceDir));
      } catch (_) {
        // Best-effort hygiene (the ClearCritiqueCapability posture).
      }
      // Do not carry correction guidance into a fresh session. Best-effort
      // inside `clearRespecLedger`; a no-op when no ledger exists.
      clearRespecLedger(workspace.workspaceDir);
      // Session-scoped exactly like the ledger (bead `pow-bhm`): a reused
      // worktree never inherits a prior session's carry or flag.
      clearFixInFlight(workspace.workspaceDir);
      clearRefinementFlag(workspace.workspaceDir);
    }
    final findings = intakeFindings(bead);
    if (findings.isEmpty) {
      return Advance({'verdict': 'driveable', 'type': bead.issueType.wire});
    }
    return Escalate(renderIntakeHold(bead, findings));
  }
}

/// TIER 2 — the CHEAP judgement lane: ONE agent grading the BEAD's readiness.
///
/// Subclasses [CriticCapability] to inherit the ENTIRE verdict-transport stack
/// unchanged (canonical file → round-fresh stray → result-envelope → fail-closed
/// F, each with its `nodePath` + `round` stamps and named `transport`; plus the
/// FT-2 usage merge) — ADR-0000 A13(3)'s doctrine: ONE transport stack, so a
/// hardening landed for the critics holds here too. Only the SPAWN differs: the
/// review subject is the BEAD (no spec exists yet, and no diff — the build has
/// not run), and the prompt is [buildReadinessPrompt].
///
/// It resolves its agent config through the SAME [resolveAgentConfig] ladder as
/// every other lane, so it carries NO model opinion of its own — ADR-0000
/// A17(6): *"`ReadinessCriticCapability` resolves through the SAME ladder as
/// every other lane, so the day `pow-edp`'s role defaults land, this lane
/// inherits the cheap model for free. Cheapness TODAY is STRUCTURAL (1 agent
/// instead of ~18), not a model pin."* That day came: it declares
/// [AgentTier.mid], so it rides [kMidModelDefault] (`sonnet`) — the ladder's
/// cheaper rung, inherited with no change here, never the build's frontier
/// model.
///
/// Whether the lane should ride [AgentTier.cheap] ([kCheapModelDefault],
/// `haiku`) instead is a BEHAVIOR change on a live governance lane, and it is
/// NOT the discovery lenses' posture when it comes: a lens reads and decides
/// nothing, while this lane emits a verdict letter. It is one line — the tier at
/// the spawn below — and it belongs to its own bead. The rung it rides TODAY is
/// pinned at the argv in `test/agent/model_tier_test.dart`, so the flip is
/// deliberate and reviewed, never drift.
class ReadinessCriticCapability extends CriticCapability {
  /// Creates the readiness lane, optionally over a rubric source (D-9 wires the
  /// Packaged-AI-Asset loader; absent ⇒ an inline placeholder so the circuit is
  /// testable with no real assets).
  ///
  /// [decisionRunner] is the COMPOSING STATION's verb and [decisionGridHome]
  /// its grid home — the same pair `buildCodeRegistry` binds from
  /// `overlayArgs` for the spec lanes. The lens is told to run the roster
  /// index ONCE, so it needs the verb the station actually composed and the
  /// cwd that verb resolves from; an unbound grid home means the prompt names
  /// NO command and says the index is unavailable, rather than spending this
  /// lane's whole bounded look on an invocation that exits
  /// `Could not find package`.
  const ReadinessCriticCapability({
    super.rubrics,
    super.verdictTextReader,
    String decisionRunner = kDefaultOverlayRunner,
    String? decisionGridHome,
  }) : _decisionRunner = decisionRunner,
       _decisionGridHome = decisionGridHome;

  final String _decisionRunner;
  final String? _decisionGridHome;

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) {
    // Read the ambient values at ENTRY (synchronously, while mounted).
    final rubric = args.params['rubric'] ?? '';
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (bead == null || workspace == null) {
      throw StateError(
        'ReadinessCriticCapability requires the ambient Bead + Workspace '
        '(WorkBead/SessionScope mount them)',
      );
    }
    // Same incarnation stamp as the code committee: the readiness lens shares
    // one verdict reader with the lanes whose rounds move.
    recordCriticIncarnation(
      workspaceDir: workspace.workspaceDir,
      rubric: rubric,
    );
    final round = verdictRound(args);
    // ONE builder, two call sites (the other is the filing verbs' pre-stamp
    // advisory): everything but the transport arm is settled in there, so a
    // hardening landed for this lane holds for the advisory too.
    return readinessLensRuntimeConfig(
      bead: bead,
      workspace: workspace,
      rubric: rubric,
      nodePath: args.nodePath,
      round: round,
      transport: const LensArtifactTransport(),
      rubrics: rubricSource,
      decisionRunner: _decisionRunner,
      decisionGridHome: _decisionGridHome,
      ambient:
          context.getInheritedSeedOfExactType<AgentConfig>() ??
          const AgentConfig(),
      registry:
          context.getInheritedSeedOfExactType<EnvironmentRegistry>() ??
          buildBuiltinEnvironmentRegistry(),
      siteBinding:
          context.getInheritedSeedOfExactType<SiteBinding>() ??
          SiteBinding.none,
      typedEnvironment: CriticAgentEnvironment.of(
        context,
        lane: CriticLane(rubric),
      ),
      stepParams: args.params,
      // The repair carry is ARTIFACT-ONLY by construction: it is read off the
      // refused artifact of a prior attempt, and the in-process arm has none.
      promptSuffix: criticRepairInstruction(
        workspaceDir: workspace.workspaceDir,
        rubric: rubric,
        nodePath: args.nodePath,
        round: round,
      ),
    );
  }

  /// Assembles the readiness lens's prompt over the work [bead].
  ///
  /// A thin adapter over the shared [readinessLensPrompt] on the ARTIFACT arm
  /// — the one this in-pipeline lane rides. Kept as a method because it is the
  /// shape the suites already drive, and because the injected [rubricSource]
  /// and decision-invocation values live on this capability.
  ///
  /// Exposed for unit tests.
  String buildReadinessPrompt(
    Bead bead,
    String rubric,
    String nodePath,
    String workspaceDir, {
    required int round,
  }) => readinessLensPrompt(
    bead: bead,
    rubric: rubric,
    nodePath: nodePath,
    workspaceDir: workspaceDir,
    round: round,
    transport: const LensArtifactTransport(),
    rubrics: rubricSource,
    decisionRunner: _decisionRunner,
    decisionGridHome: _decisionGridHome,
  );
}

/// The rubric prose a readiness prompt embeds — the injected source (D-9), or
/// an inline placeholder so the lane is testable with no real assets.
String readinessRubricText(String rubric, RubricSource? rubrics) =>
    rubrics?.call(rubric) ??
    '(rubric `$rubric` — the Packaged-AI-Asset loader supplies the bands)';

/// The TRANSPORT-INVARIANT body of the readiness lens's prompt — everything
/// through [kVerdictStampInstruction], and the whole of what the lens is asked
/// to JUDGE.
///
/// This is the byte-for-byte shared half of the two call sites: the
/// spec-review lane ([ReadinessCriticCapability]) and the filing verbs'
/// pre-stamp advisory. It carries the SAME hardening as
/// [CriticCapability.buildCriticPrompt]: the verdict JSON's `nodePath` stamp
/// (the foreign-node fence, ADR-0000 A4 as re-scoped by A15(5)) and the
/// `round` stamp (A15(5) alt-A). What differs from a critic is the SUBJECT and
/// the BUDGET: it grades the BEAD (there is no spec and no diff), and it is
/// told to stay CHEAP — one pass, bounded reads — because the whole point of
/// this lane is to cost a fraction of what it withholds.
///
/// It says nothing about WHERE the answer goes. That is
/// [readinessLensPrompt]'s single added paragraph, and the only thing the two
/// call sites do differently.
String readinessLensPromptBody({
  required Bead bead,
  required String rubric,
  required String nodePath,
  required int round,
  RubricSource? rubrics,
  String decisionRunner = kDefaultOverlayRunner,
  String? decisionGridHome,
}) {
  // The station's own verb, run FROM the grid home it resolves in. Unbound ⇒
  // the shared unavailable rule: no invocation is named, and the lens reads
  // the mounted registers directly.
  final home = decisionGridHome?.trim() ?? '';
  final rosterIndex = rosterDecisionIndexCommand(
    runner: decisionRunner,
    gridHome: home,
  );
  final lookupDirection = home.isEmpty
      ? '. ${decisionLookupRule(runner: decisionRunner)}'
      : ': run `$rosterIndex` '
            'ONCE to see what the roster union already decides. It takes NO '
            'register-directory argument on purpose — the grid adapter '
            'resolves the live mounted-substation roster, so a SIBLING '
            'substation\'s decisions are in the answer too; the `cd` is what '
            'makes it run at all, because the composing station\'s verb '
            'resolves only where that station\'s own package is.';
  final b = StringBuffer()
    ..writeln('# Spec-readiness intake — rubric: `$rubric`')
    ..writeln()
    ..writeln(
      'You are a CHEAP pre-flight lens, upstream of everything expensive. The '
      'bead below has NOT been specified and has NOT been built: there is no '
      'spec and no diff to grade. You are grading the WORK BEAD ITSELF, and '
      'exactly one question: **does it carry enough that the `specify` '
      'architect will PLAUSIBLY produce a spec the spec-readiness committee '
      'passes?** If it does not, it is HELD for refinement — no specify agent '
      'and no 4-critic committee will run, and a governor will refine it '
      'against your rationale. Review ONLY against the `$rubric` rubric below.',
    )
    ..writeln()
    ..writeln('## Rubric: $rubric')
    ..writeln(readinessRubricText(rubric, rubrics))
    ..write(beadUnderIntake(bead))
    ..writeln()
    ..writeln('## Stay cheap — this is a lens, not a committee')
    ..writeln(
      'You are standing in the bead\'s worktree. Spend a BOUNDED look, not '
      'an exploration$lookupDirection Grep ONLY the '
      'surfaces the bead actually names. Do NOT design the change, do NOT '
      'write a plan, do NOT read the tree broadly — that is the architect\'s '
      'job downstream, and duplicating it here defeats this lane\'s purpose. '
      'Judge the BRIEF, not the codebase.',
    )
    ..writeln()
    ..writeln('## Your verdict')
    ..writeln(
      'Grade the BEAD A (best) through F (worst) against `$rubric` ONLY. '
      'A, B or C ⇒ the bead DRIVES (it is specifiable). D, E or F ⇒ the bead '
      'is HELD for refinement. Your rationale IS the refinement ask a governor '
      'reads — so on a D or worse, say CONCRETELY what is missing and what '
      'would fix it (a named surface, a decision to make, a constraint to '
      'cite), never just that the bead is vague.',
    )
    ..writeln('Your verdict is JSON of this exact shape:')
    ..writeln(
      verdictJsonTemplate(
        rubric: rubric,
        nodePath: nodePath,
        round: round,
        rationaleHint: '<why + what would fix it>',
      ),
    )
    ..writeln()
    ..writeln(kVerdictStampInstruction);
  return b.toString();
}

/// The COMPLETE readiness prompt: [readinessLensPromptBody] plus the one
/// paragraph that names [transport]'s destination.
///
/// On [LensArtifactTransport] the tail is the workspace-derived ABSOLUTE
/// canonical write path (gate-integrity #4 — cwd-invariant) with the
/// file-write instruction as the LAST thing the prompt says (tg-291 —
/// recency). On [LensInProcessTransport] it is [kInProcessResultInstruction],
/// which is equally emphatic in the other direction: write NOTHING.
String readinessLensPrompt({
  required Bead bead,
  required String rubric,
  required String nodePath,
  required String workspaceDir,
  required int round,
  required LensResultTransport transport,
  RubricSource? rubrics,
  String decisionRunner = kDefaultOverlayRunner,
  String? decisionGridHome,
}) {
  final body = readinessLensPromptBody(
    bead: bead,
    rubric: rubric,
    nodePath: nodePath,
    round: round,
    rubrics: rubrics,
    decisionRunner: decisionRunner,
    decisionGridHome: decisionGridHome,
  );
  final tail = switch (transport) {
    LensArtifactTransport() => verdictWriteInstruction(
      p.join(critiqueDirPath(workspaceDir), '$rubric.json'),
    ),
    LensInProcessTransport() => kInProcessResultInstruction,
  };
  return '$body\n$tail\n';
}

/// Renders the readiness lens's spawn for [transport] — the ONE place the
/// lane's tier, environment resolution, site binding, usage posture and prompt
/// are settled.
///
/// [AgentTier.mid] is the lane's declared rung (ADR-0000 A17(6)), pinned at the
/// argv in `test/agent/model_tier_test.dart` so a flip is deliberate rather
/// than drift. [promptSuffix] appends the artifact arm's verdict-contract
/// repair carry; it is empty on the in-process arm, which has no prior
/// artifact to have refused.
///
/// The transport also decides the USAGE posture. The artifact arm captures FT-2
/// telemetry to the node's usage file exactly as every other lane does; the
/// in-process arm passes no `usageOut` at all, because capture redirects the
/// harness's whole JSON envelope to a file and the caller reads this answer
/// from stdout.
RuntimeConfig readinessLensRuntimeConfig({
  required Bead bead,
  required Workspace workspace,
  required String rubric,
  required String nodePath,
  required int round,
  required LensResultTransport transport,
  required AgentConfig ambient,
  required EnvironmentRegistry registry,
  required SiteBinding siteBinding,
  RubricSource? rubrics,
  String decisionRunner = kDefaultOverlayRunner,
  String? decisionGridHome,
  AgentEnvironment? typedEnvironment,
  Map<String, String> stepParams = const {},
  String promptSuffix = '',
}) {
  final config = resolveAgentConfig(
    tier: AgentTier.mid,
    ambient: ambient,
    beadMetadata: bead.metadata,
    stepParams: stepParams,
    registry: registry,
    typedEnvironment: typedEnvironment,
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
          readinessLensPrompt(
            bead: bead,
            rubric: rubric,
            nodePath: nodePath,
            workspaceDir: workspace.workspaceDir,
            round: round,
            transport: transport,
            rubrics: rubrics,
            decisionRunner: decisionRunner,
            decisionGridHome: decisionGridHome,
          ) +
          promptSuffix,
    ),
    workspace: workspace,
    usageOut: switch (transport) {
      // CAPTURE-ONLY usage telemetry (FT-2), same as every other lane.
      LensArtifactTransport() => usageReportPath(nodePath),
      LensInProcessTransport() => null,
    },
  );
}

/// Renders the work bead into the readiness prompt — the same title/task/design/
/// acceptance/notes rendering the committees embed, re-labeled so the lens knows
/// the BEAD is the artifact under review (not a spec, not a diff).
String beadUnderIntake(Bead bead) {
  final title = bead.title.isNotEmpty ? bead.title : 'work bead ${bead.id}';
  final b = StringBuffer()
    ..writeln()
    ..writeln('## The work bead (IT is what you are grading)')
    ..writeln('`${bead.id}` — $title')
    ..writeln('type: `${bead.issueType.wire}`');
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

/// TIER 3 — the readiness DECISION point (zero agents) AND the readiness lane's
/// JOIN. It decides over THREE states of the lane's result, never two:
///
///  - **PRESENT and passing** (`A`–`C`) ⇒ [Advance], carrying the route-style
///    provenance the code and spec routes emit plus the verdict's own SOURCE
///    (`source_state`, `source_path`, `transport`).
///  - **PRESENT and failing** (`D`–`F`, or an off-ladder letter) ⇒ [Escalate]
///    carrying the refinement ask. This is the ONLY hold this route mints.
///  - **ABSENT** ⇒ neither. Nothing has been published for this round, so there
///    is nothing to decide: WAIT [lanePoll] and re-read. A lane that is ALREADY
///    positively terminal has finished without publishing — a broken LANE, not
///    a verdict — and that throws [RouteFailure] naming the missing invocation.
///    A lane still silent at [laneWaitBudget] throws too. Absence NEVER holds.
///
/// **Every field name in the payload is an IDENTIFIER** (`[a-z0-9_]+`). A step
/// result persists through `ResultKeys.keyFor`, which renders
/// `grid.result.<node path>.<field>` with the field segment RAW, and `bd`
/// refuses a metadata key carrying a hyphen — it refuses the WHOLE update, not
/// the offending key. The wave that first shipped these two fields spelled them
/// `source-state`/`source-path`, and every session minted under it died at its
/// first advance on `1 of 1 issues failed to update`; the older fields survived
/// only because they were already identifiers. `readiness_test.dart` pins the
/// COMPLETE field set against that alphabet, so a new field has to be spelled
/// for the wire before it can be added.
///
/// **Why absence stopped being a hold.** On 2026-09-14 twelve rounds across
/// four substations escalated here on "no verdict" WITH the lens's grade
/// already on disk, written seconds either side of the escalation: the route
/// read `SiblingView.resultOf` before the lane's result was visible and treated
/// ABSENT exactly as it treated FAILED. Each cost a governor wake and a hand
/// resolve, and the gate it minted named no finding anyone could act on — a
/// hold on absence is not fail-closed, it is a false hold on a bead the lens
/// had already passed. The correction is recorded as
/// `power_station#readiness-route-joins-on-a-published-verdict-never-on-absence`;
/// it AMENDS ADR-0000 A17(7)'s missing-verdict arm and keeps its no-free-pass
/// half intact — absence still never advances the bead, it waits or it fails.
///
/// **The bounded mid-wave join is [SpecRouteCapability]'s shape, reused**
/// (`respec.dart`), exactly as [DiscoveryRouteCapability] reuses it: re-read
/// every [lanePoll] until the lane publishes, bounded by [laneWaitBudget], with
/// the mounted- and cancel-checks BEFORE the ambient re-read, then refuse
/// LOUDLY rather than decide over an unpublished lane. The wait is kept LOCAL
/// to this route rather than hoisted into `RouteCapability`: hoisting it would
/// change two sibling routes this bead does not touch.
///
/// **The live source is the committee's own reader.** A live workspace joins
/// through [currentVerdictOnDisk] — the SAME single strict parser, canonical→
/// round-fresh-stray transport, `nodePath` fence (ADR-0000 A4) and `round`
/// fence (A15(5) alt-A via A34) `CriticCapability.result()` reads through — so
/// this route adds NO second parser and cannot accept a foreign or stale
/// verdict. The lane's completion contract is artifact DURABILITY
/// ([ReadinessCriticCapability] inherits it), so a positively-terminal lane
/// provably HAS a durable current-round artifact and one that does not truly
/// did not run — which is what makes the ABSENT arm's loud failure honest
/// rather than a guess. Offline (a
/// workspace dir that does not exist — the synthetic path an offline suite
/// mounts) there is no artifact to read, so the lane's recorded step result is
/// the candidate, labelled `sibling-view`.
///
/// The lane it reads is its `lane` param (default [kReadinessStep]) and the
/// verdict it reads is its `rubric` param (default [kReadinessRubric]) — the
/// same honesty the committee routes carry in their `critics`/`gating` params:
/// a route NAMES the lane it decided over and the artifact it decided on.
class ReadinessRouteCapability extends RouteCapability {
  /// Creates the readiness route, optionally over its JOIN tuning: the
  /// [lanePoll] interval between re-reads, and the [laneWaitBudget] after which
  /// a still-silent lane fails LOUDLY. The defaults cover one mid-tier lens
  /// ride with margin; tests inject millisecond values.
  const ReadinessRouteCapability({
    this.lanePoll = const Duration(seconds: 15),
    this.laneWaitBudget = const Duration(minutes: 20),
  });

  /// How often the WAIT re-reads the join (see [route]).
  final Duration lanePoll;

  /// How long the WAIT may last before the route refuses LOUDLY.
  final Duration laneWaitBudget;

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async {
    // Read the ambient values at ENTRY (while mounted); after every await only
    // the captured values + the cancel token are touched before re-reading.
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    final laneId = args.params['lane'] ?? kReadinessStep;
    final rubric = args.params['rubric'] ?? kReadinessRubric;
    final laneNodePath = '${parentPath(args.nodePath)}/$laneId';
    final workspaceDir = workspace?.workspaceDir ?? '';
    final sourcePath = p.join(critiqueDirPath(workspaceDir), '$rubric.json');
    final round = verdictRound(args);
    final live =
        workspaceDir.isNotEmpty && Directory(workspaceDir).existsSync();
    final deadline = DateTime.now().add(laneWaitBudget);
    var siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();

    while (true) {
      final candidate = live
          ? currentVerdictOnDisk(
              workspaceDir: workspaceDir,
              rubric: rubric,
              nodePath: laneNodePath,
              round: round,
            )
          : _recordedCandidate(siblings.resultOf(laneNodePath));
      final transport = candidate?['transport'] ?? '';

      switch (decideReadiness(
        grade: candidate?['grade'],
        rationale: candidate?['rationale'] ?? '',
      )) {
        case ReadinessDrive(:final grade):
          return Advance({
            'verdict': 'drive',
            'grade': grade,
            'lane': laneId,
            'rule': 'ready',
            'source_state': 'PRESENT',
            'source_path': sourcePath,
            'transport': transport,
          });
        case ReadinessHold(:final reason):
          return Escalate(
            '$reason\nVERDICT SOURCE: PRESENT — $sourcePath via $transport.',
          );
        case ReadinessAbsent():
          // The lane FINISHED and published nothing. Its completion contract is
          // artifact durability, so this is a missing INVOCATION — name it and
          // fail; a hold here would park the bead on a defect of the lane.
          if (siblings.cursorOf(laneNodePath).isPositiveTerminal) {
            throw RouteFailure(
              'readiness-route: ABSENT — the `$rubric` lane at $laneNodePath is '
              'positively terminal for round $round but published NO verdict: '
              'nothing reached its step result and no current-round artifact '
              'exists at $sourcePath. That is a missing invocation (a broken '
              'LANE), not a grade — failing LOUDLY rather than holding the bead '
              'on an absence.',
            );
          }
          if (!DateTime.now().isBefore(deadline)) {
            throw RouteFailure(
              'readiness-route: waited ${laneWaitBudget.inSeconds}s '
              '(${laneWaitBudget.inMilliseconds}ms) but the `$rubric` lane at '
              '$laneNodePath is still non-terminal with no current-round '
              '(round $round) verdict at $sourcePath — a stalled lane. Refusing '
              'LOUDLY; deciding over an unpublished lane is withheld.',
            );
          }
      }

      await Future<void>.delayed(lanePoll);
      // A context torn down across the wait is a route that no longer has a
      // node to decide for. Unwind on the SAME channel as an explicit cancel —
      // kept a separate statement from the token check so the handle is
      // provably mounted before it is read again.
      if (!context.mounted) throw kRouteCancelled;
      if (args.cancel.isCancelled) throw kRouteCancelled;
      // Re-read the ambient view for the next attempt (post-mounted- and
      // post-cancel-check — the effect verb is snapshot-at-read and safe across
      // the wait, the `SpecRouteCapability` precedent).
      siblings =
          context.getInheritedSeedOfExactType<SiblingView>() ??
          const SiblingView();
    }
  }
}

/// The OFFLINE join candidate — the lane's RECORDED step result, labelled with
/// the transport it came through so an advance or a hold still names its
/// source. An EMPTY result is null: absence, never an empty verdict.
Map<String, String>? _recordedCandidate(Map<String, String> recorded) =>
    recorded.isEmpty ? null : {...recorded, 'transport': 'sibling-view'};
