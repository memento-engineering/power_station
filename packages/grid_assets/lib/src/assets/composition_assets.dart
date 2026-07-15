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
/// that resolution: the substation has ONE source control, and there is no name
/// to select it by. (The engine's [ServiceBundle] declares no root-keyed map at
/// all now — it is five plain fields: source control, delivery, escalation,
/// trust, transport.)
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
import '../agent/environment_registry.dart';
import '../code/code_capabilities.dart';
import '../code/delivery.dart';
import '../code/pr_composition.dart';

/// **GitServices** — the station's git-execution machinery as ONE ambient
/// value: the shared [StationGitService] provisioner + the [GitOps]
/// commit/push half (bead `pow-72b`).
///
/// The delegate mounts it ONCE (an `InheritedSeed<GitServices>` above the
/// substation fan-out); each seat's [GitGridAssets] then constructs BARE —
/// `Substation(name, root, assets: [GitGridAssets(), GitHubGridAssets()])` —
/// sourcing both halves from context instead of per-seat constructor
/// threading. Defined here (not in the delegate) so grid_assets READS it and
/// the space-station delegate PROVIDES it against the same type.
///
/// Absence is NOT an error: no carrier — like a carrier with null halves — IS
/// the documented offline/dry-run posture (provisioning + land no-op), so the
/// read is the quiet [maybeOf] only; a loud `of` would turn the valid offline
/// build into a refusal (guards LOUD or GONE — there is no invariant here).
class GitServices {
  /// Bundles the optional [provisioner] and [gitOps] halves; a null half is
  /// the offline posture for that half.
  const GitServices({this.provisioner, this.gitOps});

  /// The station's shared worktree-provisioning service (leased per
  /// substation); null ⇒ provisioning no-ops (offline).
  final StationGitService? provisioner;

  /// Commit/push ops — the half [GitHubGridAssets] needs to bind a delivery
  /// method; null ⇒ no delivery bound (commit-only).
  final GitOps? gitOps;

  /// The ambient [GitServices], or null when no carrier encloses [context]
  /// (the offline posture). SUBSCRIBES (the D-H build verb, ADR-0008): a
  /// re-provided carrier rebuilds the dependent, so every substation's source
  /// control re-derives over the new machinery.
  static GitServices? maybeOf(TreeContext context) =>
      context.dependOnInheritedSeedOfExactType<GitServices>();
}

/// **GitGridAssets** — the substation-scoped SOURCE-CONTROL asset (v3 §3).
///
/// Mounted under the `Substation` it serves, it reads that substation's ambient
/// [sdk.SubstationScope] (its name + its ONE root — v3 §0: a substation is a
/// name and ONE root, never a set, never a `metadata.grid.root` selector),
/// builds the git [SourceControl] for that root, and provides it to the work
/// subtree as `InheritedSeed<ServiceBundle>`.
///
/// It PROVISIONS but binds NO delivery on its own: the provided [ServiceBundle]
/// carries a source control and a null `delivery` (the commit-only posture) until
/// [GitHubGridAssets] is mounted below it to bind one. A substation with only
/// `GitGridAssets` commits its work; adding `GitHubGridAssets` lets it deliver.
///
/// The git-execution machinery ("the station supplies the machinery the
/// substation leases" — the shared [StationGitService] provisioner) is sourced
/// from the ambient [GitServices] carrier the delegate mounts once above the
/// substation fan-out, so a bare `GitGridAssets()` seat works (bead `pow-72b`).
/// The [provisioner] ctor param stays a per-seat OVERRIDE (tests inject; a set
/// ctor field wins over the carrier's). Supplied by neither is the offline/dry-run
/// build (provisioning no-ops, but `workspaceFor`/`branchFor`/`baseBranch` still
/// resolve from the root — the layout is deterministic + pure). The carrier's
/// `gitOps` half is consumed by [GitHubGridAssets], the node that now needs it.
class GitGridAssets extends SingleChildStatelessSeed {
  /// Creates the git asset for the enclosing substation's root. [provisioner] is
  /// an optional per-seat override of the ambient [GitServices] machinery;
  /// [child] is supplied by an enclosing [Nest] (or set for standalone use).
  const GitGridAssets({
    this.provisioner,
    this.defaultBranch = 'main',
    this.remote = 'origin',
    super.child,
    super.key,
  });

  /// The station's shared worktree-provisioning service (leased per substation);
  /// null ⇒ the ambient [GitServices]'s (absent there too ⇒ provisioning
  /// no-ops, offline).
  final StationGitService? provisioner;

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
    // The station machinery: an explicit ctor override wins (tests inject),
    // else the ambient GitServices carrier. The subscribing read (D-H,
    // ADR-0008): re-provided machinery re-derives this substation's source
    // control rather than leaving a stale snapshot mounted below.
    final services = GitServices.maybeOf(context);
    final root = RootCheckout(
      path: scope.root,
      substation: scope.name,
      defaultBranch: defaultBranch,
      remote: remote,
    );
    final sourceControl = GitSourceControl(
      provisioner: provisioner ?? services?.provisioner,
      root: root,
    );
    return InheritedSeed<ServiceBundle>(
      // ONE source control, resolved by TREE POSITION (the v3 "no string-keyed
      // bundle map"): the substation's own root, never a name selected against a
      // map. No delivery bound — GitHubGridAssets binds it below.
      value: ServiceBundle(sourceControl: sourceControl),
      child: child,
    );
  }
}

/// **GitHubGridAssets** — the substation-scoped asset that BINDS the GitHub
/// DELIVERY METHOD onto the substation's git asset (v3 §3).
///
/// Authored BELOW [GitGridAssets] in the substation's `Nest`
/// (`[GitGridAssets(...), GitHubGridAssets()]` folds outermost-first, so
/// GitGridAssets is the ancestor and this is its descendant). It OBSERVES the
/// ambient [ServiceBundle] GitGridAssets provided (`dependOn*`, so a
/// re-provisioned bundle re-binds — D-H, ADR-0008), binds a [GitHubPrDelivery]
/// onto [ServiceBundle.delivery], and RE-provides the bundle so the work subtree
/// below delivers at its terminal advance.
///
/// M5 D-4a is what moved the binding: delivery is a bundle FIELD now, not a
/// `SourceControl` verb, so there is no source control to "enrich" with a PR
/// opener. The fold-order argument is unchanged and still load-bearing — the
/// binding must happen at the INNER GitHub node, which reads its ancestor's
/// bundle and re-provides it downward.
///
/// Fail-safe: delivery is bound only when BOTH halves are present — a [prOpener]
/// AND commit/push [GitOps] (its own, or the ambient [GitServices] carrier's).
/// With either missing it passes the ambient bundle through unchanged: GitHub can
/// only ADD delivery to a git checkout it can commit from, never conjure one.
class GitHubGridAssets extends SingleChildStatelessSeed {
  /// Creates the GitHub asset over the optional [prOpener] (the runner injects a
  /// live `GhPrOpener`; null ⇒ NO delivery bound — the commit-only arm), the
  /// optional [gitOps] per-seat override, the optional [gitRunner] the
  /// force-push runs through, and the optional [composition] PR-shaping knob;
  /// [child] is supplied by an enclosing [Nest].
  const GitHubGridAssets({
    this.prOpener,
    this.gitOps,
    this.gitRunner,
    this.composition,
    super.child,
    super.key,
  });

  /// The PR-opening seam (a live `GhPrOpener`); null ⇒ no delivery bound
  /// (offline / commit-only).
  final PrOpener? prOpener;

  /// Commit/push ops — a per-seat override of the ambient [GitServices]'s (ctor
  /// wins when present, else the carrier — merged per FIELD). Absent in both ⇒
  /// no delivery bound.
  final GitOps? gitOps;

  /// The raw `git` seam the force-with-lease push runs through; null ⇒ the real
  /// [SystemGitRunner].
  final GitRunner? gitRunner;

  /// The substation's PR title/body composition knob (bead `pow-8dx`) — the
  /// trailer token, the body sections, and the describe model — mounted as
  /// `InheritedSeed<PrComposition>` for the work subtree and read by
  /// `DeliverRouteCapability`/`AgentCapability` at their route/spawn edges. Null
  /// ⇒ nothing mounted; both fall back to `const PrComposition()` (the
  /// better-by-default shape). Config = VALUES in the tree (ADR-0008).
  final PrComposition? composition;

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    // OBSERVE the ambient bundle (D-H: watch deps in `build`, ADR-0008) — a
    // non-subscribing `get*` here would leave this asset re-providing a bundle
    // that wraps the STALE source control after GitGridAssets (which watches
    // `SubstationScope`) re-provides a fresh one. The subscribing read rebuilds
    // this node so delivery stays bound alongside the CURRENT source control.
    final ambient = context.dependOnInheritedSeedOfExactType<ServiceBundle>();
    // The carrier read is the QUIET, SUBSCRIBING `maybeOf` (absence is the
    // documented offline posture, not an error). It happens HERE — not only in
    // GitGridAssets — because THIS is the node that consumes the gitOps half, and
    // re-provided machinery must RE-DERIVE the binding rather than leave a stale
    // one mounted.
    final services = GitServices.maybeOf(context);
    final ops = gitOps ?? services?.gitOps;
    final opener = prOpener;
    final knob = composition;

    var wired = child;
    // BOTH halves, or nothing is bound (commit-only).
    if (ops != null && opener != null) {
      wired = InheritedSeed<ServiceBundle>(
        // Carry through EVERY field the bundle declares — silently dropping one
        // here would unbind an unrelated service.
        value: ServiceBundle(
          sourceControl: ambient?.sourceControl,
          delivery: GitHubPrDelivery(
            gitOps: ops,
            prOpener: opener,
            gitRunner: gitRunner,
            composition: knob ?? const PrComposition(),
          ),
          escalation: ambient?.escalation,
          trust: ambient?.trust,
          transport: ambient?.transport,
        ),
        child: child,
      );
    }
    // The composition knob mounts INDEPENDENTLY of the delivery binding (it is a
    // VALUE, not a service): a pass-through build still carries the substation's
    // PR shaping — and the build agent's commit policy — for whatever source
    // control is ambient.
    return knob == null
        ? wired
        : InheritedSeed<PrComposition>(value: knob, child: wired);
  }
}

/// **HarnessProvider** — harness provision as a STATION-scoped asset (v3 §3).
///
/// Provides the station's default [EnvironmentRegistry] (which named inference
/// environments the machine arms) and its ambient [AgentConfig] (the default
/// harness / model / params — the bottom rung of the agent-config ladder, ADR-0008
/// Decision 10) to everything mounted below. Station scope, because these serve
/// the MACHINE, not a single project (v3 §3: station-level assets serve the
/// machine). Mounted above the `Substations` fan-out, every substation's work
/// inherits it; a bead's `grid.agent` envelope and a step's params still
/// override it per-work at the effect boundary ([resolveAgentConfig]).
///
/// [registry] defaults to [buildBuiltinEnvironmentRegistry] (the first-party
/// claude/copilot/pi/opencode/codex set as data) — a `const` value, so the
/// default is canonical (repeated resolution is the SAME instance, no dependent
/// churn).
class HarnessProvider extends SingleChildStatelessSeed {
  /// Creates the harness asset over the station-default [registry] and ambient
  /// [config]; [child] is supplied by an enclosing [Nest].
  const HarnessProvider({
    this.registry,
    this.config = const AgentConfig(),
    super.child,
    super.key,
  });

  /// The station's environment registry; null ⇒ [buildBuiltinEnvironmentRegistry].
  final EnvironmentRegistry? registry;

  /// The station-default agent config (the ladder's ambient rung).
  final AgentConfig config;

  @override
  Seed buildWithChild(TreeContext context, Seed child) =>
      InheritedSeed<EnvironmentRegistry>(
        value: registry ?? buildBuiltinEnvironmentRegistry(),
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
/// the retired root-keyed bundle map (bead `tg-5r9`).
///
/// **Source-control resolution is pure over bead → substation → root, with no
/// string-keyed bundle map.** A work bead is mounted UNDER its owning
/// substation's scope, so the nearest ambient [ServiceBundle] — provided by that
/// substation's own [GitGridAssets] / [GitHubGridAssets] — carries its source
/// control. The bead's identity enters through its TREE POSITION (which
/// substation owns it), not through a root name looked up in a map. Returns null
/// when no source-control asset is mounted above (the offline / no-git posture,
/// where provisioning no-ops).
SourceControl? sourceControlOf(TreeContext context) =>
    context.getInheritedSeedOfExactType<ServiceBundle>()?.sourceControl;
