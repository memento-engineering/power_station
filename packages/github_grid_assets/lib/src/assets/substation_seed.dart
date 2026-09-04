/// The COMPOSED SUBSTATION SEED (bead `pow-lb0`) — one substation of a
/// composing station, authored as a value-configured `StatelessSeed`, vended so
/// a downstream station depends on `the_grid` + `power_station` and nothing
/// else.
///
/// It lands HERE and not in `grid_assets` because it mounts five
/// github_grid_assets types and this package already declares `grid_assets` as a
/// dependency; the reverse edge is a cycle pub cannot resolve (the recorded
/// "no new dependency edge, no reverse edge" direction).
///
/// **Per-seat identity is COMPOSITION, never lookup**: there is no
/// `deliveryFor(name)` and no stringy seat registry. A seat's delivery posture
/// is what its OWN subtree mounts. A [SubstationAppIdentity] selects
/// App-authenticated delivery on a live seat; no value preserves the nearest
/// ambient opener. Polling is independently and explicitly selected by the
/// seat's reconciler config.
///
/// **The git bundle is COMPOSED, never copied**: the stack mounts
/// `grid_assets`' own [GitGridAssets], which provides the substation's
/// `ServiceBundle` over a watched `StationGitService`. This library declares no
/// source-control asset of its own.
library;

import 'package:beads_dart/beads_dart.dart' show BdRunner, ProcessBdRunner;
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart'
    show
        AgentArming,
        AgentConfig,
        AvailableEnvironments,
        BuildAgentEnvironment,
        CriticAgentEnvironment,
        GatherAgentEnvironment,
        GitGridAssets,
        GridAssetRosterOverride,
        MountEligibilityAssets,
        SeatEnvironments,
        SpecAgentEnvironment,
        SubstationFactsSnapshot,
        SubstationKey,
        TypedEnvironmentProvider,
        resolveGridAssets;
import 'package:grid_assets/station_asset_registry.dart'
    show GeneratedGridAssetRegistrant;
import 'package:grid_runtime/grid_runtime.dart' show GitOps;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:grid_sdk/grid_sdk.dart' show Provider, ProviderTreeContext;

import '../code/github_delivery_policy.dart';
import '../credentials.dart';
import '../intake/github_self_trust.dart';
import 'github_app_client_assets.dart';
import 'github_grid_assets.dart';
import 'github_reconciler_assets.dart';
import 'github_reconciler_binding_assets.dart';

/// A GitHub App DELIVERY IDENTITY for ONE substation seat — config identity
/// only, a plain value type.
///
/// Deliberately NOT [GitHubAppConfig], which is the App CLIENT's transport
/// config (`appId`, `installationId`, `apiBaseUri`). This value drops the
/// endpoint and adds [privateKeyVar], the NAME of the variable the injected
/// credential loader resolves at effect time; [SubstationSeed] builds a
/// [GitHubAppConfig] from it internally. It has nowhere to store a secret.
class SubstationAppIdentity {
  /// Creates the identity value.
  const SubstationAppIdentity({
    required this.appId,
    required this.installationId,
    required this.privateKeyVar,
  });

  /// The GitHub App identifier used by App-authenticated PR delivery.
  final String appId;

  /// The installation whose access tokens delivery acts under.
  ///
  /// An `int` at AUTHORING time on purpose: the App client wants an `int`, so a
  /// malformed installation id is a static error where the seat is authored
  /// rather than a `FormatException` thrown from `build` during mount.
  final int installationId;

  /// The configured NAME for the App private key. This library never reads the
  /// process environment; the injected credential loader owns secret
  /// resolution at effect time.
  final String privateKeyVar;

  @override
  bool operator ==(Object other) =>
      other is SubstationAppIdentity &&
      other.appId == appId &&
      other.installationId == installationId &&
      other.privateKeyVar == privateKeyVar;

  @override
  int get hashCode => Object.hash(appId, installationId, privateKeyVar);

  @override
  String toString() =>
      'SubstationAppIdentity(appId: $appId, installationId: $installationId, '
      'privateKeyVar: $privateKeyVar)';
}

/// The offline-enumerable projection mounted by one [SubstationSeed].
final class MountedSubstationSeed {
  /// Creates one mounted substation projection.
  const MountedSubstationSeed({
    required this.scope,
    required this.githubPollingConfigured,
    this.agentConfig,
    this.environments,
  });

  /// The SDK-resolved scope for this substation.
  final sdk.SubstationScope scope;

  /// Whether this substation carries authored GitHub polling configuration.
  final bool githubPollingConfigured;

  /// The agent config RESOLVED AT THIS SEAT'S POSITION — the station's ambient
  /// value. Null only when no harness provider is mounted above (a bare
  /// standalone seed mount).
  final AgentConfig? agentConfig;

  /// The four TYPED lookups resolved AT THIS SEAT'S POSITION — the seat's own
  /// nested [TypedEnvironmentProvider] where it arms one, else the station's.
  /// This is what makes the per-substation rung offline-PROVABLE through the
  /// SDK's mounted-value walk (ADR-0002 D5, ADR-0006 D2).
  final SeatEnvironments? environments;
}

/// THE composed substation seed — one substation of the composing station,
/// authored as a value-configured `StatelessSeed`.
///
/// A seed that BUILDS a `Substation`, never subclasses it (ADR-0008 D2).
class SubstationSeed extends StatelessSeed {
  /// Creates the seed over its VALUE config.
  SubstationSeed({
    required this.name,
    required this.root,
    sdk.GridAssetRegistry? assetRegistry,
    this.assetRenderArguments = const <String, String>{},
    this.assetRosterOverride,
    this.prefix,
    this.app,
    this.githubPoll,
    this.landingPolicy,
    this.arming,
    this.githubAppCredentialLoader = const GitHubAppCredentialLoader(),
    this.githubTransportFactory = createGitHubHttpTransport,
    this.mountEligibilityRunnerFor,
    Key? key,
  }) : assetRegistry = assetRegistry ?? GeneratedGridAssetRegistrant.registry,
       _assetFactsKey = SubstationKey(name),
       super(key: key ?? ValueKey<String>('seat:$name'));

  /// The substation's name (its tree identity).
  final String name;

  /// The substation's ONE root — absolute, or relative to the ambient
  /// `GridRoot` (resolved by the SDK's own `Substation` build).
  final String root;

  /// The STATION-GENERATED asset registry this seat resolves its own
  /// availability from — POTENTIAL availability, which [resolveGridAssets]
  /// narrows to the ACTUAL set this seat mounts
  /// (`power_station#one-asset-resolution-defines-tree-and-writers`).
  ///
  /// OMITTING it takes [GeneratedGridAssetRegistrant.registry], the registry
  /// generated for the station composing THIS package's closure
  /// (`power_station#station-registries-use-resolved-package-closures`) — which
  /// is what a downstream station composing the vended stack wants, and what a
  /// seat authored before the resolution existed keeps getting. Pass one
  /// explicitly to resolve against a different closure (a test fixture, or a
  /// station that generates its own registrant).
  final sdk.GridAssetRegistry assetRegistry;

  /// The `{{hole}}` bindings a materializing consumer renders this seat's
  /// assets against; the seat's own mount needs none, but the value travels
  /// with the resolution so every consumer renders identically.
  final Map<String, String> assetRenderArguments;

  /// This seat's explicit include/exclude exceptions to what the selectors
  /// decide.
  final GridAssetRosterOverride? assetRosterOverride;

  /// This seat's stable facts ASPECT — built ONCE from [name], so `build`
  /// subscribes to the same value every time and one seat's changed facts
  /// cannot rebuild another's.
  final SubstationKey _assetFactsKey;

  /// The work store's issue-id prefix; null means the name (the SDK default).
  final String? prefix;

  /// The seat's delivery identity. On a live seat, non-null selects the
  /// App-authenticated opener; null preserves ambient-opener behavior.
  final SubstationAppIdentity? app;

  /// Explicit polling values for this seat; null keeps reconciliation absent.
  ///
  /// The owner and repository are consumed exactly as authored. They are never
  /// inferred from [root], a git remote, the environment, or station defaults.
  final GitHubReconcilerConfig? githubPoll;

  /// The seat's explicitly selected GitHub landing posture.
  ///
  /// Null preserves [GitHubGridAssets]' default [PrNoMergePolicy]: open or
  /// reuse a PR and leave it unmerged.
  final GitHubDeliveryPolicy? landingPolicy;

  /// The seat's AGENT ARMING — the PER-SUBSTATION rung of the ladder
  /// (ADR-0002 D5). Non-null nests a [TypedEnvironmentProvider] OUTERMOST in
  /// this seat's stack whose armed seats SHADOW the station's for everything
  /// under this substation; an unarmed seat type keeps resolving through the
  /// station's. A VALUE on the seed, exactly like [app] / [githubPoll] /
  /// [landingPolicy] — per-seat identity is COMPOSITION, never a name-keyed
  /// lookup.
  final AgentArming? arming;

  /// Loads this seat's App private key; injectable for deterministic tests.
  final GitHubAppCredentialLoader githubAppCredentialLoader;

  /// Creates this seat's GitHub transport; injectable for deterministic tests.
  final GitHubHttpTransportFactory githubTransportFactory;

  /// The mount gate's `bd`-runner factory, keyed by work-store root;
  /// injectable for deterministic tests.
  ///
  /// Null keeps [MountEligibilityAssets]' own `ProcessBdRunner` default — the
  /// production posture. A gate REFUSAL is confirmed against a FRESH store
  /// read, so an offline suite that exercises a refusal must inject this seam
  /// or the seed spawns a real `bd` at a root that does not exist. Same shape,
  /// same reason, as [githubAppCredentialLoader] and [githubTransportFactory].
  final BdRunner Function(String storeRoot)? mountEligibilityRunnerFor;

  @override
  Seed build(TreeContext context) {
    // WATCH this seat's OWN facts aspect (the D-H build verb, ADR-0008 D3):
    // the repository observes roots outside build and re-projects them, and a
    // change to ANOTHER seat's facts leaves this build alone
    // (`power_station#adr-0006-typed-environment-lookup-selects-by-value`).
    final snapshot = context
        .dependOnInheritedSeedOfExactType<SubstationFactsSnapshot>(
          aspect: _assetFactsKey,
        );
    if (snapshot == null) {
      throw StateError(
        'SubstationSeed($name) requires the ambient SubstationFactsSnapshot '
        '(grid_assets SubstationFactsAssets mounts it)',
      );
    }
    // PURE: selector evaluation only — no file read, no package parse, no
    // watcher, no state mutation.
    final selected = resolveGridAssets(
      registry: assetRegistry,
      snapshot: snapshot,
      substation: _assetFactsKey,
      renderArguments: assetRenderArguments,
      rosterOverride: assetRosterOverride,
    );
    final githubPoll = this.githubPoll;
    final mountEligibilityRunnerFor = this.mountEligibilityRunnerFor;
    final landingPolicy = this.landingPolicy;
    // The PER-SUBSTATION rung (ADR-0002 D5; ADR-0006 D2). A NESTED
    // TypedEnvironmentProvider already shadows the station's for this seat's
    // subtree, per TYPE: a seat that arms only `build` leaves spec/critic/
    // gather resolving through the station's providers.
    final arming = this.arming;
    final children = <SingleChildSeed>[
      // OUTERMOST on purpose: every asset, every work mount and the offline
      // projection below must read the SEAT's seats, not the station's.
      if (arming != null) TypedEnvironmentProvider(arming: arming),
      _MountedSubstationSeedAssets(githubPollingConfigured: githubPoll != null),
      const GitGridAssets(),
      if (githubPoll != null && githubPoll.arm == GitHubReconcilerArm.live)
        _SubstationGitHubReconcilerBindingAssets(config: githubPoll),
      if (githubPoll != null) GitHubReconcilerAssets(config: githubPoll),
      GitHubGridAssets(policy: landingPolicy),
      if (mountEligibilityRunnerFor == null)
        const MountEligibilityAssets()
      else
        MountEligibilityAssets(runnerFor: mountEligibilityRunnerFor),
    ];
    final substation = sdk.Substation(
      name,
      root,
      prefix: prefix,
      assets: [
        // Mounted presence IS availability: the SELECTED generated definitions
        // are the same `const` Seeds the registry holds, spread unchanged.
        ...selected.definitions,
        Nest(
          // MountEligibilityAssets is INNERMOST on purpose: GitGridAssets
          // builds a FRESH ServiceBundle and preserves nothing from ambient,
          // so a gate mounted above it would be silently clobbered and the
          // predicate would never reach SubstationWork. That seed derives FROM
          // the ambient bundle — it copies sourceControl/delivery/escalation/
          // trust/transport forward and adds the predicate.
          children: children,
          child: const sdk.SubstationWork(),
        ),
      ],
    );
    final identity = app;
    if (identity == null) return substation;
    final ops = context.watch<GitOps>();
    final pollAllowsEffects =
        githubPoll == null || githubPoll.arm == GitHubReconcilerArm.live;
    final openerWired = ops == null || !pollAllowsEffects
        ? substation
        : GitHubPrOpenerAssets(
            config: GitHubAppConfig(
              appId: identity.appId,
              installationId: identity.installationId,
            ),
            owner: githubPoll?.owner,
            repository: githubPoll?.repository,
            child: substation,
          );
    final clientWired = !pollAllowsEffects
        ? openerWired
        : GitHubAppClientAssets(
            config: GitHubAppConfig(
              appId: identity.appId,
              installationId: identity.installationId,
            ),
            privateKeyVar: identity.privateKeyVar,
            credentialLoader: githubAppCredentialLoader,
            transportFactory: githubTransportFactory,
            child: openerWired,
          );
    return Provider<SubstationAppIdentity>.value(identity, child: clientWired);
  }
}

final class _MountedSubstationSeedAssets extends SingleChildStatelessSeed {
  const _MountedSubstationSeedAssets({
    required this.githubPollingConfigured,
    // Nest supplies this fold child; direct call sites deliberately omit it.
    // ignore: unused_element_parameter
    super.child,
  });

  final bool githubPollingConfigured;

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    // WATCH the values this projection is derived from (the D-H build verb,
    // ADR-0008 D3): a re-armed station or seat re-derives the projection.
    // AvailableEnvironments is in the set because the availability seed can
    // re-publish presence under a live probe, which changes what every walk
    // below resolves to. SeatEnvironments.of then RESOLVES with the vended
    // effect-boundary readers, which do not subscribe (ADR-0000 A35(6)).
    context.dependOnInheritedSeedOfExactType<BuildAgentEnvironment>();
    context.dependOnInheritedSeedOfExactType<SpecAgentEnvironment>();
    context.dependOnInheritedSeedOfExactType<CriticAgentEnvironment>();
    context.dependOnInheritedSeedOfExactType<GatherAgentEnvironment>();
    context.dependOnInheritedSeedOfExactType<AvailableEnvironments>();
    return Provider<MountedSubstationSeed>.value(
      MountedSubstationSeed(
        scope: sdk.SubstationScope.of(context),
        githubPollingConfigured: githubPollingConfigured,
        agentConfig: context.dependOnInheritedSeedOfExactType<AgentConfig>(),
        environments: SeatEnvironments.of(context),
      ),
      child: child,
    );
  }
}

final class _SubstationGitHubReconcilerBindingAssets
    extends SingleChildStatelessSeed {
  const _SubstationGitHubReconcilerBindingAssets({
    required this.config,
    // Nest supplies this fold child; direct call sites deliberately omit it.
    // ignore: unused_element_parameter
    super.child,
  });

  final GitHubReconcilerConfig config;

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    final trust = context.watch<GitHubSelfTrust>();
    if (trust == null) return child;
    final scope = sdk.SubstationScope.of(context);
    return GitHubReconcilerBindingAssets(
      config: config,
      runner: ProcessBdRunner(workspaceRoot: scope.root),
      trust: trust,
      child: child,
    );
  }
}
