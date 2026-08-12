library;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart' show ProviderTreeContext;

import '../code/github_pr_delivery.dart';

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
/// Fail-safe: delivery is bound only when a checkout, [GitOps], and [PrOpener]
/// are all observed. With any one missing it passes the ambient bundle through
/// unchanged: GitHub can only add delivery to a checkout it can commit from,
/// never conjure one. The collaborators are implementations supplied through
/// DI; [PrComposition] is a tree value.
class GitHubGridAssets extends SingleChildStatelessSeed {
  /// Creates the GitHub asset over the optional [composition] tree value.
  const GitHubGridAssets({this.composition, super.child, super.key});

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
    final ops = context.watch<GitOps>();
    final opener = context.watch<PrOpener>();
    final knob = composition;

    var wired = child;
    final checkout = ambient?.sourceControl;
    if (checkout != null && ops != null && opener != null) {
      final resolvedComposition = knob ?? const PrComposition();
      wired = DerivedServiceBundleSeed(
        // Carry through EVERY field the bundle declares — silently dropping one
        // here would unbind an unrelated service.
        value: ServiceBundle(
          sourceControl: checkout,
          delivery: GitHubPrDelivery(
            gitOps: ops,
            prOpener: opener,
            composition: resolvedComposition,
          ),
          escalation: ambient?.escalation,
          trust: ambient?.trust,
          trustFloor:
              ambient?.trustFloor ?? const TrustFloor(TrustLevel.trusted),
          transport: ambient?.transport,
          mountEligibility: ambient?.mountEligibility,
        ),
        derivedFrom: [
          checkout,
          ops,
          opener,
          resolvedComposition,
          ambient?.escalation,
          ambient?.trust,
          ambient?.trustFloor,
          ambient?.transport,
          ambient?.mountEligibility,
        ],
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
