// Track F (tg-5r9): the v3 composition assets that REPLACE ServiceBundle —
// GitGridAssets / GitHubGridAssets (substation-scoped source control),
// HarnessProvider (station-scoped harness provision), CircuitProvider (the Q8
// circuit provider/scope shape), and `sourceControlOf` (bead → substation →
// root resolution, no string-keyed bundle map).
//
// Pure + offline: the assets are mounted in a bare genesis tree and their
// PROVIDED ambient values are read back at a leaf — no kernel, no live
// tg/gc/claude/git (Track F depends only on B, the composition Seeds).
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ── test infra ──────────────────────────────────────────────────────────────

/// Mounts [root] in a bare tree and flushes one build pass (the Track B
/// template). The root rides under [sdk.ProviderScope] — the availability
/// registry every production root (StationKernel.start, runGrid) mounts —
/// so a `watch<T>()` miss parks there and surfaces as the designed absence
/// posture instead of tripping the scope-less debug assert.
void mount(Seed root) {
  final owner = TreeOwner();
  owner.mountRoot(sdk.ProviderScope(child: root));
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
      value: sdk.SubstationScope(name: name, root: root, prefix: name),
      child: child,
    );

/// A non-throwing PrOpener (binding delivery only needs a non-null PR opener).
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
  group(
    'GitGridAssets — source control resolved from the substation scope',
    () {
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

      test('GitGridAssets alone is commit-only — NO delivery is bound until '
          'GitHubGridAssets binds one', () {
        ServiceBundle? bundle;
        mount(
          _underSubstation(
            'power_station',
            '/work/ps',
            GitGridAssets(
              child: _Probe(
                (ctx) =>
                    bundle = ctx.getInheritedSeedOfExactType<ServiceBundle>(),
              ),
            ),
          ),
        );
        expect(bundle!.sourceControl, isA<GitSourceControl>());
        expect(bundle!.delivery, isNull);
      });

      test('the provided ServiceBundle carries the substation\'s ONE source '
          'control, and sourceControlOf resolves it by TREE POSITION — the '
          'string-keyed bundle map is GONE from the type itself (the fossil '
          'track deleted sourceControlsByRoot/sourceControlFor outright)', () {
        ServiceBundle? bundle;
        SourceControl? resolved;
        mount(
          _underSubstation(
            'power_station',
            '/work/ps',
            GitGridAssets(
              child: _Probe((ctx) {
                bundle = ctx.getInheritedSeedOfExactType<ServiceBundle>();
                resolved = sourceControlOf(ctx);
              }),
            ),
          ),
        );
        expect(bundle, isNotNull);
        expect(bundle!.sourceControl, isNotNull);
        // The v3 resolution: bead → substation → root — the nearest bundle IS
        // the substation's own; no name ever selects against a map.
        expect(resolved, same(bundle!.sourceControl));
      });

      test('mounted outside a Substation it refuses LOUD (an asset without a '
          'scope is an authoring error, not a default)', () {
        expect(
          () => mount(GitGridAssets(child: _Probe((_) {}))),
          throwsStateError,
        );
      });
    },
  );

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
        _underSubstation(
          'sa',
          '/work/sa',
          _Probe((ctx) => sc = sourceControlOf(ctx)),
        ),
      );
      expect(sc, isNull);
    });
  });

  group('HarnessProvider — station-scoped harness provision', () {
    test('provides the default registry + ambient AgentConfig below it', () {
      EnvironmentRegistry? reg;
      AgentConfig? cfg;
      mount(
        HarnessProvider(
          child: _Probe((ctx) {
            reg = ctx.getInheritedSeedOfExactType<EnvironmentRegistry>();
            cfg = ctx.getInheritedSeedOfExactType<AgentConfig>();
          }),
        ),
      );
      expect(reg, isNotNull);
      // The default is the first-party set (claude at minimum).
      expect(reg!.names, contains('claude'));
      expect(cfg, const AgentConfig());
    });

    test('a custom registry + config flow through', () {
      const custom = AgentConfig(harness: 'opencode');
      EnvironmentRegistry? reg;
      AgentConfig? cfg;
      final registry = buildBuiltinEnvironmentRegistry();
      mount(
        HarnessProvider(
          registry: registry,
          config: custom,
          child: _Probe((ctx) {
            reg = ctx.getInheritedSeedOfExactType<EnvironmentRegistry>();
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

    test(
      'forCircuit sugar mounts a single circuit for every bead in scope',
      () {
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
      },
    );
  });

  group(
    'the assets compose under the real grid_sdk Substation (v3 §2 shape)',
    () {
      test(
        'resolves generic source control and a supplied delivery method',
        () {
          final fakeDelivery = _FakeDelivery();
          ServiceBundle? bundle;
          mount(
            _underSubstation(
              'power_station',
              '/work/ps',
              Nest(
                children: const <SingleChildSeed>[GitGridAssets()],
                child: InheritedSeed<ServiceBundle>(
                  value: ServiceBundle(delivery: fakeDelivery),
                  child: _Probe((context) {
                    bundle = context
                        .getInheritedSeedOfExactType<ServiceBundle>();
                  }),
                ),
              ),
            ),
          );
          expect(sourceControlOf, isA<Function>());
          expect(bundle!.delivery, same(fakeDelivery));
        },
      );
    },
  );

  group('GitServices — the ambient git-machinery carrier (pow-72b)', () {
    test(
      'a BARE GitGridAssets() sources the provisioner from the carrier — '
      'provisionWorkspace drives the carrier machinery, not a no-op',
      () async {
        final runner = _RecordingGitRunner();
        // A real root dir: provisionWorktree creates the substation parent dir
        // on disk before its (faked) `git worktree add`.
        final rootDir = Directory.systemTemp.createTempSync('pow72b-root');
        addTearDown(() => rootDir.deleteSync(recursive: true));
        SourceControl? sc;
        mount(
          _underSubstation(
            'ps',
            rootDir.path,
            InheritedSeed<GitServices>(
              value: GitServices(
                provisioner: StationGitService(
                  runner: runner,
                  prOpener: _FakePrOpener(),
                ),
              ),
              child: GitGridAssets(
                child: _Probe((ctx) => sc = sourceControlOf(ctx)),
              ),
            ),
          ),
        );
        await sc!.provisionWorkspace(
          beadId: 'pow-1',
          workspaceDir: sc!.workspaceFor('pow-1'),
        );
        expect(
          runner.calls,
          isNotEmpty,
          reason:
              'the context-sourced provisioner ran git for the worktree — '
              'a null provisioner would have no-opped (offline)',
        );
      },
    );
  });
}

class _FakeDelivery implements DeliveryMethod {
  final List<DeliveryRequest> requests = <DeliveryRequest>[];

  @override
  String get id => 'fake';

  @override
  Future<StepOutcome> deliver(DeliveryRequest request) async {
    requests.add(request);
    return const Ok();
  }
}

/// A recording [GitRunner] — argv capture proves WHICH machinery actually ran
/// (the carrier's vs a ctor override's) without any real git.
class _RecordingGitRunner implements GitRunner {
  final List<List<String>> calls = [];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add(args);
    if (args.length >= 2 && args[0] == 'worktree' && args[1] == 'add') {
      final target = args.contains('-b') ? args[4] : args[2];
      Directory(target).createSync(recursive: true);
      File(p.join(target, '.git')).writeAsStringSync('gitdir: fake');
    }
    return const GitRunResult(exitCode: 0, output: '');
  }
}

const SourceControl _sentinel = _SentinelSourceControl();

class _SentinelSourceControl implements SourceControl {
  const _SentinelSourceControl();

  @override
  String get baseBranch => '';

  @override
  String branchFor(String beadId) => '';

  @override
  String workspaceFor(String beadId) => '';

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async {}
}
