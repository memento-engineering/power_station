// Bead `pow-2c9` — model selection is ROLE → TIER → MODEL.
//
// A20 mapped role → model directly (build ⇒ `params['model']`, grade ⇒
// `graderModel`), so a new role meant a new station field and a retune meant
// touching roles. The tier is the axis selection actually varies on: the domain
// declares a ROLE, the role points at a TIER (`tierFor` — a tiny policy), and
// the STATION arms TIER → MODEL (`ModelTiers`). This suite pins the axis, the
// arming, `gather` = cheap = haiku end to end, the readiness lane's CURRENT rung
// (ADR-0000 A17(6) — see the group below), and the two fences that keep the
// layering honest (the tier axis knows no engine and no role; the engine knows
// no role, tier, or model).
//
// Pure-Dart, offline: no live claude/git/network; the synthetic workspace dir
// never exists on disk, so `AgentCapability`'s `grid.dart` link probe no-ops
// (the documented offline posture).
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

/// The model a spawned claude invocation actually asks for — the value right
/// after `--model` in the argv the harness built.
String _modelOf(RuntimeConfig cfg) {
  final i = cfg.args.indexOf('--model');
  expect(i, greaterThanOrEqualTo(0), reason: 'the spawn named NO --model');
  return cfg.args[i + 1];
}

/// Resolves a config for [role] off the station [ambient] (no bead override).
AgentConfig _resolve(AgentRole role, AgentConfig ambient) => resolveAgentConfig(
  role: role,
  ambient: ambient,
  beadMetadata: const {},
  stepParams: const {},
  registry: buildBuiltinEnvironmentRegistry(),
);

/// The ambient tree a spawner reads at entry: the work bead, the activation, and
/// the station's [config].
FakeTreeContext _ctx(AgentConfig config) => FakeTreeContext(
  values: {
    Bead: bead('tg-1'),
    Workspace: testWorkspace(
      'tg-1',
      workspaceDir: '/w/tg-1',
      branch: 'grid/tg-1',
    ),
    AgentConfig: config,
    EnvironmentRegistry: buildBuiltinEnvironmentRegistry(),
  },
);

/// This package's `lib` dir (the suite runs with the package as its cwd).
Directory _libDir() {
  final lib = Directory('lib');
  if (!lib.existsSync()) fail('run this suite from packages/grid_assets');
  return lib;
}

/// The package config `dart pub get` wrote — at the pub WORKSPACE root, which is
/// an ancestor of this package, so walk up for it. LOUD when it cannot be found:
/// a fence that silently finds nothing is a fence that is GONE.
File _packageConfig() {
  for (
    var dir = Directory.current.absolute;
    dir.parent.path != dir.path;
    dir = dir.parent
  ) {
    final config = File(p.join(dir.path, '.dart_tool', 'package_config.json'));
    if (config.existsSync()) return config;
  }
  fail('no .dart_tool/package_config.json above ${Directory.current.path} — '
      'run `dart pub get` first');
}

/// `grid_engine`'s resolved `lib` dir, read off that package config.
Directory _engineLibDir() {
  final config = _packageConfig();
  final json = jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
  final packages = (json['packages']! as List).cast<Map<String, dynamic>>();
  final engine = packages.firstWhere(
    (pkg) => pkg['name'] == 'grid_engine',
    orElse: () => fail('grid_engine is absent from the package config'),
  );
  // `rootUri` is relative to the config's own dir and carries NO trailing slash,
  // so it must be re-terminated before `lib/` is resolved against it.
  final rootUri = engine['rootUri']! as String;
  final root = config.absolute.parent.uri.resolve(
    rootUri.endsWith('/') ? rootUri : '$rootUri/',
  );
  final lib = Directory.fromUri(root.resolve('lib/'));
  if (!lib.existsSync()) fail('grid_engine lib not found at ${lib.path}');
  return lib;
}

/// Every `.dart` source under [dir], concatenated.
String _sourceUnder(Directory dir) => dir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => f.readAsStringSync())
    .join('\n');

void main() {
  group('the TIER is the selection axis', () {
    test('three tiers, each with an explicit asset-default model', () {
      expect(AgentTier.values, [
        AgentTier.cheap,
        AgentTier.mid,
        AgentTier.frontier,
      ]);
      expect(defaultModelForTier(AgentTier.cheap), 'haiku');
      expect(defaultModelForTier(AgentTier.mid), 'sonnet');
      expect(defaultModelForTier(AgentTier.frontier), 'opus');
    });

    test('an unarmed ModelTiers rides the asset defaults; arming one tier moves '
        'ONLY that tier', () {
      const unarmed = ModelTiers();
      expect(unarmed.armed(AgentTier.mid), isNull);
      expect(unarmed.modelFor(AgentTier.mid), 'sonnet');
      const retuned = ModelTiers(mid: 'haiku');
      expect(retuned.modelFor(AgentTier.mid), 'haiku');
      expect(retuned.modelFor(AgentTier.frontier), 'opus');
      expect(retuned.modelFor(AgentTier.cheap), 'haiku');
    });
  });

  group('the ROLE → TIER policy (the whole per-role surface)', () {
    test('build ⇒ frontier, grade ⇒ mid, gather ⇒ cheap', () {
      expect(AgentRole.values, [
        AgentRole.build,
        AgentRole.grade,
        AgentRole.gather,
      ]);
      expect(tierFor(AgentRole.build), AgentTier.frontier);
      expect(tierFor(AgentRole.grade), AgentTier.mid);
      expect(tierFor(AgentRole.gather), AgentTier.cheap);
    });

    test('role → tier → model: the A20 defaults are PRESERVED, and gather is '
        'cheap', () {
      expect(defaultModelFor(AgentRole.build), 'opus');
      expect(defaultModelFor(AgentRole.grade), 'sonnet');
      expect(defaultModelFor(AgentRole.gather), 'haiku');
      const station = AgentConfig();
      expect(station.modelForRole(AgentRole.build), 'opus');
      expect(station.modelForRole(AgentRole.grade), 'sonnet');
      expect(station.modelForRole(AgentRole.gather), 'haiku');
    });
  });

  group('the STATION arms TIER → MODEL (one change retunes a class of work)', () {
    test('arming the tiers moves every role that rides them', () {
      const station = AgentConfig(
        tiers: ModelTiers(cheap: 'c', mid: 'm', frontier: 'f'),
      );
      expect(station.modelForRole(AgentRole.build), 'f');
      expect(station.modelForRole(AgentRole.grade), 'm');
      expect(station.modelForRole(AgentRole.gather), 'c');
    });

    test('"grading is cheap now" is ONE arming change — no role churn', () {
      const station = AgentConfig(tiers: ModelTiers(mid: 'haiku'));
      expect(_resolve(AgentRole.grade, station).params['model'], 'haiku');
      // …and the other tiers are untouched.
      expect(_resolve(AgentRole.build, station).params['model'], 'opus');
      expect(_resolve(AgentRole.gather, station).params['model'], 'haiku');
    });
  });

  group('the PRE-TIER station knobs project onto tiers (A20, no wedge)', () {
    test('--model X arms FRONTIER only; --grader-model Y arms MID only', () {
      const build = AgentConfig(params: {'model': 'X'});
      expect(build.modelForRole(AgentRole.build), 'X');
      expect(build.modelForRole(AgentRole.grade), 'sonnet');
      expect(build.modelForRole(AgentRole.gather), 'haiku');
      const grade = AgentConfig(graderModel: 'Y');
      expect(grade.modelForRole(AgentRole.build), 'opus');
      expect(grade.modelForRole(AgentRole.grade), 'Y');
      expect(grade.modelForRole(AgentRole.gather), 'haiku');
    });

    test('a PRE-TIER knob OUT-RANKS an armed tier — an operator flag is never '
        'silently dropped', () {
      const station = AgentConfig(
        params: {'model': 'X'},
        graderModel: 'Y',
        tiers: ModelTiers(mid: 'm', frontier: 'f'),
      );
      expect(station.modelForRole(AgentRole.build), 'X');
      expect(station.modelForRole(AgentRole.grade), 'Y');
    });

    test('the UNMIGRATED station surface still compiles and resolves '
        '(`space up --model` / `--grader-model`)', () {
      const armed = AgentConfig(params: {'model': 'X'}, graderModel: 'Y');
      expect(
        armed.stationModelFor(AgentRole.build) ??
            defaultModelFor(AgentRole.build),
        'X',
      );
      expect(
        armed.stationModelFor(AgentRole.grade) ??
            defaultModelFor(AgentRole.grade),
        'Y',
      );
      const bare = AgentConfig();
      expect(bare.stationModelFor(AgentRole.build), isNull);
      expect(
        bare.stationModelFor(AgentRole.build) ??
            defaultModelFor(AgentRole.build),
        'opus',
      );
      expect(
        bare.stationModelFor(AgentRole.grade) ??
            defaultModelFor(AgentRole.grade),
        'sonnet',
      );
    });
  });

  group('gather = cheap = haiku, end to end at the argv', () {
    test('a gather spawn stamps --model haiku into the claude invocation', () {
      final config = _resolve(AgentRole.gather, const AgentConfig());
      expect(config.params['model'], 'haiku');
      final cfg = spawnFor(
        environment: kBuiltinEnvironments['claude']!,
        model: config.params['model'],
        brief: const AgentBrief(task: 'read the tree; cite what you find'),
        workspace: testWorkspace(
          'tg-1',
          workspaceDir: '/w/tg-1',
          branch: 'grid/tg-1',
        ),
      );
      expect(_modelOf(cfg), 'haiku');
    });

    test('a bead-pinned model still outranks the tier, for the gather role too', () {
      final pinned = bead('tg-1').copyWith(
        metadata: {
          'grid.agent': {
            'assets_version': kAgentAssetsVersion,
            'payload': {
              'params': {'model': 'Z'},
            },
          },
        },
      );
      final config = resolveAgentConfig(
        role: AgentRole.gather,
        ambient: const AgentConfig(),
        beadMetadata: pinned.metadata,
        stepParams: const {},
        registry: buildBuiltinEnvironmentRegistry(),
      );
      expect(config.params['model'], 'Z');
    });

    test('EVERY role resolves a non-empty model (no unpinned spawn)', () {
      for (final role in AgentRole.values) {
        expect(_resolve(role, const AgentConfig()).params['model'], isNotEmpty);
      }
    });
  });

  // The readiness lens (bead `pow-q7n`) is the one lane whose tier is an OPEN
  // question, and ADR-0000 A17(6) is why: *"`ReadinessCriticCapability`
  // resolves through the SAME ladder as every other lane, so the day
  // `pow-edp`'s role defaults land, this lane inherits the cheap model for
  // free. Cheapness TODAY is STRUCTURAL (1 agent instead of ~18), not a model
  // pin."* It does ride the ladder, and it inherited the cheaper of A20's two
  // rungs (sonnet, not the build's opus) — so A17(6) is KEPT. Pointing it at
  // the CHEAP tier now that one exists is a BEHAVIOR change on a live
  // governance lane, with its own bead. This test pins TODAY's rung at the
  // argv, so that flip is a deliberate two-line diff (the role in
  // `readiness.dart`, this expectation) — never silent drift.
  group('the READINESS lane rides the MID tier today (A17(6), pinned)', () {
    test('ReadinessCriticCapability spawns --model sonnet', () {
      final cfg = const ReadinessCriticCapability().spawn(
        _ctx(const AgentConfig()),
        stepArgs(
          'tg-1/spec_review/$kReadinessStep',
          params: {'rubric': kReadinessRubric},
        ),
      );
      expect(_modelOf(cfg), kMidModelDefault);
      expect(_modelOf(cfg), 'sonnet');
    });

    test('and it carries NO model opinion of its own — a station retune of the '
        'MID tier moves it', () {
      final cfg = const ReadinessCriticCapability().spawn(
        _ctx(const AgentConfig(tiers: ModelTiers(mid: 'haiku'))),
        stepArgs(
          'tg-1/spec_review/$kReadinessStep',
          params: {'rubric': kReadinessRubric},
        ),
      );
      expect(_modelOf(cfg), 'haiku');
    });
  });

  group('the fences — the layering is real', () {
    test('a NEW role added NO station model field: the arming surface is one '
        'knob per TIER', () {
      // Three tiers, three armings — and the role count moved without it.
      const armed = ModelTiers(cheap: 'c', mid: 'm', frontier: 'f');
      expect(
        {for (final t in AgentTier.values) t: armed.armed(t)},
        {AgentTier.cheap: 'c', AgentTier.mid: 'm', AgentTier.frontier: 'f'},
      );
      expect(
        _sourceUnder(_libDir()),
        isNot(contains('gatherModel')),
        reason: 'a role points at a TIER — it never grows its own model field',
      );
    });

    test('the TIER axis is dependency-free — it names no engine and no role', () {
      final src = File(
        p.join('lib', 'src', 'agent', 'model_tier.dart'),
      ).readAsStringSync();
      expect(
        src,
        isNot(contains("import '")),
        reason: 'the selection axis compiles standalone (SDK/composition edge)',
      );
    });

    test('the ENGINE stays DOMAIN-FREE — it names no role, tier, or tier map', () {
      final engine = _sourceUnder(_engineLibDir());
      for (final domain in ['AgentRole', 'AgentTier', 'ModelTiers', 'tierFor']) {
        expect(
          engine,
          isNot(contains(domain)),
          reason: 'grid_engine must not learn the asset domain ($domain)',
        );
      }
    });
  });
}
