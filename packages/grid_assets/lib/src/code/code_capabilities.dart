/// The `code` extension — agent/verify/land as Capability impls + the linear
/// `code` formula (ADR-0008 D2 / M4-P1 §6, Track H).
///
/// The agent/verify/land OPINIONS live here as opaque [Capability] leaves (never
/// a `Seed`), composed into a linear [Formula] whose always-1-wide frontier
/// reproduces the original agent→verify→land sequence. The kernel/effect core
/// references none of this — only this asset package does (the opinion-free
/// kernel invariant, ADR-0007 §1; a structural fence keeps it out of the engine).
///
/// This is the LIVE work path: `composeRunTree` wires it via the
/// [buildCodeRegistry] registry + a [FormulaResolver] that roots the `code`
/// formula per coding bead.
library;

import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

import '../agent/agent_domain.dart';
import '../agent/agent_harness.dart';
import '../agent/usage_report.dart';
import '../assets/asset_loader.dart';
import 'committee.dart';

/// agent → review → land — the live `code` formula (M5 "The Circuit" Track E).
///
/// The toy `verify` step (`sh -c 'melos test'`) is GONE: `verify` is now the
/// adversarial code-committee, a [SubFormulaStep] the engine inflates one level
/// down ([kCodeReviewFormula] — four critics in parallel → a `route` join). A
/// `dependsOn` on `review` resolves to its terminal-step descendant
/// (`<bead>/review/route`'s positive terminal), so `land` waits for the route to
/// advance; a route `Gate` parks the work (no `land`) instead.
const Formula kCodeFormula = Formula(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
    SubFormulaStep(
      stepId: 'review',
      formulaId: 'code_review',
      dependsOn: {'agent'},
    ),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'review'}),
  ],
);

/// The IMPLEMENT capability — spawn the coding agent in the bead's workspace,
/// parameterized over the AMBIENT agent scope (ADR-0008 Decision 10): it reads
/// the work `Bead`, the `Workspace`, the station's `AgentConfig` default, and
/// the `AgentHarnessRegistry` with the effect verb, resolves the effective
/// config through the ladder ([resolveAgentConfig] — step params > bead
/// `grid.agent` envelope > ambient; fail-closed → a per-work `Failed`), and
/// delegates the INVOCATION to the resolved harness. The POLICY stays here:
/// [buildAgentBrief] renders the full bead (a title-only brief starves the
/// agent, A36) + the **local-first working agreement**: work in the worktree,
/// COMMIT, do NOT push, do NOT open a PR. Landing is an explicit OPT-IN
/// (`--land`; ADR-0006 D3) and OFF by default. (claude's auth seam is the
/// macOS keychain — A38; no token rides argv.)
class AgentCapability extends ProcessCapability {
  /// Creates the agent capability.
  const AgentCapability();

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) {
    final bead = context.getInheritedSeedOfExactType<Bead>();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (bead == null || workspace == null) {
      throw StateError(
        'AgentCapability requires the ambient Bead + Workspace '
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
      brief: buildAgentBrief(bead, workspace),
      workspace: workspace,
      usageOut: usageReportPath(args.nodePath),
    );
  }

  @override
  StepSignal interpretEvent(RuntimeEvent event) => _jobSignal(event);

  /// The CAPTURE-ONLY usage telemetry (FT-2): on a clean completion, read the
  /// harness's `--output-format json` envelope the resolved harness redirected
  /// (claude) and contribute tokensIn/tokensOut/costUsd/numTurns/
  /// harnessDurationMs to `grid.result.<nodePath>.*`. FAIL-SAFE: an absent /
  /// malformed / harness-without-usage envelope yields no fields (null), NEVER a
  /// throw — telemetry can never fail, gate, or delay the agent step.
  @override
  Future<Map<String, String>?> result(TreeContext context, StepArgs args) async {
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    if (workspace == null) return null;
    final usage = readUsageFields(workspace.workspaceDir, args.nodePath);
    return usage.isEmpty ? null : usage;
  }
}

/// Assembles the agent's full-bead brief + local-first working agreement (the
/// live dogfood contract — exposed for unit tests). Model/params are AgentConfig,
/// NOT brief (OQ-a) — one brief replays across harnesses. Completion is
/// OBSERVED via process-exit (the host writes the node cursor through the
/// chokepoint when the agent's process exits clean) — the agent never DECLARES
/// it (tg-p9q).
AgentBrief buildAgentBrief(Bead bead, Workspace workspace) {
  final title = bead.title.isNotEmpty ? bead.title : 'work bead ${bead.id}';
  final substation = bead.metadata['rig'];
  final p = StringBuffer()
    ..writeln('# $title')
    ..writeln()
    ..writeln(
      substation is String && substation.isNotEmpty
          ? 'Bead `${bead.id}` (substation `$substation`).'
          : 'Bead `${bead.id}`.',
    );
  void section(String heading, String body) {
    if (body.trim().isEmpty) return;
    p
      ..writeln()
      ..writeln('## $heading')
      ..writeln(body.trim());
  }

  section('Task', bead.description);
  section('Design', bead.design);
  section('Acceptance criteria', bead.acceptanceCriteria);
  section('Notes', bead.notes);
  final agreement = StringBuffer()
    ..writeln(
      '- Work ONLY inside this worktree (${workspace.workspaceDir}); it is on '
      'branch `${workspace.branch}`, a throwaway branch the_grid provisioned '
      'for this bead.',
    )
    ..writeln('- Implement the task and COMMIT your work on that branch.')
    ..writeln(
      '- Do NOT push and do NOT open a pull request — leave the commit for '
      'human review.',
    )
    ..write('- When the work is committed you are done; exit.');
  return AgentBrief(task: p.toString(), workingAgreement: agreement.toString());
}

// The toy VERIFY capability (a fixed test command) was DELETED in M5 Track E:
// `verify` is now the adversarial code-committee ([kCodeReviewFormula]), whose
// gating `code-validation` lane runs the bead's OWN Validation Plan — real
// verification, not one hard-coded command. (The opinion-free engine names no
// build tool at all; the structural fence guards it.)

/// A job's terminal mapping: a clean `Exited(0)` completes; any other terminal
/// (non-zero exit or a `Died`) fails (routes to supervision).
StepSignal _jobSignal(RuntimeEvent event) => switch (event) {
  Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
  Exited() || Died() => StepSignal.failed,
  _ => StepSignal.none,
};

/// The LAND capability — commit → push → open the PR via the pluggable
/// [SourceControl] Service (migrated from `LandEffectSeed`; the positive
/// terminal). Offline-safe: when no [SourceControl] is wired it no-ops to [Ok]
/// (it never touches real git/GitHub); a PR that does not open is [Failed]
/// (an honest "land did not complete"). The pr url rides the [Ok] payload, which
/// the engine records on the session bead — never used as a pipeline signal.
class LandCapability extends ServiceCapability {
  /// Creates the land capability.
  const LandCapability();

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    // Read the ambient values at ENTRY (synchronously, while mounted); after
    // every await only the captured values + the cancel token are touched.
    final services =
        context.getInheritedSeedOfExactType<ServiceBundle>() ??
        const ServiceBundle();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    final sc = services.sourceControl;
    // Land not wired (no SourceControl, or provisioning-only for an early arm
    // whose working agreement is commit-only) — no-op rather than touch real
    // git. `canLand` distinguishes "deferred" (Ok) from "tried + failed" (Failed).
    if (sc == null || !sc.canLand || workspace == null) return const Ok();

    await sc.commitAll(
      workspaceDir: workspace.workspaceDir,
      message: 'grid: land ${args.beadId}',
    );
    if (args.cancel.isCancelled) return const Failed('cancelled');

    await sc.push(
      workspaceDir: workspace.workspaceDir,
      remote: 'origin',
      branch: workspace.branch,
    );
    if (args.cancel.isCancelled) return const Failed('cancelled');

    final pr = await sc.openPr(
      workspaceDir: workspace.workspaceDir,
      branch: workspace.branch,
      baseBranch: workspace.baseBranch,
      title: 'grid: ${args.beadId}',
    );
    // Check cancellation after EVERY async gap (P0 LandEffectSeed parity) — a
    // dispose mid-land must not record a stale terminal.
    if (args.cancel.isCancelled) return const Failed('cancelled');
    if (pr == null) return const Failed('pr open did not complete');
    return Ok({'pr_url': pr.url});
  }
}

/// The git [SourceControl] impl over grid_runtime (the detail the engine knows
/// only in CONCEPT — ADR-0008 D5; ships in the asset package). Two independent
/// halves:
///  - **provisioning** — [provisioner] ([StationGitService]) + [root]
///    ([RootCheckout]) cut the per-bead worktree. Provided whenever a root is
///    registered (live), so the host can materialize the workspace before the
///    agent spawns. Absent ⇒ `provisionWorkspace` no-ops (offline).
///  - **land** — [gitOps] (commit/push) + [prOpener] (PR). Absent ⇒ [canLand] is
///    false and [LandCapability] no-ops (the early-arm commit-only posture).
class GitSourceControl implements SourceControl {
  /// Wraps the optional land ops ([gitOps]/[prOpener]) and the optional
  /// provisioning seam ([provisioner]/[root]).
  const GitSourceControl({
    GitOps? gitOps,
    PrOpener? prOpener,
    StationGitService? provisioner,
    RootCheckout? root,
  }) : _gitOps = gitOps,
       _prOpener = prOpener,
       _provisioner = provisioner,
       _root = root;

  final GitOps? _gitOps;
  final PrOpener? _prOpener;
  final StationGitService? _provisioner;
  final RootCheckout? _root;

  @override
  bool get canLand => _gitOps != null && _prOpener != null;

  @override
  String workspaceFor(String beadId) {
    final root = _root;
    // The git layout is THIS impl's opinion (ADR-0008 D5): a per-bead worktree
    // under the root checkout. No root — or an EMPTY-path root (the dry-run
    // synthetic) — ⇒ the absolute synthetic placeholder, byte-identical to the
    // old EffectContext.worktreeFor null-branch. Guarding only `root == null`
    // would let an empty path produce a CWD-RELATIVE `.grid/worktrees/...`
    // (p.join drops the empty leading segment) — a latent spawn-against-CWD risk.
    return (root == null || root.path.isEmpty)
        ? '/grid/worktrees/$beadId'
        : WorktreeLayout.worktreePath(root.path, root.substation, beadId);
  }

  @override
  String branchFor(String beadId) => WorktreeLayout.branchFor(beadId);

  @override
  String get baseBranch => _root?.defaultBranch ?? 'main';

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async {
    final provisioner = _provisioner;
    final root = _root;
    // Provisioning not wired (offline) — nothing to do.
    if (provisioner == null || root == null) return;
    // Idempotent: a later step (verify/land) reuses the agent's worktree.
    if (Directory(workspaceDir).existsSync()) return;
    await provisioner.provisionWorktree(root: root, beadId: beadId);
  }

  @override
  Future<void> commitAll({
    required String workspaceDir,
    required String message,
  }) => _gitOps!.commitAll(workDir: workspaceDir, message: message);

  @override
  Future<void> push({
    required String workspaceDir,
    required String remote,
    required String branch,
  }) => _gitOps!.pushSetUpstream(
    workDir: workspaceDir,
    remote: remote,
    branch: branch,
  );

  @override
  Future<PrRef?> openPr({
    required String workspaceDir,
    required String branch,
    required String baseBranch,
    required String title,
  }) async {
    final result = await _prOpener!.open(
      workDir: workspaceDir,
      branch: branch,
      baseBranch: baseBranch,
      title: title,
    );
    return result.isOpened ? PrRef(result.ref!.url) : null;
  }
}

/// Builds the `code` registry: the agent/land capabilities + the adversarial
/// committee (`critic`/`route` + the `code_review` formula), with an optional
/// injected [clock] (the backoff seam). The composer provides it as a stable
/// `InheritedSeed<CapabilityRegistry>` above `Station`, alongside a
/// `FormulaResolver((_) => kCodeFormula)`.
///
/// The `code` formula's `verify` step is the committee (M5 Track E): the toy
/// `verify` capability is gone, and the `critic` capability is wired to the
/// Packaged-AI-Asset rubric loader (D-9) — [rubrics] overrides it for a test
/// that wants inline rubric text (absent ⇒ the on-disk `extension/rubrics/`).
DefaultCapabilityRegistry buildCodeRegistry({
  DateTime Function()? clock,
  RubricSource? rubrics,
}) {
  final rubricSource = rubrics ?? PackagedAssetLoader().rubricSource;
  return DefaultCapabilityRegistry(
    capabilities: {
      'agent': const AgentCapability(),
      'land': const LandCapability(),
      'critic': CriticCapability(rubrics: rubricSource),
      'route': const RouteCapability(),
    },
    formulas: const {'code': kCodeFormula, 'code_review': kCodeReviewFormula},
    clock: clock,
  );
}
