/// The SPEC-READINESS INTAKE LENS (bead `pow-q7n`) — the CHEAP pre-specify
/// ladder at the head of [kSpecReviewCircuit].
///
/// **The gap.** The 2026-07-11 opus wide run proved the coarse backlog is not
/// spec-ready: 4 of 7 beads gated at `spec_review` on real adr-alignment /
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
///     driveable [IssueType] + a non-empty description. It [Gate]s directly (the
///     [PinDiffCapability] posture, ADR-0000 A9: a pre-lane step whose gate
///     withholds the lanes), so a `decision`/`epic` bead — or an empty brief —
///     never spawns ANY agent.
///  2. [ReadinessCriticCapability] — the JUDGEMENT, ONE agent, riding the
///     SHARED verdict transport ([CriticCapability], ADR-0000 A13(3)) with the
///     `bead-readiness` rubric.
///  3. [ReadinessRouteCapability] — the decision point: `A`–`C` ⇒ drive;
///     `D`–`F`, or a missing verdict, ⇒ HOLD.
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
/// **The HOLD is a [Gate], honestly.** The station has ONE park primitive
/// (ADR-0000 A13(1) reuses `gated` rather than minting a state), so mechanically
/// a hold parks the bead exactly as a spec escalation does. What makes it a
/// REFINEMENT ASK and not a ruling is its CONTENT: [renderIntakeHold] /
/// [renderRefinementAsk] name every finding and the lens's rationale verbatim,
/// addressed to the governor's refine lever. It carries NO machine-actionable
/// token — ADR-0000 A15(3) deleted exactly such a prefix on the grounds that "a
/// machine-actionable gate prefix nothing reads is a doc that lies".
///
/// **The lens is NOT in the rewind set.** Every readiness step is UPSTREAM of
/// `specify`, so the auto-respec [Rewind] (beads `pow-7nm`/`pow-ui8`, which
/// re-keys `specify` ∪ its transitive dependents ∪ the route) never re-runs it:
/// a respec round rewrites the SPEC, not the BEAD, so re-grading the bead would
/// burn an agent per round to re-derive the same verdict. `spec_committee_test`
/// fences this with the engine's own `transitiveDependents` predicate.
///
/// **The bounce is guarded.** The ladder is a FOURTH `code`-circuit head shape;
/// `circuit_migration.dart` (bead `pow-3p4`, EXTENDED here) roots the frozen
/// pre-ladder circuit for an in-flight survivor, so this ladder never mounts —
/// and never spawns its agent — for a session minted before it existed.
library;

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;

import '../agent/agent_domain.dart';
import '../agent/agent_harness.dart';
import '../agent/usage_report.dart';
import 'committee.dart';

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

/// The readiness MATRIX (pure — zero I/O; the whole decision, unit-testable).
///
///  1. a MISSING/blank [grade] ⇒ [ReadinessHold] (`no-verdict`) — fail-closed.
///     The lens's job is to withhold an expensive fan-out; a transport miss must
///     never buy a free pass to it. The fail direction is SAFE by construction
///     (ADR-0000 A13(7)): a false HOLD a governor unwinds, never a false drive.
///  2. `A`/`B`/`C` ⇒ [ReadinessDrive] — the bead is specifiable.
///  3. anything else (`D`/`E`/`F`, or an off-ladder letter) ⇒ [ReadinessHold]
///     (`not-ready`) carrying the lens's [rationale] VERBATIM as the ask.
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
  if (raw.isEmpty) {
    return const ReadinessHold(
      rule: 'no-verdict',
      reason:
          'SPEC-READINESS HOLD — the `$kReadinessRubric` lens returned NO '
          'verdict (no grade reached the route). Fail-closed: a bead advances '
          'to the specify stage only on a verdict that SAYS it is ready. '
          'Re-arm the bead to re-run the lens; if this repeats, the lane '
          'itself is broken.',
    );
  }
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
/// carrying a driveable type and a real brief. It [Gate]s directly rather than
/// grading into a route — the [PinDiffCapability] posture (ADR-0000 A9): a
/// pre-lane step whose gate WITHHOLDS the lanes is the whole point when the
/// saving IS the un-spawned agent. Fail-closed: a missing ambient bead gates too.
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
class IntakeCapability extends ServiceCapability {
  /// Creates the intake gate, optionally over an injected [clearer] (tests
  /// inject a no-op so the offline suite never touches a real filesystem at a
  /// synthetic workspace path — Fakes, not mocks); defaults to [clearDirectory].
  const IntakeCapability({DirectoryClearer? clearer}) : _clearer = clearer;

  final DirectoryClearer? _clearer;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    // Read the ambient values at ENTRY (while mounted); the check below is pure
    // over the captured value.
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (bead == null) {
      return const Gate(
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
    }
    final findings = intakeFindings(bead);
    if (findings.isEmpty) {
      return Ok({'verdict': 'driveable', 'type': bead.issueType.wire});
    }
    return Gate(renderIntakeHold(bead, findings));
  }
}

/// TIER 2 — the CHEAP judgement lane: ONE agent grading the BEAD's readiness.
///
/// Subclasses [CriticCapability] to inherit the ENTIRE verdict-transport stack
/// unchanged (canonical file → round-fresh stray → result-envelope → fail-closed
/// F, each with its `nodePath` stamp and named `transport`; plus the FT-2 usage
/// merge) — ADR-0000 A13(3)'s doctrine: ONE transport stack, so a hardening
/// landed for the critics holds here too. Only the SPAWN differs: the review
/// subject is the BEAD (no spec exists yet, and no diff — the build has not run),
/// and the prompt is [buildReadinessPrompt].
///
/// It resolves its agent config through the SAME [resolveAgentConfig] ladder as
/// every other lane, so it carries NO model opinion of its own: sibling bead
/// `pow-edp` (per-role model selection — grade on sonnet, build on opus) is the
/// rung that will make this lane's model cheap, and this lane picks it up with
/// no change here.
class ReadinessCriticCapability extends CriticCapability {
  /// Creates the readiness lane, optionally over a rubric source (D-9 wires the
  /// Packaged-AI-Asset loader; absent ⇒ an inline placeholder so the circuit is
  /// testable with no real assets).
  const ReadinessCriticCapability({super.rubrics});

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
    final ambient =
        context.getInheritedSeedOfExactType<AgentConfig>() ??
        const AgentConfig();
    final registry =
        context.getInheritedSeedOfExactType<AgentHarnessRegistry>() ??
        buildAgentHarnessRegistry();
    final config = resolveAgentConfig(
      ambient: ambient,
      beadMetadata: bead.metadata,
      stepParams: args.params,
      registry: registry,
    );
    return registry.harness(config.harness)!.spawnFor(
      config: config,
      brief: AgentBrief(
        task: buildReadinessPrompt(
          bead,
          rubric,
          args.nodePath,
          workspace.workspaceDir,
        ),
      ),
      workspace: workspace,
      // CAPTURE-ONLY usage telemetry (FT-2), same as every other lane.
      usageOut: usageReportPath(args.nodePath),
    );
  }

  /// The rubric prose embedded in the lens's prompt — the inherited injected
  /// source (D-9), or an inline placeholder so the circuit is testable with no
  /// assets.
  String _rubricText(String rubric) =>
      rubricSource?.call(rubric) ??
      '(rubric `$rubric` — the Packaged-AI-Asset loader supplies the bands)';

  /// Assembles the readiness lens's prompt over the work [bead].
  ///
  /// Carries the SAME hardening as [CriticCapability.buildCriticPrompt]: the
  /// verdict JSON's `nodePath` stamp (the foreign-node fence, ADR-0000 A4 as
  /// re-scoped by A15(5)), the workspace-derived ABSOLUTE canonical write path
  /// (gate-integrity #4 — cwd-invariant), and the file-write instruction as the
  /// LAST thing the prompt says (tg-291 — recency). What differs is the SUBJECT
  /// and the BUDGET: it grades the BEAD (there is no spec and no diff), and it
  /// is told to stay CHEAP — one pass, bounded reads — because the whole point
  /// of this lane is to cost a fraction of what it withholds.
  ///
  /// Exposed for unit tests.
  String buildReadinessPrompt(
    Bead bead,
    String rubric,
    String nodePath,
    String workspaceDir,
  ) {
    final path = p.join(critiqueDirPath(workspaceDir), '$rubric.json');
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
      ..writeln(_rubricText(rubric))
      ..write(beadUnderIntake(bead))
      ..writeln()
      ..writeln('## Stay cheap — this is a lens, not a committee')
      ..writeln(
        'You are standing in the bead\'s worktree. Spend a BOUNDED look, not an '
        'exploration: `ls docs/adr/` to see what register exists, and grep ONLY '
        'the surfaces the bead actually names. Do NOT design the change, do NOT '
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
        '{"rubric":"$rubric","version":1,"grade":"<A-F>","rationale":"<why + '
        'what would fix it>","nodePath":"$nodePath"}',
      )
      ..writeln()
      ..writeln(
        'The `nodePath` value above is FIXED — copy it byte-for-byte into your '
        'verdict; it is how the reviewer confirms the verdict belongs to THIS '
        'node.',
      )
      ..writeln()
      ..writeln(
        'You MUST write that JSON to the exact ABSOLUTE path `$path` before you '
        'finish. It is an absolute path on purpose — write it there regardless '
        'of your current working directory. This is REQUIRED even if you also '
        'state your verdict in your response text — stating the grade in prose '
        'alone does NOT satisfy this instruction. Write the file at `$path`.',
      );
    return b.toString();
  }
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

/// TIER 3 — the readiness DECISION point (zero agents). Reads the readiness
/// lane's grade + rationale off the ambient [SiblingView] (the effect verb —
/// never a subscription/re-query, D-5), applies the pure [decideReadiness]
/// matrix, and either advances ([Ok], with the route-style provenance the code
/// and spec routes emit) or HOLDS ([Gate], carrying the refinement ask).
///
/// The lane it reads is its `lane` param (default [kReadinessStep]) — the same
/// honesty the committee routes carry in their `critics`/`gating` params: a
/// route NAMES the lanes it decided over.
class ReadinessRouteCapability extends ServiceCapability {
  /// Creates the readiness route.
  const ReadinessRouteCapability();

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    // Read the ambient value at ENTRY (while mounted); the matrix is pure over
    // the captured values.
    final siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    final laneId = args.params['lane'] ?? kReadinessStep;
    final lane = siblings.resultOf('${parentPath(args.nodePath)}/$laneId');

    return switch (decideReadiness(
      grade: lane['grade'],
      rationale: lane['rationale'] ?? '',
    )) {
      ReadinessDrive(:final grade) => Ok({
        'verdict': 'drive',
        'grade': grade,
        'lane': laneId,
        'rule': 'ready',
      }),
      ReadinessHold(:final reason) => Gate(reason),
    };
  }
}
