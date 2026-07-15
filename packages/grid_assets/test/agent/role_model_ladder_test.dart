// Bead `pow-edp` — the ROLE-model ladder: grade on sonnet, build on opus.
//
// Until this split, every spawner (the coding agent, the architect, and the
// committee's critics) resolved the ONE station-wide AgentConfig, so a station
// could not grade cheap while building strong — the fable/opus incident
// (2026-07-11) pinned one model and hit builders and critics alike.
//
// The ladder, most-explicit first:
//   1. the bead's `grid.agent` envelope `params.model` — every role, that bead;
//   2. the STATION's arming of the role's TIER — `tiers` (bead `pow-2c9`), plus
//      the PRE-TIER knobs `params['model']` → frontier and `graderModel` → mid;
//   3. the TIER's asset default — frontier ⇒ opus, mid ⇒ sonnet, cheap ⇒ haiku.
//
// The winner is stamped into `params['model']`, the transport key every harness
// reads, so these tests assert the CLAUDE ARGV each capability actually spawns —
// the thing that decides which model bills.
//
// Pure-Dart, offline: no live claude/git/network; the synthetic workspace dir
// never exists on disk, so AgentCapability's `grid.dart` link probe no-ops (the
// documented offline posture).
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

/// A bead whose `grid.agent` envelope pins [model] for every agent it spawns —
/// the TOP rung. `params` is the envelope's documented model channel
/// (agent_domain.dart), so the shape (and `assets_version`) is unchanged.
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
/// absent (an unpinned spawn is exactly the regression this bead closes).
String _modelOf(RuntimeConfig cfg) {
  final i = cfg.args.indexOf('--model');
  expect(
    i,
    greaterThanOrEqualTo(0),
    reason: 'the spawn named NO --model: ${cfg.args}',
  );
  return cfg.args[i + 1];
}

/// The build-role spawns (agent + specify) for the given bead + station config.
Map<String, RuntimeConfig> _buildSpawns(Bead b, AgentConfig config) => {
  'agent': const AgentCapability().spawn(_ctx(b, config), stepArgs('tg-1/agent')),
  'specify': const SpecifyCapability().spawn(
    _ctx(b, config),
    stepArgs('tg-1/spec_review/specify'),
  ),
};

/// The grade-role spawns (a code critic + a spec critic) for the given bead +
/// station config. Both ride an LLM rubric — the gating lanes are `sh -c`
/// runners, not agents, and are asserted separately.
Map<String, RuntimeConfig> _gradeSpawns(Bead b, AgentConfig config) => {
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

void main() {
  group('pow-edp — the ASSET rung (no station flags, no bead envelope)', () {
    test('build + specify spawn opus; the critics spawn sonnet', () {
      const station = AgentConfig(); // `space up` with neither model flag.
      _buildSpawns(bead('tg-1'), station).forEach((lane, cfg) {
        expect(
          _modelOf(cfg),
          kFrontierModelDefault,
          reason: '$lane must build strong',
        );
        expect(_modelOf(cfg), 'opus');
      });
      _gradeSpawns(bead('tg-1'), station).forEach((lane, cfg) {
        expect(
          _modelOf(cfg),
          kMidModelDefault,
          reason: '$lane must grade cheap',
        );
        expect(_modelOf(cfg), 'sonnet');
      });
    });

    test('the role resolves its model through its TIER (role → tier → model)', () {
      expect(defaultModelFor(AgentRole.build), 'opus');
      expect(defaultModelFor(AgentRole.grade), 'sonnet');
      expect(defaultModelFor(AgentRole.gather), 'haiku');
      expect(AgentRole.values, [
        AgentRole.build,
        AgentRole.grade,
        AgentRole.gather,
      ]);
    });
  });

  group('pow-edp — the STATION rung (the two flags move the two roles)', () {
    test('--model X moves BUILD only; the critics stay on the grade default', () {
      const station = AgentConfig(params: {'model': 'X'});
      _buildSpawns(
        bead('tg-1'),
        station,
      ).forEach((_, cfg) => expect(_modelOf(cfg), 'X'));
      _gradeSpawns(
        bead('tg-1'),
        station,
      ).forEach((_, cfg) => expect(_modelOf(cfg), 'sonnet'));
    });

    test('--grader-model Y moves GRADE only; build stays on the build default', () {
      const station = AgentConfig(graderModel: 'Y');
      _buildSpawns(
        bead('tg-1'),
        station,
      ).forEach((_, cfg) => expect(_modelOf(cfg), 'opus'));
      _gradeSpawns(
        bead('tg-1'),
        station,
      ).forEach((_, cfg) => expect(_modelOf(cfg), 'Y'));
    });

    test('both flags are independent', () {
      const station = AgentConfig(params: {'model': 'X'}, graderModel: 'Y');
      _buildSpawns(
        bead('tg-1'),
        station,
      ).forEach((_, cfg) => expect(_modelOf(cfg), 'X'));
      _gradeSpawns(
        bead('tg-1'),
        station,
      ).forEach((_, cfg) => expect(_modelOf(cfg), 'Y'));
    });
  });

  group('pow-edp — the BEAD rung (grid.agent.params.model wins over everything)', () {
    test('a bead-pinned model overrides the station AND the role defaults, for '
        'BOTH roles', () {
      const station = AgentConfig(params: {'model': 'X'}, graderModel: 'Y');
      final pinned = _beadPinning('Z');
      _buildSpawns(pinned, station).forEach((_, cfg) => expect(_modelOf(cfg), 'Z'));
      _gradeSpawns(pinned, station).forEach((_, cfg) => expect(_modelOf(cfg), 'Z'));
    });

    test('a bead-pinned model overrides the role defaults with no station flags', () {
      const station = AgentConfig();
      _buildSpawns(
        _beadPinning('Z'),
        station,
      ).forEach((_, cfg) => expect(_modelOf(cfg), 'Z'));
      _gradeSpawns(
        _beadPinning('Z'),
        station,
      ).forEach((_, cfg) => expect(_modelOf(cfg), 'Z'));
    });
  });

  group('pow-edp — the precedence table, per role, at the resolver', () {
    // (bead model, station build knob, station grade knob) → (build, grade,
    // gather). Neither PRE-TIER knob arms the CHEAP tier (bead `pow-2c9`), so a
    // gatherer rides its asset default unless the BEAD pins one.
    final rows =
        <({
          String label,
          String? beadModel,
          String? stationBuild,
          String? stationGrade,
          String build,
          String grade,
          String gather,
        })>[
          (
            label: 'nothing set',
            beadModel: null,
            stationBuild: null,
            stationGrade: null,
            build: 'opus',
            grade: 'sonnet',
            gather: 'haiku',
          ),
          (
            label: '--model only',
            beadModel: null,
            stationBuild: 'X',
            stationGrade: null,
            build: 'X',
            grade: 'sonnet',
            gather: 'haiku',
          ),
          (
            label: '--grader-model only',
            beadModel: null,
            stationBuild: null,
            stationGrade: 'Y',
            build: 'opus',
            grade: 'Y',
            gather: 'haiku',
          ),
          (
            label: 'both flags',
            beadModel: null,
            stationBuild: 'X',
            stationGrade: 'Y',
            build: 'X',
            grade: 'Y',
            gather: 'haiku',
          ),
          (
            label: 'bead over nothing',
            beadModel: 'Z',
            stationBuild: null,
            stationGrade: null,
            build: 'Z',
            grade: 'Z',
            gather: 'Z',
          ),
          (
            label: 'bead over --model',
            beadModel: 'Z',
            stationBuild: 'X',
            stationGrade: null,
            build: 'Z',
            grade: 'Z',
            gather: 'Z',
          ),
          (
            label: 'bead over --grader-model',
            beadModel: 'Z',
            stationBuild: null,
            stationGrade: 'Y',
            build: 'Z',
            grade: 'Z',
            gather: 'Z',
          ),
          (
            label: 'bead over both',
            beadModel: 'Z',
            stationBuild: 'X',
            stationGrade: 'Y',
            build: 'Z',
            grade: 'Z',
            gather: 'Z',
          ),
        ];

    for (final row in rows) {
      test('${row.label}: build=${row.build}, grade=${row.grade}, '
          'gather=${row.gather}', () {
        final ambient = AgentConfig(
          params: {if (row.stationBuild != null) 'model': row.stationBuild!},
          graderModel: row.stationGrade,
        );
        final metadata = row.beadModel == null
            ? const <String, dynamic>{}
            : _beadPinning(row.beadModel!).metadata;
        final registry = buildBuiltinEnvironmentRegistry();
        for (final (role, expected) in [
          (AgentRole.build, row.build),
          (AgentRole.grade, row.grade),
          (AgentRole.gather, row.gather),
        ]) {
          final resolved = resolveAgentConfig(
            role: role,
            ambient: ambient,
            beadMetadata: metadata,
            stepParams: const {},
            registry: registry,
          );
          expect(resolved.params['model'], expected, reason: '$role');
          // No silent fallback — EVERY resolved config names a real model.
          expect(resolved.params['model'], isNotEmpty);
        }
      });
    }
  });

  group('pow-edp — fail-closed + the runner lanes', () {
    for (final blank in ['', '   ']) {
      test('a blank bead model ("$blank") is REFUSED WHOLE, never a blank '
          '--model', () {
        expect(
          () => resolveAgentConfig(
            role: AgentRole.build,
            ambient: const AgentConfig(),
            beadMetadata: _beadPinning(blank).metadata,
            stepParams: const {},
            registry: buildBuiltinEnvironmentRegistry(),
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
}
