/// ONE asset RESOLUTION — the single selector authority behind mounted
/// availability and both materialized views (bead `pow-4peu`,
/// `power_station#one-asset-resolution-defines-tree-and-writers`).
///
/// The station-generated [GridAssetRegistry] describes POTENTIAL availability:
/// every asset every composed pack vends. What is ACTUALLY available at one
/// substation is the subset whose declared [AssetSelector] holds against that
/// substation's real root — and that same subset is what the checkout writer,
/// the worktree writer and the landing guard must see. Three answers to one
/// question is how they drifted; [resolveGridAssets] is the one answer.
///
/// **Pure in, pure out.** [resolveGridAssets] performs NO I/O: it evaluates the
/// declared selectors against an immutable [SubstationFacts] value, returns the
/// ORIGINAL generated [GridAssetDefinition] instances (so one `const` value is
/// both the registry member and the mounted Seed — `the_grid#asset-definitions-
/// are-const-collections-are-validated`), and maps each declared Claude/agents
/// [AssetArtifact] to the EXACT source file and target path a writer copies. No
/// writer walks a source tree any more; nothing is discovered at write time.
///
/// **Roots are observed OUTSIDE build** (the D-H doctrine, ADR-0008 D3 /
/// `power_station#a8-bead-tg-kx1-the-d-h-doctrine-rides-the-coding-agent-worki`).
/// [SubstationFactsRepository] is the ONE observer: it reads each configured
/// substation root's package config and the finite set of `RequiresPath` inputs
/// the registry declares, and emits immutable [SubstationFactsSnapshot] values.
/// [SubstationFactsAssets] subscribes to it and RE-PROJECTS each snapshot into
/// the tree as an aspect-scoped [SubstationFactsModelSeed]; it exposes no
/// synchronous state accessor. A substation build WATCHES its own stable
/// [SubstationKey] aspect (`power_station#adr-0006-typed-environment-lookup-
/// selects-by-value` — same-class lookups that differ by DATA select by value),
/// so one substation's changed facts rebuild only that substation.
library;

import 'dart:async';
import 'dart:io';

import 'package:grid_sdk/grid_sdk.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

/// The vended-tree prefix a [AssetDeliveryTarget.claude] artifact is declared
/// under.
const String _kClaudeArtifactHead = 'extension/station_overlay/claude';

/// The vended-tree prefix an [AssetDeliveryTarget.agents] artifact is declared
/// under.
const String _kAgentsArtifactHead = 'extension/station_overlay/agents';

/// Where Claude Code reads a repo's assets — the head every `claude` leg
/// materializes under.
const String kClaudeTargetHead = '.claude';

/// Where the harness-neutral agents layout reads a repo's assets — the head
/// every `agents` leg materializes under.
const String kAgentsTargetHead = '.agents';

/// ONE substation's stable identity — its tree [Key] AND the aspect a
/// substation build subscribes to on [SubstationFactsModelSeed].
///
/// Extends the substrate's [Key] the way `AssetKey` does: one value is both the
/// logical identity and the reconciliation identity, and it stays `const`.
final class SubstationKey extends Key {
  /// Identifies the substation called [name].
  const SubstationKey(this.name) : super.empty();

  /// The substation's name — its tree identity.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is SubstationKey &&
      other.runtimeType == runtimeType &&
      other.name == name;

  @override
  int get hashCode => Object.hash(runtimeType, name);

  @override
  String toString() => 'SubstationKey($name)';
}

/// The FILESYSTEM and PACKAGE-GRAPH observations for ONE substation root — an
/// immutable value, observed outside build and never re-derived inside one.
final class SubstationFacts {
  /// Records the observations for [root]: the [dartPackages] its package graph
  /// resolves, each package's absolute root ([packageRoots]), and which of the
  /// registry's declared relative paths EXIST ([existingPaths]).
  factory SubstationFacts({
    required String root,
    Iterable<String> dartPackages = const <String>[],
    Map<String, String> packageRoots = const <String, String>{},
    Iterable<String> existingPaths = const <String>[],
  }) => SubstationFacts._(
    p.normalize(p.absolute(root)),
    Set<String>.unmodifiable(dartPackages),
    Map<String, String>.unmodifiable(<String, String>{
      for (final entry in packageRoots.entries)
        entry.key: p.normalize(p.absolute(entry.value)),
    }),
    Set<String>.unmodifiable(existingPaths.map(p.normalize)),
  );

  const SubstationFacts._(
    this.root,
    this.dartPackages,
    this.packageRoots,
    this.existingPaths,
  );

  /// The substation's absolute, normalized root.
  final String root;

  /// Every package name the root's package graph resolves.
  final Set<String> dartPackages;

  /// Package name → that package's absolute root (where its artifacts live).
  final Map<String, String> packageRoots;

  /// The registry-declared relative paths that EXIST under [root].
  final Set<String> existingPaths;

  @override
  bool operator ==(Object other) =>
      other is SubstationFacts &&
      other.root == root &&
      _sameSet(other.dartPackages, dartPackages) &&
      _sameMap(other.packageRoots, packageRoots) &&
      _sameSet(other.existingPaths, existingPaths);

  @override
  int get hashCode => Object.hash(
    root,
    Object.hashAllUnordered(dartPackages),
    Object.hashAllUnordered(
      packageRoots.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    Object.hashAllUnordered(existingPaths),
  );

  @override
  String toString() => 'SubstationFacts($root)';
}

/// ONE immutable emission covering EVERY configured substation — what the
/// repository publishes and the tree projects.
final class SubstationFactsSnapshot {
  /// Collects [facts], keyed by substation.
  factory SubstationFactsSnapshot(Map<SubstationKey, SubstationFacts> facts) =>
      SubstationFactsSnapshot._(
        Map<SubstationKey, SubstationFacts>.unmodifiable(facts),
      );

  const SubstationFactsSnapshot._(this._facts);

  final Map<SubstationKey, SubstationFacts> _facts;

  /// The facts observed for [key], or null when it is not configured.
  SubstationFacts? factsFor(SubstationKey key) => _facts[key];

  /// Every configured substation.
  Set<SubstationKey> get keys => Set<SubstationKey>.unmodifiable(_facts.keys);

  @override
  bool operator ==(Object other) =>
      other is SubstationFactsSnapshot && _sameMap(other._facts, _facts);

  @override
  int get hashCode => Object.hashAllUnordered(
    _facts.entries.map((entry) => Object.hash(entry.key, entry.value)),
  );

  @override
  String toString() =>
      'SubstationFactsSnapshot(${_facts.keys.map((key) => key.name).join(', ')})';
}

/// A station's EXPLICIT exceptions to what the selectors decide — composition
/// values, validated at construction.
///
/// [include] force-selects an asset whose selector does not hold; [exclude]
/// withholds one that does. Exclude wins over a selector AND over an include —
/// but naming one key in both is authorial confusion, so it REFUSES rather than
/// resolving a precedence nobody meant (guards LOUD or GONE).
final class GridAssetRosterOverride {
  /// Creates the override, refusing a key named in both lists.
  factory GridAssetRosterOverride({
    Iterable<AssetKey> include = const <AssetKey>[],
    Iterable<AssetKey> exclude = const <AssetKey>[],
  }) {
    final includes = Set<AssetKey>.unmodifiable(include);
    final excludes = Set<AssetKey>.unmodifiable(exclude);
    final overlap = includes.intersection(excludes);
    if (overlap.isNotEmpty) {
      throw ArgumentError(
        'roster keys cannot be both included and excluded: '
        '${overlap.map((key) => key.canonical).join(', ')}',
      );
    }
    return GridAssetRosterOverride._(includes, excludes);
  }

  const GridAssetRosterOverride._(this.include, this.exclude);

  /// Assets selected regardless of their declared selector.
  final Set<AssetKey> include;

  /// Assets withheld regardless of their declared selector.
  final Set<AssetKey> exclude;

  /// Every key this override names.
  Set<AssetKey> get keys =>
      Set<AssetKey>.unmodifiable(<AssetKey>{...include, ...exclude});
}

/// ONE selected file: the definition that vends it, the declared leg, and the
/// EXACT source and target paths. No discovery remains for a writer to do.
final class ResolvedGridAssetArtifact {
  /// Records the resolution of [artifact] under [definition].
  const ResolvedGridAssetArtifact({
    required this.definition,
    required this.artifact,
    required this.packageRoot,
    required this.sourcePath,
    required this.relativePath,
  });

  /// The generated definition this leg belongs to.
  final GridAssetDefinition definition;

  /// The declared delivery leg.
  final AssetArtifact artifact;

  /// The vending package's absolute root.
  final String packageRoot;

  /// The absolute path of the file to read.
  final String sourcePath;

  /// The path to write, relative to a target ROOT (`.claude/…`, `.agents/…`).
  final String relativePath;
}

/// The COMPLETE immutable answer: what is available at one substation, and the
/// exact files both writers act on.
final class GridAssetResolution {
  /// Collects the resolution for [substation].
  GridAssetResolution({
    required this.substation,
    required List<GridAssetDefinition> definitions,
    required List<ResolvedGridAssetArtifact> artifacts,
    required Map<String, String> renderArguments,
  }) : definitions = List<GridAssetDefinition>.unmodifiable(definitions),
       artifacts = List<ResolvedGridAssetArtifact>.unmodifiable(artifacts),
       renderArguments = Map<String, String>.unmodifiable(renderArguments);

  /// The substation this resolution answers for.
  final SubstationKey substation;

  /// The SELECTED generated definitions, in registry order — the Seeds a
  /// substation mounts, by identity.
  final List<GridAssetDefinition> definitions;

  /// Every selected Claude/agents artifact, in registry-then-declaration order.
  final List<ResolvedGridAssetArtifact> artifacts;

  /// The `{{hole}}` bindings a writer renders each file against.
  final Map<String, String> renderArguments;

  /// Every selected target path, in resolution order.
  List<String> get relativePaths => List<String>.unmodifiable(
    artifacts.map((artifact) => artifact.relativePath),
  );

  /// The selected artifacts that land under [subtrees] (root-relative
  /// prefixes); an EMPTY scope means every artifact — the operator install is
  /// unscoped, the worktree leg takes `kWorktreeOverlaySubtrees`.
  List<ResolvedGridAssetArtifact> artifactsUnder(Iterable<String> subtrees) {
    final scope = subtrees.map(p.normalize).toList(growable: false);
    if (scope.isEmpty) return artifacts;
    return List<ResolvedGridAssetArtifact>.unmodifiable(
      artifacts.where(
        (artifact) => scope.any(
          (root) =>
              artifact.relativePath == root ||
              p.isWithin(root, artifact.relativePath),
        ),
      ),
    );
  }
}

/// Resolves ACTUAL availability — and both writers' exact file sets — from the
/// generated [registry], the observed [snapshot], and this station's
/// composition values. PURE: no filesystem, no package graph, no process.
///
/// Registry order is preserved. An explicit [GridAssetRosterOverride.include]
/// overrides a selector that does not hold; [GridAssetRosterOverride.exclude]
/// overrides both. `mcp` and `station` delivery legs are not materialized
/// anywhere, so they contribute no artifact.
///
/// THROWS (LOUD, by doctrine) when: [substation] has no facts in [snapshot]; the
/// roster override names an asset outside the registry; a selected asset's
/// vending package has no root in the facts (its files could not be read, and
/// silently dropping it is exactly the drift this resolution exists to end); a
/// materialized artifact is declared outside its delivery leg's vended head; or
/// two selected artifacts collide on one target path.
GridAssetResolution resolveGridAssets({
  required GridAssetRegistry registry,
  required SubstationFactsSnapshot snapshot,
  required SubstationKey substation,
  Map<String, String> renderArguments = const <String, String>{},
  GridAssetRosterOverride? rosterOverride,
}) {
  final facts = snapshot.factsFor(substation);
  if (facts == null) {
    throw StateError('no facts for substation ${substation.name}');
  }
  final override = rosterOverride ?? GridAssetRosterOverride();
  final known = registry.assets.map((asset) => asset.assetKey).toSet();
  final unknown = override.keys.difference(known);
  if (unknown.isNotEmpty) {
    throw ArgumentError(
      'roster override names assets outside the registry: '
      '${unknown.map((key) => key.canonical).join(', ')}',
    );
  }

  final definitions = <GridAssetDefinition>[];
  final artifacts = <ResolvedGridAssetArtifact>[];
  final targets = <String>{};
  for (final definition in registry.assets) {
    final key = definition.assetKey;
    final selected =
        !override.exclude.contains(key) &&
        (override.include.contains(key) ||
            _selectorApplies(definition.selector, facts));
    if (!selected) continue;
    definitions.add(definition);
    for (final artifact in definition.artifacts) {
      final target = _materializedTarget(artifact);
      if (target == null) continue;
      final packageRoot = facts.packageRoots[key.package];
      if (packageRoot == null) {
        throw StateError(
          'no package root for selected asset ${key.canonical} — the '
          "substation's package graph does not resolve ${key.package}",
        );
      }
      if (!targets.add(target)) {
        throw StateError('selected artifacts collide at $target');
      }
      artifacts.add(
        ResolvedGridAssetArtifact(
          definition: definition,
          artifact: artifact,
          packageRoot: packageRoot,
          sourcePath: p.join(packageRoot, p.normalize(artifact.path)),
          relativePath: target,
        ),
      );
    }
  }
  return GridAssetResolution(
    substation: substation,
    definitions: definitions,
    artifacts: artifacts,
    renderArguments: renderArguments,
  );
}

/// Whether [selector] holds against [facts] — the ONE evaluator, exhaustive
/// over the SDK's sealed selector union.
bool _selectorApplies(AssetSelector selector, SubstationFacts facts) =>
    switch (selector) {
      AlwaysApplies() => true,
      RequiresPackage(:final packageName) => facts.dartPackages.contains(
        packageName,
      ),
      RequiresPath(:final relativePath) => facts.existingPaths.contains(
        p.normalize(relativePath),
      ),
      RequiresAll(:final selectors) => selectors.every(
        (part) => _selectorApplies(part, facts),
      ),
    };

/// The root-relative target [artifact] materializes to, or null when its leg is
/// never written into a repository (`mcp`, `station`).
String? _materializedTarget(AssetArtifact artifact) {
  final (sourceHead, targetHead) = switch (artifact.target) {
    AssetDeliveryTarget.claude => (_kClaudeArtifactHead, kClaudeTargetHead),
    AssetDeliveryTarget.agents => (_kAgentsArtifactHead, kAgentsTargetHead),
    AssetDeliveryTarget.mcp || AssetDeliveryTarget.station => (null, null),
  };
  if (sourceHead == null || targetHead == null) return null;
  final source = p.normalize(artifact.path);
  if (!p.isWithin(sourceHead, source)) {
    throw StateError(
      '${artifact.target.name} artifact is outside $sourceHead: $source',
    );
  }
  return p.join(targetHead, p.relative(source, from: sourceHead));
}

/// The SINGLE source of root observations — injected, never constructed inside
/// a build (config = VALUES in the tree, impls = DI).
abstract interface class SubstationFactsRepository {
  /// The latest emitted snapshot.
  SubstationFactsSnapshot get current;

  /// Every snapshot after [current] — emitted only when the facts CHANGED.
  Stream<SubstationFactsSnapshot> get changes;

  /// Re-observes every configured root. The ONLY rescan entry point.
  void refresh();

  /// Releases this repository's own resources.
  void dispose();
}

/// The filesystem [SubstationFactsRepository]: observes EXPLICITLY configured
/// substation roots, and nothing else.
///
/// Per root it reads `<root>/.dart_tool/package_config.json` (absent ⇒ an EMPTY
/// package graph — an operator who has not run `dart pub get` gets no packages,
/// not a crashed tree) and probes the FINITE set of relative paths the
/// registry's `RequiresPath` selectors declare. A malformed package config or a
/// non-`file:` package root REFUSES loudly: those are broken observations, not
/// empty ones.
final class FileSystemSubstationFactsRepository
    implements SubstationFactsRepository {
  /// Observes [roots] (substation → configured root) for the selector inputs
  /// [registry] declares.
  FileSystemSubstationFactsRepository({
    required Map<SubstationKey, String> roots,
    required GridAssetRegistry registry,
  }) : _roots = Map<SubstationKey, String>.unmodifiable(roots),
       _requiredPaths = Set<String>.unmodifiable(
         registry.assets.expand((asset) => _selectorPaths(asset.selector)),
       ) {
    _current = _observe();
  }

  final Map<SubstationKey, String> _roots;
  final Set<String> _requiredPaths;
  final StreamController<SubstationFactsSnapshot> _controller =
      StreamController<SubstationFactsSnapshot>.broadcast(sync: true);
  late SubstationFactsSnapshot _current;

  @override
  SubstationFactsSnapshot get current => _current;

  @override
  Stream<SubstationFactsSnapshot> get changes => _controller.stream;

  @override
  void refresh() {
    final next = _observe();
    if (next == _current) return;
    _current = next;
    _controller.add(next);
  }

  SubstationFactsSnapshot _observe() => SubstationFactsSnapshot(
    <SubstationKey, SubstationFacts>{
      for (final entry in _roots.entries) entry.key: _observeRoot(entry.value),
    },
  );

  SubstationFacts _observeRoot(String configuredRoot) {
    final root = p.normalize(p.absolute(configuredRoot));
    final configFile = File(p.join(root, '.dart_tool', 'package_config.json'));
    final packages = <String>{};
    final packageRoots = <String, String>{};
    if (configFile.existsSync()) {
      final config = PackageConfig.parseString(
        configFile.readAsStringSync(),
        configFile.uri,
      );
      for (final package in config.packages) {
        if (package.root.scheme != 'file') {
          throw StateError(
            'package ${package.name} has non-file root ${package.root}',
          );
        }
        packages.add(package.name);
        packageRoots[package.name] = p.normalize(
          Directory.fromUri(package.root).absolute.path,
        );
      }
    }
    return SubstationFacts(
      root: root,
      dartPackages: packages,
      packageRoots: packageRoots,
      existingPaths: _requiredPaths.where(
        (relative) =>
            FileSystemEntity.typeSync(
              p.join(root, relative),
              followLinks: false,
            ) !=
            FileSystemEntityType.notFound,
      ),
    );
  }

  @override
  void dispose() => unawaited(_controller.close());
}

/// The finite relative paths [selector] declares — the whole probe set, so the
/// repository never walks a root.
Iterable<String> _selectorPaths(AssetSelector selector) sync* {
  switch (selector) {
    case AlwaysApplies():
    case RequiresPackage():
      return;
    case RequiresPath(:final relativePath):
      yield p.normalize(relativePath);
    case RequiresAll(:final selectors):
      for (final part in selectors) {
        yield* _selectorPaths(part);
      }
  }
}

/// The ambient facts, scoped BY SUBSTATION: a dependent that watches one
/// [SubstationKey] aspect is invalidated only when THAT substation's facts
/// change (`power_station#adr-0006-typed-environment-lookup-selects-by-value`).
final class SubstationFactsModelSeed
    extends InheritedModelSeed<SubstationFactsSnapshot, SubstationKey> {
  /// Provides [value] over [child], aspect-scoped by substation.
  const SubstationFactsModelSeed({
    required super.value,
    required super.child,
    super.key,
  });

  @override
  bool updateShouldNotifyDependent(
    InheritedModelSeed<SubstationFactsSnapshot, SubstationKey> oldSeed,
    Set<SubstationKey> dependencies,
  ) => dependencies.any(
    (substation) =>
        value.factsFor(substation) != oldSeed.value.factsFor(substation),
  );
}

/// PROJECTS the injected repository's snapshots into the tree.
///
/// The D-H shape: the repository observes OUTSIDE build and this seed
/// subscribes in lifecycle; the mutable snapshot is re-projected as an
/// [InheritedModelSeed] and has NO public synchronous accessor; `build` reads
/// state and composes, and never rescans. Repository LIFETIME stays with its
/// constructor's owner — this seed disposes only its own subscription.
final class SubstationFactsAssets extends SingleChildStatefulSeed {
  /// Projects [repository]'s snapshots over [child].
  const SubstationFactsAssets({
    required this.repository,
    super.child,
    super.key,
  });

  /// The injected observer (impls are DI).
  final SubstationFactsRepository repository;

  @override
  SingleChildState<SubstationFactsAssets> createState() =>
      _SubstationFactsAssetsState();
}

class _SubstationFactsAssetsState
    extends SingleChildState<SubstationFactsAssets> {
  late SubstationFactsSnapshot _snapshot;
  StreamSubscription<SubstationFactsSnapshot>? _subscription;

  @override
  void initState() {
    _snapshot = seed.repository.current;
    _subscription = seed.repository.changes.listen((next) {
      if (next != _snapshot) setState(() => _snapshot = next);
    });
  }

  @override
  Seed buildWithChild(TreeContext context, Seed child) =>
      SubstationFactsModelSeed(value: _snapshot, child: child);

  @override
  void dispose() {
    final subscription = _subscription;
    if (subscription != null) unawaited(subscription.cancel());
  }
}

bool _sameSet<T>(Set<T> left, Set<T> right) =>
    left.length == right.length && left.containsAll(right);

bool _sameMap<K, V>(Map<K, V> left, Map<K, V> right) =>
    left.length == right.length &&
    left.entries.every((entry) => right[entry.key] == entry.value);
