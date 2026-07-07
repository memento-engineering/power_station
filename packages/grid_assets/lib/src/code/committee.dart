/// The adversarial code-committee — a reentrant sub-circuit composed at the
/// existing `CircuitScope` seam (ADR-0008 D2/D4 / M5 "The Circuit" Track C).
///
/// factoryskills' code review runs ONE critic per rubric in ISOLATION
/// (anti-anchoring: a critic sees only its own rubric, never the others' grades),
/// fans the four critics out in parallel, then a `route` step aggregates their
/// grades through a deterministic matrix (asset policy, never engine). The
/// committee is just circuit wiring + two `Capability` leaves — the parallelism +
/// await-all join is already proven by the Burn (M4-P1 Track J); no new engine
/// machinery is introduced here.
///
/// The four lanes:
///  - `code-validation` — the GATING lane: runs the bead's OWN Validation Plan in
///    the workspace (a real `sh` command); grade A iff every command was zero,
///    else F. A non-zero plan is a HARD block, decided by the route.
///  - `spec-adherence` / `regression-risk` / `test-coverage` — three LLM critics:
///    each RIDES the resolved agent harness (ADR-0008 Decision 10 — critics are
///    agents; `claude` by default) with ONLY its own rubric and writes a verdict
///    JSON the `result()` hook parses into a grade.
///
/// **Gate-integrity #3 — the stale-shadow + no-file transport miss (bead
/// `tg-bns`)**: a rework round reuses the SAME workspace directory, so
/// `.grid/critique/<rubric>.json` (and the gating lane's `.rc`) from a PRIOR
/// round survives on disk. When the CURRENT round's critic exits clean but
/// (tg-291's residual risk) never writes its file, `result()` was reading the
/// PREVIOUS round's file — a stale grade impersonating a fresh one, not a
/// recognized miss. Two independent, defense-in-depth fixes:
///  1. [ClearCritiqueCapability] (`clear-critique`) — a dep-free step every
///     critic lane `dependsOn` — wipes `.grid/critique/` at the START of every
///     round, before any lane can read or write.
///  2. Every LLM verdict JSON carries a `nodePath` freshness stamp (the
///     round-qualified step path — round is embedded in the bead id via the
///     rework re-key, `<bead>#rN`); [_verdictFromFile] REJECTS a file whose
///     stamp doesn't match the CURRENT step's `nodePath`, falling through to
///     the envelope/fail-closed transports exactly as if the file were absent.
///     (The gating lane's `.rc` needs no stamp — fix 1 alone already clears it
///     every round, and it carries no separate fallback transport.)
///  Every verdict's result payload also carries a `transport` field
///  (`file`/`envelope`/`fail-closed-default`) naming which of the three
///  channels actually produced the grade — durable, queryable provenance
///  (visible on `grid.result.<nodePath>.transport`) rather than a silent
///  choice, so a false-gate post-mortem never again has to guess which path
///  fired (case B: a fail-closed default with NO rationale was itself a gap —
///  it now always carries one).
///
/// **The flaky write path itself (item 4, root-cause)**: the two live
/// incidents #3 addressed (tg-x1j r3 regression-risk: 346s/28-turns/no file;
/// tg-42f r1 test-coverage: 13-turns/no file, no stale shadow) had no captured
/// transcript to confirm WHY the critic's own file-write tool call never landed
/// — cwd drift, a turn-budget cutoff before the write, or prompt drift were all
/// plausible and not distinguishable from static review alone; the #3 fixes
/// close the SYMPTOM (a stale/absent file being mis-scored) regardless of which.
///
/// **Gate-integrity #4 — the cwd-relative write path, confirmed (bead
/// `tg-r66`)**: a later live incident (session `tgdog-snp`/`tg-m2q` r1,
/// 2026-07-07) DID capture the cwd-drift hypothesis in the act: the critic
/// prompt asked for the RELATIVE path `.grid/critique/<rubric>.json`, and a
/// `test-coverage` critic that `cd`d into a package to run `dart test`
/// resolved it against its new cwd, writing a STRAY verdict at
/// `packages/grid_assets/.grid/critique/test-coverage.json` — so the canonical
/// path was empty AND the stdout envelope parse missed the critic's
/// `## Grade: A` summary shape ⇒ a false fail-closed F ⇒ ps#11's false gate.
/// Three defense-in-depth fixes: (1) [CriticCapability.buildCriticPrompt] now
/// interpolates the workspace-derived ABSOLUTE canonical path, so the write is
/// cwd-invariant; (2) [_strayVerdict] is a read-side belt that accepts a
/// round-fresh stray `.grid/critique/<rubric>.json` found anywhere under the
/// worktree (the `nodePath` freshness stamp keeps it safe); (3) the envelope
/// fallback ([_verdictFromHeading]) now also recognizes a `Grade: <A-F>`
/// heading, not just `Verdict:`. A critic that keeps failing to write a
/// canonical file now reliably grades a LOUD, provenanced fail-closed F every
/// round (or is recovered from the stray/envelope), never a silently-recycled
/// stale grade.
///
/// **A third, DISTINCT incident class (tg-83y r3, 2026-07-04) is OUT OF SCOPE
/// here**: the LLM lanes graded against a tree the agent was still editing
/// (its final commit landed AFTER the grading window), and the gating lane's
/// re-run still F'd against what looked like the committed tree — an
/// intra-round ORDERING bug (the review sub-circuit mounting before the
/// agent's completion is truly durable), not a transport miss. Nothing in
/// this file can fix it: every capability here reads the ambient [Workspace]
/// / bead state the_grid's engine hands it at entry and trusts it; the fix is
/// upstream, in the_grid's own session/reconcile sequencing (gating the
/// `review` mount on the agent step's durable completion — a fence/commit —
/// and running against the COMMITTED tree state), tracked alongside
/// `SCRATCH-orchestration-determinism.md`'s I-catalog in that repo.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;

import '../agent/agent_domain.dart';
import '../agent/agent_harness.dart';
import '../agent/usage_report.dart';

/// The gating rubric id — its grade `F` is a hard block (a non-zero Validation
/// Plan command), decided by the route's matrix.
const String kGatingRubric = 'code-validation';

/// The three LLM critic rubric ids (each graded in isolation by a `claude`
/// critic; anti-anchoring).
const List<String> kLlmRubrics = [
  'spec-adherence',
  'regression-risk',
  'test-coverage',
];

/// Every committee rubric id, in declaration order (the gating lane first).
const List<String> kCommitteeRubrics = [kGatingRubric, ...kLlmRubrics];

/// The workspace-relative directory each critic writes its verdict / rc into.
const String _critiqueDir = '.grid/critique';

/// The hygiene step id every critic lane `dependsOn` (gate-integrity #3) —
/// wipes [_critiqueDir] before any lane can read or write this round.
const String kClearCritiqueStep = 'clear-critique';

/// A pluggable source of a rubric's prose text by id (D-9: the Packaged-AI-Asset
/// loader replaces the inline placeholder). Returns the rubric body a critic's
/// prompt embeds.
typedef RubricSource = String Function(String rubricId);

/// The pluggable critique-dir hygiene seam [ClearCritiqueCapability] uses
/// (D-9-style injection, mirrors [RubricSource]) — defaults to the real
/// delete+recreate; tests inject a no-op so the offline suite never touches a
/// real filesystem at a synthetic workspace path.
typedef DirectoryClearer = void Function(String dir);

/// The adversarial code-committee circuit (id `code_review`) — a hygiene step
/// (gate-integrity #3, [ClearCritiqueCapability]) followed by four critic
/// lanes fanned out in parallel, then a `route` step that joins on all four
/// and aggregates their grades (M5 Track C / C1).
///
/// Reentrant: composed at the same `CircuitScope` seam as any other circuit, so
/// Track E can drop it in as the `code` circuit's `verify` via a `SubCircuitStep`
/// with zero engine changes.
const Circuit kCodeReviewCircuit = Circuit(
  id: 'code_review',
  terminalStepId: 'route',
  steps: [
    CapabilityStep(stepId: kClearCritiqueStep, capabilityId: kClearCritiqueStep),
    CapabilityStep(
      stepId: kGatingRubric,
      capabilityId: 'critic',
      params: {'rubric': kGatingRubric},
      dependsOn: {kClearCritiqueStep},
    ),
    CapabilityStep(
      stepId: 'spec-adherence',
      capabilityId: 'critic',
      params: {'rubric': 'spec-adherence'},
      dependsOn: {kClearCritiqueStep},
    ),
    CapabilityStep(
      stepId: 'regression-risk',
      capabilityId: 'critic',
      params: {'rubric': 'regression-risk'},
      dependsOn: {kClearCritiqueStep},
    ),
    CapabilityStep(
      stepId: 'test-coverage',
      capabilityId: 'critic',
      params: {'rubric': 'test-coverage'},
      dependsOn: {kClearCritiqueStep},
    ),
    CapabilityStep(
      stepId: 'route',
      capabilityId: 'route',
      dependsOn: {
        kGatingRubric,
        'spec-adherence',
        'regression-risk',
        'test-coverage',
      },
      params: {
        'critics': 'code-validation,spec-adherence,regression-risk,test-coverage',
        'gating': kGatingRubric,
      },
    ),
  ],
);

/// Wipes [_critiqueDir] at the START of every committee round — a
/// [ServiceCapability] all four critic lanes `dependsOn`, so it always
/// completes before any lane can read OR write a verdict (gate-integrity #3).
/// A rework round reuses the SAME workspace directory, so a prior round's
/// verdict/rc file otherwise survives on disk; clearing first turns a
/// critic's missing write back into a recognizable miss instead of a stale
/// grade impersonating a fresh one.
///
/// Best-effort BY DESIGN: a delete/recreate failure never Gates the round —
/// [_verdictFromFile]'s `nodePath` freshness stamp is the fail-safe backstop
/// for the LLM lanes when the clear itself couldn't run; the gating lane's own
/// `sh -c` script always `mkdir -p`s the dir again regardless.
class ClearCritiqueCapability extends ServiceCapability {
  /// Creates the capability, optionally over an injected [clearer] (tests
  /// inject a no-op so the offline suite never touches a real filesystem at a
  /// synthetic workspace path — Fakes, not mocks); defaults to the real
  /// delete+recreate.
  const ClearCritiqueCapability({DirectoryClearer? clearer}) : _clearer = clearer;

  final DirectoryClearer? _clearer;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (workspace == null) return const Ok();
    try {
      (_clearer ?? _clearDirectory)(p.join(workspace.workspaceDir, _critiqueDir));
    } catch (_) {
      // Best-effort hygiene — the freshness stamp is the fail-safe backstop.
    }
    return const Ok();
  }
}

/// The real [DirectoryClearer]: deletes [dir] (if present) and recreates it
/// empty.
void _clearDirectory(String dir) {
  final d = Directory(dir);
  if (d.existsSync()) d.deleteSync(recursive: true);
  d.createSync(recursive: true);
}

/// One critic, in isolation — a [ProcessCapability] whose `params['rubric']`
/// selects the lane (C2). Two flavors behind the single `critic` capability id:
///
///  - the GATING `code-validation` lane runs the bead's OWN Validation Plan via
///    `sh`: it wraps the plan so the plan's exit code is captured to an rc file,
///    so ANY terminal exit `complete`s the step (the grade — A iff the plan was
///    zero, else F — rides the [result] hook, leaving the route as the single
///    decision point: no retry storm on a deterministic command failure). It is
///    a VALIDATION RUNNER, not an agent — it keeps its direct `sh -c` config;
///  - the three LLM lanes RIDE THE HARNESS (ADR-0008 Decision 10 — critics are
///    agents): the effective [AgentConfig] resolves through the same ladder as
///    the coding agent, and the resolved harness carries the critic's prompt
///    (ONLY its own rubric); the verdict JSON is parsed by the [result] hook,
///    which also merges the harness's CAPTURE-ONLY usage telemetry (FT-2 —
///    tokens/cost/turns/duration) alongside the grade (fail-safe: no usage ⇒
///    just the grade).
///
/// A capability reads its ambient values — the work [Bead], the [Workspace],
/// the agent scope — with the effect verb (`getInheritedSeedOfExactType`) at
/// entry, and holds no writer/notifier: the four derailment-invariants hold by
/// layering + the host's single write-locus.
class CriticCapability extends ProcessCapability {
  /// Creates the critic, optionally over a [rubrics] source (D-9 wires the
  /// Packaged-AI-Asset loader; absent ⇒ an inline placeholder so C is testable
  /// with no real assets).
  const CriticCapability({RubricSource? rubrics}) : _rubrics = rubrics;

  final RubricSource? _rubrics;

  String _rubricOf(StepArgs args) => args.params['rubric'] ?? '';

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) {
    // Read the ambient values at ENTRY (synchronously, while mounted).
    final rubric = _rubricOf(args);
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (bead == null || workspace == null) {
      throw StateError(
        'CriticCapability requires the ambient Bead + Workspace '
        '(WorkBead/SessionScope mount them)',
      );
    }
    if (rubric == kGatingRubric) {
      // The validation runner — a deterministic `sh -c`, NOT an agent.
      return RuntimeConfig(
        workDir: workspace.workspaceDir,
        command: 'sh',
        args: ['-c', _gatingScript(_validationPlan(bead))],
        lifecycle: Lifecycle.oneTurn,
      );
    }
    // The critic lanes are agents (ADR-0008 Decision 10): resolve the
    // effective config through the ladder and delegate the invocation to the
    // resolved harness — exactly like AgentCapability.spawn.
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
        task: buildCriticPrompt(
          bead,
          rubric,
          args.nodePath,
          workspace.workspaceDir,
        ),
      ),
      workspace: workspace,
      // CAPTURE-ONLY usage telemetry (FT-2): the resolved harness (claude)
      // redirects its `--output-format json` envelope here; result() merges the
      // fields into the critic's payload. The verdict file the critic writes is
      // a separate path, so capture never touches the grade.
      usageOut: usageReportPath(args.nodePath),
    );
  }

  @override
  StepSignal interpretEvent(RuntimeEvent event) {
    // The lane is encoded in the event name (`$sessionId/.../$stepId`, and the
    // step id IS the rubric id) — the only lane signal available to the
    // ctx-free interpretEvent. The GATING lane `complete`s on ANY terminal exit
    // (the grade rides result()); the LLM lanes use the standard job mapping (a
    // clean exit completes, a non-zero exit / death fails).
    final isGating = event.name.endsWith('/$kGatingRubric');
    if (isGating) {
      return switch (event) {
        Exited() => StepSignal.complete,
        Died() => StepSignal.failed,
        _ => StepSignal.none,
      };
    }
    return switch (event) {
      Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
      Exited() || Died() => StepSignal.failed,
      _ => StepSignal.none,
    };
  }

  @override
  Future<Map<String, String>?> result(TreeContext context, StepArgs args) async {
    // Read the ambient workspace at ENTRY (while mounted); only the captured
    // value is touched below.
    final rubric = _rubricOf(args);
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (workspace == null) {
      throw StateError(
        'CriticCapability.result requires the ambient Workspace '
        '(SessionScope mounts it)',
      );
    }
    final workspaceDir = workspace.workspaceDir;
    if (rubric == kGatingRubric) {
      // The plan's exit code, captured by the spawn wrapper. Fail-closed: a
      // missing rc (the plan never ran) grades F — a plan-less bead must NEVER
      // silently pass. [ClearCritiqueCapability] wipes this file every round,
      // so an rc found here is guaranteed fresh — no separate stamp needed.
      final rc = File(p.join(workspaceDir, _critiqueDir, '$kGatingRubric.rc'));
      if (!rc.existsSync()) {
        return const {
          'grade': 'F',
          'transport': 'fail-closed-default',
          'rationale': 'no validation-plan rc file — fail-closed default',
        };
      }
      final code = rc.readAsStringSync().trim();
      return {'grade': code == '0' ? 'A' : 'F', 'transport': 'file'};
    }
    // An LLM critic's verdict JSON. Fail-closed: a missing / malformed / STALE
    // verdict (no file, unparseable JSON, no readable `grade`, or a `nodePath`
    // stamp that doesn't match THIS round — gate-integrity #3) falls back, in
    // order, to a round-fresh STRAY verdict (gate-integrity #4 — a critic that
    // cd'd mid-run wrote the file under a subdir instead of the canonical path;
    // [_strayVerdict]) then to the captured harness RESULT TEXT (tg-291 — the
    // verdict-transport brittleness: a critic that graded cleanly but wrote its
    // verdict into stdout instead of the file must not be scored F on a
    // transport slip alone). The canonical FILE wins whenever it parses AND is
    // fresh; only an absent/malformed/stale canonical file consults the
    // fallbacks. No parseable verdict ANYWHERE still grades F — every path now
    // names its own `transport` (`file`/`file-stray`/`envelope`/
    // `fail-closed-default`), so a false-gate post-mortem never has to guess
    // which channel produced the grade.
    final verdict = File(p.join(workspaceDir, _critiqueDir, '$rubric.json'));
    final graded = _verdictFromFile(verdict, expectedNodePath: args.nodePath) ??
        _strayVerdict(workspaceDir, rubric, args.nodePath) ??
        _verdictFromResultText(
          readEnvelopeResultText(workspaceDir, args.nodePath),
        ) ??
        const {
          'grade': 'F',
          'transport': 'fail-closed-default',
          'rationale':
              'no parseable verdict via file or envelope — fail-closed default',
        };
    // Merge the CAPTURE-ONLY usage telemetry (FT-2) into the payload. FAIL-SAFE:
    // an absent / malformed envelope yields no fields, NEVER a throw — the grade
    // (fail-closed above) is unaffected. Collision-safe keys (grade/rationale vs
    // tokensIn/…), so the merge never shadows the verdict.
    final usage = readUsageFields(workspaceDir, args.nodePath);
    return usage.isEmpty ? graded : {...graded, ...usage};
  }

  /// The rubric prose embedded in a critic's prompt — the injected [rubrics]
  /// source (D-9), or an inline placeholder so C is testable with no assets.
  String _rubricText(String rubric) =>
      _rubrics?.call(rubric) ??
      '(rubric `$rubric` — the Packaged-AI-Asset loader supplies the bands in '
          'Track D)';

  /// Assembles the LLM critic's prompt for [rubric] over the work [bead] —
  /// names ONLY its own rubric (anti-anchoring: a critic must not see the other
  /// lanes' concerns or grades), carries the full bead, and instructs a single
  /// A–F grade written as a verdict JSON. Rides the harness as a bare
  /// `AgentBrief(task: …)` (no working agreement, no context blocks — so the
  /// rendered brief IS this prompt, byte-identical).
  ///
  /// The file-write instruction is deliberately the LAST thing the prompt says
  /// (tg-291 — recency: a model observed to state a clean verdict in its
  /// response prose while skipping the file write, tripping a false gate on the
  /// fail-closed missing-file rule). It is imperative, names the exact path, and
  /// is explicit that stating the verdict in prose does NOT satisfy it — the
  /// file write is REQUIRED regardless. `result()` still has a stdout-envelope
  /// fallback for when a critic slips anyway; this hardening is to make the
  /// slip rarer, not to rely on the fallback.
  ///
  /// The verdict JSON also carries a `nodePath` FRESHNESS STAMP — [nodePath]
  /// copied byte-for-byte (gate-integrity #3) — so [_verdictFromFile] can
  /// reject a file left over from an earlier round (the SAME workspace
  /// directory is reused across rework rounds) instead of silently reading it
  /// as this round's verdict.
  ///
  /// **Gate-integrity #4 — the cwd-relative write path (bead `tg-r66`)**: the
  /// path handed to the critic is the workspace-derived ABSOLUTE canonical
  /// path (`[workspaceDir]/.grid/critique/<rubric>.json`), NOT a
  /// workspace-relative one. A critic that `cd`s mid-run (`test-coverage` cd's
  /// into a package to run `dart test` — the chronically flaky lane) would
  /// resolve a relative `.grid/critique/<rubric>.json` against its CURRENT cwd
  /// and write a STRAY verdict under the package (observed live:
  /// `packages/grid_assets/.grid/critique/test-coverage.json`), leaving the
  /// canonical path empty ⇒ a false fail-closed gate. An absolute path is
  /// cwd-invariant, so the write lands where `result()` reads regardless of
  /// where the critic wandered. ([_strayVerdict] is the read-side belt for a
  /// critic that still writes off-path some other way.)
  ///
  /// Exposed for unit tests.
  String buildCriticPrompt(
    Bead bead,
    String rubric,
    String nodePath,
    String workspaceDir,
  ) {
    final path = p.join(workspaceDir, _critiqueDir, '$rubric.json');
    final b = StringBuffer()
      ..writeln('# Code review — rubric: `$rubric`')
      ..writeln()
      ..writeln(
        'You are ONE critic in an adversarial committee. Review the work ONLY '
        'against the `$rubric` rubric below — do not weigh any other concern.',
      )
      ..writeln()
      ..writeln('## Rubric: $rubric')
      ..writeln(_rubricText(rubric))
      ..write(_beadBlock(bead))
      ..writeln()
      ..writeln('## Your verdict')
      ..writeln(
        'Grade the work A (best) through F (worst) against `$rubric` ONLY. '
        'Your verdict is JSON of this exact shape:',
      )
      ..writeln(
        '{"rubric":"$rubric","version":1,"grade":"<A-F>","rationale":"<why>",'
        '"nodePath":"$nodePath"}',
      )
      ..writeln()
      ..writeln(
        'The `nodePath` value above is FIXED — copy it byte-for-byte into your '
        'verdict; it is how the reviewer confirms your verdict belongs to THIS '
        'round, not a leftover from an earlier one.',
      )
      ..writeln()
      ..writeln(
        'You MUST write that JSON to the exact ABSOLUTE path `$path` before you '
        'finish. It is an absolute path on purpose — write it there regardless '
        'of your current working directory (if you `cd` elsewhere to run a '
        'command, this path still resolves to the right file). This is REQUIRED '
        'even if you also state your verdict in your response text — stating the '
        'grade in prose alone does NOT satisfy this instruction. Write the file '
        'at `$path`.',
      );
    return b.toString();
  }
}

/// The route/aggregate step — a [ServiceCapability] that reads its sibling
/// critics' grades through the AMBIENT [SiblingView] (mounted by
/// `SessionScope`; read with the effect verb — D-5, never a subscription/
/// re-query) and applies the deterministic matrix (C3, asset policy):
///
///  - the gating critic grade `F` (a non-zero Validation Plan) → [Gate] (hard
///    block);
///  - a grade SPREAD ≥ 3 letters across the lanes → [Gate] (human ultimatum);
///  - any NON-gating critic at `D`/`F` → [Gate] (rework — the `restForOne`
///    transitive re-key is deferred, so a D/F parks at a gate for now);
///  - else (all A–C, gating not F, spread < 3) → [Ok] (advance to land).
///
/// The advance [Ok] payload carries ROUTE PROVENANCE (FT-2, CAPTURE-ONLY): the
/// grade vector consumed (`grades` — `lane=grade` CSV in [kCommitteeRubrics]
/// order), the computed `spread`, and the matrix arm that fired (`rule` =
/// `all-approve`) — making the keep/kill export self-contained without changing
/// the matrix. Gate outcomes are UNCHANGED (their reason string already names
/// the rule).
///
/// Fail-closed: an unread / missing sibling grade is treated as `F`, so a forged
/// or absent grade can NEVER advance (the mutation-tested property).
class RouteCapability extends ServiceCapability {
  /// Creates the route capability.
  const RouteCapability();

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    // Read the ambient sibling view at ENTRY (while mounted); the matrix below
    // is pure over the captured values.
    final siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    final parent = _parentPath(args.nodePath);
    final gating = args.params['gating'] ?? '';
    final criticIds = (args.params['critics'] ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // Read each lane's RAW grade once (null/empty ⇒ missing), then the
    // fail-closed grade used by the block rules (missing ⇒ F).
    final rawGrades = <String, String?>{
      for (final id in criticIds)
        id: siblings.resultOf('$parent/$id')['grade'],
    };
    final grades = <String, String>{
      for (final entry in rawGrades.entries)
        entry.key: _normalizeGrade(entry.value),
    };

    // 1. the gating lane failed (a non-zero Validation Plan, or a missing
    // gating grade) — a hard block.
    if (grades[gating] == 'F') {
      return const Gate('code-validation failed: hard block');
    }

    // 2. a grade spread ≥ 3 letters across the PRESENT lanes — a human
    // ultimatum. Missing grades are IGNORED here (they are already caught by
    // the fail-closed gating/D-F block rules), so the spread reflects only the
    // grades the critics actually returned.
    final indices = [
      for (final entry in rawGrades.entries)
        if (entry.value != null && entry.value!.trim().isNotEmpty)
          _gradeIndex(_normalizeGrade(entry.value)),
    ];
    final spread = indices.isEmpty
        ? 0
        : indices.reduce(math.max) - indices.reduce(math.min);
    if (spread >= 3) return const Gate('grade spread ≥ 3 — human ultimatum');

    // 3. any non-gating critic at D/F — rework → restForOne re-key is deferred
    // (build-order); a D/F parks at a gate for now.
    for (final entry in grades.entries) {
      if (entry.key == gating) continue;
      if (entry.value == 'D' || entry.value == 'F') {
        return const Gate('a critic returned D/F — rework');
      }
    }

    // 4. all A–C, gating clean, spread < 3 — advance. The advance payload
    // carries the ROUTE PROVENANCE (FT-2): the per-lane grade vector it consumed
    // (CSV `lane=grade` in kCommitteeRubrics order), the computed spread, and the
    // matrix arm that fired (`all-approve`) — so the keep/kill export is
    // self-contained. Gate outcomes keep their reason string (it names the rule).
    final gradesCsv = criticIds.map((id) => '$id=${grades[id]}').join(',');
    return Ok({
      'verdict': 'advance',
      'grades': gradesCsv,
      'spread': '$spread',
      'rule': 'all-approve',
    });
  }
}

/// The default code-committee critic-id index of [grade] (A=0 … F=5); a grade
/// outside `A..F` clamps to F (the fail-closed worst).
int _gradeIndex(String grade) {
  const ladder = ['A', 'B', 'C', 'D', 'E', 'F'];
  final i = ladder.indexOf(grade);
  return i < 0 ? ladder.length - 1 : i;
}

/// Normalizes a raw sibling grade to an upper-case letter, fail-closing a
/// null/empty grade to `F`.
String _normalizeGrade(String? grade) =>
    (grade == null || grade.trim().isEmpty) ? 'F' : grade.trim().toUpperCase();

/// The parent node path of [nodePath] (`'a/b/route'` → `'a/b'`), so a route
/// computes its sibling critic paths (`'$parent/$criticId'`).
String _parentPath(String nodePath) {
  final i = nodePath.lastIndexOf('/');
  return i < 0 ? '' : nodePath.substring(0, i);
}

/// The bead's OWN Validation Plan — the `validation_plan` metadata command. A
/// plan-less bead defaults to `false` (an explicit non-zero) so it grades F
/// rather than silently passing.
String _validationPlan(Bead bead) {
  final plan = bead.metadata['validation_plan'];
  if (plan is String && plan.trim().isNotEmpty) return plan.trim();
  return 'false';
}

/// The `sh -c` script the gating lane runs: ensure the critique dir, run the
/// plan in a subshell, and capture ITS exit code to the rc file `result()`
/// reads. The outer `sh` exits clean regardless, so the step always `complete`s
/// and the route is the single decision point.
String _gatingScript(String plan) =>
    'mkdir -p $_critiqueDir; ( $plan ) ; echo \$? > $_critiqueDir/$kGatingRubric.rc';

/// Renders the full work bead into a prompt block (title/description/design/
/// acceptance/notes) — the load-bearing review input.
String _beadBlock(Bead bead) {
  final title = bead.title.isNotEmpty ? bead.title : 'work bead ${bead.id}';
  final b = StringBuffer()
    ..writeln()
    ..writeln('## The work bead')
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

/// The verdict file's grade, when it parses AND is FRESH — `null` for an
/// absent file, invalid JSON, a missing/blank `grade` field, OR a `nodePath`
/// stamp that doesn't match [expectedNodePath] (gate-integrity #3: a rework
/// round reuses the same workspace, so a prior round's file can otherwise
/// survive on disk and be misread as this round's verdict). Every one of
/// these is treated as "unparseable" so [CriticCapability.result] falls
/// through to the RESULT TEXT fallback (tg-291). Never throws.
Map<String, String>? _verdictFromFile(
  File verdict, {
  required String expectedNodePath,
}) {
  if (!verdict.existsSync()) return null;
  try {
    final json = jsonDecode(verdict.readAsStringSync()) as Map<String, dynamic>;
    final grade = (json['grade'] as String?)?.trim().toUpperCase();
    if (grade == null || grade.isEmpty) return null;
    final stampedNodePath = (json['nodePath'] as String?)?.trim();
    if (stampedNodePath != expectedNodePath) return null; // stale — not ours.
    final rationale = (json['rationale'] as String?)?.trim() ?? '';
    return {
      'grade': grade,
      'transport': 'file',
      if (rationale.isNotEmpty) 'rationale': rationale,
    };
  } catch (_) {
    return null;
  }
}

/// A round-fresh verdict a critic wrote to a STRAY
/// `.../.grid/critique/<rubric>.json` somewhere OTHER than the canonical
/// workspace-root path — the read-side belt for gate-integrity #4 (bead
/// `tg-r66`). A critic that `cd`s mid-run (`test-coverage` cd's into a package
/// to run `dart test`) can resolve the verdict path against its current cwd and
/// write it under the package instead of at the worktree root (observed live:
/// `packages/grid_assets/.grid/critique/test-coverage.json`). [buildCriticPrompt]
/// now hands the critic the ABSOLUTE path so the write lands correctly, but this
/// belt recovers a verdict a critic still writes off-path some other way.
///
/// Walks [workspaceDir] for every `.grid/critique/<rubric>.json` and returns the
/// FIRST whose `nodePath` stamp matches THIS round — the stamp (gate-integrity
/// #3) is exactly what makes accepting an off-path file safe: a stale or foreign
/// stray can never match, so a leftover from an earlier round is never misread
/// as this round's verdict. The canonical path is skipped (the caller already
/// consulted it). `null` when no fresh stray exists. Best-effort: never throws.
Map<String, String>? _strayVerdict(
  String workspaceDir,
  String rubric,
  String expectedNodePath,
) {
  final canonical =
      p.canonicalize(p.join(workspaceDir, _critiqueDir, '$rubric.json'));
  for (final file in _strayVerdictFiles(workspaceDir, rubric)) {
    if (p.canonicalize(file.path) == canonical) continue; // the canonical path.
    final graded = _verdictFromFile(file, expectedNodePath: expectedNodePath);
    if (graded != null) return {...graded, 'transport': 'file-stray'};
  }
  return null;
}

/// Every `.../.grid/critique/<rubric>.json` file under [root], found by a
/// bounded DFS that prunes VCS/build/dependency dirs (`.git`, `.dart_tool`,
/// `node_modules`, `build`) so the fallback walk stays cheap. Symlinks are not
/// followed. Best-effort: an unreadable directory is skipped, never thrown.
Iterable<File> _strayVerdictFiles(String root, String rubric) sync* {
  const prune = {'.git', '.dart_tool', 'node_modules', 'build'};
  final target = p.join(_critiqueDir, '$rubric.json'); // '.grid/critique/<r>.json'
  final stack = <Directory>[Directory(root)];
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } catch (_) {
      continue; // unreadable — skip this subtree.
    }
    for (final entry in entries) {
      if (entry is Directory) {
        if (!prune.contains(p.basename(entry.path))) stack.add(entry);
      } else if (entry is File && _endsWithPath(entry.path, target)) {
        yield entry;
      }
    }
  }
}

/// Whether [path] ends with the relative [suffix] on a path-separator boundary
/// (so `.../pkg/.grid/critique/r.json` matches `.grid/critique/r.json`, but
/// `.../x.grid/critique/r.json` would not spuriously match `grid/critique/…`).
bool _endsWithPath(String path, String suffix) {
  if (!path.endsWith(suffix)) return false;
  if (path.length == suffix.length) return true;
  final boundary = path[path.length - suffix.length - 1];
  return boundary == p.separator || boundary == '/';
}

/// Recovers a verdict from a critic's raw harness RESULT TEXT (tg-291) — the
/// fallback transport [CriticCapability.result] consults when the verdict file
/// is absent or unparseable. FT-2 already captures the harness's
/// `--output-format json` result envelope for telemetry; its `result` field is
/// the critic's full stdout text, which sometimes carries the verdict the
/// critic forgot to also write to disk.
///
/// Recognizes, in order:
///  1. an embedded JSON verdict object (fenced or inline — `{"grade":...}`);
///  2. a `Verdict: <A-F>` OR `Grade: <A-F>` heading (markdown `##` and other
///     lead-ins allowed), with the prose that follows it as rationale — a
///     critic that summarizes with `## Grade: A` instead of `Verdict:` was
///     silently missed before (gate-integrity #4, bead `tg-r66`: the live
///     false gate whose stray file the belt above now also recovers).
///
/// Every recovered rationale is marked `[from result envelope]` so a grade
/// that rode this fallback is visibly distinguishable downstream. `null` when
/// neither shape yields a parseable grade (the caller then fail-closes to F).
Map<String, String>? _verdictFromResultText(String? text) {
  if (text == null) return null;
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  return _verdictFromEmbeddedJson(trimmed) ?? _verdictFromHeading(trimmed);
}

/// A single-letter A-F grade — the same strict shape [_verdictHeading]
/// enforces via its capture group. [buildCriticPrompt] hands the critic a
/// LITERAL `"grade":"<A-F>"` template; without this check, an echoed
/// template/example object in a stdout preamble would parse as a "valid"
/// verdict (tg-291 rework round 1). `grade` is already upper-cased by the
/// caller before this check runs.
final RegExp _validGradeLetter = RegExp(r'^[A-F]$');

/// Scans [text] for EVERY balanced-brace `{...}` substring that decodes as
/// JSON carrying a `grade` matching [_validGradeLetter] exactly, and returns
/// the LAST such match. A verdict concludes a critic's output — any earlier
/// object (an echoed prompt template, a worked example in prose) is a
/// preamble, not the verdict, so the first match must NOT win (tg-291 rework
/// round 1: a false ADVANCE was possible when a real F verdict followed an
/// earlier template/example echo with a matched-looking grade).
Map<String, String>? _verdictFromEmbeddedJson(String text) {
  Map<String, String>? last;
  for (var start = 0; start < text.length; start++) {
    if (text[start] != '{') continue;
    var depth = 0;
    for (var end = start; end < text.length; end++) {
      if (text[end] == '{') depth++;
      if (text[end] == '}') {
        depth--;
        if (depth != 0) continue;
        try {
          final json = jsonDecode(text.substring(start, end + 1));
          if (json is Map) {
            final grade = (json['grade'] as String?)?.trim().toUpperCase();
            if (grade != null && _validGradeLetter.hasMatch(grade)) {
              final rationale = (json['rationale'] as String?)?.trim() ?? '';
              last = {
                'grade': grade,
                'transport': 'envelope',
                'rationale': rationale.isEmpty
                    ? '[from result envelope]'
                    : '$rationale [from result envelope]',
              };
            }
          }
        } catch (_) {
          // not a decodable/relevant object at this start — keep scanning.
        }
        break; // matched braces exhausted for this start; try the next '{'.
      }
    }
  }
  return last;
}

/// A `Verdict: <A-F>` or `Grade: <A-F>` heading (case-insensitive) — the
/// prose-heading shapes a critic falls back to when it states its verdict in
/// plain text (tg-291), including the markdown `## Grade: A` summary a critic
/// was observed to emit while skipping the file write (gate-integrity #4,
/// bead `tg-r66`). The keyword is immediately followed by `:` (optional
/// whitespace only), so the `"grade":"A"` inside an echoed JSON template — where
/// a `"` sits between the word and the colon — never matches here (that shape is
/// already handled by [_verdictFromEmbeddedJson]).
final RegExp _verdictHeading =
    RegExp(r'(?:verdict|grade)\s*:\s*([A-Fa-f])\b', caseSensitive: false);

/// The prose that follows the LAST `Verdict:`/`Grade: <A-F>` heading in [text],
/// as a grade + marked rationale — `null` when no heading is present. A verdict
/// concludes a critic's output, so an earlier heading (a worked example, a
/// restated instruction) must not win over a later, real one — mirrors
/// [_verdictFromEmbeddedJson]'s last-match scan (tg-291 rework round 2: an
/// early "Verdict: A" followed by a real, later "Verdict: F" must yield F, not
/// the earlier A).
Map<String, String>? _verdictFromHeading(String text) {
  final matches = _verdictHeading.allMatches(text);
  if (matches.isEmpty) return null;
  final match = matches.last;
  final grade = match.group(1)!.toUpperCase();
  final rationale = text.substring(match.end).trim();
  return {
    'grade': grade,
    'transport': 'envelope',
    'rationale': rationale.isEmpty
        ? '[from result envelope]'
        : '$rationale [from result envelope]',
  };
}
