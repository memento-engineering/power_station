// The composed seat, mounted from a DOWNSTREAM consumer's import set:
// `the_grid` (grid_sdk / grid_engine / grid_runtime / genesis_tree) plus
// `power_station` (github_grid_assets / grid_assets). NO composing-station
// import appears here, and that absence is the whole claim this file makes.
//
// Pure + offline: every tree mounts in a bare `TreeOwner` under a
// `ProviderScope` (the availability registry `runGrid` mounts at the production
// root). The synthetic roots never exist on disk; the mount gate's predicate is
// only inspected, never invoked, so its default `ProcessBdRunner` never spawns.
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart' show ServiceBundle;
import 'package:grid_runtime/grid_runtime.dart' show PrOpener;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:test/test.dart';

/// The station-generated asset registry a seat resolves its own availability
/// from: one unconditional skill and one gated behind a package the seat's
/// facts may or may not carry.
const sdk.GridAssetDefinition _always = sdk.GridAssetDefinition(
  assetKey: sdk.AssetKey(
    package: 'fixture_assets',
    kind: sdk.AssetKind.skill,
    id: 'always',
  ),
  description: 'mounted at every seat',
  artifacts: <sdk.AssetArtifact>[
    sdk.AssetArtifact(
      target: sdk.AssetDeliveryTarget.claude,
      path: 'extension/station_overlay/claude/skills/always/SKILL.md',
    ),
  ],
);
const sdk.GridAssetDefinition _gatedAsset = sdk.GridAssetDefinition(
  assetKey: sdk.AssetKey(
    package: 'fixture_assets',
    kind: sdk.AssetKind.skill,
    id: 'gated',
  ),
  description: 'mounted only where grid_sdk is resolved',
  selector: sdk.RequiresPackage('grid_sdk'),
  artifacts: <sdk.AssetArtifact>[
    sdk.AssetArtifact(
      target: sdk.AssetDeliveryTarget.claude,
      path: 'extension/station_overlay/claude/skills/gated/SKILL.md',
    ),
  ],
);

final sdk.GridAssetRegistry _assetRegistry = sdk.GridAssetRegistry(
  <sdk.GridAssetPackDefinition>[
    sdk.GridAssetPackDefinition(
      package: 'fixture_assets',
      assets: const <sdk.GridAssetDefinition>[_always, _gatedAsset],
    ),
  ],
);

/// The facts observed for [names]; a name in [withGridSdk] additionally
/// resolves `grid_sdk`, which is what the gated asset's selector asks for.
SubstationFactsSnapshot _facts(
  Iterable<String> names, {
  Set<String> withGridSdk = const <String>{},
}) => SubstationFactsSnapshot(<SubstationKey, SubstationFacts>{
  for (final name in names)
    SubstationKey(name): SubstationFacts(
      root: '/home/me/$name',
      dartPackages: <String>{
        'fixture_assets',
        if (withGridSdk.contains(name)) 'grid_sdk',
      },
      packageRoots: const <String, String>{'fixture_assets': '/packs/fixture'},
    ),
});

/// A Fake observer — a seat never constructs one; the station injects it.
class _FakeFactsRepository implements SubstationFactsRepository {
  _FakeFactsRepository(this._current);

  SubstationFactsSnapshot _current;
  final StreamController<SubstationFactsSnapshot> _controller =
      StreamController<SubstationFactsSnapshot>.broadcast(sync: true);

  @override
  SubstationFactsSnapshot get current => _current;

  @override
  Stream<SubstationFactsSnapshot> get changes => _controller.stream;

  void emit(SubstationFactsSnapshot next) {
    if (next == _current) return;
    _current = next;
    _controller.add(next);
  }

  @override
  void refresh() {}

  @override
  void dispose() => unawaited(_controller.close());
}

/// Complete, standalone environments: the availability walk compares in the
/// `AgentEnvironment.flattened` normal form, so a preference entry must be its
/// own normal form to be PRESENT.
const AgentEnvironment _stationBuild = AgentEnvironment(
  command: 'claude',
  model: 'station-build',
  target: InferenceTarget.providerManaged,
);
const AgentEnvironment _seatBuild = AgentEnvironment(
  command: 'claude',
  model: 'seat-build',
  target: InferenceTarget.providerManaged,
);
const AgentEnvironment _stationSpec = AgentEnvironment(
  command: 'claude',
  model: 'station-spec',
  target: InferenceTarget.providerManaged,
);

const EnvironmentRegistry _registry = EnvironmentRegistry(
  custom: {
    'station-build': _stationBuild,
    'seat-build': _seatBuild,
    'station-spec': _stationSpec,
  },
);

const AgentArming _stationArming = AgentArming(
  build: BuildAgentEnvironment([_stationBuild]),
  spec: SpecAgentEnvironment([_stationSpec]),
);

/// Walks a mounted tree. `values` reads what the tree PROVIDES; `seeds` reads
/// what it COMPOSES.
///
/// Deliberately local rather than `grid_assets`' `mountedValuesOf`: that vended
/// walker takes an `sdk.GridDelegate` and owns its own `TreeOwner`, and these
/// tests mount a bare `Seed` and keep the owner. Same idea, different entry
/// point — no second walker abstraction is introduced.
class _Walk {
  _Walk(this.root);

  final Branch root;

  List<T> values<T extends Object>() {
    final found = <T>[];
    void walk(Branch b) {
      if (b is InheritedBranch<T>) found.add(b.value);
      b.visitChildren(walk);
    }

    walk(root);
    return found;
  }

  /// Every mounted seed of type [T] — the STRUCTURAL half. Needed because a
  /// leg that provides NOTHING offline (a `GitHubPrOpenerAssets` with no client
  /// mounts no `PrOpener`) is indistinguishable from an absent leg by value
  /// alone, and an absence assertion that cannot fail proves nothing.
  List<T> seeds<T extends Seed>() {
    final found = <T>[];
    void walk(Branch b) {
      final seed = b.seed;
      if (seed is T) found.add(seed);
      b.visitChildren(walk);
    }

    walk(root);
    return found;
  }
}

typedef _Mounted = ({TreeOwner owner, _Walk walk});

_Mounted _mount(Seed root) {
  final owner = TreeOwner();
  final branch = owner.mountRoot(root);
  owner.flush();
  return (owner: owner, walk: _Walk(branch));
}

/// The station tree a downstream consumer authors: a raw grid root over the
/// given seats, under the availability registry scope and the ONE facts
/// projection every seat resolves its own assets through.
Seed _station(
  List<Seed> seats, {
  AgentArming? arming,
  SubstationFactsRepository? facts,
}) => sdk.ProviderScope(
  child: SubstationFactsAssets(
    repository:
        facts ??
        _FakeFactsRepository(
          _facts(const <String>[
            'mine',
            'plain',
            'armed',
            'quiet',
            'ambient',
            'org',
          ]),
        ),
    child: InheritedSeed<EnvironmentRegistry>(
      value: _registry,
      child: arming == null
          ? sdk.RawAssetGrid(root: '/home/me/station', assets: seats)
          : TypedEnvironmentProvider(
              arming: arming,
              child: sdk.RawAssetGrid(root: '/home/me/station', assets: seats),
            ),
    ),
  ),
);

/// The EFFECTIVE seat bundle — the one `SubstationWork` resolves. Each seat
/// mounts two: `GitGridAssets`' fresh bundle and, innermost, the bundle
/// `MountEligibilityAssets` derives from it. Only the latter carries the mount
/// predicate, so it is the one every assertion about seat posture means.
ServiceBundle _gated(_Walk walk) =>
    walk.values<ServiceBundle>().singleWhere((b) => b.mountEligibility != null);

void main() {
  test('a downstream seat mounts offline: the projection resolves and the '
      'work subtree gets a git bundle behind the mount gate', () {
    final mounted = _mount(
      _station([
        SubstationSeed(
          name: 'mine',
          root: '../mine',
          prefix: 'mn',
          assetRegistry: _assetRegistry,
        ),
      ]),
    );
    addTearDown(mounted.owner.dispose);

    final seat = mounted.walk.values<MountedSubstationSeed>().single;
    expect(seat.scope.name, 'mine');
    expect(seat.scope.root, '/home/me/mine');
    expect(seat.scope.prefix, 'mn');
    expect(seat.githubPollingConfigured, isFalse);

    final gated = _gated(mounted.walk);
    expect(
      gated.sourceControl,
      isA<GitSourceControl>(),
      reason:
          'the gate DERIVES from GitGridAssets\' bundle — a gate that dropped '
          'sourceControl would break provisioning for every seat',
    );
    expect(
      gated.mountEligibility,
      isNotNull,
      reason: 'an unmounted MountEligibilityAssets is an INERT gate',
    );
  });

  test('selected generated definitions are mounted and excluded definitions '
      'are absent', () {
    // `withGridSdk` decides the gated asset's selector at THIS seat: `armed`
    // resolves grid_sdk, `plain` does not.
    final repository = _FakeFactsRepository(
      _facts(const <String>['plain', 'armed'], withGridSdk: const {'armed'}),
    );
    final plainBuilds = <int>[];
    final mounted = _mount(
      _station([
        SubstationSeed(
          name: 'plain',
          root: '../plain',
          assetRegistry: _assetRegistry,
        ),
        SubstationSeed(
          name: 'armed',
          root: '../armed',
          assetRegistry: _assetRegistry,
          assetRosterOverride: GridAssetRosterOverride(
            exclude: const [
              sdk.AssetKey(
                package: 'fixture_assets',
                kind: sdk.AssetKind.skill,
                id: 'always',
              ),
            ],
          ),
        ),
      ], facts: repository),
    );
    addTearDown(mounted.owner.dispose);

    List<sdk.GridAssetDefinition> mountedFixtureAssets() => mounted.walk
        .seeds<sdk.GridAssetDefinition>()
        .where((definition) => definition.assetKey.package == 'fixture_assets')
        .toList();

    expect(
      mounted.walk.values<MountedSubstationSeed>().map((s) => s.scope.name),
      unorderedEquals(<String>['plain', 'armed']),
    );
    // `plain` mounts the unconditional asset BY IDENTITY — the same `const`
    // value the registry holds — and not the gated one its facts do not select.
    expect(
      mountedFixtureAssets().where((d) => identical(d, _always)),
      hasLength(1),
      reason: 'only `plain` mounts it: `armed` EXCLUDED it by roster',
    );
    // `armed` resolves grid_sdk, so the gated asset IS mounted there.
    expect(
      mountedFixtureAssets().where((d) => identical(d, _gatedAsset)),
      hasLength(1),
      reason: 'the seat whose facts select it mounts the gated definition',
    );

    // A facts change at ONE seat rebuilds ONLY that seat: `plain` gains
    // grid_sdk and mounts the gated asset; `armed` is untouched.
    plainBuilds.add(
      mounted.walk
          .seeds<sdk.GridAssetDefinition>()
          .where((d) => d.assetKey.id == 'gated')
          .length,
    );
    repository.emit(
      _facts(
        const <String>['plain', 'armed'],
        withGridSdk: const {'armed', 'plain'},
      ),
    );
    mounted.owner.flush();
    plainBuilds.add(
      mounted.walk
          .seeds<sdk.GridAssetDefinition>()
          .where((d) => d.assetKey.id == 'gated')
          .length,
    );
    expect(
      plainBuilds,
      [1, 2],
      reason: 'the changed seat re-resolved and now mounts the gated asset',
    );
  });

  test('the seat arming rung SHADOWS the station on the type it arms and '
      'leaves every other type resolving through the station', () {
    final mounted = _mount(
      _station([
        SubstationSeed(
          name: 'plain',
          root: '../plain',
          assetRegistry: _assetRegistry,
        ),
        SubstationSeed(
          name: 'armed',
          root: '../armed',
          assetRegistry: _assetRegistry,
          arming: const AgentArming(build: BuildAgentEnvironment([_seatBuild])),
        ),
      ], arming: _stationArming),
    );
    addTearDown(mounted.owner.dispose);

    final seats = {
      for (final seat in mounted.walk.values<MountedSubstationSeed>())
        seat.scope.name: seat,
    };
    expect(seats.keys, unorderedEquals(<String>['plain', 'armed']));
    expect(seats['plain']!.environments?.build, _stationBuild);
    expect(seats['armed']!.environments?.build, _seatBuild);
    expect(
      seats['armed']!.environments?.spec,
      _stationSpec,
      reason: 'an UNARMED type keeps resolving through the station rung',
    );
  });

  test('OFFLINE POSTURE: a null githubPoll composes no reconciler leg and '
      'provides no reconciler values', () {
    final mounted = _mount(
      _station([
        SubstationSeed(
          name: 'quiet',
          root: '../quiet',
          assetRegistry: _assetRegistry,
        ),
      ]),
    );
    addTearDown(mounted.owner.dispose);

    expect(mounted.walk.seeds<GitHubReconcilerAssets>(), isEmpty);
    expect(mounted.walk.values<GitHubReconcilerRuntime>(), isEmpty);
    expect(mounted.walk.values<GitHubCursorStore>(), isEmpty);
    expect(mounted.walk.values<GitHubEventSink>(), isEmpty);
    expect(mounted.walk.values<GitHubAppClient>(), isEmpty);
  });

  test('OFFLINE POSTURE: a null app composes no App legs at all, so the '
      'ambient opener stands', () {
    final mounted = _mount(
      _station([
        SubstationSeed(
          name: 'ambient',
          root: '../ambient',
          assetRegistry: _assetRegistry,
        ),
      ]),
    );
    addTearDown(mounted.owner.dispose);

    expect(mounted.walk.values<SubstationAppIdentity>(), isEmpty);
    expect(mounted.walk.seeds<GitHubAppClientAssets>(), isEmpty);
    expect(mounted.walk.seeds<GitHubPrOpenerAssets>(), isEmpty);
    expect(
      mounted.walk.values<PrOpener>(),
      isEmpty,
      reason: 'this seat binds no opener; whatever is ambient above it stands',
    );
    expect(
      mounted.walk.values<MountedSubstationSeed>(),
      hasLength(1),
      reason:
          'the seat itself still mounts — the absences above are the App legs, '
          'not a tree that failed to build',
    );
  });

  test('an authored app identity is mounted as a VALUE with an int '
      'installation id, and DOES compose the App client leg', () {
    const identity = SubstationAppIdentity(
      appId: '101',
      installationId: 201,
      privateKeyVar: 'ORG_APP_KEY',
    );
    final mounted = _mount(
      _station([
        SubstationSeed(
          name: 'org',
          root: '../org',
          assetRegistry: _assetRegistry,
          app: identity,
          // The key variable is UNSET, so the loader resolves null and the
          // seat composes INERT: an absent key is a POSTURE, never an error.
          githubAppCredentialLoader: const GitHubAppCredentialLoader(
            environment: _noEnvironment,
          ),
        ),
      ]),
    );
    addTearDown(mounted.owner.dispose);

    final mountedIdentity = mounted.walk.values<SubstationAppIdentity>().single;
    expect(mountedIdentity, identity);
    expect(mountedIdentity.installationId, 201);
    expect(
      mounted.walk.seeds<GitHubAppClientAssets>(),
      hasLength(1),
      reason:
          'the paired positive: the previous test\'s isEmpty is falsifiable',
    );
  });

  test('SubstationAppIdentity is a VALUE: equality by value and nowhere to '
      'store a secret', () {
    const a = SubstationAppIdentity(
      appId: '1234',
      installationId: 99,
      privateKeyVar: 'MY_APP_KEY',
    );
    const b = SubstationAppIdentity(
      appId: '1234',
      installationId: 99,
      privateKeyVar: 'MY_APP_KEY',
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect('$a', contains('MY_APP_KEY'), reason: 'the NAME is config');
  });
}

/// An EMPTY process environment — the Fake that keeps the App-key read
/// hermetic against an operator's exported `GRID_GITHUB_APP_KEY_*` variables.
Map<String, String> _noEnvironment() => const <String, String>{};
