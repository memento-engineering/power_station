/// The AVAILABILITY SEED (ADR-0006 D3, bead `pow-n6n.3`) — presence in the tree
/// IS availability.
///
/// [AvailabilityAssets] probes every boot-validated registry environment and
/// PUBLISHES the survivors as an `InheritedSeed<AvailableEnvironments>`. A dead
/// local server simply STOPS BEING MOUNTED, and the very next
/// `resolveEnvironment` walk skips it because the value is no longer in the
/// ambient set — no probe cache, no try-then-fall-through, no retry ladder.
///
/// D-H DOCTRINE (ADR-0000 A8; ADR-0008 D3), three ways: the registry and the
/// site binding are WATCHED with `dependOnInheritedSeedOfExactType` in
/// `didChangeDependencies` (never snapshot-and-cache); the mutable presence set
/// is RE-PROJECTED into the tree and has no public synchronous accessor; and
/// the probe implementation is DI while the interval is a VALUE — both carried
/// together as [EnvironmentProbeArming], an ambient value a nested
/// `HarnessProvider` INHERITS (ADR-0002 D5 per-substation arming).
///
/// STALENESS IS THE TREE'S ANSWER, not a hand-kept counter. One probe pass is a
/// VALUE mounted above a `LifecycleProvider`; replacing that value is what
/// starts a pass, and the [TreeDependencyScope] the participant is handed is
/// what an in-flight pass tests before it publishes. `_disposed` still answers
/// REMOVAL — the two questions stay separate.
library;

import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';

import 'agent_environment.dart';
import 'agent_harness.dart';
import 'environment_probe.dart';
import 'environment_registry.dart';
import 'lane_environment_health.dart';
import 'site_binding.dart';
import 'typed_environment.dart';

/// The BOUNDED re-probe interval (ADR-0006 D3 "re-probes on a bounded
/// interval"). Five minutes: long enough that a probe pass is free, short
/// enough that a recovered local server rejoins within one committee round.
const Duration kEnvironmentProbeInterval = Duration(minutes: 5);

/// A cancellable repeating tick — the DI seam over `Timer.periodic`, so a test
/// FIRES the bounded re-probe instead of sleeping on a wall clock.
abstract interface class ProbeTicker {
  /// Stops the tick. Idempotent.
  void cancel();
}

/// Starts a repeating [period] tick that calls [onTick]. Injected into
/// [AvailabilityAssets]; the real one is [timerProbeSchedule].
typedef ProbeSchedule =
    ProbeTicker Function(Duration period, void Function() onTick);

/// The real schedule: a `Timer.periodic`.
ProbeTicker timerProbeSchedule(Duration period, void Function() onTick) =>
    _TimerProbeTicker(Timer.periodic(period, (_) => onTick()));

class _TimerProbeTicker implements ProbeTicker {
  _TimerProbeTicker(this._timer);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}

/// A station's LIVE availability ARMING as ONE ambient value: the injected
/// [probe] plus the bounded [interval] it runs on.
///
/// The `GitServices` precedent (`assets/composition_assets.dart`) — an impl
/// carrier mounted ONCE as an `InheritedSeed` and read in `build` — applied to
/// arming, and it is what makes ADR-0002 D5's per-substation arming compose: a
/// NESTED `HarnessProvider` that overrides only its registry re-mounts an
/// [AvailabilityAssets] over the INHERITED arming, so its subtree's presence
/// set is computed against the registry actually in effect there.
class EnvironmentProbeArming {
  /// Arms [probe] on the bounded [interval], with the station's optional
  /// [laneHealth] coordinator.
  const EnvironmentProbeArming({
    required this.probe,
    this.interval = kEnvironmentProbeInterval,
    this.laneHealth,
  });

  /// The injected probe implementation (impls are DI).
  final EnvironmentProbe probe;

  /// The bounded re-probe interval (a VALUE, authored by the station).
  final Duration interval;

  /// The station's LANE-HEALTH coordinator (bead `pow-u1bi`), or null when it
  /// arms none — in which case a lane is exactly as available as the boolean
  /// probe says, which is the pre-`pow-u1bi` behaviour.
  ///
  /// It rides the ARMING for the same reason the probe does (A38(4)): a nested
  /// `HarnessProvider` that overrides only its registry must diagnose against
  /// the SAME coordinator, or a lane parked above it would come back to life
  /// one subtree down.
  final LaneEnvironmentHealth? laneHealth;

  /// Value equality over the probe IDENTITY and the interval, so re-providing
  /// the same arming down a nested `HarnessProvider` notifies nobody.
  @override
  bool operator ==(Object other) =>
      other is EnvironmentProbeArming &&
      other.probe == probe &&
      other.interval == interval &&
      identical(other.laneHealth, laneHealth);

  @override
  int get hashCode =>
      Object.hash(probe, interval, identityHashCode(laneHealth));

  @override
  String toString() => 'EnvironmentProbeArming($interval)';
}

/// The probing seed: mounts [AvailableEnvironments] over the ambient
/// [EnvironmentRegistry], re-probing on a bounded [interval] and whenever the
/// registry or the ambient [SiteBinding] changes.
///
/// Mounted BELOW the registry it probes — `HarnessProvider(probe: …)` does this
/// (`assets/composition_assets.dart`); mounting it above a registry would leave
/// it probing the builtins while the station armed something else.
class AvailabilityAssets extends SingleChildStatefulSeed {
  /// Creates the seed over its injected [probe], the bounded [interval], and
  /// the injected [schedule] (the real `Timer.periodic` by default).
  const AvailabilityAssets({
    required this.probe,
    this.interval = kEnvironmentProbeInterval,
    this.schedule = timerProbeSchedule,
    this.laneHealth,
    super.child,
    super.key,
  });

  /// The injected probe implementation (impls are DI).
  final EnvironmentProbe probe;

  /// The bounded re-probe interval (a VALUE, authored by the station).
  final Duration interval;

  /// The injected tick schedule.
  final ProbeSchedule schedule;

  /// The station's LANE-HEALTH coordinator, or null when it arms none.
  ///
  /// This seed SUBSCRIBES to its condition stream and re-projects the answer as
  /// a narrowing of the presence set — the D-H way round, because the
  /// coordinator has no synchronous accessor to read and a `build` may only
  /// observe tree values.
  final LaneEnvironmentHealth? laneHealth;

  @override
  SingleChildState<AvailabilityAssets> createState() =>
      _AvailabilityAssetsState();
}

/// ONE probe pass, as a tree VALUE — identity IS the pass.
///
/// The host replaces it when a watched dependency changes and on every bounded
/// tick; mounting the replacement delivers a fresh dependency pass to
/// [_AvailabilityLifecycle], which invalidates the previous pass's scope before
/// the newer probe starts. That is the whole supersession mechanism: a slow
/// pass cannot publish over a newer one, and nothing counts generations.
final class _AvailabilityProbePass {
  _AvailabilityProbePass();
}

/// Owns the probe pass's dependency callback without retaining a tree reader
/// outside it (the `CapabilityHost` precedent in `grid_engine`'s
/// `circuit/capability_host.dart`).
///
/// Its ONLY field is the host State, and its dependency callback does one
/// thing: hand the call-scoped reader and this pass's [TreeDependencyScope] to
/// a single host method, which watches there. The scope rides into the host's
/// probe run as a PARAMETER and is stored nowhere.
final class _AvailabilityLifecycle implements TreeLifecycleParticipant {
  _AvailabilityLifecycle(this._host);

  final _AvailabilityAssetsState _host;

  @override
  void initState(TreeSnapshotReader reader) {}

  @override
  void didChangeDependencies(
    TreeWatchingReader reader,
    TreeDependencyScope scope,
  ) => _host._startProbePass(reader, scope);

  @override
  void dispose() {}
}

class _AvailabilityAssetsState extends SingleChildState<AvailabilityAssets> {
  EnvironmentRegistry? _registry;
  SiteBinding _siteBinding = SiteBinding.none;
  AvailableEnvironments? _present;
  ProbeTicker? _ticker;
  LaneEnvironmentCondition _condition = LaneEnvironmentCondition.none;
  StreamSubscription<LaneEnvironmentCondition>? _conditionSub;
  var _pass = _AvailabilityProbePass();
  var _disposed = false;

  /// Subscribes to the armed coordinator's conditions ONCE, for this mount.
  ///
  /// The subscription starts a new probe PASS rather than editing the published
  /// set directly: a lane going down or coming back is exactly the kind of
  /// supersedable change the pass marker already sequences, so parking rides
  /// the mechanism that is already there instead of a second one beside it.
  @override
  void initState() {
    final health = seed.laneHealth;
    if (health == null) return;
    _conditionSub = health.conditions.listen((condition) {
      if (_disposed || condition == _condition) return;
      setState(() {
        _condition = condition;
        _pass = _AvailabilityProbePass();
      });
    });
  }

  @override
  void didChangeDependencies() {
    // WATCH the deps (the D-H build verb): a re-armed registry or a re-bound
    // site binding re-probes; a stale presence set is never re-published.
    final registry =
        context.dependOnInheritedSeedOfExactType<EnvironmentRegistry>() ??
        buildBuiltinEnvironmentRegistry();
    final siteBinding =
        context.dependOnInheritedSeedOfExactType<SiteBinding>() ??
        SiteBinding.none;
    // `==` for both: `SiteBinding` has value equality, and `EnvironmentRegistry`
    // declares no `==` so it compares by IDENTITY — which is exactly what
    // `InheritedSeed.updateShouldNotify` already compares, and
    // `buildBuiltinEnvironmentRegistry()` returns a canonical `const`.
    if (_ticker != null &&
        registry == _registry &&
        siteBinding == _siteBinding) {
      return;
    }

    _registry = registry;
    _siteBinding = siteBinding;
    // Fall back to the boot-validated default while the new pass is in flight
    // (ADR-0000 A35(5)) rather than publishing a stale set.
    _present = null;
    _ticker?.cancel();
    _ticker = null;
    _pass = _AvailabilityProbePass();
  }

  /// Starts the pass [scope] qualifies: the bounded ticker (once per arming)
  /// and ONE probe run. Called from the owning lifecycle's dependency callback
  /// — the `CapabilityHost` shape, where the participant holds only its host
  /// and every watch happens here — so the scope handed to the run is always
  /// that pass's own.
  ///
  /// The marker is the participant's SUBSCRIPTION, not this pass's read: the
  /// host's own `didChangeDependencies` already applied the registry and the
  /// site binding (with their absent-value fallbacks) before the subtree
  /// carrying the participant was built. Watching it is a COMPLETE
  /// subscription, because the host mints a replacement marker on exactly the
  /// changes that supersede a probe — and, mounting it directly above this
  /// provider, can never let the lookup miss.
  ///
  /// Watching [EnvironmentRegistry] and [SiteBinding] here as well would be
  /// worse than redundant. Both are OPTIONAL above this asset — the host falls
  /// back to the builtin registry and to [SiteBinding.none] — and `watch` on a
  /// MISS parks a pending registration, asserting that a `ProviderScope` exists
  /// to park it with. A bare composition is supported here, so the subscription
  /// stays on the one value this asset mounts itself.
  void _startProbePass(TreeWatchingReader reader, TreeDependencyScope scope) {
    reader.watch<_AvailabilityProbePass>();
    _ticker ??= seed.schedule(seed.interval, _reprobe);
    unawaited(_runProbe(scope));
  }

  /// The bounded tick. It starts no probe of its own: it replaces the pass
  /// marker, and the dependency pass that lands invalidates the older scope
  /// before the newer run begins — so a tick can never publish behind itself.
  void _reprobe() {
    if (_disposed) return;
    setState(() => _pass = _AvailabilityProbePass());
  }

  /// ONE probe pass. Probes only [EnvironmentRegistry.validatedEnvironments],
  /// so the published set can only ever hold registry members that passed boot
  /// legality (ADR-0000 A35(1)) — presence NARROWS the legal set, never widens
  /// it.
  Future<void> _runProbe(TreeDependencyScope scope) async {
    // The host's own dependency callback stores the registry BEFORE the subtree
    // that owns this pass is ever built, so a pass without one cannot exist.
    final registry = _registry!;
    final siteBinding = _siteBinding;
    final probe = seed.probe;
    final health = seed.laneHealth;
    final present = <AgentEnvironment>{};
    for (final environment in registry.validatedEnvironments) {
      final name = registry.nameOf(environment);
      final Uri? endpoint;
      try {
        endpoint = siteBinding.endpointFor(
          name: name,
          environment: environment,
        );
      } on SiteBindingError {
        // Unbound HERE ⇒ absent HERE. The LOUD refusal for an unbound machine
        // fact is the composition root's boot check; a live tree must not tear
        // down because one endpoint went unbound mid-run.
        continue;
      }
      var reachable = false;
      try {
        reachable = await probe(
          EnvironmentProbeRequest(
            name: name,
            environment: environment,
            endpoint: endpoint,
          ),
        );
      } on Object {
        // A probe that throws IS the failure signal: absent, and the rest of
        // the pass still publishes.
        reachable = false;
      }
      // THE PARK, applied here and nowhere else: a lane the coordinator holds
      // down is absent no matter what the boolean probe says — in the measured
      // incident the binary was present and the provider was reachable the
      // whole time, which is precisely why presence alone could not see it.
      //
      // A conditioned lane gets ONE question per pass, and it is the
      // coordinator's, not ours: this asset never reads a park back out of its
      // own state to decide whether to lift it (guards LOUD or GONE — the
      // coordinator owns the predicate, so there is exactly one of it).
      if (health != null && _condition.isDown(name)) {
        try {
          reachable = await health.confirmScheduledRecovery(
            lane: name,
            present: reachable,
          );
        } on Object {
          reachable = false;
        }
      }
      if (reachable) present.add(environment);
    }
    // Two questions, two guards: `_disposed` answers REMOVAL and the scope
    // answers STALENESS (a newer pass started while this one was in flight).
    if (_disposed || !scope.isCurrent) return;
    final next = AvailableEnvironments(present);
    // Value equality: an unchanged presence set re-publishes nothing, so a
    // five-minute tick never churns a single dependent.
    if (_present == next) return;
    setState(() => _present = next);
  }

  /// [probed] without the environments armed under a PARKED lane name.
  ///
  /// Resolving the name needs the registry, so a pass with none published yet
  /// narrows nothing — there is no lane to name, and the boot-validated
  /// fallback is the only set there is.
  AvailableEnvironments _narrow(
    AvailableEnvironments probed,
    EnvironmentRegistry? registry,
  ) {
    if (_condition.down.isEmpty || registry == null) return probed;
    final kept = <AgentEnvironment>{
      for (final environment in probed.values)
        if (!_condition.isDown(_laneOf(registry, environment))) environment,
    };
    return kept.length == probed.values.length
        ? probed
        : AvailableEnvironments(kept);
  }

  /// [registry]'s name for [environment], or the empty string when it arms no
  /// such member.
  ///
  /// An unnameable environment is never a PARKED one: parking keys on a lane
  /// name, so something the registry cannot name cannot be the lane that was
  /// parked, and dropping it here would remove an environment nobody condemned.
  String _laneOf(EnvironmentRegistry registry, AgentEnvironment environment) {
    try {
      return registry.nameOf(environment);
    } on Object {
      return '';
    }
  }

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    final registry = _registry;
    // Until the FIRST pass lands, the presence set is exactly the boot-
    // validated registry members (ADR-0000 A35(5)) — nothing regresses.
    final probed =
        _present ??
        (registry == null
            ? AvailableEnvironments.none
            : AvailableEnvironments.fromRegistry(registry));
    // THE PARK IS APPLIED AT PUBLICATION, not only inside a pass: a lane going
    // down must leave the set on the build the condition arrives on, without
    // waiting for the in-flight probe to finish agreeing. That is what stops
    // the THIRD spawn — the one the live incident served while the second
    // failure was still being classified.
    final present = _narrow(probed, registry);
    return InheritedSeed<_AvailabilityProbePass>(
      value: _pass,
      child: LifecycleProvider<_AvailabilityLifecycle>(
        create: () => _AvailabilityLifecycle(this),
        child: InheritedSeed<AvailableEnvironments>(
          value: present,
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _ticker = null;
    unawaited(_conditionSub?.cancel());
    _conditionSub = null;
  }
}
