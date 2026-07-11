/// The SPECIFY stage + the spec-readiness committee (bead `pow-6ao`).
///
/// The corrected model (Nico, 2026-07-10): specify is a station ASSET — pure
/// agentic work AFTER discovery — that mounts as a stage in the PER-BEAD
/// WORKTREE upstream of the build stage, with its own committee review. The
/// `code` circuit's drive loop is now
///
///   [specify agent → SPEC committee gate] → [build agent → CODE committee
///   gate → land]
///
/// with zero engine change: `specify` and `spec_review` are two more steps in
/// [kCodeCircuit] (`code_capabilities.dart`), and `agent`'s `dependsOn:
/// {'spec_review'}` resolves through the engine's existing one-hop terminal
/// resolution to `<bead>/spec_review/route`'s positive terminal — a route
/// [Gate] parks the bead in the SAME `gated` state (the `type=gate` bead + the
/// `<bead>#rN` rework re-key) the code committee already uses, so spec rework
/// reuses the existing gated machinery rather than a new state.
///
/// **The stage** ([SpecifyCapability]): an architect-equivalent harness ride —
/// the resolved agent (claude by default, ADR-0008 Decision 10) runs in the
/// bead's worktree and writes the implementation-ready spec INTO the bead via
/// the bd CLI: testable `--acceptance` checkboxes; a `--design` body carrying
/// `## Implementation Plan` (literal Dart code / exact file paths / exact
/// `dart test` commands / conventional-commit messages), `## Touches`, a
/// MANDATORY `## ADR Alignment` (grep the SUBSTATION's `docs/adr/` — the
/// ADR-0000 register, the org invariant — and cite load-bearing clauses), and
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
/// **Freshness posture**: the committee grades the ambient [Bead] the engine
/// re-provides after specify's bd mutation lands — the same bd-watch →
/// diff → reconcile loop that made the bead ready in the first place. Every
/// capability here reads that ambient state at entry and trusts it (the
/// tg-83y posture, `committee.dart`); the fail direction is SAFE by
/// construction — a stale or empty spec grades F and gates (a false PARK a
/// human unwinds), never a false advance to the build.
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

/// The spec-readiness committee circuit (id `spec_review`) — a hygiene step
/// ([ClearCritiqueCapability], shared with the code committee so a rework
/// round's verdict files are always round-fresh) → the deterministic gating
/// lane + four LLM critics fanned out in parallel → a `route` join running
/// the SAME deterministic matrix ([RouteCapability]) over the spec grades.
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
    CapabilityStep(stepId: kClearCritiqueStep, capabilityId: kClearCritiqueStep),
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
      capabilityId: 'route',
      dependsOn: {
        kSpecGatingRubric,
        'coherence',
        'adr-alignment',
        'acceptance-testability',
        'plan-completeness',
      },
      params: {
        'critics': 'spec-validation,coherence,adr-alignment,'
            'acceptance-testability,plan-completeness',
        'gating': kSpecGatingRubric,
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
  const SpecifyCapability();

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
      brief: buildSpecifyBrief(bead, workspace),
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
  Future<Map<String, String>?> result(TreeContext context, StepArgs args) async {
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (workspace == null) return null;
    final usage = readUsageFields(workspace.workspaceDir, args.nodePath);
    return usage.isEmpty ? null : usage;
  }
}

/// Assembles the specify agent's full-bead brief + the spec-writing working
/// agreement (exposed for unit tests). Mirrors [buildAgentBrief]'s shape —
/// the full bead renders first (A36), the agreement carries the stage policy
/// — but the contract is the ARCHITECT's, not the builder's: write the spec
/// into the bead, verify it against the live tree, touch no code.
///
/// Q3′ (Track E): the only paths interpolated are the ambient [Workspace]'s
/// (`workspaceDir`/`branch`); bead reads are content + the bead ID (a
/// reference, never a path).
AgentBrief buildSpecifyBrief(Bead bead, Workspace workspace) {
  final title = bead.title.isNotEmpty ? bead.title : 'work bead ${bead.id}';
  final substation = bead.metadata['rig'];
  final id = bead.id;
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
      'LOUD or GONE. No placeholders — "TBD", "add appropriate error '
      'handling", "similar to step N" are spec failures the committee '
      'F-gates.',
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
      'FIRST, from the worktree root: `ls docs/adr/` then `grep -li '
      '"<keyword1>\\|<keyword2>" docs/adr/*.md` with 3-6 keywords from the '
      'bead\'s title and touched surfaces (the register\'s ADR-0000 is the '
      'living AI-decision register — its pending `A<n>` amendments bind too). '
      'Cite each load-bearing ADR/amendment by file path AND clause (e.g. '
      '`docs/adr/ADR-0000-ai-decision-register.md` A9 — "<one-sentence '
      'quote>") and say how the plan aligns. If grep returns nothing '
      'relevant, write exactly: No ADR applies — verified via grep on '
      '`<keywords>`.',
    )
    ..writeln()
    ..writeln(
      '**## Validation Plan** — one item per acceptance criterion, mapped '
      '1:1: `- [ ] <criterion> → \'<exact command>\' → <expected output>`. No '
      'gaps — every criterion has its validation, every validation names its '
      'criterion.',
    )
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
/// each with the `nodePath` freshness stamp and a named `transport`; plus the
/// FT-2 usage merge): one transport stack serves both committees, so a
/// hardening landed for the code critics (gate-integrity #3/#4, tg-291)
/// automatically holds here. Only the SPAWN differs — a spec critic is always
/// an agent (there is no `sh -c` validation-runner flavor; the spec gate is
/// [SpecValidationCapability]) and its prompt is [buildSpecCriticPrompt]: the
/// review subject is the bead's SPEC, never a pinned diff (no code exists
/// yet).
class SpecCriticCapability extends CriticCapability {
  /// Creates the spec critic, optionally over a rubric source (D-9 wires
  /// the Packaged-AI-Asset loader; absent ⇒ an inline placeholder so the
  /// circuit is testable with no real assets).
  const SpecCriticCapability({super.rubrics});

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
        task: buildSpecCriticPrompt(
          bead,
          rubric,
          args.nodePath,
          workspace.workspaceDir,
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
  /// round reuses the workspace directory), the workspace-derived ABSOLUTE
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
    String workspaceDir,
  ) {
    final path = p.join(workspaceDir, '.grid', 'critique', '$rubric.json');
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
        'announced as new is a finding, not a style nit), and check the '
        'substation\'s ADR register under `docs/adr/` for the decisions the '
        'spec cites — or should have cited. A claim you cannot verify grades '
        'down; do not take the spec\'s word for the world.',
      )
      ..writeln()
      ..writeln('## Your verdict')
      ..writeln(
        'Grade the spec A (best) through F (worst) against `$rubric` ONLY. '
        'Your verdict is JSON of this exact shape:',
      )
      ..writeln(
        '{"rubric":"$rubric","version":1,"grade":"<A-F>","rationale":"<why>",'
        '"nodePath":"$nodePath"}',
      )
      ..writeln()
      ..writeln(
        'The `nodePath` value above is FIXED — copy it byte-for-byte into '
        'your verdict; it is how the reviewer confirms your verdict belongs '
        'to THIS round, not a leftover from an earlier one.',
      )
      ..writeln()
      ..writeln(
        'You MUST write that JSON to the exact ABSOLUTE path `$path` before '
        'you finish. It is an absolute path on purpose — write it there '
        'regardless of your current working directory. This is REQUIRED even '
        'if you also state your verdict in your response text — stating the '
        'grade in prose alone does NOT satisfy this instruction. Write the '
        'file at `$path`.',
      );
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
    ..writeln('## The work bead (its Acceptance criteria + Design ARE the spec)')
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
/// (`## Implementation Plan` with numbered steps, `## Touches`,
/// `## ADR Alignment`, `## Validation Plan` with at least one item), free of
/// the placeholder tokens the pack bans (TBD / TODO / "implement later" /
/// "as needed" / "appropriate error handling" / "similar to step"). A bead
/// with no spec at all — the pre-specify state — grades F, so the specify
/// stage can never be silently skipped. Fail-closed: a missing ambient bead
/// grades F too.
///
/// The placeholder fence reads the spec's PROSE only: markdown quotation
/// contexts — fenced ``` blocks, inline `code` spans, `>` blockquote lines —
/// are stripped before matching, so a spec that QUOTES a banned token as
/// evidence (a `// TODO` comment the plan deletes, an ADR clause or gate note
/// cited verbatim) is pointing at work, not deferring it, and never parks.
///
/// What the structure check does NOT judge — whether the criteria are truly
/// testable, the plan truly complete, the ADR citations truly load-bearing —
/// is exactly what the four LLM lanes own.
class SpecValidationCapability extends ServiceCapability {
  /// Creates the spec-validation gate.
  const SpecValidationCapability();

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    // Read the ambient bead at ENTRY (while mounted); the check below is pure
    // over the captured value.
    final bead = context.getInheritedSeedOfExactType<Bead>();
    if (bead == null) {
      return const Ok({
        'grade': 'F',
        'transport': 'structural',
        'rationale': 'no ambient work bead to validate — fail-closed',
      });
    }
    final findings = specStructuralFindings(bead);
    if (findings.isEmpty) {
      return const Ok({'grade': 'A', 'transport': 'structural'});
    }
    return Ok({
      'grade': 'F',
      'transport': 'structural',
      'rationale': findings.join('; '),
    });
  }
}

/// The placeholder tokens that anchor an automatic structural F — a spec that
/// says "fill in later" in any spelling is not implementation-ready. Word
/// tokens (`tbd`/`todo`) match on word boundaries so an identifier that
/// merely contains the letters never trips; the phrases match verbatim
/// (case-insensitive). Matched against [_proseOnly] output — a token inside a
/// markdown quotation context (quoted code, a cited clause) never trips.
final List<RegExp> _placeholderPatterns = [
  RegExp(r'\btbd\b', caseSensitive: false),
  RegExp(r'\btodo\b', caseSensitive: false),
  RegExp('implement later', caseSensitive: false),
  RegExp('fill in later', caseSensitive: false),
  RegExp('as needed', caseSensitive: false),
  RegExp('appropriate error handling', caseSensitive: false),
  RegExp('similar to step', caseSensitive: false),
];

/// The structural findings for [bead]'s spec — empty iff the spec is whole.
/// Pure and exposed for unit tests; [SpecValidationCapability] grades A iff
/// this returns empty. Each finding names what is missing (guards LOUD), so
/// the route's gate reason — and the rework round's operator — never has to
/// diff the spec by hand.
List<String> specStructuralFindings(Bead bead) {
  final findings = <String>[];
  final acceptance = bead.acceptanceCriteria;
  final design = bead.design;

  // Testable acceptance: at least one `- [ ]` checkbox criterion.
  if (!RegExp(r'^\s*-\s*\[[ xX]\]\s*\S', multiLine: true).hasMatch(acceptance)) {
    findings.add('acceptance: no testable `- [ ]` checkbox criteria');
  }

  // The four design sections.
  if (!design.contains('## Implementation Plan')) {
    findings.add('design: no `## Implementation Plan` section');
  } else if (!RegExp(r'^\s*1[.)]\s', multiLine: true).hasMatch(design)) {
    findings.add('design: `## Implementation Plan` has no numbered steps');
  }
  if (!design.contains('## Touches')) {
    findings.add('design: no `## Touches` section');
  }
  if (!design.contains('## ADR Alignment')) {
    findings.add('design: no `## ADR Alignment` section');
  }
  final validationAt = design.indexOf('## Validation Plan');
  if (validationAt < 0) {
    findings.add('design: no `## Validation Plan` section');
  } else {
    final body = _sectionBody(design, validationAt);
    if (!RegExp(r'^\s*-\s*\S', multiLine: true).hasMatch(body)) {
      findings.add('design: `## Validation Plan` has no items');
    }
  }

  // Placeholder tokens anywhere in the spec's PROSE — quotation contexts
  // (quoted code, cited clauses) are evidence, not deferral, and never trip.
  final prose = _proseOnly('$acceptance\n$design');
  for (final pattern in _placeholderPatterns) {
    final match = pattern.firstMatch(prose);
    if (match != null) {
      findings.add('placeholder: "${match.group(0)}" — not implementation-ready');
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
String _proseOnly(String spec) => spec
    .replaceAll(RegExp('```.*?```', dotAll: true), '  ')
    .replaceAll(RegExp(r'^[ \t]*>.*$', multiLine: true), '  ')
    .replaceAll(RegExp('`[^`\n]*`'), '  ');

/// The body of the section whose `## ` heading starts at [headingAt] — the
/// text after the heading line up to the next `## ` heading (or the end).
String _sectionBody(String design, int headingAt) {
  final afterHeading = design.indexOf('\n', headingAt);
  if (afterHeading < 0) return '';
  final next = design.indexOf('\n## ', afterHeading);
  return design.substring(afterHeading, next < 0 ? design.length : next);
}
