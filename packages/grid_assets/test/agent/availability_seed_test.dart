// Bead `pow-n6n.3` (epic `pow-n6n`) - the availability seed: presence in the
// tree IS availability (ADR-0006 D3). Fakes only; nothing here touches a
// machine.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

/// Ends every probe tree (the `typed_environment_test.dart` idiom).
class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const []);
}

/// Records the ambient presence set on every build, SUBSCRIBING so a
/// re-published set rebuilds it.
class _Watcher extends StatelessSeed {
  const _Watcher(this.seen);
  final List<AvailableEnvironments> seen;

  @override
  Seed build(TreeContext context) {
    seen.add(
      context.dependOnInheritedSeedOfExactType<AvailableEnvironments>() ??
          AvailableEnvironments.none,
    );
    return const _Leaf();
  }
}

/// Records the ambient STATION permission policy on every build, SUBSCRIBING
/// so a re-published policy rebuilds it (bead `pow-ed1c`).
class _PolicyWatcher extends StatelessSeed {
  const _PolicyWatcher(this.seen);
  final List<AgentPermissionPolicy> seen;

  @override
  Seed build(TreeContext context) {
    seen.add(
      context.dependOnInheritedSeedOfExactType<AgentPermissionPolicy>() ??
          const AgentPermissionPolicy.unavailable(),
    );
    return const _Leaf();
  }
}

/// The `pow-n6n.2` shape, PRIVATE here: the TYPE is the scope.
class _SpecPreference extends ModelPreference {
  const _SpecPreference(super.entries);
}

/// A Fake probe: an environment is present unless its NAME is down, and a name
/// in [throwing] makes the probe throw (the failure-signal case).
class _FakeProbe {
  _FakeProbe({Set<String> down = const {}, Set<String> throwing = const {}})
    : _down = {...down},
      _throwing = {...throwing};

  final Set<String> _down;
  final Set<String> _throwing;
  final List<String> calls = <String>[];

  void goDown(String name) => _down.add(name);
  void comeBack(String name) => _down.remove(name);

  Future<bool> call(EnvironmentProbeRequest request) async {
    calls.add(request.name);
    if (_throwing.contains(request.name)) {
      throw StateError('probe blew up for ${request.name}');
    }
    return !_down.contains(request.name);
  }
}

/// A Fake schedule: captures the tick so the bounded re-probe FIRES on demand.
class _FakeSchedule implements ProbeTicker {
  void Function()? _onTick;
  var cancels = 0;

  ProbeTicker start(Duration period, void Function() onTick) {
    _onTick = onTick;
    return this;
  }

  void fire() => _onTick!();

  @override
  void cancel() => cancels++;
}

const AgentEnvironment _frontier = AgentEnvironment(
  command: 'claude',
  model: 'opus',
  target: InferenceTarget.providerManaged,
);
const AgentEnvironment _local = AgentEnvironment(
  command: 'claude',
  model: 'qwen',
  target: InferenceTarget.swiftInfer,
);
const AgentEnvironment _broken = AgentEnvironment(model: 'unspawnable');
const AgentEnvironment _seat = AgentEnvironment(
  command: 'codex',
  model: 'gpt',
  target: InferenceTarget.providerManaged,
);

const EnvironmentRegistry _registry = EnvironmentRegistry(
  custom: {'frontier': _frontier, 'local': _local},
);

final SiteBinding _bound = SiteBinding({
  'local': Uri.parse('http://127.0.0.1:8080'),
});

typedef _Mounted = ({TreeOwner owner, List<AvailableEnvironments> seen});

/// Mounts registry -> site binding -> the availability seed -> a watcher, and
/// drains the first probe pass.
Future<_Mounted> _mount(
  _FakeProbe probe,
  _FakeSchedule schedule, {
  EnvironmentRegistry registry = _registry,
  SiteBinding? siteBinding,
}) async {
  final seen = <AvailableEnvironments>[];
  final owner = TreeOwner();
  owner.mountRoot(
    InheritedSeed<EnvironmentRegistry>(
      value: registry,
      child: InheritedSeed<SiteBinding>(
        value: siteBinding ?? _bound,
        child: AvailabilityAssets(
          probe: probe.call,
          schedule: schedule.start,
          child: _Watcher(seen),
        ),
      ),
    ),
  );
  owner.flush();
  await _settle(owner);
  return (owner: owner, seen: seen);
}

/// Drains the in-flight probe pass and flushes what it dirtied (the
/// `track_f_composition_assets_test.dart` idiom).
Future<void> _settle(TreeOwner owner) async {
  await pumpEventQueue();
  owner.flush();
}

void main() {
  group('pow-n6n.3 - presence is the truth', () {
    test('an environment whose probe FAILS is absent from the set', () async {
      final probe = _FakeProbe(down: {'local'});
      final schedule = _FakeSchedule();
      final mounted = await _mount(probe, schedule);

      final present = mounted.seen.last;
      expect(present.contains(_frontier), isTrue);
      expect(present.contains(_local), isFalse);
      expect(probe.calls, containsAll(<String>['frontier', 'local']));
      mounted.owner.dispose();
    });

    test('recovery RE-ADDS it on the bounded tick', () async {
      final probe = _FakeProbe(down: {'local'});
      final schedule = _FakeSchedule();
      final mounted = await _mount(probe, schedule);
      expect(mounted.seen.last.contains(_local), isFalse);

      probe.comeBack('local');
      schedule.fire();
      await _settle(mounted.owner);

      expect(mounted.seen.last.contains(_local), isTrue);
      expect(mounted.seen.last.contains(_frontier), isTrue);
      mounted.owner.dispose();
    });

    test(
      'a live environment that GOES DOWN leaves the set on the tick',
      () async {
        final probe = _FakeProbe();
        final schedule = _FakeSchedule();
        final mounted = await _mount(probe, schedule);
        expect(mounted.seen.last.contains(_local), isTrue);

        probe.goDown('local');
        schedule.fire();
        await _settle(mounted.owner);

        expect(mounted.seen.last.contains(_local), isFalse);
        expect(mounted.seen.last.contains(_frontier), isTrue);
        mounted.owner.dispose();
      },
    );

    test(
      'a probe that THROWS counts as absent, and the pass survives',
      () async {
        final probe = _FakeProbe(throwing: {'local'});
        final schedule = _FakeSchedule();
        final mounted = await _mount(probe, schedule);

        expect(mounted.seen.last.contains(_local), isFalse);
        expect(mounted.seen.last.contains(_frontier), isTrue);
        mounted.owner.dispose();
      },
    );

    test(
      'an UNBOUND machine fact is absent and no SiteBindingError escapes',
      () async {
        final probe = _FakeProbe();
        final schedule = _FakeSchedule();
        final mounted = await _mount(
          probe,
          schedule,
          siteBinding: SiteBinding.none,
        );

        expect(mounted.seen.last.contains(_local), isFalse);
        expect(mounted.seen.last.contains(_frontier), isTrue);
        expect(probe.calls, isNot(contains('local')));
        mounted.owner.dispose();
      },
    );

    test('a boot-REFUSED member never enters the set', () async {
      final probe = _FakeProbe();
      final schedule = _FakeSchedule();
      final mounted = await _mount(
        probe,
        schedule,
        registry: const EnvironmentRegistry(
          custom: {'frontier': _frontier, 'broken': _broken},
        ),
      );

      expect(mounted.seen.last.contains(_frontier), isTrue);
      expect(mounted.seen.last.contains(_broken), isFalse);
      expect(probe.calls, isNot(contains('broken')));
      mounted.owner.dispose();
    });

    test(
      'before the first pass the set is the boot-validated default',
      () async {
        final probe = _FakeProbe(down: {'local'});
        final schedule = _FakeSchedule();
        final seen = <AvailableEnvironments>[];
        final owner = TreeOwner();
        owner.mountRoot(
          InheritedSeed<EnvironmentRegistry>(
            value: _registry,
            child: InheritedSeed<SiteBinding>(
              value: _bound,
              child: AvailabilityAssets(
                probe: probe.call,
                schedule: schedule.start,
                child: _Watcher(seen),
              ),
            ),
          ),
        );
        owner.flush();

        expect(seen.single, AvailableEnvironments.fromRegistry(_registry));
        await _settle(owner);
        expect(seen.last.contains(_local), isFalse);
        owner.dispose();
      },
    );

    test('an UNCHANGED presence set rebuilds no dependent', () async {
      final probe = _FakeProbe(down: {'local'});
      final schedule = _FakeSchedule();
      final mounted = await _mount(probe, schedule);
      final builds = mounted.seen.length;

      schedule.fire();
      await _settle(mounted.owner);

      expect(mounted.seen.length, builds);
      mounted.owner.dispose();
    });

    test('dispose cancels the tick and a later tick is a no-op', () async {
      final probe = _FakeProbe();
      final schedule = _FakeSchedule();
      final mounted = await _mount(probe, schedule);
      final calls = probe.calls.length;

      mounted.owner.dispose();
      expect(schedule.cancels, 1);

      schedule.fire();
      await pumpEventQueue();
      expect(probe.calls.length, calls);
    });
  });

  group('pow-n6n.3 - the resolver follows presence', () {
    test('the choice CHANGES across down and recovered, and every winner '
        'converts to an armed NAME', () async {
      final probe = _FakeProbe(down: {'local'});
      final schedule = _FakeSchedule();
      final chosen = <AgentEnvironment?>[];
      final owner = TreeOwner();
      owner.mountRoot(
        InheritedSeed<EnvironmentRegistry>(
          value: _registry,
          child: InheritedSeed<SiteBinding>(
            value: _bound,
            child: AvailabilityAssets(
              probe: probe.call,
              schedule: schedule.start,
              child: InheritedSeed<_SpecPreference>(
                value: const _SpecPreference([_local, _frontier]),
                child: _Resolver(chosen),
              ),
            ),
          ),
        ),
      );
      owner.flush();
      await _settle(owner);
      expect(chosen.last, _frontier);

      probe.comeBack('local');
      schedule.fire();
      await _settle(owner);
      expect(chosen.last, _local);

      // The "no spawn fails" proof: every winner converts to an armed NAME the
      // transport can carry (`resolveAgentConfig`'s one conversion, A35(2)).
      for (final winner in chosen.whereType<AgentEnvironment>()) {
        expect(_registry.nameOf(winner), isNotEmpty);
      }
      owner.dispose();
    });
  });

  group('pow-n6n.3 - HarnessProvider arming', () {
    test(
      'unarmed, nothing is mounted and the effect read is unchanged',
      () async {
        final seen = <AvailableEnvironments>[];
        final owner = TreeOwner();
        owner.mountRoot(
          HarnessProvider(registry: _registry, child: _Watcher(seen)),
        );
        owner.flush();
        await _settle(owner);

        expect(seen.last, AvailableEnvironments.none);
        expect(
          _resolvedUnderHarness(registry: _registry),
          AvailableEnvironments.fromRegistry(_registry),
        );
        owner.dispose();
      },
    );

    test('armed, a down environment leaves the ambient set', () async {
      final probe = _FakeProbe(down: {'local'});
      final seen = <AvailableEnvironments>[];
      final owner = TreeOwner();
      owner.mountRoot(
        InheritedSeed<SiteBinding>(
          value: _bound,
          child: HarnessProvider(
            registry: _registry,
            probe: probe.call,
            child: _Watcher(seen),
          ),
        ),
      );
      owner.flush();
      await _settle(owner);

      expect(seen.last.contains(_frontier), isTrue);
      expect(seen.last.contains(_local), isFalse);
      owner.dispose();
    });

    test('ADR-0002 D5: a NESTED HarnessProvider inherits the arming and '
        'probes its OWN registry', () async {
      final probe = _FakeProbe(down: {'local'});
      final seen = <AvailableEnvironments>[];
      final owner = TreeOwner();
      owner.mountRoot(
        InheritedSeed<SiteBinding>(
          value: _bound,
          child: HarnessProvider(
            registry: _registry,
            probe: probe.call,
            child: HarnessProvider(
              // The seat's OWN arming rung (D5): a different registry, no
              // probe of its own.
              registry: const EnvironmentRegistry(custom: {'seat': _seat}),
              child: _Watcher(seen),
            ),
          ),
        ),
      );
      owner.flush();
      await _settle(owner);

      // The seat's subtree sees the SEAT registry probed, not the station's.
      expect(seen.last.contains(_seat), isTrue);
      expect(seen.last.contains(_frontier), isFalse);
      expect(probe.calls, contains('seat'));
      owner.dispose();
    });
  });

  // The AUTHORIZATION boundary is station configuration, so it is a VALUE in
  // the tree exactly like the registry and the config (ADR-0008: config =
  // values, impls = DI). Bead `pow-ed1c`.
  group('pow-ed1c - the station permission policy is a mounted VALUE', () {
    test('HarnessProvider mounts permission policy by value', () async {
      // UNCONFIGURED, the station grants nothing: the default is the
      // unavailable policy, mounted (not merely absent).
      final defaults = <AgentPermissionPolicy>[];
      final bare = TreeOwner();
      bare.mountRoot(
        HarnessProvider(registry: _registry, child: _PolicyWatcher(defaults)),
      );
      bare.flush();
      await _settle(bare);
      expect(defaults.last, const AgentPermissionPolicy.unavailable());
      expect(
        defaults.last.grantFor(AgentPermissionCapability.edit),
        AgentPermissionGrant.deny,
      );
      bare.dispose();

      // A station's explicit scope survives the mount unchanged, and a NESTED
      // provider shadows it by exact type — the seat's own boundary, the same
      // rung ADR-0002 D5 gives arming.
      const station = AgentPermissionPolicy.scoped(
        id: 'station',
        grants: <AgentPermissionCapability, AgentPermissionGrant>{
          AgentPermissionCapability.read: AgentPermissionGrant.allowAlways,
        },
      );
      final seen = <AgentPermissionPolicy>[];
      final owner = TreeOwner();
      owner.mountRoot(
        HarnessProvider(
          registry: _registry,
          permissionPolicy: station,
          child: HarnessProvider(
            registry: _registry,
            permissionPolicy: const AgentPermissionPolicy.scoped(
              id: 'seat',
              grants: <AgentPermissionCapability, AgentPermissionGrant>{
                AgentPermissionCapability.edit: AgentPermissionGrant.allowOnce,
              },
            ),
            child: _PolicyWatcher(seen),
          ),
        ),
      );
      owner.flush();
      await _settle(owner);
      expect(seen.last.id, 'seat');
      expect(
        seen.last.grantFor(AgentPermissionCapability.edit),
        AgentPermissionGrant.allowOnce,
      );
      // The station's own grant does NOT leak through the seat's shadow.
      expect(
        seen.last.grantFor(AgentPermissionCapability.read),
        AgentPermissionGrant.deny,
      );
      // And no builtin is trusted: reaching the old blanket posture takes an
      // explicit `trustedHeadless` value.
      expect(seen.last.isTrustedHeadless, isFalse);
      expect(station.isTrustedHeadless, isFalse);
      owner.dispose();
    });
  });

  group('pow-n6n.3 - ProcessEnvironmentProbe composition', () {
    ProcessEnvironmentProbe build({
      bool binary = true,
      bool reachable = true,
      Set<String> models = const {'qwen'},
    }) => ProcessEnvironmentProbe(
      binaryPresent: (_) async => binary,
      endpointReachable: (_) async => reachable,
      listModels: (_) async => models,
    );

    EnvironmentProbeRequest request(AgentEnvironment environment) =>
        EnvironmentProbeRequest(
          name: 'x',
          environment: environment,
          endpoint: environment.needsSiteEndpoint
              ? Uri.parse('http://127.0.0.1:8080')
              : null,
        );

    test('a missing binary is absent', () async {
      expect(await build(binary: false)(request(_frontier)), isFalse);
    });

    test('a provider-managed target needs only the binary', () async {
      expect(
        await build(reachable: false, models: const {})(request(_frontier)),
        isTrue,
      );
    });

    test('an endpoint-needing target needs reachability', () async {
      expect(await build(reachable: false)(request(_local)), isFalse);
    });

    test('an endpoint-needing target needs the pinned model LISTED', () async {
      expect(await build(models: const {'other'})(request(_local)), isFalse);
      expect(await build()(request(_local)), isTrue);
    });

    test('a command-less environment is absent', () async {
      expect(await build()(request(_broken)), isFalse);
    });
  });
}

/// Records what `resolveEnvironment<_SpecPreference>` sees on every build.
class _Resolver extends StatelessSeed {
  const _Resolver(this.chosen);
  final List<AgentEnvironment?> chosen;

  @override
  Seed build(TreeContext context) {
    context.dependOnInheritedSeedOfExactType<AvailableEnvironments>();
    chosen.add(resolveEnvironment<_SpecPreference>(context));
    return const _Leaf();
  }
}

/// The ambient presence set an unarmed [HarnessProvider] leaves in place, read
/// with the EFFECT verb (`availableEnvironmentsOf`, A35(6)).
AvailableEnvironments _resolvedUnderHarness({
  required EnvironmentRegistry registry,
}) {
  late AvailableEnvironments observed;
  final owner = TreeOwner();
  owner.mountRoot(
    HarnessProvider(
      registry: registry,
      child: _Effect((context) => observed = availableEnvironmentsOf(context)),
    ),
  );
  owner.flush();
  owner.dispose();
  return observed;
}

/// Runs [read] once at build (the effect-boundary read).
class _Effect extends StatelessSeed {
  const _Effect(this.read);
  final void Function(TreeContext) read;

  @override
  Seed build(TreeContext context) {
    read(context);
    return const _Leaf();
  }
}
