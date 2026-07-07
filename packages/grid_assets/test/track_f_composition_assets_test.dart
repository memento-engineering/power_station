// Track F (tg-5r9): the v3 composition assets that REPLACE ServiceBundle —
// GitGridAssets / GitHubGridAssets (substation-scoped source control),
// HarnessProvider (station-scoped harness provision), CircuitProvider (the Q8
// circuit provider/scope shape), and `sourceControlOf` (bead → substation →
// root resolution, no string-keyed bundle map).
//
// Pure + offline: the assets are mounted in a bare genesis tree and their
// PROVIDED ambient values are read back at a leaf — no kernel, no live
// tg/gc/claude/git (Track F depends only on B, the composition Seeds).
import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:test/test.dart';

// ── test infra ──────────────────────────────────────────────────────────────

/// Mounts [root] in a bare tree and flushes one build pass (the Track B
/// template).
void mount(Seed root) {
  final owner = TreeOwner();
  owner.mountRoot(root);
  owner.flush();
}

/// A terminal leaf (an empty fan-out).
class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const []);
}

/// Runs [onBuild] against a live TreeContext at the leaf's build — the read
/// happens WHILE mounted (inherited lookups are valid only then).
class _Probe extends StatelessSeed {
  const _Probe(this.onBuild);

  final void Function(TreeContext) onBuild;

  @override
  Seed build(TreeContext context) {
    onBuild(context);
    return const _Leaf();
  }
}

/// A `Substation`-less scope provider — mounts an ambient grid_sdk
/// [sdk.SubstationScope] (name + ONE root) directly, the value grid_sdk's
/// `Substation` provides. Lets the source-control asset tests focus on ONE
/// asset without the full RawAssetGrid → Station → Substations spine.
Seed _underSubstation(String name, String root, Seed child) =>
    InheritedSeed<sdk.SubstationScope>(
      value: sdk.SubstationScope(name: name, root: root),
      child: child,
    );

/// A non-throwing GitRunner (canLand only needs a non-null GitOps).
class _FakeGitRunner implements GitRunner {
  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async => const GitRunResult(exitCode: 0, output: '');
}

/// A non-throwing PrOpener (canLand only needs a non-null PR opener).
class _FakePrOpener implements PrOpener {
  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async =>
      PullRequestResult.opened(const PullRequestRef(url: 'https://x/pr/1'));
}

void main() {
  group('GitGridAssets — source control resolved from the substation scope', () {
    test('provides a GitSourceControl bound to the substation ONE root '
        '(bead → substation → root, no root-name selector)', () {
      SourceControl? sc;
      mount(
        _underSubstation(
          'power_station',
          '/work/ps',
          GitGridAssets(child: _Probe((ctx) => sc = sourceControlOf(ctx))),
        ),
      );
      expect(sc, isA<GitSourceControl>());
      // The worktree layout is derived from the substation's root + name — a
      // path, not a map lookup.
      expect(
        sc!.workspaceFor('tg-1'),
        '/work/ps/.grid/worktrees/power_station/tg-1',
      );
      expect(sc!.branchFor('tg-1'), 'grid/tg-1');
      expect(sc!.baseBranch, 'main');
    });

    test('an explicit defaultBranch drives the base branch (a live '
        'registerRootCheckout probes this; an offline asset authors it)', () {
      SourceControl? sc;
      mount(
        _underSubstation(
          'tg',
          '/work/tg',
          GitGridAssets(
            defaultBranch: 'm3-runtime',
            child: _Probe((ctx) => sc = sourceControlOf(ctx)),
          ),
        ),
      );
      expect(sc!.baseBranch, 'm3-runtime');
    });

    test('GitGridAssets alone is commit-only — canLand is false until GitHub '
        'adds the PR opener', () {
      SourceControl? sc;
      mount(
        _underSubstation(
          'power_station',
          '/work/ps',
          GitGridAssets(
            gitOps: GitOps(_FakeGitRunner()),
            child: _Probe((ctx) => sc = sourceControlOf(ctx)),
          ),
        ),
      );
      expect(sc!.canLand, isFalse);
    });

    test('the provided ServiceBundle carries an EMPTY sourceControlsByRoot — a '
        'stray root name resolves back to the ONE substation source control '
        '(no string-keyed bundle map)', () {
      ServiceBundle? bundle;
      mount(
        _underSubstation(
          'power_station',
          '/work/ps',
          GitGridAssets(
            child: _Probe(
              (ctx) => bundle =
                  ctx.getInheritedSeedOfExactType<ServiceBundle>(),
            ),
          ),
        ),
      );
      expect(bundle, isNotNull);
      expect(bundle!.sourceControlsByRoot, isEmpty);
      // Any name — including a non-existent one — collapses to the substation's
      // single source control (the fallback IS the resolution now).
      expect(bundle!.sourceControlFor('whatever'), same(bundle!.sourceControl));
      expect(bundle!.sourceControlFor(null), same(bundle!.sourceControl));
    });

    test('mounted outside a Substation it refuses LOUD (an asset without a '
        'scope is an authoring error, not a default)', () {
      expect(
        () => mount(GitGridAssets(child: _Probe((_) {}))),
        throwsStateError,
      );
    });
  });

  group('GitHubGridAssets — adds land onto the git asset', () {
    test('GitGridAssets + GitHubGridAssets in a Nest → canLand true '
        '(the substation can PR)', () {
      SourceControl? sc;
      mount(
        _underSubstation(
          'the_grid',
          '/work/tg',
          Nest(
            children: [
              GitGridAssets(gitOps: GitOps(_FakeGitRunner())),
              GitHubGridAssets(prOpener: _FakePrOpener()),
            ],
            child: _Probe((ctx) => sc = sourceControlOf(ctx)),
          ),
        ),
      );
      expect(sc, isA<GitSourceControl>());
      expect(sc!.canLand, isTrue);
      // Land was ADDED, not replaced — the same root's layout is intact.
      expect(sc!.workspaceFor('tg-9'), '/work/tg/.grid/worktrees/the_grid/tg-9');
    });

    test('GitHubGridAssets with no git asset above passes through — GitHub can '
        'only ADD land to a checkout it can commit from, never conjure one', () {
      SourceControl? sc = _sentinel;
      mount(
        _underSubstation(
          'the_grid',
          '/work/tg',
          Nest(
            children: [GitHubGridAssets(prOpener: _FakePrOpener())],
            child: _Probe((ctx) => sc = sourceControlOf(ctx)),
          ),
        ),
      );
      // No ambient ServiceBundle at all — resolution is null (offline posture).
      expect(sc, isNull);
    });

    test('GitHubGridAssets offline (no prOpener) leaves the git asset '
        'commit-only', () {
      SourceControl? sc;
      mount(
        _underSubstation(
          'the_grid',
          '/work/tg',
          Nest(
            children: [
              GitGridAssets(gitOps: GitOps(_FakeGitRunner())),
              const GitHubGridAssets(),
            ],
            child: _Probe((ctx) => sc = sourceControlOf(ctx)),
          ),
        ),
      );
      expect(sc!.canLand, isFalse);
    });
  });

  group('sourceControlOf — pure resolution, isolated per substation', () {
    test('two substations resolve their OWN root, never each other\'s '
        '(the routing proof, offline)', () {
      SourceControl? a;
      SourceControl? b;
      // Two independent subtrees, each its own substation scope + git asset.
      mount(
        _underSubstation(
          'sa',
          '/work/sa',
          GitGridAssets(child: _Probe((ctx) => a = sourceControlOf(ctx))),
        ),
      );
      mount(
        _underSubstation(
          'sb',
          '/work/sb',
          GitGridAssets(child: _Probe((ctx) => b = sourceControlOf(ctx))),
        ),
      );
      expect(a!.workspaceFor('x'), '/work/sa/.grid/worktrees/sa/x');
      expect(b!.workspaceFor('x'), '/work/sb/.grid/worktrees/sb/x');
    });

    test('null when no source-control asset is mounted (the offline / no-git '
        'posture — provisioning + land no-op)', () {
      SourceControl? sc = _sentinel;
      mount(
        _underSubstation('sa', '/work/sa', _Probe((ctx) => sc = sourceControlOf(ctx))),
      );
      expect(sc, isNull);
    });
  });

  group('HarnessProvider — station-scoped harness provision', () {
    test('provides the default registry + ambient AgentConfig below it', () {
      AgentHarnessRegistry? reg;
      AgentConfig? cfg;
      mount(
        HarnessProvider(
          child: _Probe((ctx) {
            reg = ctx.getInheritedSeedOfExactType<AgentHarnessRegistry>();
            cfg = ctx.getInheritedSeedOfExactType<AgentConfig>();
          }),
        ),
      );
      expect(reg, isNotNull);
      // The default is the first-party set (claude at minimum).
      expect(reg!.ids, contains('claude'));
      expect(cfg, const AgentConfig());
    });

    test('a custom registry + config flow through', () {
      const custom = AgentConfig(harness: 'opencode');
      AgentHarnessRegistry? reg;
      AgentConfig? cfg;
      final registry = buildAgentHarnessRegistry();
      mount(
        HarnessProvider(
          registry: registry,
          config: custom,
          child: _Probe((ctx) {
            reg = ctx.getInheritedSeedOfExactType<AgentHarnessRegistry>();
            cfg = ctx.getInheritedSeedOfExactType<AgentConfig>();
          }),
        ),
      );
      expect(reg, same(registry));
      expect(cfg, custom);
    });
  });

  group('CircuitProvider — the Q8 circuit provider/scope shape', () {
    test('mounts a CircuitResolver into scope (the resolver seam, '
        'asset-shaped)', () {
      CircuitResolver? resolver;
      final r = CircuitResolver((_) => kCodeCircuit);
      mount(
        CircuitProvider(
          r,
          child: _Probe(
            (ctx) =>
                resolver = ctx.getInheritedSeedOfExactType<CircuitResolver>(),
          ),
        ),
      );
      expect(resolver, same(r));
    });

    test('forCircuit sugar mounts a single circuit for every bead in scope', () {
      CircuitResolver? resolver;
      mount(
        CircuitProvider.forCircuit(
          kCodeCircuit,
          child: _Probe(
            (ctx) =>
                resolver = ctx.getInheritedSeedOfExactType<CircuitResolver>(),
          ),
        ),
      );
      expect(resolver, isNotNull);
      final anyBead = Bead(
        id: 'any',
        issueType: IssueType.task,
        status: BeadStatus.open,
      );
      expect(resolver!.rootCircuitFor(anyBead).id, kCodeCircuit.id);
    });
  });

  group('the assets compose under the real grid_sdk Substation (v3 §2 shape)',
      () {
    test('RawAssetGrid → Station(HarnessProvider) → Substations → '
        'Substation(Nest[GitGridAssets, GitHubGridAssets]) resolves, at the '
        'leaf, the substation land-capable source control AND the station '
        'harness registry AND the substation scope', () {
      SourceControl? sc;
      AgentHarnessRegistry? reg;
      sdk.SubstationScope? scope;
      mount(
        sdk.RawAssetGrid(
          root: '/home/space_station',
          assets: [
            sdk.Station(
              name: 'MBP',
              assets: [
                HarnessProvider(
                  child: sdk.Substations(
                    substations: [
                      sdk.Substation(
                        name: 'the_grid',
                        root: '/work/the_grid',
                        assets: [
                          Nest(
                            children: [
                              GitGridAssets(gitOps: GitOps(_FakeGitRunner())),
                              GitHubGridAssets(prOpener: _FakePrOpener()),
                            ],
                            child: _Probe((ctx) {
                              sc = sourceControlOf(ctx);
                              reg = ctx
                                  .getInheritedSeedOfExactType<
                                      AgentHarnessRegistry>();
                              scope = sdk.SubstationScope.maybeOf(ctx);
                            }),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      // Substation-scoped: the substation's own land-capable git.
      expect(sc, isA<GitSourceControl>());
      expect(sc!.canLand, isTrue);
      expect(
        sc!.workspaceFor('tg-1'),
        '/work/the_grid/.grid/worktrees/the_grid/tg-1',
      );
      // Station-scoped: the machine's harness registry reaches the leaf.
      expect(reg, isNotNull);
      expect(reg!.ids, contains('claude'));
      // The substation scope the asset resolved against.
      expect(scope, const sdk.SubstationScope(name: 'the_grid', root: '/work/the_grid'));
    });
  });
}

/// A distinct-from-null sentinel so a test can tell "assigned null" from "never
/// ran".
const SourceControl _sentinel = _SentinelSourceControl();

class _SentinelSourceControl implements SourceControl {
  const _SentinelSourceControl();
  @override
  bool get canLand => false;
  @override
  String get baseBranch => '';
  @override
  String branchFor(String beadId) => '';
  @override
  String workspaceFor(String beadId) => '';
  @override
  Future<void> commitAll({required String workspaceDir, required String message}) async {}
  @override
  Future<void> provisionWorkspace({required String beadId, required String workspaceDir}) async {}
  @override
  Future<void> push({required String workspaceDir, required String remote, required String branch}) async {}
  @override
  Future<PrRef?> openPr({required String workspaceDir, required String branch, required String baseBranch, required String title}) async => null;
}
