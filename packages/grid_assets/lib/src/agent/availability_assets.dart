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
library;

import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';

import 'agent_environment.dart';
import 'agent_harness.dart';
import 'environment_probe.dart';
import 'environment_registry.dart';
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
  /// Arms [probe] on the bounded [interval].
  const EnvironmentProbeArming({
    required this.probe,
    this.interval = kEnvironmentProbeInterval,
  });

  /// The injected probe implementation (impls are DI).
  final EnvironmentProbe probe;

  /// The bounded re-probe interval (a VALUE, authored by the station).
  final Duration interval;

  /// Value equality over the probe IDENTITY and the interval, so re-providing
  /// the same arming down a nested `HarnessProvider` notifies nobody.
  @override
  bool operator ==(Object other) =>
      other is EnvironmentProbeArming &&
      other.probe == probe &&
      other.interval == interval;

  @override
  int get hashCode => Object.hash(probe, interval);

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
    super.child,
    super.key,
  });

  /// The injected probe implementation (impls are DI).
  final EnvironmentProbe probe;

  /// The bounded re-probe interval (a VALUE, authored by the station).
  final Duration interval;

  /// The injected tick schedule.
  final ProbeSchedule schedule;

  @override
  SingleChildState<AvailabilityAssets> createState() =>
      _AvailabilityAssetsState();
}

class _AvailabilityAssetsState extends SingleChildState<AvailabilityAssets> {
  EnvironmentRegistry? _registry;
  SiteBinding _siteBinding = SiteBinding.none;
  EnvironmentProbe? _probe;
  AvailableEnvironments? _present;
  ProbeTicker? _ticker;
  var _generation = 0;
  var _disposed = false;

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
    final probe = seed.probe;
    // `==` for all three: `SiteBinding` has value equality, and
    // `EnvironmentRegistry` declares no `==` so it compares by IDENTITY — which
    // is exactly what `InheritedSeed.updateShouldNotify` already compares, and
    // `buildBuiltinEnvironmentRegistry()` returns a canonical `const`.
    if (_ticker != null &&
        registry == _registry &&
        probe == _probe &&
        siteBinding == _siteBinding) {
      return;
    }

    _registry = registry;
    _siteBinding = siteBinding;
    _probe = probe;
    // Fall back to the boot-validated default while the new pass is in flight
    // (ADR-0000 A35(5)) rather than publishing a stale set.
    _present = null;
    _ticker?.cancel();
    _ticker = seed.schedule(seed.interval, _reprobe);
    _generation++;
    unawaited(_runProbe(registry, siteBinding, probe, _generation));
  }

  void _reprobe() {
    if (_disposed) return;
    final registry = _registry;
    final probe = _probe;
    if (registry == null || probe == null) return;
    _generation++;
    unawaited(_runProbe(registry, _siteBinding, probe, _generation));
  }

  /// ONE probe pass. Probes only [EnvironmentRegistry.validatedEnvironments],
  /// so the published set can only ever hold registry members that passed boot
  /// legality (ADR-0000 A35(1)) — presence NARROWS the legal set, never widens
  /// it.
  Future<void> _runProbe(
    EnvironmentRegistry registry,
    SiteBinding siteBinding,
    EnvironmentProbe probe,
    int generation,
  ) async {
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
      if (reachable) present.add(environment);
    }
    if (_disposed || generation != _generation) return;
    final next = AvailableEnvironments(present);
    // Value equality: an unchanged presence set re-publishes nothing, so a
    // five-minute tick never churns a single dependent.
    if (_present == next) return;
    setState(() => _present = next);
  }

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    final registry = _registry;
    // Until the FIRST pass lands, the presence set is exactly the boot-
    // validated registry members (ADR-0000 A35(5)) — nothing regresses.
    final present =
        _present ??
        (registry == null
            ? AvailableEnvironments.none
            : AvailableEnvironments.fromRegistry(registry));
    return InheritedSeed<AvailableEnvironments>(value: present, child: child);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _ticker?.cancel();
    _ticker = null;
  }
}
