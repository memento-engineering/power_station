// The shared ASSET RESOLUTION fixture — one declared registry, one temp package
// root holding its exact declared artifacts, and the Fake repository that
// publishes facts for it (Fakes, not mocks).
//
// Every writer suite rides this instead of hand-building an overlay tree: the
// resolution is what both writers consume, so a fixture that produced files any
// other way could not prove they consume the SAME one.
import 'dart:async';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;

/// The fixture pack's vending package name.
const String kFixturePackage = 'fixture_assets';

/// The substation every fixture resolution answers for.
const SubstationKey kFixtureSubstation = SubstationKey('fixture');

/// A skill declared on BOTH harness legs at the vended paths the real pack uses.
GridAssetDefinition fixtureSkill(
  String id, {
  AssetSelector selector = const AlwaysApplies(),
  AssetAudience audience = AssetAudience.agent,
}) => GridAssetDefinition(
  assetKey: AssetKey(package: kFixturePackage, kind: AssetKind.skill, id: id),
  description: 'the $id fixture skill',
  audience: audience,
  selector: selector,
  artifacts: <AssetArtifact>[
    AssetArtifact(
      target: AssetDeliveryTarget.claude,
      path: 'extension/station_overlay/claude/skills/$id/SKILL.md',
    ),
    AssetArtifact(
      target: AssetDeliveryTarget.agents,
      path: 'extension/station_overlay/agents/skills/$id/SKILL.md',
    ),
  ],
);

/// A LOOSE operator-seat asset (`.claude/settings.json` shaped) — declared, so
/// the unscoped operator writer sees it and the scoped worktree writer does not.
GridAssetDefinition fixtureSettings(String id) => GridAssetDefinition(
  assetKey: AssetKey(
    package: kFixturePackage,
    kind: AssetKind.settings,
    id: id,
  ),
  description: 'the $id fixture settings',
  audience: AssetAudience.human,
  artifacts: const <AssetArtifact>[
    AssetArtifact(
      target: AssetDeliveryTarget.claude,
      path: 'extension/station_overlay/claude/settings.json',
    ),
  ],
);

/// An asset with NO materialized leg — the `mcp`-only rubric shape, which every
/// writer must ignore while the tree still mounts it.
GridAssetDefinition fixtureRubric(String id) => GridAssetDefinition(
  assetKey: AssetKey(package: kFixturePackage, kind: AssetKind.rubric, id: id),
  description: 'the $id fixture rubric',
  artifacts: <AssetArtifact>[
    AssetArtifact(
      target: AssetDeliveryTarget.mcp,
      path: 'extension/rubrics/$id.md',
    ),
  ],
);

/// A stampable (frontmatter-led) SKILL.md body.
String fixtureSkillBody(String name, [String body = 'body']) =>
    '---\nname: $name\n---\n$body\n';

/// A Fake [SubstationFactsRepository] — hand-published snapshots, no disk.
class FakeSubstationFactsRepository implements SubstationFactsRepository {
  FakeSubstationFactsRepository(this._current);

  SubstationFactsSnapshot _current;
  final StreamController<SubstationFactsSnapshot> _controller =
      StreamController<SubstationFactsSnapshot>.broadcast(sync: true);

  /// How many times [refresh] was asked for.
  int refreshes = 0;

  /// Whether [dispose] ran.
  bool disposed = false;

  @override
  SubstationFactsSnapshot get current => _current;

  @override
  Stream<SubstationFactsSnapshot> get changes => _controller.stream;

  @override
  void refresh() => refreshes++;

  /// Publishes [next] the way the real repository does: unequal only.
  void emit(SubstationFactsSnapshot next) {
    if (next == _current) return;
    _current = next;
    _controller.add(next);
  }

  @override
  void dispose() {
    disposed = true;
    unawaited(_controller.close());
  }
}

/// One declared fixture pack on disk: the registry, a package root holding
/// exactly its declared artifact files, and the facts that select them.
class TestAssetResolutionFixture {
  /// Creates the fixture under [root], writing each declared artifact's source
  /// file. [extraPackages] widen the observed package graph so a
  /// `RequiresPackage` selector can hold.
  TestAssetResolutionFixture({
    required Directory root,
    required List<GridAssetDefinition> assets,
    Map<String, String> bodies = const <String, String>{},
    Iterable<String> extraPackages = const <String>[],
    Iterable<String> existingPaths = const <String>[],
  }) : packageRoot = p.join(root.path, kFixturePackage),
       substationRoot = p.join(root.path, 'substation'),
       registry = GridAssetRegistry(<GridAssetPackDefinition>[
         GridAssetPackDefinition(package: kFixturePackage, assets: assets),
       ]) {
    for (final asset in assets) {
      for (final artifact in asset.artifacts) {
        final body =
            bodies[artifact.path] ?? fixtureSkillBody(asset.assetKey.id);
        File(p.join(packageRoot, artifact.path))
          ..createSync(recursive: true)
          ..writeAsStringSync(body);
      }
    }
    Directory(substationRoot).createSync(recursive: true);
    _facts = SubstationFacts(
      root: substationRoot,
      dartPackages: <String>{kFixturePackage, ...extraPackages},
      packageRoots: <String, String>{kFixturePackage: packageRoot},
      existingPaths: existingPaths,
    );
  }

  /// The vending package root the declared artifact paths resolve against.
  final String packageRoot;

  /// The substation root the facts were observed at.
  final String substationRoot;

  /// The fixture's registry — the value every consumer resolves against.
  final GridAssetRegistry registry;

  late SubstationFacts _facts;

  /// The facts this fixture publishes for [kFixtureSubstation].
  SubstationFacts get facts => _facts;

  /// The one-substation snapshot.
  SubstationFactsSnapshot get snapshot => SubstationFactsSnapshot(
    <SubstationKey, SubstationFacts>{kFixtureSubstation: _facts},
  );

  /// Re-observes the substation with [dartPackages]/[existingPaths] replaced —
  /// the shape of a real facts CHANGE (a package added, a path created).
  SubstationFactsSnapshot withFacts({
    Iterable<String>? dartPackages,
    Iterable<String>? existingPaths,
  }) {
    _facts = SubstationFacts(
      root: substationRoot,
      dartPackages: dartPackages ?? _facts.dartPackages,
      packageRoots: _facts.packageRoots,
      existingPaths: existingPaths ?? _facts.existingPaths,
    );
    return snapshot;
  }

  /// A repository already publishing [snapshot].
  FakeSubstationFactsRepository repository() =>
      FakeSubstationFactsRepository(snapshot);

  /// The resolution every consumer under test is handed — the PUBLIC resolver,
  /// never a fixture-local re-implementation.
  GridAssetResolution resolution({
    Map<String, String> renderArguments = const <String, String>{},
    GridAssetRosterOverride? rosterOverride,
  }) => resolveGridAssets(
    registry: registry,
    snapshot: snapshot,
    substation: kFixtureSubstation,
    renderArguments: renderArguments,
    rosterOverride: rosterOverride,
  );

  /// Writes an UNDECLARED file next to the declared sources — the stray no
  /// writer may ever install.
  File writeStraySource(String relativePath, String body) =>
      File(p.join(packageRoot, relativePath))
        ..createSync(recursive: true)
        ..writeAsStringSync(body);
}

/// The substation name every provision fixture mounts under.
const String kFixtureSubstationName = 'fixture';

/// This package's root, resolved the CWD-INDEPENDENT way (the loader's own
/// package-config resolution, whose root is `<packageRoot>/extension`).
String liveAssetPackageRoot() => p.dirname(PackagedAssetLoader().root);

/// The facts that select the LIVE `grid_assets` pack in full for
/// [kFixtureSubstation] — the vending package's real root, plus the package
/// graph its `RequiresPackage` selectors ask for.
SubstationFactsSnapshot liveStationFacts({
  String substation = kFixtureSubstationName,
  Iterable<String> packages = const <String>['grid_assets', 'grid_sdk'],
}) {
  final packageRoot = liveAssetPackageRoot();
  return SubstationFactsSnapshot(<SubstationKey, SubstationFacts>{
    SubstationKey(substation): SubstationFacts(
      root: packageRoot,
      dartPackages: packages,
      packageRoots: <String, String>{'grid_assets': packageRoot},
    ),
  });
}

/// The ambient values a provision/landing fixture mounts so the one resolution
/// can run at an effect edge: the observed facts and the substation identity.
Map<Type, Object> liveAssetContextValues({
  String substation = kFixtureSubstationName,
  Iterable<String> packages = const <String>['grid_assets', 'grid_sdk'],
}) => <Type, Object>{
  SubstationFactsSnapshot: liveStationFacts(
    substation: substation,
    packages: packages,
  ),
  SubstationScope: SubstationScope(
    name: substation,
    root: liveAssetPackageRoot(),
    prefix: substation,
  ),
};

/// A [SubstationFactsRepository] over ONE fixed snapshot — the harness shape of
/// an observer whose roots never change during a test.
class StaticSubstationFactsRepository implements SubstationFactsRepository {
  /// Publishes [current] and nothing else.
  const StaticSubstationFactsRepository(this.current);

  @override
  final SubstationFactsSnapshot current;

  @override
  Stream<SubstationFactsSnapshot> get changes =>
      const Stream<SubstationFactsSnapshot>.empty();

  @override
  void refresh() {}

  @override
  void dispose() {}
}
