/// The adversarial code-committee — a reentrant sub-formula composed at the
/// existing `FormulaScope` seam (ADR-0008 D2/D4 / M5 "The Circuit" Track C).
///
/// factoryskills' code review runs ONE critic per rubric in ISOLATION
/// (anti-anchoring: a critic sees only its own rubric, never the others' grades),
/// fans the four critics out in parallel, then a `route` step aggregates their
/// grades through a deterministic matrix (asset policy, never engine). The
/// committee is just formula wiring + two `Capability` leaves — the parallelism +
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
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;

import '../agent/agent_domain.dart';
import '../agent/agent_harness.dart';

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

/// A pluggable source of a rubric's prose text by id (D-9: the Packaged-AI-Asset
/// loader replaces the inline placeholder). Returns the rubric body a critic's
/// prompt embeds.
typedef RubricSource = String Function(String rubricId);

/// The adversarial code-committee formula (id `code_review`) — four dep-free
/// critic lanes fanned out in parallel, then a `route` step that joins on all
/// four and aggregates their grades (M5 Track C / C1).
///
/// Reentrant: composed at the same `FormulaScope` seam as any other formula, so
/// Track E can drop it in as the `code` formula's `verify` via a `SubFormulaStep`
/// with zero engine changes.
const Formula kCodeReviewFormula = Formula(
  id: 'code_review',
  terminalStepId: 'route',
  steps: [
    CapabilityStep(
      stepId: kGatingRubric,
      capabilityId: 'critic',
      params: {'rubric': kGatingRubric},
    ),
    CapabilityStep(
      stepId: 'spec-adherence',
      capabilityId: 'critic',
      params: {'rubric': 'spec-adherence'},
    ),
    CapabilityStep(
      stepId: 'regression-risk',
      capabilityId: 'critic',
      params: {'rubric': 'regression-risk'},
    ),
    CapabilityStep(
      stepId: 'test-coverage',
      capabilityId: 'critic',
      params: {'rubric': 'test-coverage'},
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
///    (ONLY its own rubric); the verdict JSON is parsed by the [result] hook.
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
      brief: AgentBrief(task: buildCriticPrompt(bead, rubric)),
      workspace: workspace,
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
      // silently pass.
      final rc = File(p.join(workspaceDir, _critiqueDir, '$kGatingRubric.rc'));
      if (!rc.existsSync()) return const {'grade': 'F'};
      final code = rc.readAsStringSync().trim();
      return {'grade': code == '0' ? 'A' : 'F'};
    }
    // An LLM critic's verdict JSON. Fail-closed: a missing / malformed verdict
    // grades F (a critic that did not produce a readable grade can never
    // advance).
    final verdict = File(p.join(workspaceDir, _critiqueDir, '$rubric.json'));
    if (!verdict.existsSync()) return const {'grade': 'F'};
    try {
      final json = jsonDecode(verdict.readAsStringSync()) as Map<String, dynamic>;
      final grade = (json['grade'] as String?)?.trim().toUpperCase();
      final rationale = (json['rationale'] as String?)?.trim() ?? '';
      return {
        'grade': (grade == null || grade.isEmpty) ? 'F' : grade,
        if (rationale.isNotEmpty) 'rationale': rationale,
      };
    } catch (_) {
      return const {'grade': 'F'};
    }
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
  /// rendered brief IS this prompt, byte-identical). Exposed for unit tests.
  String buildCriticPrompt(Bead bead, String rubric) {
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
        'Grade the work A (best) through F (worst) against `$rubric` ONLY, then '
        'write your verdict as JSON to `$_critiqueDir/$rubric.json`:',
      )
      ..writeln(
        '{"rubric":"$rubric","version":1,"grade":"<A-F>","rationale":"<why>"}',
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
    if (indices.isNotEmpty) {
      final spread = indices.reduce(math.max) - indices.reduce(math.min);
      if (spread >= 3) return const Gate('grade spread ≥ 3 — human ultimatum');
    }

    // 3. any non-gating critic at D/F — rework → restForOne re-key is deferred
    // (build-order); a D/F parks at a gate for now.
    for (final entry in grades.entries) {
      if (entry.key == gating) continue;
      if (entry.value == 'D' || entry.value == 'F') {
        return const Gate('a critic returned D/F — rework');
      }
    }

    // 4. all A–C, gating clean, spread < 3 — advance.
    return const Ok({'verdict': 'advance'});
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
