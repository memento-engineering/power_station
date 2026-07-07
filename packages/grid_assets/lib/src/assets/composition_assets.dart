/// The v3 **composition assets** — the source control / harness / circuit
/// opinions mounted into the grid tree AT A SCOPE (Track F, bead `tg-5r9`;
/// `SCRATCH-station-config-model.md` v3 §3, `GRID-SDK-BUILD-ORDER.md` Track F).
///
/// This is the REPLACEMENT the ServiceBundle dissolution earns: instead of a
/// runner hand-building a `Map<String, ServiceBundle>` keyed by substation id
/// (and, inside each bundle, a string-keyed `sourceControlsByRoot` selector),
/// per-substation git/GitHub are just **assets mounted under the Substation
/// they serve** (v3 §3: "this is where ServiceBundle actually dissolves"), and
/// harness provision is a **station-scoped asset**. The ServiceBundle /
/// serviceBundleMapFor DELETION itself is the fossil track's (grid_engine); THIS
/// track builds the replacement that makes the deletion possible.
///
/// **Resolution — bead → substation → root, no string-keyed map.** A work bead
/// is mounted UNDER its owning substation's scope, so the nearest mounted
/// source-control asset ([GitGridAssets] / [GitHubGridAssets]) IS its
/// substation's own — a capability's `getInheritedSeedOfExactType<ServiceBundle>`
/// resolves it by TREE POSITION, never by a root name. [sourceControlOf] names
/// that resolution (the v3 successor to `ServiceBundle.sourceControlFor(rootName)`);
/// the provided bundle carries an EMPTY `sourceControlsByRoot`, so a stray
/// rootName can only ever resolve back to the one substation source control.
///
/// **The assets are `SingleChildStatelessSeed`s** — each wraps the downstream
/// subtree, so they chain in a `Nest` exactly as the v3 sketch authors them:
/// `assets: Nest(children: [GitGridAssets(...), GitHubGridAssets()])`. The
/// engine reads the ambient values it always has (`ServiceBundle`,
/// `AgentHarnessRegistry`, `AgentConfig`); nothing in the opinion-free engine
/// learns a new type (ADR-0007 §1).
library;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
// grid_sdk's SubstationScope (a freezed name+root VALUE, provided by the SDK's
// `Substation`) collides in NAME with grid_engine's SubstationScope (the old
// StatefulSeed that provided ServiceBundle — the thing this track replaces).
// Prefix the SDK so the two never ambiguate; we only read the SDK scope values.
import 'package:grid_sdk/grid_sdk.dart' as sdk;

import '../agent/agent_harness.dart';
import '../code/code_capabilities.dart';

/// **GitGridAssets** — the substation-scoped SOURCE-CONTROL asset (v3 §3).
///
/// Mounted under the `Substation` it serves, it reads that substation's ambient
/// [sdk.SubstationScope] (its name + its ONE root — v3 §0: a substation is a
/// name and ONE root, never a set, never a `metadata.grid.root` selector),
/// builds the git [SourceControl] for that root, and provides it to the work
/// subtree as `InheritedSeed<ServiceBundle>`.
///
/// It provisions + commits/pushes but does NOT open PRs on its own: [canLand] on
/// the provided [GitSourceControl] stays false (the early-arm, commit-only
/// posture) until [GitHubGridAssets] is mounted below it to add the PR opener.
/// A substation with only `GitGridAssets` commits its work; adding
/// `GitHubGridAssets` lets it land.
///
/// [provisioner] (the station's shared [StationGitService] — "the station
/// supplies the git-execution machinery the substation leases") and [gitOps]
/// (commit/push) are injected by the runner; both null is the offline/dry-run
/// build (provisioning + land no-op, but `workspaceFor`/`branchFor`/`baseBranch`
/// still resolve from the root — the layout is deterministic + pure).
class GitGridAssets extends SingleChildStatelessSeed {
  /// Creates the git asset over the optional station machinery
  /// ([provisioner]/[gitOps]) for the enclosing substation's root; [child] is
  /// supplied by an enclosing [Nest] (or set for standalone use).
  const GitGridAssets({
    this.provisioner,
    this.gitOps,
    this.defaultBranch = 'main',
    this.remote = 'origin',
    super.child,
    super.key,
  });

  /// The station's shared worktree-provisioning service (leased per substation);
  /// null ⇒ provisioning no-ops (offline).
  final StationGitService? provisioner;

  /// Commit/push ops; null ⇒ land no-ops (`canLand` false — the commit-only arm).
  final GitOps? gitOps;

  /// The base branch per-bead worktrees rebase/PR against — the substation
  /// root's mainline. A live [StationGitService.registerRootCheckout] PROBES
  /// this from `origin/HEAD`; an offline asset authors it (defaulting to `main`).
  final String defaultBranch;

  /// The push remote (default `origin`).
  final String remote;

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    // bead → substation → root: the substation's ambient scope names its ONE
    // root. `.of` refuses LOUD when no `Substation` encloses — an asset mounted
    // outside a substation is an authoring error, not a default (v3 §0).
    final scope = sdk.SubstationScope.of(context);
    final root = RootCheckout(
      path: scope.root,
      substation: scope.name,
      defaultBranch: defaultBranch,
      remote: remote,
    );
    final sourceControl = GitSourceControl(
      provisioner: provisioner,
      gitOps: gitOps,
      root: root,
      // No prOpener → canLand false. GitHubGridAssets adds the PR half below.
    );
    return InheritedSeed<ServiceBundle>(
      // A single sourceControl, EMPTY sourceControlsByRoot: the v3 "no
      // string-keyed bundle map" — resolution is the substation's one root,
      // never a name selected against a map.
      value: ServiceBundle(sourceControl: sourceControl),
      child: child,
    );
  }
}

/// **GitHubGridAssets** — the substation-scoped asset that adds GitHub
/// PR-opening (land) onto the substation's git asset (v3 §3).
///
/// Authored BELOW [GitGridAssets] in the substation's `Nest`
/// (`[GitGridAssets(...), GitHubGridAssets()]` folds outermost-first, so
/// GitGridAssets is the ancestor and this is its descendant). It reads the
/// ambient [ServiceBundle] GitGridAssets provided, enriches its
/// [GitSourceControl] with the PR [prOpener] ([GitSourceControl.withPrOpener] →
/// [canLand] true), and RE-provides the bundle so the work subtree below sees
/// the land-capable source control.
///
/// Fail-safe: with no PR [prOpener] wired (offline), or no git asset above (a
/// `GitHubGridAssets` without a `GitGridAssets`), or a non-git [SourceControl],
/// it passes the ambient bundle through unchanged — GitHub can only ADD land to
/// a git checkout it can commit from, never conjure one.
class GitHubGridAssets extends SingleChildStatelessSeed {
  /// Creates the GitHub asset over the optional [prOpener] (the runner injects a
  /// live `GhPrOpener`; null ⇒ offline, land stays deferred); [child] is
  /// supplied by an enclosing [Nest].
  const GitHubGridAssets({this.prOpener, super.child, super.key});

  /// The PR-opening seam (a live `GhPrOpener`); null ⇒ no land added (offline).
  final PrOpener? prOpener;

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    final ambient = context.getInheritedSeedOfExactType<ServiceBundle>();
    final sourceControl = ambient?.sourceControl;
    final opener = prOpener;
    if (opener != null && sourceControl is GitSourceControl) {
      return InheritedSeed<ServiceBundle>(
        value: ServiceBundle(sourceControl: sourceControl.withPrOpener(opener)),
        child: child,
      );
    }
    // Nothing to add — the ambient bundle (if any) stays visible from above.
    return child;
  }
}

/// **HarnessProvider** — harness provision as a STATION-scoped asset (v3 §3).
///
/// Provides the station's default [AgentHarnessRegistry] (which coding harnesses
/// the machine can run) and its ambient [AgentConfig] (the default harness /
/// model / params — the bottom rung of the agent-config ladder, ADR-0008
/// Decision 10) to everything mounted below. Station scope, because these serve
/// the MACHINE, not a single project (v3 §3: station-level assets serve the
/// machine). Mounted above the `Substations` fan-out, every substation's work
/// inherits it; a bead's `grid.agent` envelope and a step's params still
/// override it per-work at the effect boundary ([resolveAgentConfig]).
///
/// [registry] defaults to [buildAgentHarnessRegistry] (the first-party
/// claude/copilot/pi/opencode set) — a `const` value, so the default is
/// canonical (repeated resolution is the SAME instance, no dependent churn).
class HarnessProvider extends SingleChildStatelessSeed {
  /// Creates the harness asset over the station-default [registry] and ambient
  /// [config]; [child] is supplied by an enclosing [Nest].
  const HarnessProvider({
    this.registry,
    this.config = const AgentConfig(),
    super.child,
    super.key,
  });

  /// The station's harness DI registry; null ⇒ [buildAgentHarnessRegistry].
  final AgentHarnessRegistry? registry;

  /// The station-default agent config (the ladder's ambient rung).
  final AgentConfig config;

  @override
  Seed buildWithChild(TreeContext context, Seed child) =>
      InheritedSeed<AgentHarnessRegistry>(
        value: registry ?? buildAgentHarnessRegistry(),
        child: InheritedSeed<AgentConfig>(value: config, child: child),
      );
}

/// **CircuitProvider** — the circuit provider / circuit scope shape (Q8, v3 §3):
/// an asset that mounts a [Circuit] into a substation's scope, making it
/// available for that substation's work (the resolver seam, ASSET-SHAPED).
///
/// It provides the bead→circuit [CircuitResolver] as an ambient value; the
/// composition sketch's `ChaosBurnOrder` is exactly this — an asset that mounts
/// an orderable circuit at substation scope. THIS track establishes the SHAPE;
/// binding the mounted resolver into the kernel's `SessionResolver` seam (today
/// a station-level kernel parameter) is Track G's runner work.
///
/// **The gc-`Order` clarification (Q8 closed).** gc's *Order* pairs a trigger
/// with a formula — the **when** axis over the formula's **what**
/// (gc `docs/tutorials/07-orders.md`), fired by the controller's 30-second
/// tick. That is COMPAT VOCABULARY ONLY. A grid analogue of the *when* axis, if
/// it ever earns its way in, is a separate future design — and CLOCKLESS: the
/// engine is event-driven, so a grid trigger would be observed state, never a
/// tick. [CircuitProvider] carries only the *what* (a circuit made available),
/// never a *when*.
class CircuitProvider extends SingleChildStatelessSeed {
  /// Mounts [resolver] (the bead→circuit policy) into the enclosing scope;
  /// [child] is supplied by an enclosing [Nest].
  const CircuitProvider(this.resolver, {super.child, super.key});

  /// Mounts a SINGLE [circuit] for every bead in the enclosing scope — the
  /// common case (one substation, one circuit). Sugar over a constant
  /// [CircuitResolver].
  CircuitProvider.forCircuit(Circuit circuit, {Seed? child, Key? key})
    : this(CircuitResolver((_) => circuit), child: child, key: key);

  /// The bead→circuit policy this asset makes available in scope.
  final CircuitResolver resolver;

  @override
  Seed buildWithChild(TreeContext context, Seed child) =>
      InheritedSeed<CircuitResolver>(value: resolver, child: child);
}

/// Resolves the [SourceControl] a bead's work runs under — the v3 successor to
/// `ServiceBundle.sourceControlFor(rootName)` (bead `tg-5r9`).
///
/// **`sourceControlFor(bead)` becomes pure resolution over bead → substation →
/// root, with no string-keyed bundle map.** A work bead is mounted UNDER its
/// owning substation's scope, so the nearest ambient [ServiceBundle] — provided
/// by that substation's own [GitGridAssets] / [GitHubGridAssets] — carries its
/// source control. The bead's identity enters through its TREE POSITION (which
/// substation owns it), not through a root name looked up in a map. Returns null
/// when no source-control asset is mounted above (the offline / no-git posture,
/// where provisioning + land no-op).
SourceControl? sourceControlOf(TreeContext context) =>
    context.getInheritedSeedOfExactType<ServiceBundle>()?.sourceControl;
