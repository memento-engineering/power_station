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
/// source-control asset ([GitGridAssets] / the GitHub delivery asset) IS its
/// substation's own — a capability's `getInheritedSeedOfExactType<ServiceBundle>`
/// resolves it by TREE POSITION, never by a root name. [sourceControlOf] names
/// that resolution: the substation has ONE source control, and there is no name
/// to select it by. (The engine's [ServiceBundle] declares no root-keyed map at
/// all now — it is five plain fields: source control, delivery, escalation,
/// trust, transport.)
///
/// **The assets are single-child seeds** — each wraps the downstream subtree,
/// so they chain in a `Nest` exactly as the v3 sketch authors them:
/// `assets: Nest(children: [GitGridAssets(...), the GitHub delivery asset])`. The
/// engine reads the ambient values it always has (`ServiceBundle`,
/// `AgentHarnessRegistry`, `AgentConfig`); nothing in the opinion-free engine
/// learns a new type (ADR-0007 §1).
library;

import 'dart:async';

import 'package:beads_dart/beads_dart.dart'
    show BdCliService, BdRunner, Bead, ProcessBdRunner;
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
// grid_sdk's SubstationScope (a freezed name+root VALUE, provided by the SDK's
// `Substation`) collides in NAME with grid_engine's SubstationScope (the old
// StatefulSeed that provided ServiceBundle — the thing this track replaces).
// Prefix the SDK so the two never ambiguate; we only read the SDK scope values.
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:grid_sdk/grid_sdk.dart' show ProviderTreeContext;

import '../agent/agent_harness.dart';
import '../agent/availability_assets.dart';
import '../agent/environment_probe.dart';
import '../agent/environment_registry.dart';
import '../code/code_capabilities.dart';
import '../code/mount_eligibility.dart';

/// Injects grid_assets mount eligibility into the ambient service bundle.
///
/// Eligible snapshots pass through synchronously. A refused snapshot starts one
/// scoped fresh-bead query; while it is in flight the refusal stays LOUD, and
/// completion re-provides the bundle with either the fresh decision or a
/// refusal that names the read failure.
class MountEligibilityAssets extends SingleChildStatefulSeed {
  /// Creates the mount-boundary assets node.
  ///
  /// [runnerFor] is the injected bd runner factory. The default delegates all
  /// process policy to [ProcessBdRunner].
  const MountEligibilityAssets({
    BdRunner Function(String storeRoot) runnerFor = _processRunnerFor,
    super.child,
    super.key,
  }) : _runnerFor = runnerFor;

  final BdRunner Function(String storeRoot) _runnerFor;

  static BdRunner _processRunnerFor(String storeRoot) =>
      ProcessBdRunner(workspaceRoot: storeRoot);

  @override
  SingleChildState<MountEligibilityAssets> createState() =>
      _MountEligibilityAssetsState();
}

class _MountEligibilityAssetsState
    extends SingleChildState<MountEligibilityAssets> {
  ServiceBundle? _ambient;
  sdk.SubstationScope? _scope;
  BdRunner Function(String storeRoot)? _runnerFor;
  BdCliService? _bd;
  final Map<String, Bead> _snapshotsById = <String, Bead>{};
  final Set<String> _readsInFlight = <String>{};
  final Map<String, MountEligibilityDecision> _freshDecisionsById =
      <String, MountEligibilityDecision>{};
  final Map<String, Object> _readFailuresById = <String, Object>{};
  var _generation = 0;
  var _revision = 0;
  var _disposed = false;

  @override
  void didChangeDependencies() {
    _ambient = context.dependOnInheritedSeedOfExactType<ServiceBundle>();
    final scope = context
        .dependOnInheritedSeedOfExactType<sdk.SubstationScope>();
    final runnerFor = seed._runnerFor;
    if (scope == _scope && identical(runnerFor, _runnerFor)) return;

    _scope = scope;
    _runnerFor = runnerFor;
    _bd = scope == null ? null : BdCliService(runnerFor(scope.root));
    _generation++;
    _revision++;
    _resetRechecks();
  }

  MountEligibilityDecision _decisionFor(Bead bead, sdk.SubstationScope scope) {
    final snapshotDecision = mountEligibilityDecision(bead);
    switch (snapshotDecision) {
      case MountEligible():
        _forget(bead.id);
        return snapshotDecision;
      case MountRefused():
        if (_snapshotsById[bead.id] != bead) {
          _forget(bead.id);
          _snapshotsById[bead.id] = bead;
        }

        final freshDecision = _freshDecisionsById[bead.id];
        if (freshDecision != null) return freshDecision;

        final failure = _readFailuresById[bead.id];
        if (failure != null) {
          return MountEligibilityDecision.refused(
            clause:
                'fresh mount-eligibility read failed for ${bead.id} '
                'in ${scope.root}: $failure',
          );
        }

        if (_readsInFlight.add(bead.id)) {
          final bd = _bd;
          if (bd == null) {
            _readsInFlight.remove(bead.id);
            return MountEligibilityDecision.refused(
              clause:
                  'fresh mount-eligibility read failed for ${bead.id} '
                  'in ${scope.root}: bd service unavailable',
            );
          }
          unawaited(_readFresh(bead, scope, bd, _generation));
        }
        return MountEligibilityDecision.refused(
          clause: 'fresh mount-eligibility read pending: ${bead.id}',
        );
    }
  }

  Future<void> _readFresh(
    Bead snapshot,
    sdk.SubstationScope scope,
    BdCliService bd,
    int generation,
  ) async {
    MountEligibilityDecision decision;
    try {
      final beads = await bd.query('id=${snapshot.id}', includeClosed: true);
      if (beads.length != 1 || beads.single.id != snapshot.id) {
        throw StateError(
          'fresh mount-eligibility query for ${scope.root} expected '
          '${snapshot.id}, got [${beads.map((bead) => bead.id).join(', ')}]',
        );
      }
      decision = mountEligibilityDecision(snapshot, freshBead: beads.single);
    } on Object catch (error) {
      _completeFailure(snapshot, generation, error);
      return;
    }
    _completeDecision(snapshot, generation, decision);
  }

  void _completeDecision(
    Bead snapshot,
    int generation,
    MountEligibilityDecision decision,
  ) {
    if (!_isCurrent(snapshot, generation)) return;
    setState(() {
      _readsInFlight.remove(snapshot.id);
      _readFailuresById.remove(snapshot.id);
      _freshDecisionsById[snapshot.id] = decision;
      _revision++;
    });
  }

  void _completeFailure(Bead snapshot, int generation, Object error) {
    if (!_isCurrent(snapshot, generation)) return;
    setState(() {
      _readsInFlight.remove(snapshot.id);
      _freshDecisionsById.remove(snapshot.id);
      _readFailuresById[snapshot.id] = error;
      _revision++;
    });
  }

  bool _isCurrent(Bead snapshot, int generation) =>
      !_disposed &&
      generation == _generation &&
      _snapshotsById[snapshot.id] == snapshot &&
      _readsInFlight.contains(snapshot.id);

  void _forget(String beadId) {
    _snapshotsById.remove(beadId);
    _readsInFlight.remove(beadId);
    _freshDecisionsById.remove(beadId);
    _readFailuresById.remove(beadId);
  }

  void _resetRechecks() {
    _snapshotsById.clear();
    _readsInFlight.clear();
    _freshDecisionsById.clear();
    _readFailuresById.clear();
  }

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    final scope = _scope;
    final MountEligibilityPredicate predicate;
    if (scope == null) {
      predicate = mountEligibilityDecision;
    } else {
      predicate = (bead) => _decisionFor(bead, scope);
    }

    final ambient = _ambient;
    return DerivedServiceBundleSeed(
      value: ServiceBundle.derive(
        ambient ?? const ServiceBundle(),
        mountEligibility: predicate,
      ),
      derivedFrom: [ambient, scope, seed._runnerFor, _revision],
      child: child,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
  }
}

/// **GitServices** — the station's git-execution machinery as ONE ambient
/// value: the shared [StationGitService] provisioner + the [GitOps]
/// commit/push half (bead `pow-72b`).
///
/// The delegate mounts it ONCE (an `InheritedSeed<GitServices>` above the
/// substation fan-out); each seat's [GitGridAssets] then constructs BARE —
/// `Substation(name, root, assets: [GitGridAssets(), the GitHub delivery asset])` —
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

  /// Commit/push ops — the half the GitHub delivery asset needs to bind a delivery
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
/// the GitHub delivery asset is mounted below it to bind one. A substation with only
/// `GitGridAssets` commits its work; adding the GitHub delivery asset lets it deliver.
///
/// The git-execution machinery ("the station supplies the machinery the
/// substation leases" — the shared [StationGitService] provisioner) is watched
/// individually through `context.watch<StationGitService>()`. The observation
/// is nullable: absence is the offline/dry-run build (provisioning no-ops, but
/// `workspaceFor`/`branchFor`/`baseBranch` still resolve from the root — the
/// layout is deterministic + pure). Provider availability drives
/// re-derivation, so machinery appearing or changing never leaves a stale
/// source control mounted below.
class GitGridAssets extends SingleChildStatelessSeed {
  /// Creates the git asset for the enclosing substation's root; [child] is
  /// supplied by an enclosing [Nest] (or set for standalone use).
  const GitGridAssets({
    this.defaultBranch = 'main',
    this.remote = 'origin',
    super.child,
    super.key,
  });

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
    final provisioner = context.watch<StationGitService>();
    return DerivedServiceBundleSeed(
      // ONE source control, resolved by TREE POSITION (the v3 "no string-keyed
      // bundle map"): the substation's own root, never a name selected against a
      // map. No delivery bound — the GitHub delivery asset binds it below.
      value: ServiceBundle(
        sourceControl: GitSourceControl(
          provisioner: provisioner,
          root: RootCheckout(
            path: scope.root,
            substation: scope.name,
            defaultBranch: defaultBranch,
            remote: remote,
          ),
        ),
      ),
      derivedFrom: [provisioner, scope.root, scope.name, defaultBranch, remote],
      child: child,
    );
  }
}

/// Provides a derived service bundle and notifies only when a derivation input
/// changes.
class DerivedServiceBundleSeed extends InheritedSeed<ServiceBundle> {
  /// Creates a bundle provider whose notification identity is [derivedFrom].
  const DerivedServiceBundleSeed({
    required super.value,
    required this.derivedFrom,
    required super.child,
  });

  /// The exact inputs used to construct [value], in a stable order.
  final List<Object?> derivedFrom;

  @override
  bool updateShouldNotify(InheritedSeed<ServiceBundle> oldSeed) {
    if (oldSeed is! DerivedServiceBundleSeed) return true;
    final old = oldSeed.derivedFrom;
    if (old.length != derivedFrom.length) return true;
    for (var i = 0; i < derivedFrom.length; i++) {
      if (derivedFrom[i] != old[i]) return true;
    }
    return false;
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
///
/// **Availability (ADR-0006 D3, bead `pow-n6n.3`).** Passing [probe] mounts an
/// [AvailabilityAssets] BELOW the registry seed, which probes every
/// boot-validated environment and publishes the survivors as
/// `InheritedSeed<AvailableEnvironments>`; a dead local server disappears from
/// the set and the next `resolveEnvironment` walk skips it. Unarmed AND with no
/// ambient [EnvironmentProbeArming], the set stays the boot-validated registry
/// members (ADR-0000 A35(5)).
///
/// **Per-substation arming composes (ADR-0002 D5).** D5 makes a nested
/// `HarnessProvider` the seat's own arming rung, and a nested one re-provides
/// its registry unconditionally — so arming is published as an ambient
/// [EnvironmentProbeArming] and a nested provider WITHOUT its own [probe]
/// INHERITS it, re-mounting an [AvailabilityAssets] over the registry actually
/// in effect for that subtree. Without that, a seat overriding only its
/// registry would keep reading an ancestor's presence set, computed over a
/// different registry.
class HarnessProvider extends SingleChildStatelessSeed {
  /// Creates the harness asset over the station-default [registry] and ambient
  /// [config]; [child] is supplied by an enclosing [Nest].
  const HarnessProvider({
    this.registry,
    this.config = const AgentConfig(),
    this.probe,
    this.probeInterval = kEnvironmentProbeInterval,
    super.child,
    super.key,
  });

  /// The station's environment registry; null ⇒ [buildBuiltinEnvironmentRegistry].
  final EnvironmentRegistry? registry;

  /// The station-default agent config (the ladder's ambient rung).
  final AgentConfig config;

  /// The station's LIVE availability probe (ADR-0006 D3), injected — impls are
  /// DI. A station arms it as `probe: const ProcessEnvironmentProbe().call`.
  ///
  /// NULL (the default) ⇒ this provider mounts no probe of its own; it falls
  /// back to the ambient [EnvironmentProbeArming] (D5 inheritance) and, absent
  /// that too, to the pre-`pow-n6n.3` behaviour: every boot-validated registry
  /// member is present (ADR-0000 A35(5)). Arming is a station's call because
  /// probing touches the machine.
  final EnvironmentProbe? probe;

  /// The bounded re-probe interval used when [probe] is armed (a VALUE).
  final Duration probeInterval;

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    final own = probe;
    // WATCH the ambient arming (the D-H build verb): a station that re-arms
    // above this seat re-mounts this seat's probe pass too.
    final inherited = context
        .dependOnInheritedSeedOfExactType<EnvironmentProbeArming>();
    final arming = own == null
        ? inherited
        : EnvironmentProbeArming(probe: own, interval: probeInterval);
    // The availability seed sits BELOW the registry seed: it READS the registry
    // it probes, and its `AvailableEnvironments` must shadow nothing above it.
    // Bead `pow-2eg` mounts `InheritedSeed<SiteBinding>` in this same nest — it
    // belongs ABOVE this seed, which watches the site binding.
    final below = arming == null
        ? child
        : InheritedSeed<EnvironmentProbeArming>(
            value: arming,
            child: AvailabilityAssets(
              probe: arming.probe,
              interval: arming.interval,
              child: child,
            ),
          );
    return InheritedSeed<EnvironmentRegistry>(
      value: registry ?? buildBuiltinEnvironmentRegistry(),
      child: InheritedSeed<AgentConfig>(value: config, child: below),
    );
  }
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
/// substation's own [GitGridAssets] / the GitHub delivery asset — carries its source
/// control. The bead's identity enters through its TREE POSITION (which
/// substation owns it), not through a root name looked up in a map. Returns null
/// when no source-control asset is mounted above (the offline / no-git posture,
/// where provisioning no-ops).
SourceControl? sourceControlOf(TreeContext context) =>
    context.getInheritedSeedOfExactType<ServiceBundle>()?.sourceControl;
