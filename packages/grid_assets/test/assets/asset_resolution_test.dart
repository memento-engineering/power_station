// The ONE asset resolution (bead `pow-4peu`,
// `power_station#one-asset-resolution-defines-tree-and-writers`): the pure
// selector evaluation both writers and the tree consume, the repository that
// observes roots OUTSIDE build, and the aspect-scoped projection that keeps one
// substation's facts from rebuilding another's.
//
// Pure + offline: values, a bare `TreeOwner`, one temp dir for the repository's
// real package-config read. No CLI, no git, no network.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _package = 'fixture_assets';
const SubstationKey _alpha = SubstationKey('alpha');
const SubstationKey _beta = SubstationKey('beta');

/// Every selector variant, declared `const` exactly as a generated pack emits
/// them — so the identity assertion below means what it says.
const GridAssetDefinition _always = GridAssetDefinition(
  assetKey: AssetKey(package: _package, kind: AssetKind.skill, id: 'always'),
  description: 'unconditional',
  artifacts: <AssetArtifact>[
    AssetArtifact(
      target: AssetDeliveryTarget.claude,
      path: 'extension/station_overlay/claude/skills/always/SKILL.md',
    ),
    AssetArtifact(
      target: AssetDeliveryTarget.agents,
      path: 'extension/station_overlay/agents/skills/always/SKILL.md',
    ),
  ],
);
const GridAssetDefinition _needsPackage = GridAssetDefinition(
  assetKey: AssetKey(package: _package, kind: AssetKind.skill, id: 'packaged'),
  description: 'needs grid_sdk',
  selector: RequiresPackage('grid_sdk'),
  artifacts: <AssetArtifact>[
    AssetArtifact(
      target: AssetDeliveryTarget.claude,
      path: 'extension/station_overlay/claude/skills/packaged/SKILL.md',
    ),
  ],
);
const GridAssetDefinition _needsPath = GridAssetDefinition(
  assetKey: AssetKey(package: _package, kind: AssetKind.skill, id: 'pathed'),
  description: 'needs docs/decisions',
  selector: RequiresPath('docs/decisions'),
  artifacts: <AssetArtifact>[
    AssetArtifact(
      target: AssetDeliveryTarget.claude,
      path: 'extension/station_overlay/claude/skills/pathed/SKILL.md',
    ),
  ],
);
const GridAssetDefinition _needsAll = GridAssetDefinition(
  assetKey: AssetKey(package: _package, kind: AssetKind.skill, id: 'both'),
  description: 'needs both',
  selector: RequiresAll(<AssetSelector>[
    RequiresPackage('grid_sdk'),
    RequiresPath('docs/decisions'),
  ]),
  artifacts: <AssetArtifact>[
    AssetArtifact(
      target: AssetDeliveryTarget.claude,
      path: 'extension/station_overlay/claude/skills/both/SKILL.md',
    ),
  ],
);
const GridAssetDefinition _rubric = GridAssetDefinition(
  assetKey: AssetKey(package: _package, kind: AssetKind.rubric, id: 'graded'),
  description: 'mcp-only, materialized nowhere',
  artifacts: <AssetArtifact>[
    AssetArtifact(
      target: AssetDeliveryTarget.mcp,
      path: 'extension/rubrics/graded.md',
    ),
  ],
);
const GridAssetDefinition _stationOnly = GridAssetDefinition(
  assetKey: AssetKey(package: _package, kind: AssetKind.prompt, id: 'inline'),
  description: 'station-only, materialized nowhere',
  artifacts: <AssetArtifact>[
    AssetArtifact(
      target: AssetDeliveryTarget.station,
      path: 'extension/prompts/inline.md',
    ),
  ],
);

GridAssetRegistry _registry([
  List<GridAssetDefinition> assets = const <GridAssetDefinition>[
    _always,
    _needsPackage,
    _needsPath,
    _needsAll,
    _rubric,
    _stationOnly,
  ],
]) => GridAssetRegistry(<GridAssetPackDefinition>[
  GridAssetPackDefinition(package: _package, assets: assets),
]);

SubstationFactsSnapshot _snapshot({
  SubstationKey key = _alpha,
  String root = '/substation/alpha',
  Iterable<String> packages = const <String>[_package],
  Iterable<String> paths = const <String>[],
  String packageRoot = '/packages/fixture_assets',
}) => SubstationFactsSnapshot(<SubstationKey, SubstationFacts>{
  key: SubstationFacts(
    root: root,
    dartPackages: packages,
    packageRoots: <String, String>{_package: packageRoot},
    existingPaths: paths,
  ),
});

/// Ends every probe tree.
class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const <Seed>[]);
}

/// WATCHES one substation aspect and records the facts it saw, per build.
class _AspectWatcher extends StatelessSeed {
  const _AspectWatcher(this.substation, this.seen);

  final SubstationKey substation;
  final List<SubstationFacts?> seen;

  @override
  Seed build(TreeContext context) {
    final snapshot = context
        .dependOnInheritedSeedOfExactType<SubstationFactsSnapshot>(
          aspect: substation,
        );
    seen.add(snapshot?.factsFor(substation));
    return const _Leaf();
  }
}

void main() {
  group('resolveGridAssets — the ONE selector authority', () {
    test('pure resolution evaluates every selector and maps declared artifacts '
        'only', () {
      final root = Directory.systemTemp.createTempSync('asset-resolution-');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final packageRoot = p.join(root.path, 'fixture_assets');
      // An UNDECLARED file adjacent to a selected source: a source WALK would
      // install it; a resolution cannot see it.
      File(
          p.join(
            packageRoot,
            'extension',
            'station_overlay',
            'claude',
            'skills',
            'always',
            'STRAY.md',
          ),
        )
        ..createSync(recursive: true)
        ..writeAsStringSync('---\nname: stray\n---\nundeclared\n');

      GridAssetResolution resolve() => resolveGridAssets(
        registry: _registry(),
        snapshot: _snapshot(
          packages: const <String>[_package, 'grid_sdk'],
          paths: const <String>['docs/decisions'],
          packageRoot: packageRoot,
        ),
        substation: _alpha,
      );

      final first = resolve();
      final second = resolve();

      // DETERMINISTIC: same values, same order, twice.
      expect(
        first.definitions.map((d) => d.assetKey.canonical),
        second.definitions.map((d) => d.assetKey.canonical),
      );
      expect(first.relativePaths, second.relativePaths);
      expect(
        first.artifacts.map((a) => a.sourcePath),
        second.artifacts.map((a) => a.sourcePath),
      );
      // Every selector variant held, in REGISTRY order, and the two
      // never-materialized legs still MOUNT.
      expect(first.definitions.map((d) => d.assetKey.id), [
        'always',
        'packaged',
        'pathed',
        'both',
        'graded',
        'inline',
      ]);
      expect(
        identical(first.definitions.first, _always),
        isTrue,
        reason: 'the ORIGINAL generated const value is what mounts',
      );
      expect(first.relativePaths, [
        p.join('.claude', 'skills', 'always', 'SKILL.md'),
        p.join('.agents', 'skills', 'always', 'SKILL.md'),
        p.join('.claude', 'skills', 'packaged', 'SKILL.md'),
        p.join('.claude', 'skills', 'pathed', 'SKILL.md'),
        p.join('.claude', 'skills', 'both', 'SKILL.md'),
      ]);
      expect(
        first.artifacts.first.sourcePath,
        p.join(
          packageRoot,
          'extension',
          'station_overlay',
          'claude',
          'skills',
          'always',
          'SKILL.md',
        ),
      );
      expect(
        first.relativePaths.where((path) => path.contains('STRAY')),
        isEmpty,
        reason: 'an undeclared file is not an asset — nothing can install it',
      );
      expect(
        first.artifacts
            .map((a) => a.sourcePath)
            .where((path) => path.contains('STRAY')),
        isEmpty,
      );

      // A FACTS change re-decides: no package, no path ⇒ only the
      // unconditional asset and the two unmaterialized legs survive.
      final narrowed = resolveGridAssets(
        registry: _registry(),
        snapshot: _snapshot(packageRoot: packageRoot),
        substation: _alpha,
      );
      expect(narrowed.definitions.map((d) => d.assetKey.id), [
        'always',
        'graded',
        'inline',
      ]);
      expect(narrowed.relativePaths, [
        p.join('.claude', 'skills', 'always', 'SKILL.md'),
        p.join('.agents', 'skills', 'always', 'SKILL.md'),
      ]);

      // The worktree SCOPE is a projection of the same list.
      expect(
        first
            .artifactsUnder(kWorktreeOverlaySubtrees)
            .map((a) => a.relativePath),
        first.relativePaths,
      );
      expect(
        first
            .artifactsUnder(const <String>[kAgentsSkillsSubtree])
            .map((a) => a.relativePath),
        [p.join('.agents', 'skills', 'always', 'SKILL.md')],
      );
    });

    test('roster include and exclude precedence is validated', () {
      const excluded = AssetKey(
        package: _package,
        kind: AssetKind.skill,
        id: 'always',
      );
      const forced = AssetKey(
        package: _package,
        kind: AssetKind.skill,
        id: 'packaged',
      );

      // An explicit include overrides a selector that does NOT hold.
      final included = resolveGridAssets(
        registry: _registry(),
        snapshot: _snapshot(),
        substation: _alpha,
        rosterOverride: GridAssetRosterOverride(include: const [forced]),
      );
      expect(included.definitions.map((d) => d.assetKey.id), [
        'always',
        'packaged',
        'graded',
        'inline',
      ]);

      // Exclude overrides a selector that DOES hold.
      final excludedResult = resolveGridAssets(
        registry: _registry(),
        snapshot: _snapshot(),
        substation: _alpha,
        rosterOverride: GridAssetRosterOverride(exclude: const [excluded]),
      );
      expect(excludedResult.definitions.map((d) => d.assetKey.id), [
        'graded',
        'inline',
      ]);
      expect(excludedResult.artifacts, isEmpty);

      // Both lists at once, on different keys, resolve independently.
      final both = resolveGridAssets(
        registry: _registry(),
        snapshot: _snapshot(),
        substation: _alpha,
        rosterOverride: GridAssetRosterOverride(
          include: const [forced],
          exclude: const [excluded],
        ),
      );
      expect(both.definitions.map((d) => d.assetKey.id), [
        'packaged',
        'graded',
        'inline',
      ]);

      // One key in BOTH lists is authorial confusion — refused, never ranked.
      expect(
        () => GridAssetRosterOverride(
          include: const [forced],
          exclude: const [forced],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => '${error.message}',
            'message',
            contains('both included and excluded'),
          ),
        ),
      );
    });

    test('malformed, colliding, and unknown inputs refuse loudly', () {
      // No facts for the substation asked about.
      expect(
        () => resolveGridAssets(
          registry: _registry(),
          snapshot: _snapshot(),
          substation: _beta,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('no facts for substation beta'),
          ),
        ),
      );

      // A roster key the registry does not vend.
      expect(
        () => resolveGridAssets(
          registry: _registry(),
          snapshot: _snapshot(),
          substation: _alpha,
          rosterOverride: GridAssetRosterOverride(
            exclude: const [
              AssetKey(
                package: 'other_pack',
                kind: AssetKind.skill,
                id: 'ghost',
              ),
            ],
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => '${error.message}',
            'message',
            contains('outside the registry'),
          ),
        ),
      );

      // A selected asset whose vending package has no observed root: LOUD,
      // never silently dropped from the install.
      expect(
        () => resolveGridAssets(
          registry: _registry(),
          snapshot: SubstationFactsSnapshot(<SubstationKey, SubstationFacts>{
            _alpha: SubstationFacts(root: '/substation/alpha'),
          }),
          substation: _alpha,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(contains('no package root'), contains('fixture_assets')),
          ),
        ),
      );

      // A materialized artifact declared OUTSIDE its leg's vended head.
      const malformed = GridAssetDefinition(
        assetKey: AssetKey(
          package: _package,
          kind: AssetKind.skill,
          id: 'loose',
        ),
        description: 'declared outside the claude head',
        artifacts: <AssetArtifact>[
          AssetArtifact(
            target: AssetDeliveryTarget.claude,
            path: 'extension/elsewhere/SKILL.md',
          ),
        ],
      );
      expect(
        () => resolveGridAssets(
          registry: _registry(const <GridAssetDefinition>[malformed]),
          snapshot: _snapshot(),
          substation: _alpha,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('claude artifact is outside'),
          ),
        ),
      );

      // Two selected artifacts landing on ONE target path.
      const collidingA = GridAssetDefinition(
        assetKey: AssetKey(package: _package, kind: AssetKind.skill, id: 'one'),
        description: 'first claimant',
        artifacts: <AssetArtifact>[
          AssetArtifact(
            target: AssetDeliveryTarget.claude,
            path: 'extension/station_overlay/claude/skills/dup/SKILL.md',
          ),
        ],
      );
      const collidingB = GridAssetDefinition(
        assetKey: AssetKey(package: _package, kind: AssetKind.skill, id: 'two'),
        description: 'second claimant',
        artifacts: <AssetArtifact>[
          AssetArtifact(
            target: AssetDeliveryTarget.claude,
            path: 'extension/station_overlay/claude/skills/dup/SKILL.md',
          ),
        ],
      );
      expect(
        () => resolveGridAssets(
          registry: _registry(const <GridAssetDefinition>[
            collidingA,
            collidingB,
          ]),
          snapshot: _snapshot(),
          substation: _alpha,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('collide at'),
          ),
        ),
      );
    });
  });

  group('the repository observes, the seed projects', () {
    test('repository projection notifies only the changed stable substation '
        'aspect', () async {
      final temp = Directory.systemTemp.createTempSync('facts-repo-');
      addTearDown(() {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final alphaRoot = Directory(p.join(temp.path, 'alpha'))
        ..createSync(recursive: true);
      final betaRoot = Directory(p.join(temp.path, 'beta'))
        ..createSync(recursive: true);
      final packageRoot = Directory(p.join(temp.path, 'fixture_assets'))
        ..createSync(recursive: true);
      File(p.join(alphaRoot.path, '.dart_tool', 'package_config.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '{"configVersion":2,"packages":['
          '{"name":"$_package","rootUri":"${packageRoot.uri}",'
          '"packageUri":"lib/"}]}',
        );

      final repository = FileSystemSubstationFactsRepository(
        roots: <SubstationKey, String>{
          _alpha: alphaRoot.path,
          _beta: betaRoot.path,
        },
        registry: _registry(),
      );
      addTearDown(repository.dispose);
      final emitted = <SubstationFactsSnapshot>[];
      repository.changes.listen(emitted.add);

      // The FIRST observation is available before any refresh, and it read the
      // real package config (a root with none is an EMPTY graph, not a crash).
      expect(
        repository.current.factsFor(_alpha)!.dartPackages,
        contains(_package),
      );
      expect(
        repository.current.factsFor(_alpha)!.packageRoots[_package],
        p.normalize(packageRoot.path),
      );
      expect(repository.current.factsFor(_beta)!.dartPackages, isEmpty);
      expect(
        repository.current.factsFor(_alpha)!.existingPaths,
        isEmpty,
        reason: 'the registry-declared path does not exist yet',
      );

      // An unchanged rescan emits NOTHING (value equality, not identity).
      repository.refresh();
      expect(emitted, isEmpty);

      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final alphaSeen = <SubstationFacts?>[];
      final betaSeen = <SubstationFacts?>[];
      owner.mountRoot(
        SubstationFactsAssets(
          repository: repository,
          child: Nest(
            children: const <SingleChildSeed>[],
            child: _Fork(
              left: _AspectWatcher(_alpha, alphaSeen),
              right: _AspectWatcher(_beta, betaSeen),
            ),
          ),
        ),
      );
      owner.flush();
      expect(alphaSeen, hasLength(1));
      expect(betaSeen, hasLength(1));

      // A REAL change under alpha's root only.
      Directory(
        p.join(alphaRoot.path, 'docs', 'decisions'),
      ).createSync(recursive: true);
      repository.refresh();
      owner.flush();

      expect(emitted, hasLength(1));
      expect(
        emitted.single.factsFor(_alpha)!.existingPaths,
        contains('docs/decisions'),
      );
      expect(
        alphaSeen,
        hasLength(2),
        reason: 'the substation whose facts changed rebuilt',
      );
      expect(
        betaSeen,
        hasLength(1),
        reason: 'the OTHER substation watches its own stable aspect only',
      );
      expect(
        alphaSeen.last!.existingPaths,
        contains('docs/decisions'),
        reason: 'the rebuild saw the NEW facts, never a cached snapshot',
      );

      // Disposal closes the repository's own stream; a later refresh publishes
      // to nobody rather than throwing into a torn-down tree.
      repository.dispose();
      expect(emitted, hasLength(1));
    });
  });
}

/// A two-child fork so both aspect watchers mount under ONE projection.
class _Fork extends MultiChildSeed {
  _Fork({required Seed left, required Seed right})
    : super(children: <Seed>[left, right]);
}
