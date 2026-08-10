library;

import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

import '../code/github_pr_delivery.dart';
import '../github/github_reconciler_runtime.dart';

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
class GitHubGridAssets extends SingleChildStatefulSeed {
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
    this.reconcilerRuntime,
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

  /// Optional resident polling lifecycle for this substation's repository.
  final GitHubReconcilerRuntime? reconcilerRuntime;

  @override
  SingleChildState<SingleChildStatefulSeed> createState() =>
      _GitHubGridAssetsState();
}

class _GitHubGridAssetsState extends SingleChildState<SingleChildStatefulSeed> {
  GitHubGridAssets get _seed => seed as GitHubGridAssets;
  late final GitHubReconcilerRuntime? _runtime;

  @override
  void initState() {
    super.initState();
    _runtime = _seed.reconcilerRuntime;
    _runtime?.start();
  }

  @override
  void dispose() {
    if (_runtime case final runtime?) unawaited(runtime.stop());
    super.dispose();
  }

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
    final ops = _seed.gitOps ?? services?.gitOps;
    final opener = _seed.prOpener;
    final knob = _seed.composition;

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
            gitRunner: _seed.gitRunner,
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
