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

import 'support/asset_fakes.dart';

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
      value: sdk.SubstationScope(name: name, root: root, prefix: name),
      child: child,
    );

/// A non-throwing GitRunner (binding delivery only needs a non-null GitOps).
class _FakeGitRunner implements GitRunner {
  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async => const GitRunResult(exitCode: 0, output: '');
}

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

  group('GitHubGridAssets — BINDS the delivery method onto the git asset', () {
    test('GitGridAssets + GitHubGridAssets (BOTH halves) in a Nest → a bound '
        'GitHubPrDelivery (the substation can deliver)', () {
      ServiceBundle? bundle;
      mount(
        _underSubstation(
          'the_grid',
          '/work/tg',
          Nest(
            children: [
              const GitGridAssets(),
              GitHubGridAssets(
                gitOps: GitOps(_FakeGitRunner()),
                prOpener: _FakePrOpener(),
              ),
            ],
            child: _Probe(
              (ctx) =>
                  bundle = ctx.getInheritedSeedOfExactType<ServiceBundle>(),
            ),
          ),
        ),
      );
      expect(bundle!.delivery, isA<GitHubPrDelivery>());
      // Delivery was ADDED, not replaced — the ancestor's source control (and
      // so the same root's layout) rides through (A7(3)'s fold-order invariant).
      expect(bundle!.sourceControl, isA<GitSourceControl>());
      expect(
        bundle!.sourceControl!.workspaceFor('tg-9'),
        '/work/tg/.grid/worktrees/the_grid/tg-9',
      );
    });

    test(
      'GitHubGridAssets with no git asset above binds NOTHING — GitHub can '
      'only ADD delivery to a checkout it can commit from, never conjure one '
      '(A7(3)\'s fold-order invariant, preserved across the mechanism change)',
      () {
        SourceControl? sc = _sentinel;
        ServiceBundle? bundle;
        mount(
          _underSubstation(
            'the_grid',
            '/work/tg',
            Nest(
              children: [
                GitHubGridAssets(
                  gitOps: GitOps(_FakeGitRunner()),
                  prOpener: _FakePrOpener(),
                ),
              ],
              child: _Probe((ctx) {
                sc = sourceControlOf(ctx);
                bundle = ctx.getInheritedSeedOfExactType<ServiceBundle>();
              }),
            ),
          ),
        );
        // The bundle GitHubGridAssets re-provides carries a NULL source control —
        // there was no ancestor to read one from — so nothing can be delivered FROM.
        expect(sc, isNull);
        expect(bundle?.sourceControl, isNull);
      },
    );

    test(
      'GitHubGridAssets with only ONE half (no prOpener) binds NOTHING — the '
      'substation stays commit-only',
      () {
        ServiceBundle? bundle;
        mount(
          _underSubstation(
            'the_grid',
            '/work/tg',
            Nest(
              children: [
                const GitGridAssets(),
                GitHubGridAssets(gitOps: GitOps(_FakeGitRunner())),
              ],
              child: _Probe(
                (ctx) =>
                    bundle = ctx.getInheritedSeedOfExactType<ServiceBundle>(),
              ),
            ),
          ),
        );
        expect(bundle!.delivery, isNull);
        expect(bundle!.sourceControl, isA<GitSourceControl>());
      },
    );
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
      test('RawAssetGrid → Station(HarnessProvider) → Substations → '
          'Substation(Nest[GitGridAssets, GitHubGridAssets]) resolves, at the '
          'leaf, the substation land-capable source control AND the station '
          'harness registry AND the substation scope', () {
        SourceControl? sc;
        DeliveryMethod? delivery;
        EnvironmentRegistry? reg;
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
                          'the_grid',
                          '/work/the_grid',
                          assets: [
                            Nest(
                              children: [
                                const GitGridAssets(),
                                GitHubGridAssets(
                                  gitOps: GitOps(_FakeGitRunner()),
                                  prOpener: _FakePrOpener(),
                                ),
                              ],
                              child: _Probe((ctx) {
                                sc = sourceControlOf(ctx);
                                delivery = ctx
                                    .getInheritedSeedOfExactType<
                                      ServiceBundle
                                    >()
                                    ?.delivery;
                                reg = ctx
                                    .getInheritedSeedOfExactType<
                                      EnvironmentRegistry
                                    >();
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
        // Substation-scoped: the substation's own git, with delivery BOUND.
        expect(sc, isA<GitSourceControl>());
        expect(delivery, isA<GitHubPrDelivery>());
        expect(
          sc!.workspaceFor('tg-1'),
          '/work/the_grid/.grid/worktrees/the_grid/tg-1',
        );
        // Station-scoped: the machine's harness registry reaches the leaf.
        expect(reg, isNotNull);
        expect(reg!.names, contains('claude'));
        // The substation scope the asset resolved against.
        expect(
          scope,
          const sdk.SubstationScope(
            name: 'the_grid',
            root: '/work/the_grid',
            prefix: 'the_grid',
          ),
        );
      });
    },
  );

  group('GitServices — the ambient git-machinery carrier (pow-72b)', () {
    test('BARE seat assets source the gitOps half from the CARRIER — the clean '
        'substation seat (with GitHub below, the substation can deliver), and '
        'the layout is the SAME source control it produces today', () {
      SourceControl? sc;
      DeliveryMethod? delivery;
      mount(
        _underSubstation(
          'ps',
          '/work/ps',
          InheritedSeed<GitServices>(
            value: GitServices(gitOps: GitOps(_FakeGitRunner())),
            child: Nest(
              children: [
                const GitGridAssets(),
                GitHubGridAssets(prOpener: _FakePrOpener()),
              ],
              child: _Probe((ctx) {
                sc = sourceControlOf(ctx);
                delivery = ctx
                    .getInheritedSeedOfExactType<ServiceBundle>()
                    ?.delivery;
              }),
            ),
          ),
        ),
      );
      expect(sc, isA<GitSourceControl>());
      expect(
        delivery,
        isA<GitHubPrDelivery>(),
        reason: 'carrier gitOps + GitHub prOpener',
      );
      expect(sc!.workspaceFor('pow-1'), '/work/ps/.grid/worktrees/ps/pow-1');
      expect(sc!.branchFor('pow-1'), 'grid/pow-1');
      expect(sc!.baseBranch, 'main');
    });

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

    test(
      'an explicit ctor arg WINS over the carrier, per FIELD (tests inject) '
      '— now at GitHubGridAssets, the node that CONSUMES the gitOps half',
      () async {
        final carrierRunner = _RecordingGitRunner();
        final ctorRunner = _RecordingGitRunner();
        DeliveryMethod? delivery;
        mount(
          _underSubstation(
            'ps',
            '/work/ps',
            InheritedSeed<GitServices>(
              value: GitServices(gitOps: GitOps(carrierRunner)),
              child: Nest(
                children: [
                  const GitGridAssets(),
                  GitHubGridAssets(
                    gitOps: GitOps(ctorRunner),
                    prOpener: _FakePrOpener(),
                  ),
                ],
                child: _Probe(
                  (ctx) => delivery = ctx
                      .getInheritedSeedOfExactType<ServiceBundle>()
                      ?.delivery,
                ),
              ),
            ),
          ),
        );
        // Drive the BOUND METHOD: whichever GitOps it closed over is the one that
        // runs git.
        await delivery!.deliver(
          DeliveryRequest(
            bead: bead('ps-1'),
            sessionId: 's-1',
            nodePath: 'ps-1/deliver',
            workspace: testWorkspace('ps-1', workspaceDir: '/work/ps/x'),
          ),
        );
        expect(
          ctorRunner.calls,
          isNotEmpty,
          reason: 'the ctor gitOps committed',
        );
        expect(carrierRunner.calls, isEmpty, reason: 'the carrier half lost');
      },
    );

    test('the carrier read is SUBSCRIBING (D-H watch-deps) — re-provided '
        'machinery re-derives the seat\'s binding (offline → live BINDS '
        'delivery)', () {
      ServiceBundle? bundle;
      final services = _ServicesController(const GitServices());
      final owner = TreeOwner();
      owner.mountRoot(
        _underSubstation(
          'ps',
          '/work/ps',
          _ReprovidingServices(
            services,
            Nest(
              children: [
                const GitGridAssets(),
                GitHubGridAssets(prOpener: _FakePrOpener()),
              ],
              child: _Probe(
                (ctx) => bundle = ctx
                    .dependOnInheritedSeedOfExactType<ServiceBundle>(),
              ),
            ),
          ),
        ),
      );
      owner.flush();
      // First mount: an EMPTY carrier — no gitOps half, so nothing is bound.
      // (Offline: the substation commits, but nothing leaves it.)
      expect(bundle!.delivery, isNull);

      // The delegate re-provides live machinery. GitHubGridAssets must OBSERVE
      // the carrier (D-H) and RE-DERIVE its binding.
      services.set(GitServices(gitOps: GitOps(_FakeGitRunner())));
      owner.flush();
      expect(
        bundle!.delivery,
        isA<GitHubPrDelivery>(),
        reason:
            'a non-subscribing (get*) carrier read would keep the STALE '
            'unbound bundle mounted — the sync-notifier-read class',
      );
    });
  });

  group('GitHubGridAssets OBSERVES the ambient bundle (D-H watch-deps, tg-kx1)', () {
    test('a substation re-provision re-derives the binding — GitHubGridAssets '
        're-provides over the NEW root, never a stale wrap of the old one', () {
      SourceControl? sc;
      DeliveryMethod? delivery;
      final scope = _ScopeController('sa', '/work/before');
      final owner = TreeOwner();
      owner.mountRoot(
        _ReprovidingScope(
          scope,
          Nest(
            children: [
              const GitGridAssets(),
              GitHubGridAssets(
                gitOps: GitOps(_FakeGitRunner()),
                prOpener: _FakePrOpener(),
              ),
            ],
            // The leaf OBSERVES the re-provided bundle, so it re-runs when
            // GitHubGridAssets re-provides — and (the discriminator) stays put
            // when a non-subscribing GitHubGridAssets wrongly doesn't.
            child: _Probe((ctx) {
              final b = ctx.dependOnInheritedSeedOfExactType<ServiceBundle>();
              sc = b?.sourceControl;
              delivery = b?.delivery;
            }),
          ),
        ),
      );
      owner.flush();
      // First mount: delivery bound over the BEFORE root.
      expect(delivery, isA<GitHubPrDelivery>());
      expect(sc!.workspaceFor('x'), '/work/before/.grid/worktrees/sa/x');

      // Re-provision the substation onto a NEW name + root. GitGridAssets watches
      // SubstationScope, so it re-provides a fresh ServiceBundle; GitHubGridAssets
      // must OBSERVE that (D-H) and re-enrich over the new source control.
      scope.retarget('sb', '/work/after');
      owner.flush();
      expect(
        delivery,
        isA<GitHubPrDelivery>(),
        reason: 'delivery stays bound after a re-provision',
      );
      expect(
        sc!.workspaceFor('x'),
        '/work/after/.grid/worktrees/sb/x',
        reason:
            'a non-subscribing (get*) read here would keep wrapping the '
            'STALE /work/before source control — the sync-notifier-read class',
      );
    });
  });

  group('GitHubGridAssets — the PR composition knob (pow-8dx)', () {
    test('a composition set on the asset is mounted for the work subtree — '
        'DeliverRouteCapability/AgentCapability read it at their route/spawn '
        'edges', () {
      PrComposition? seen;
      const knob = PrComposition(
        trailerToken: 'Bead',
        sections: [PrSection.circuitReceipt],
        model: 'sonnet',
      );
      mount(
        _underSubstation(
          'power_station',
          '/work/ps',
          Nest(
            children: [
              const GitGridAssets(),
              GitHubGridAssets(
                gitOps: GitOps(_FakeGitRunner()),
                prOpener: _FakePrOpener(),
                composition: knob,
              ),
            ],
            child: _Probe(
              (ctx) =>
                  seen = ctx.dependOnInheritedSeedOfExactType<PrComposition>(),
            ),
          ),
        ),
      );
      expect(seen, same(knob));
    });

    test('the knob mounts INDEPENDENTLY of the delivery binding (a value, not '
        'a service): no prOpener ⇒ still mounted', () {
      PrComposition? seen;
      const knob = PrComposition(trailerToken: 'Bead');
      mount(
        _underSubstation(
          'power_station',
          '/work/ps',
          Nest(
            children: [
              const GitGridAssets(),
              const GitHubGridAssets(composition: knob),
            ],
            child: _Probe(
              (ctx) =>
                  seen = ctx.dependOnInheritedSeedOfExactType<PrComposition>(),
            ),
          ),
        ),
      );
      expect(seen, same(knob));
    });

    test('no knob set ⇒ nothing mounted (both capabilities fall back to the '
        'default const PrComposition())', () {
      PrComposition? seen;
      mount(
        _underSubstation(
          'power_station',
          '/work/ps',
          Nest(
            children: [
              const GitGridAssets(),
              GitHubGridAssets(
                gitOps: GitOps(_FakeGitRunner()),
                prOpener: _FakePrOpener(),
              ),
            ],
            child: _Probe(
              (ctx) =>
                  seen = ctx.dependOnInheritedSeedOfExactType<PrComposition>(),
            ),
          ),
        ),
      );
      expect(seen, isNull);
    });
  });
}

/// A [StatefulSeed] that re-provides an ambient [sdk.SubstationScope] on demand
/// (via [_ScopeController.retarget]) — lets a test flip the substation name+root
/// AFTER first mount and prove the downstream composition assets re-derive (the
/// D-H watch-deps invariant, bead tg-kx1). [child] is a fixed subtree (built
/// once), so ONLY the provided scope VALUE changes across a re-provision.
class _ReprovidingScope extends StatefulSeed {
  _ReprovidingScope(this.controller, this.child);

  final _ScopeController controller;
  final Seed child;

  @override
  State<_ReprovidingScope> createState() => _ReprovidingScopeState();
}

/// The test-side handle that drives a [_ReprovidingScope] re-provision.
class _ScopeController {
  _ScopeController(this._name, this._root);

  String _name;
  String _root;
  void Function()? _apply;

  /// Points the scope at a NEW substation name+root and re-provisions the tree.
  void retarget(String name, String root) {
    _name = name;
    _root = root;
    _apply!();
  }
}

class _ReprovidingScopeState extends State<_ReprovidingScope> {
  @override
  void initState() {
    super.initState();
    // Re-provision = a setState that re-reads the controller's current values.
    seed.controller._apply = () => setState(() {});
  }

  @override
  Seed build(TreeContext context) => InheritedSeed<sdk.SubstationScope>(
    value: sdk.SubstationScope(
      name: seed.controller._name,
      root: seed.controller._root,
      prefix: seed.controller._name,
    ),
    child: seed.child,
  );
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

/// A [StatefulSeed] that re-provides an ambient [GitServices] on demand (via
/// [_ServicesController.set]) — proves `GitGridAssets` OBSERVES the machinery
/// carrier (D-H watch-deps, bead pow-72b), mirroring [_ReprovidingScope].
class _ReprovidingServices extends StatefulSeed {
  _ReprovidingServices(this.controller, this.child);

  final _ServicesController controller;
  final Seed child;

  @override
  State<_ReprovidingServices> createState() => _ReprovidingServicesState();
}

/// The test-side handle that drives a [_ReprovidingServices] re-provision.
class _ServicesController {
  _ServicesController(this._value);

  GitServices _value;
  void Function()? _apply;

  /// Swaps the provided machinery and re-provisions the tree.
  void set(GitServices value) {
    _value = value;
    _apply!();
  }
}

class _ReprovidingServicesState extends State<_ReprovidingServices> {
  @override
  void initState() {
    super.initState();
    seed.controller._apply = () => setState(() {});
  }

  @override
  Seed build(TreeContext context) => InheritedSeed<GitServices>(
    value: seed.controller._value,
    child: seed.child,
  );
}

/// A distinct-from-null sentinel so a test can tell "assigned null" from "never
/// ran".
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
