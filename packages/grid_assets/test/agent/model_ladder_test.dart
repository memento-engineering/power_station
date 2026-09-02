// Bead `pow-n6n.4` — the model ladder after the ROLES retired (ADR-0006 D5).
//
// The role indirection is gone: a spawn site declares the model CLASS it rides
// (`AgentTier`, bead `pow-2c9`) and its typed seat (ADR-0006 D2) decides WHICH
// environment runs. The ladder, most-explicit first:
//   1. the bead's `grid.agent` envelope `params.model` — every tier, that bead;
//   2. the SELECTED environment's own model (null on every claude builtin);
//   3. the STATION's arming of the declared TIER — `tiers` (bead `pow-2c9`),
//      plus the PRE-TIER knobs `params['model']` → frontier, `graderModel` → mid;
//   4. the TIER's asset default — frontier ⇒ opus, mid ⇒ sonnet, cheap ⇒ haiku.
//
// Rung 4 is TOTAL, so ADR-0000 A20(3) ("no fallbackModel and no unpinned spawn")
// still holds by construction. The winner is stamped into `params['model']`, so
// these tests assert the CLAUDE ARGV each capability actually spawns — the thing
// that decides which model bills.
//
// Pure-Dart, offline: no live claude/git/network; the synthetic workspace dir
// never exists on disk, so AgentCapability's `grid.dart` link probe no-ops (the
// documented offline posture).
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

/// A bead whose `grid.agent` envelope pins [model] for every agent it spawns —
/// the TOP rung.
Bead _beadPinning(String model) => bead('tg-1').copyWith(
  metadata: {
    'grid.agent': {
      'assets_version': kAgentAssetsVersion,
      'payload': {
        'params': {'model': model},
      },
    },
  },
);

/// The ambient tree a spawner reads at entry: the work bead, the activation, and
/// the station's [config] (the ladder's station rung).
FakeTreeContext _ctx(Bead b, AgentConfig config) => FakeTreeContext(
  values: {
    Bead: b,
    Workspace: testWorkspace(
      'tg-1',
      workspaceDir: '/w/tg-1',
      branch: 'grid/tg-1',
    ),
    AgentConfig: config,
    EnvironmentRegistry: buildBuiltinEnvironmentRegistry(),
  },
);

/// The model a spawned claude invocation actually asks for — the value right
/// after `--model` in the argv the harness built. Fails loudly when the flag is
/// absent (an unpinned spawn is exactly the regression A20(3) closes).
String _modelOf(RuntimeConfig cfg) {
  final i = cfg.args.indexOf('--model');
  expect(
    i,
    greaterThanOrEqualTo(0),
    reason: 'the spawn named NO --model: ${cfg.args}',
  );
  return cfg.args[i + 1];
}

/// Resolves a config for [tier] off the station [ambient] and [metadata].
AgentConfig _resolve(
  AgentTier tier,
  AgentConfig ambient, [
  Map<String, dynamic> metadata = const {},
]) => resolveAgentConfig(
  tier: tier,
  ambient: ambient,
  beadMetadata: metadata,
  stepParams: const {},
  registry: buildBuiltinEnvironmentRegistry(),
);

/// The FRONTIER spawns (the coding agent + the spec author).
Map<String, RuntimeConfig> _frontierSpawns(Bead b, AgentConfig config) => {
  'agent': const AgentCapability().spawn(
    _ctx(b, config),
    stepArgs('tg-1/agent'),
  ),
  'specify': const SpecifyCapability().spawn(
    _ctx(b, config),
    stepArgs('tg-1/spec_review/specify'),
  ),
};

/// The MID spawns (a code critic + a spec critic). Both ride an LLM rubric —
/// the gating lanes are `sh -c` runners, not agents, and are asserted below.
Map<String, RuntimeConfig> _midSpawns(Bead b, AgentConfig config) => {
  'critic': const CriticCapability().spawn(
    _ctx(b, config),
    stepArgs(
      'tg-1/review/spec-adherence',
      params: {'rubric': 'spec-adherence'},
    ),
  ),
  'spec-critic': const SpecCriticCapability().spawn(
    _ctx(b, config),
    stepArgs('tg-1/spec_review/coherence', params: {'rubric': 'coherence'}),
  ),
};

/// Every `.dart` source under `lib`, concatenated (the deletion fence's corpus).
String _libSource() {
  final lib = Directory('lib');
  if (!lib.existsSync()) fail('run this suite from packages/grid_assets');
  return lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.readAsStringSync())
      .join('\n');
}

void main() {
  group('the ASSET rung (no station flags, no bead envelope)', () {
    test('build + specify spawn opus; the critics spawn sonnet', () {
      const station = AgentConfig(); // `space up` with neither model flag.
      _frontierSpawns(bead('tg-1'), station).forEach((lane, cfg) {
        expect(
          _modelOf(cfg),
          kFrontierModelDefault,
          reason: '$lane must build strong',
        );
        expect(_modelOf(cfg), 'opus');
      });
      _midSpawns(bead('tg-1'), station).forEach((lane, cfg) {
        expect(
          _modelOf(cfg),
          kMidModelDefault,
          reason: '$lane must grade cheap',
        );
        expect(_modelOf(cfg), 'sonnet');
      });
    });
  });

  group('the STATION rung (the two flags move the two tiers)', () {
    test('--model X moves FRONTIER only; the critics stay on mid', () {
      const station = AgentConfig(params: {'model': 'X'});
      _frontierSpawns(
        bead('tg-1'),
        station,
      ).forEach((_, cfg) => expect(_modelOf(cfg), 'X'));
      _midSpawns(
        bead('tg-1'),
        station,
      ).forEach((_, cfg) => expect(_modelOf(cfg), 'sonnet'));
    });

    test('--grader-model Y moves MID only; the build stays on frontier', () {
      const station = AgentConfig(graderModel: 'Y');
      _frontierSpawns(
        bead('tg-1'),
        station,
      ).forEach((_, cfg) => expect(_modelOf(cfg), 'opus'));
      _midSpawns(
        bead('tg-1'),
        station,
      ).forEach((_, cfg) => expect(_modelOf(cfg), 'Y'));
    });
  });

  group('the BEAD rung (grid.agent.params.model wins over everything)', () {
    test('a bead-pinned model overrides the station AND the tier defaults', () {
      const station = AgentConfig(params: {'model': 'X'}, graderModel: 'Y');
      final pinned = _beadPinning('Z');
      _frontierSpawns(
        pinned,
        station,
      ).forEach((_, cfg) => expect(_modelOf(cfg), 'Z'));
      _midSpawns(
        pinned,
        station,
      ).forEach((_, cfg) => expect(_modelOf(cfg), 'Z'));
    });
  });

  group('the precedence table, per TIER, at the resolver', () {
    // (bead model, station --model, station --grader-model) → (frontier, mid,
    // cheap). Neither PRE-TIER knob arms the CHEAP tier (bead `pow-2c9`), so a
    // lens rides its asset default unless the BEAD pins one.
    final rows =
        <
          ({
            String label,
            String? beadModel,
            String? stationBuild,
            String? stationGrade,
            String frontier,
            String mid,
            String cheap,
          })
        >[
          (
            label: 'nothing set',
            beadModel: null,
            stationBuild: null,
            stationGrade: null,
            frontier: 'opus',
            mid: 'sonnet',
            cheap: 'haiku',
          ),
          (
            label: '--model only',
            beadModel: null,
            stationBuild: 'X',
            stationGrade: null,
            frontier: 'X',
            mid: 'sonnet',
            cheap: 'haiku',
          ),
          (
            label: '--grader-model only',
            beadModel: null,
            stationBuild: null,
            stationGrade: 'Y',
            frontier: 'opus',
            mid: 'Y',
            cheap: 'haiku',
          ),
          (
            label: 'both flags',
            beadModel: null,
            stationBuild: 'X',
            stationGrade: 'Y',
            frontier: 'X',
            mid: 'Y',
            cheap: 'haiku',
          ),
          (
            label: 'bead over both',
            beadModel: 'Z',
            stationBuild: 'X',
            stationGrade: 'Y',
            frontier: 'Z',
            mid: 'Z',
            cheap: 'Z',
          ),
        ];

    for (final row in rows) {
      test('${row.label}: frontier=${row.frontier}, mid=${row.mid}, '
          'cheap=${row.cheap}', () {
        final ambient = AgentConfig(
          params: {if (row.stationBuild != null) 'model': row.stationBuild!},
          graderModel: row.stationGrade,
        );
        final metadata = row.beadModel == null
            ? const <String, dynamic>{}
            : _beadPinning(row.beadModel!).metadata;
        for (final (tier, expected) in [
          (AgentTier.frontier, row.frontier),
          (AgentTier.mid, row.mid),
          (AgentTier.cheap, row.cheap),
        ]) {
          final resolved = _resolve(tier, ambient, metadata);
          expect(resolved.params['model'], expected, reason: '$tier');
          // No silent fallback — EVERY resolved config names a real model.
          expect(resolved.params['model'], isNotEmpty);
        }
      });
    }
  });

  group('fail-closed + the runner lanes', () {
    for (final blank in ['', '   ']) {
      test('a blank bead model ("$blank") is REFUSED WHOLE, never a blank '
          '--model', () {
        expect(
          () => _resolve(
            AgentTier.frontier,
            const AgentConfig(),
            _beadPinning(blank).metadata,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('grid.agent envelope malformed'),
            ),
          ),
        );
      });
    }

    test('the gating lane is a RUNNER, not an agent — it names no model', () {
      final withPlan = bead('tg-1').copyWith(
        metadata: const {'validation_plan': 'dart analyze && dart test'},
      );
      final cfg = const CriticCapability().spawn(
        _ctx(withPlan, const AgentConfig()),
        stepArgs(
          'tg-1/review/$kGatingRubric',
          params: {'rubric': kGatingRubric},
        ),
      );
      expect(cfg.command, 'sh');
      expect(cfg.args, isNot(contains('--model')));
      expect(cfg.args[1], contains('dart analyze && dart test'));
    });
  });

  group('the ROLE MAP is GONE (ADR-0006 D5)', () {
    test('no lib source names a retired role symbol', () {
      final src = _libSource();
      for (final retired in [
        'AgentRole',
        'roleEnvironments',
        'modelForRole',
        'stationModelFor',
        'tierFor',
        'defaultModelFor(',
      ]) {
        expect(
          src,
          isNot(contains(retired)),
          reason: 'ADR-0006 D5 retired "$retired" — no code, no doc comment',
        );
      }
    });
  });
}
