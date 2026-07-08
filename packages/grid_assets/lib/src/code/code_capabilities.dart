/// The `code` extension — agent/verify/land as Capability impls + the linear
/// `code` circuit (ADR-0008 D2 / M4-P1 §6, Track H).
///
/// The agent/verify/land OPINIONS live here as opaque [Capability] leaves (never
/// a `Seed`), composed into a linear [Circuit] whose always-1-wide frontier
/// reproduces the original agent→verify→land sequence. The kernel/effect core
/// references none of this — only this asset package does (the opinion-free
/// kernel invariant, ADR-0007 §1; a structural fence keeps it out of the engine).
///
/// This is the LIVE work path: `composeRunTree` wires it via the
/// [buildCodeRegistry] registry + a [CircuitResolver] that roots the `code`
/// circuit per coding bead.
library;

import 'dart:io';

import 'package:dart_grid_assets/dart_grid_assets.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

import '../agent/agent_domain.dart';
import '../agent/agent_harness.dart';
import '../agent/usage_report.dart';
import '../assets/asset_loader.dart';
import 'committee.dart';
import 'landing.dart';

/// agent → review → land — the live `code` circuit (M5 "The Circuit" Track E;
/// the `land` step is itself the landing circuit as of bead `tg-rm5`).
///
/// The toy `verify` step (`sh -c 'melos test'`) is GONE: `verify` is now the
/// adversarial code-committee, a [SubCircuitStep] the engine inflates one level
/// down ([kCodeReviewCircuit] — four critics in parallel → a `route` join). A
/// `dependsOn` on `review` resolves to its terminal-step descendant
/// (`<bead>/review/route`'s positive terminal), so `land` waits for the route to
/// advance; a route `Gate` parks the work (no `land`) instead.
///
/// `land` is likewise a [SubCircuitStep] (`tg-rm5`, `landing.dart`'s
/// [kLandingCircuit]): `rebase → revalidate → land` — rebase the bead
/// branch onto the CURRENT base before re-running the bead's OWN Validation
/// Plan against the rebased tree (closing the stale-base hole: with N
/// parallel beads on one repo, the second-to-land would otherwise validate
/// against a `main` that already moved), commit/push, then open the PR. A
/// `dependsOn` on `land` resolves through the SAME one-hop terminal
/// resolution to `<bead>/land/land`'s positive terminal.
const Circuit kCodeCircuit = Circuit(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
    SubCircuitStep(
      stepId: 'review',
      circuitId: 'code_review',
      dependsOn: {'agent'},
    ),
    SubCircuitStep(stepId: 'land', circuitId: 'landing', dependsOn: {'review'}),
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
///
/// Also materializes the bead's declared `grid.dart` pub linkage into the
/// worktree ([_linkWorkspace] — ADR-0000 A1): the DART domain's envelope is
/// part of the work DEFINITION, read here alongside the rest of the bead, and
/// applied via the [DartLinkService] the_grid's dart_grid_assets pack ships
/// (grid_assets → dart_grid_assets, the pub-subordinate-to-Dart direction).
class AgentCapability extends ProcessCapability {
  /// Creates the agent capability. [devRoot] is the station's registered root
  /// checkout path ([RootCheckout.path] — "the registered root checkout's
  /// path") relative `grid.dart` dev-path links absolutize against in the
  /// per-bead worktree; null in an offline/dry-run build (no root
  /// registered — a relative link then refuses, never silently applies a
  /// broken override). [linkService] is injectable for tests.
  const AgentCapability({
    String? devRoot,
    DartLinkService linkService = const DartLinkService(),
  }) : _devRoot = devRoot,
       _linkService = linkService;

  final String? _devRoot;
  final DartLinkService _linkService;

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
    _linkWorkspace(bead, workspace);
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

  /// Decodes [bead]'s `grid.dart` envelope and applies its pub linkage into
  /// [workspace] — right after [GitSourceControl.provisionWorkspace] cut the
  /// worktree (ADR-0008 D5: provisioning is this asset's opinion; the_grid
  /// engine carries no pub/dart-domain concept, so this lives here rather
  /// than in grid_engine). A SYNCHRONOUS [DartLinkService] call
  /// ([ProcessCapability.spawn] returns a `RuntimeConfig` directly, not a
  /// `Future` — it cannot await).
  ///
  /// A worktree dir that does not yet exist (offline/dry-run —
  /// [GitSourceControl] never materializes one there) skips silently, same
  /// posture as `GitSourceControl.provisionWorkspace`'s own offline no-op. A
  /// breaking `grid.dart` envelope THROWS, which [ProcessAllocation] (the
  /// existing `capability.spawn` fail-closed contract, ADR-0008 Decision 10)
  /// routes to supervision as a per-work `Failed` — never a half-applied
  /// override file.
  void _linkWorkspace(Bead bead, Workspace workspace) {
    if (!Directory(workspace.workspaceDir).existsSync()) return;
    final outcome = _linkService.applySync(
      metadata: bead.metadata,
      context: PubLinkContext.worktree,
      workspaceDir: workspace.workspaceDir,
      devRoot: _devRoot,
    );
    if (outcome is LinkRefused) {
      throw StateError(
        'AgentCapability: grid.dart pub linkage refused (fail-closed): '
        '${outcome.reason}',
      );
    }
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
/// live dogfood contract — exposed for unit tests). The agreement closes with
/// the **D-H genesis_tree doctrine** (ADR-0008; companion to the_grid
/// `GridDelegate` D-H fix): watch deps / no sync accessor over `StateNotifier`
/// state / config = values, impls = DI / guards LOUD or GONE — every coding
/// agent this station spawns carries it. Model/params are AgentConfig, NOT brief
/// (OQ-a) — one brief replays across harnesses. Completion is OBSERVED via
/// process-exit (the host writes the node cursor through the chokepoint when the
/// agent's process exits clean) — the agent never DECLARES it (tg-p9q).
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
    ..writeln('- When the work is committed you are done; exit.')
    ..writeln()
    ..writeln(
      'When you touch genesis_tree / grid code, hold the D-H doctrine '
      '(ADR-0008):',
    )
    ..writeln(
      '- Always watch deps: read ambient tree values in `build` via '
      '`dependOn*`; never snapshot-and-`??=`-cache reactive state.',
    )
    ..writeln(
      '- No public synchronous accessor over `StateNotifier` state — `.state`/'
      '`current` never escapes; re-project it as an `InheritedSeed` and observe '
      'it in `build`.',
    )
    ..writeln(
      '- Config = VALUES in the tree; impls = DI (no services in a branch '
      'except injected).',
    )
    ..write(
      '- Guards LOUD or GONE: a guard exists only if it protects a NAMED '
      'invariant and is loud (throws/refuses) when violated — otherwise delete '
      'it.',
    );
  return AgentBrief(task: p.toString(), workingAgreement: agreement.toString());
}

// The toy VERIFY capability (a fixed test command) was DELETED in M5 Track E:
// `verify` is now the adversarial code-committee ([kCodeReviewCircuit]), whose
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
///
/// The PR opens with the FULL circuit receipt as its body (`tg-rm5`,
/// [buildCircuitReceipt]) — the code-review committee's grade/route
/// provenance plus this landing circuit's own rebase/revalidate outcomes, read
/// via the ambient [SiblingView]. [SourceControl.openPr] itself carries no
/// `body` param (the receipt-regression gap — see `landing.dart`'s header);
/// when [sc] is ALSO a [ReceiptCapableSourceControl] (the real [GitSourceControl]
/// always is), the richer overload is called instead so the receipt actually
/// reaches the real PR today.
///
/// **Rework-aware delivery (`tg-w3c`)** — a preceding rework round REBASES the
/// bead branch and leaves round one's PR open, which wedged the plain
/// commit→push→PR path (push refused non-fast-forward, `gh pr create` errored
/// "already exists", the DONE+approved bead escalated). When [sc] is a
/// [ReworkAwareSourceControl] (the real [GitSourceControl] always is), land
/// force-pushes with `--force-with-lease`, reuses an already-open PR as
/// success, and — on a genuine git/gh failure — [Failed]s with the stderr TAIL
/// as the reason, which FT-1 stamps as the node's `failureReason` so an
/// operator sees WHY without forensics. A bare [SourceControl] still lands
/// through the plain, unwidened methods.
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
    final siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
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

    // Verify land committed the WHOLE reviewed tree (the tg-x1j r1 incident —
    // a botched land silently committed a SUBSET, stripping session_scope.dart
    // edits from the PR). `SourceControl.commitAll` returns void, so when [sc]
    // is ALSO a [TreeVerifiableSourceControl] (the real [GitSourceControl]
    // always is), this is the only signal available; a plain [SourceControl]
    // (a bare test fake, or a future non-Git impl) skips the check, same
    // opt-in posture as [ReceiptCapableSourceControl].
    if (sc is TreeVerifiableSourceControl) {
      final residue = await sc.uncommittedResidue(
        workspaceDir: workspace.workspaceDir,
      );
      if (args.cancel.isCancelled) return const Failed('cancelled');
      if (residue != null) {
        return Gate(
          'land committed a SUBSET of the reviewed tree (the tg-x1j r1 class '
          'of incident) — never pushed: $residue',
        );
      }
    }

    final title = 'grid: ${args.beadId}';
    final body = buildCircuitReceipt(beadId: args.beadId, siblings: siblings);

    // REWORK-AWARE delivery (bead `tg-w3c`): a preceding rework round rebased
    // the branch and left round one's PR open, so a plain push is refused and
    // `gh pr create` errors "already exists". When [sc] supports it (the real
    // [GitSourceControl] always does), force-with-lease push + reuse the open
    // PR, and stamp the git/gh stderr tail as the `failureReason` (FT-1) so an
    // operator sees WHY without forensics. A bare/non-git [SourceControl] (a
    // test fake) still lands through the plain, unwidened methods below.
    if (sc is ReworkAwareSourceControl) {
      final pushed = await sc.pushForBranch(
        workspaceDir: workspace.workspaceDir,
        remote: 'origin',
        branch: workspace.branch,
      );
      if (args.cancel.isCancelled) return const Failed('cancelled');
      if (!pushed.ok) {
        return Failed(
          'grid land ${args.beadId}: force-with-lease push refused — '
          '${landReasonTail(pushed.output)}',
        );
      }
      final pr = await sc.openOrReusePr(
        workspaceDir: workspace.workspaceDir,
        branch: workspace.branch,
        baseBranch: workspace.baseBranch,
        title: title,
        body: body,
      );
      if (args.cancel.isCancelled) return const Failed('cancelled');
      if (!pr.ok) {
        return Failed(
          'grid land ${args.beadId}: pr open failed — '
          '${landReasonTail(pr.failureReason ?? '')}',
        );
      }
      return Ok({'pr_url': pr.url!});
    }

    await sc.push(
      workspaceDir: workspace.workspaceDir,
      remote: 'origin',
      branch: workspace.branch,
    );
    if (args.cancel.isCancelled) return const Failed('cancelled');

    final pr = sc is ReceiptCapableSourceControl
        ? await sc.openPr(
            workspaceDir: workspace.workspaceDir,
            branch: workspace.branch,
            baseBranch: workspace.baseBranch,
            title: title,
            body: body,
          )
        : await sc.openPr(
            workspaceDir: workspace.workspaceDir,
            branch: workspace.branch,
            baseBranch: workspace.baseBranch,
            title: title,
          );
    // Check cancellation after EVERY async gap (P0 LandEffectSeed parity) — a
    // dispose mid-land must not record a stale terminal.
    if (args.cancel.isCancelled) return const Failed('cancelled');
    if (pr == null) return const Failed('pr open did not complete');
    return Ok({'pr_url': pr.url});
  }
}

/// A [SourceControl] that can ALSO carry a PR body (`tg-rm5` — the "circuit
/// receipt", grades/route-provenance/rebase+revalidate outcomes). The
/// receipt-regression gap: `PrOpener.open`/`GhPrOpener` (grid_runtime) already
/// thread a `body` through to `gh pr create --body`, but the engine's own
/// [SourceControl.openPr] (grid_engine) never grew one — so `land` has only
/// ever opened empty-body PRs. This is the power_station-local STOPGAP: until
/// a future the_grid change widens `SourceControl.openPr` itself,
/// [LandCapability] detects this marker via `is` and calls the richer
/// overload. A plain [SourceControl] (e.g. a bare test fake) still lands
/// correctly through the unwidened interface method — just without a body.
abstract interface class ReceiptCapableSourceControl implements SourceControl {
  @override
  Future<PrRef?> openPr({
    required String workspaceDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body,
  });
}

/// A [SourceControl] that can ALSO report whether its own [SourceControl.
/// commitAll] left residue behind (bead `tg-bns`, the tg-x1j r1 incident — a
/// botched land silently committed a SUBSET of the reviewed tree, dropping
/// `session_scope.dart` edits from the PR). `commitAll` returns `void`, so
/// [LandCapability] has no other signal that its own commit actually captured
/// everything. This is the power_station-local STOPGAP, same posture as
/// [ReceiptCapableSourceControl]: [LandCapability] detects this marker via
/// `is` and Gates when residue is reported; a plain [SourceControl] (a bare
/// test fake, or a future non-Git impl) skips the check entirely.
abstract interface class TreeVerifiableSourceControl implements SourceControl {
  /// Returns `null` when [workspaceDir] is clean (nothing left uncommitted
  /// after `commitAll`); otherwise a human-readable description of the residue
  /// — including when the check itself couldn't run (fail-closed: an
  /// unreadable probe is treated as unsafe, never silently trusted clean).
  Future<String?> uncommittedResidue({required String workspaceDir});
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
///
/// Also [ReceiptCapableSourceControl] (`tg-rm5`): [openPr] carries an optional
/// `body` beyond what the [SourceControl] interface itself declares, so `land`
/// can thread the circuit receipt into the real PR today. Also
/// [TreeVerifiableSourceControl] (`tg-bns`): [uncommittedResidue] reuses
/// [GitOps.hasUncommittedWork] (the SAME three-gate `git status --porcelain`
/// probe the worktree-reap gate already trusts) — no new git call, just a new
/// consumer of an existing one. Also [ReworkAwareSourceControl] (`tg-w3c`):
/// [pushForBranch] force-pushes with `--force-with-lease` (a rework round
/// rebased the branch, so a plain push is refused) and [openOrReusePr] treats
/// an already-open PR as success — both returning the git/gh output so `land`
/// can stamp the stderr tail as the `failureReason`.
class GitSourceControl
    implements
        SourceControl,
        ReceiptCapableSourceControl,
        TreeVerifiableSourceControl,
        ReworkAwareSourceControl {
  /// Wraps the optional land ops ([gitOps]/[prOpener]) and the optional
  /// provisioning seam ([provisioner]/[root]). [gitRunner] is the raw `git`
  /// seam the rework-aware force-push runs through — `null` ⇒ a real
  /// [SystemGitRunner] (the live default; tests inject the SAME recording fake
  /// [gitOps] wraps, so the force-push argv is asserted offline).
  const GitSourceControl({
    GitOps? gitOps,
    PrOpener? prOpener,
    StationGitService? provisioner,
    RootCheckout? root,
    GitRunner? gitRunner,
  }) : _gitOps = gitOps,
       _prOpener = prOpener,
       _provisioner = provisioner,
       _root = root,
       _gitRunner = gitRunner;

  final GitOps? _gitOps;
  final PrOpener? _prOpener;
  final StationGitService? _provisioner;
  final RootCheckout? _root;
  final GitRunner? _gitRunner;

  /// Returns a copy with [prOpener] wired for land — the composition seam the
  /// substation-scoped `GitHubGridAssets` uses to ADD PR-opening onto the git
  /// asset (Track F, `tg-5r9`): `GitGridAssets` provides the provision +
  /// commit/push half (`canLand` false until a PR opener exists); mounting
  /// `GitHubGridAssets` below it enriches THIS source control with the opener,
  /// flipping [canLand] true. The provisioner / gitOps / root are carried
  /// through unchanged, so the enriched impl provisions the SAME worktree it
  /// lands from.
  GitSourceControl withPrOpener(PrOpener prOpener) => GitSourceControl(
    gitOps: _gitOps,
    prOpener: prOpener,
    provisioner: _provisioner,
    root: _root,
    gitRunner: _gitRunner,
  );

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
  Future<String?> uncommittedResidue({required String workspaceDir}) async {
    final outcome = await _gitOps!.hasUncommittedWork(workspaceDir);
    return switch (outcome) {
      GateOutcome.clear => null,
      GateOutcome.present =>
        'uncommitted changes remain in the workspace after commitAll',
      GateOutcome.probeError =>
        'could not verify a clean tree after commitAll (git status probe '
            'failed) — fail-closed, treated as unsafe',
    };
  }

  @override
  Future<PrRef?> openPr({
    required String workspaceDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async {
    final result = await _prOpener!.open(
      workDir: workspaceDir,
      branch: branch,
      baseBranch: baseBranch,
      title: title,
      body: body,
    );
    return result.isOpened ? PrRef(result.ref!.url) : null;
  }

  @override
  Future<LandPushOutcome> pushForBranch({
    required String workspaceDir,
    required String remote,
    required String branch,
  }) async {
    // `--force-with-lease` ALWAYS (`tg-w3c`): a rework round rebased this
    // branch, so a plain `git push` is refused non-fast-forward. It is the
    // circuit's OWN branch, so forcing is safe; the lease still refuses if a
    // racing writer moved `origin/$branch` since the last fetch. `-u` keeps
    // upstream set (so a later `hasUnpushedCommits` reads clear), matching
    // [GitOps.pushSetUpstream]. A `null` runner ⇒ the real, clean-env
    // [SystemGitRunner] (mirrors [RebaseCapability]'s own default).
    final runner = _gitRunner ?? SystemGitRunner();
    final result = await runner.run(
      workingDirectory: workspaceDir,
      args: ['push', '--force-with-lease', '-u', remote, branch],
    );
    return LandPushOutcome(ok: result.ok, output: result.output);
  }

  @override
  Future<LandPrOutcome> openOrReusePr({
    required String workspaceDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async {
    final result = await _prOpener!.open(
      workDir: workspaceDir,
      branch: branch,
      baseBranch: baseBranch,
      title: title,
      body: body,
    );
    if (result.isOpened) return LandPrOutcome.opened(result.ref!.url);
    // Idempotent (`tg-w3c`): `gh pr create` refusing because round one's PR is
    // still OPEN is a SUCCESS, not a failure — the branch is delivered and the
    // PR is there. Reuse its url (parsed from gh's refusal, which prints it);
    // an "already exists" without a parseable url still counts as reused (the
    // PR exists) rather than escalating a DONE bead.
    //
    // Refreshing the reused PR's BODY with the new round's receipt (the task's
    // OPTIONAL `gh pr edit`) is deferred: [PrOpener] only OPENS, so an edit
    // would need a gh-runner seam threaded through the composition — out of
    // scope for the escalation fix. The force-push already updated the PR's
    // diff; only the receipt text lags a round.
    final reason = result.failure?.reason ?? 'pr open did not complete';
    if (isPrAlreadyOpen(reason)) {
      return LandPrOutcome.reused(extractPrUrl(reason) ?? '');
    }
    return LandPrOutcome.failed(reason);
  }
}

/// Builds the `code` registry: the agent/land capabilities + the adversarial
/// committee (`critic`/`route` + the `code_review` circuit) + the landing
/// circuit (`rebase`/`revalidate` + the `landing` circuit, `tg-rm5`), with an
/// optional injected [clock] (the backoff seam). The composer provides it as a
/// stable `InheritedSeed<CapabilityRegistry>` above `Station`, alongside a
/// `CircuitResolver((_) => kCodeCircuit)`.
///
/// The `code` circuit's `verify` step is the committee (M5 Track E): the toy
/// `verify` capability is gone, and the `critic` capability is wired to the
/// Packaged-AI-Asset rubric loader (D-9) — [rubrics] overrides it for a test
/// that wants inline rubric text (absent ⇒ the on-disk `extension/rubrics/`).
/// [devRoot] threads the station's registered root checkout path into
/// [AgentCapability] (the `grid.dart` pub-link worktree absolutize root; null
/// ⇒ offline/dry-run, no root registered). [gitRunner]/[shellRunner] override
/// `rebase`/`revalidate`'s real git/shell seams (tests inject recording fakes —
/// Fakes, not mocks; absent ⇒ the real [SystemGitRunner]/[SystemShellRunner]).
/// [critiqueDirClearer] overrides [ClearCritiqueCapability]'s real
/// delete+recreate (gate-integrity #3, bead `tg-bns`) — tests inject a no-op
/// so the offline suite never touches a real filesystem at a synthetic
/// workspace path.
DefaultCapabilityRegistry buildCodeRegistry({
  DateTime Function()? clock,
  RubricSource? rubrics,
  String? devRoot,
  GitRunner? gitRunner,
  ShellRunner? shellRunner,
  DirectoryClearer? critiqueDirClearer,
}) {
  final rubricSource = rubrics ?? PackagedAssetLoader().rubricSource;
  return DefaultCapabilityRegistry(
    capabilities: {
      'agent': AgentCapability(devRoot: devRoot),
      'land': const LandCapability(),
      'critic': CriticCapability(rubrics: rubricSource),
      'route': const RouteCapability(),
      'rebase': RebaseCapability(runner: gitRunner),
      'revalidate': RevalidateCapability(runner: shellRunner),
      kClearCritiqueStep: ClearCritiqueCapability(clearer: critiqueDirClearer),
    },
    circuits: const {
      'code': kCodeCircuit,
      'code_review': kCodeReviewCircuit,
      'landing': kLandingCircuit,
    },
    clock: clock,
  );
}
