// Bead `pow-n6n.2` (epic `pow-n6n`) - the four SEAT preference types at the six
// spawn sites, and the critics' lane routing (ADR-0006 D2/D4).
//
// Pure-Dart, offline: the synthetic workspace dir never exists on disk, so the
// spawners' filesystem probes no-op (the documented offline posture of
// `model_ladder_test.dart`). The models below are deliberately NOT the
// tier defaults (opus/sonnet/haiku), so a typed win is distinguishable from the
// tier floor by the `--model` argv alone.
import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

const AgentEnvironment _fast = AgentEnvironment(
  command: 'claude',
  model: 'fast-model',
  target: InferenceTarget.providerManaged,
);
const AgentEnvironment _strong = AgentEnvironment(
  command: 'claude',
  model: 'strong-model',
  target: InferenceTarget.providerManaged,
);
const AgentEnvironment _shared = AgentEnvironment(
  command: 'claude',
  model: 'shared-model',
  target: InferenceTarget.providerManaged,
);

/// Custom arming PLUS the builtins, so an UNMOUNTED preference still resolves
/// `AgentConfig().harness` ('claude') through the ambient rung.
const EnvironmentRegistry _registry = EnvironmentRegistry(
  custom: {'fast': _fast, 'strong': _strong, 'shared': _shared},
  builtins: kBuiltinEnvironments,
);

const CriticLane _adr = CriticLane('decision-alignment');
const CriticLane _coherence = CriticLane('coherence');

/// The ambient tree a spawner reads at entry, plus whatever seat preference
/// [seat] mounts (keyed by exact type, like the real inherited lookup).
FakeTreeContext _ctx([Map<Type, Object> seat = const {}]) => FakeTreeContext(
  values: {
    Bead: bead('tg-1'),
    Workspace: testWorkspace(
      'tg-1',
      workspaceDir: '/w/tg-1',
      branch: 'grid/tg-1',
    ),
    AgentConfig: const AgentConfig(),
    EnvironmentRegistry: _registry,
    ...seat,
  },
);

/// The model a spawned invocation actually asks for.
String _modelOf(RuntimeConfig cfg) {
  final i = cfg.args.indexOf('--model');
  expect(
    i,
    greaterThanOrEqualTo(0),
    reason: 'the spawn named NO --model: ${cfg.args}',
  );
  return cfg.args[i + 1];
}

String _specify(Map<Type, Object> seat) => _modelOf(
  const SpecifyCapability().spawn(
    _ctx(seat),
    stepArgs('tg-1/spec_review/specify'),
  ),
);

String _build(Map<Type, Object> seat) =>
    _modelOf(const AgentCapability().spawn(_ctx(seat), stepArgs('tg-1/agent')));

String _gather(Map<Type, Object> seat) => _modelOf(
  const DiscoveryLensCapability().spawn(
    _ctx(seat),
    stepArgs(
      'tg-1/spec_review/discovery/prior-art',
      params: {'lens': 'prior-art'},
    ),
  ),
);

String _critic(Map<Type, Object> seat, String rubric) => _modelOf(
  const CriticCapability().spawn(
    _ctx(seat),
    stepArgs('tg-1/review/$rubric', params: {'rubric': rubric}),
  ),
);

String _specCritic(Map<Type, Object> seat, String rubric) => _modelOf(
  const SpecCriticCapability().spawn(
    _ctx(seat),
    stepArgs('tg-1/spec_review/$rubric', params: {'rubric': rubric}),
  ),
);

String _readiness(Map<Type, Object> seat, String rubric) => _modelOf(
  const ReadinessCriticCapability().spawn(
    _ctx(seat),
    stepArgs('tg-1/spec_review/$rubric', params: {'rubric': rubric}),
  ),
);

/// Ends every probe tree (the `typed_environment_test.dart` idiom).
class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const []);
}

/// A BUILD-time dependent scoped to one [lane] - the only place the aspect
/// itself is exercised (a spawn edge reads with the effect verb).
class _LaneProbe extends StatelessSeed {
  const _LaneProbe({required this.lane, required this.onBuild});

  final CriticLane lane;
  final void Function() onBuild;

  @override
  Seed build(TreeContext context) {
    context.dependOnInheritedSeedOfExactType<CriticAgentEnvironment>(
      aspect: lane,
    );
    onBuild();
    return const _Leaf();
  }
}

/// Hosts a SWAPPABLE [CriticAgentEnvironment] over a [CriticEnvironmentSeed]:
/// `TreeOwner` has no `updateRoot`, so the republish rides `setState`.
class _LaneHost extends StatefulSeed {
  const _LaneHost({
    required this.initial,
    required this.onReady,
    required this.child,
  });

  final CriticAgentEnvironment initial;
  final void Function(void Function(CriticAgentEnvironment)) onReady;
  final Seed child;

  @override
  State<_LaneHost> createState() => _LaneHostState();
}

class _LaneHostState extends State<_LaneHost> {
  late CriticAgentEnvironment _value = seed.initial;

  @override
  void initState() {
    super.initState();
    seed.onReady((next) => setState(() => _value = next));
  }

  @override
  Seed build(TreeContext context) =>
      CriticEnvironmentSeed(value: _value, child: seed.child);
}

void main() {
  group('pow-n6n.2 - the SPEC seat', () {
    test('a mounted SpecAgentEnvironment decides the spawn', () {
      expect(
        _specify({
          SpecAgentEnvironment: const SpecAgentEnvironment([_fast]),
        }),
        'fast-model',
      );
    });

    test('an absent specific falls back to the generic', () {
      expect(
        _specify({
          ModelPreference: const ModelPreference([_fast]),
        }),
        'fast-model',
      );
    });

    test('the specific WINS over a mounted generic', () {
      expect(
        _specify({
          ModelPreference: const ModelPreference([_fast]),
          SpecAgentEnvironment: const SpecAgentEnvironment([_strong]),
        }),
        'strong-model',
      );
    });

    test('nothing mounted keeps the TIER floor', () {
      expect(_specify(const {}), kFrontierModelDefault);
    });
  });

  group('pow-n6n.2 - the BUILD seat', () {
    test('a mounted BuildAgentEnvironment decides the spawn', () {
      expect(
        _build({
          BuildAgentEnvironment: const BuildAgentEnvironment([_fast]),
        }),
        'fast-model',
      );
    });

    test('an absent specific falls back to the generic', () {
      expect(
        _build({
          ModelPreference: const ModelPreference([_strong]),
        }),
        'strong-model',
      );
    });

    test('nothing mounted keeps the TIER floor', () {
      expect(_build(const {}), kFrontierModelDefault);
    });
  });

  group('pow-n6n.2 - the GATHER seat', () {
    test('a mounted GatherAgentEnvironment decides the spawn', () {
      expect(
        _gather({
          GatherAgentEnvironment: const GatherAgentEnvironment([_strong]),
        }),
        'strong-model',
      );
    });

    test('an absent specific falls back to the generic', () {
      expect(
        _gather({
          ModelPreference: const ModelPreference([_fast]),
        }),
        'fast-model',
      );
    });

    test('nothing mounted keeps the TIER floor', () {
      expect(_gather(const {}), kCheapModelDefault);
    });
  });

  group('pow-n6n.2 - the CRITIC seat and its lane', () {
    final routed = CriticAgentEnvironment(
      const [_shared],
      lanes: {
        _adr: const [_strong],
        _coherence: const [_fast],
      },
    );
    final seat = <Type, Object>{CriticAgentEnvironment: routed};

    test('ONE provider routes decision-alignment and coherence apart', () {
      expect(_critic(seat, 'decision-alignment'), 'strong-model');
      expect(_critic(seat, 'coherence'), 'fast-model');
    });

    test('the spec critic and the readiness lens read the SAME seat', () {
      expect(_specCritic(seat, 'coherence'), 'fast-model');
      expect(_specCritic(seat, 'decision-alignment'), 'strong-model');
      expect(_readiness(seat, 'decision-alignment'), 'strong-model');
      expect(_readiness(seat, 'coherence'), 'fast-model');
    });

    test('an unrouted lane rides the seat shared entries', () {
      expect(_critic(seat, 'spec-adherence'), 'shared-model');
      expect(_readiness(seat, kReadinessRubric), 'shared-model');
    });

    test('an absent critic seat falls back to the generic', () {
      final generic = <Type, Object>{
        ModelPreference: const ModelPreference([_fast]),
      };
      expect(_critic(generic, 'coherence'), 'fast-model');
      expect(_specCritic(generic, 'coherence'), 'fast-model');
      expect(_readiness(generic, 'coherence'), 'fast-model');
    });

    test('nothing mounted keeps the TIER floor', () {
      expect(_critic(const {}, 'coherence'), kMidModelDefault);
      expect(_specCritic(const {}, 'coherence'), kMidModelDefault);
      expect(_readiness(const {}, 'coherence'), kMidModelDefault);
    });

    test('the gating lane is still an sh runner and names no model', () {
      final gating = const CriticCapability().spawn(
        FakeTreeContext(
          values: {
            Bead: bead(
              'tg-1',
            ).copyWith(metadata: const {'validation_plan': 'dart analyze'}),
            Workspace: testWorkspace(
              'tg-1',
              workspaceDir: '/w/tg-1',
              branch: 'grid/tg-1',
            ),
            AgentConfig: const AgentConfig(),
            EnvironmentRegistry: _registry,
            CriticAgentEnvironment: routed,
          },
        ),
        stepArgs(
          'tg-1/review/$kGatingRubric',
          params: {'rubric': kGatingRubric},
        ),
      );
      expect(gating.command, 'sh');
      expect(gating.args, isNot(contains('--model')));
    });
  });

  group('pow-n6n.2 - preferenceFor and value equality', () {
    test('preferenceFor routes a lane and falls back to the entries', () {
      final seat = CriticAgentEnvironment(
        const [_shared],
        lanes: {
          _adr: const [_strong],
        },
      );
      expect(seat.preferenceFor(_adr), const ModelPreference([_strong]));
      expect(seat.preferenceFor(_coherence), const ModelPreference([_shared]));
      expect(seat.preferenceFor(null), const ModelPreference([_shared]));
    });

    test('a lanes-only difference is a DIFFERENT value', () {
      final a = CriticAgentEnvironment(
        const [_shared],
        lanes: {
          _adr: const [_strong],
        },
      );
      final b = CriticAgentEnvironment(
        const [_shared],
        lanes: {
          _adr: const [_fast],
        },
      );
      final same = CriticAgentEnvironment(
        const [_shared],
        lanes: {
          _adr: const [_strong],
        },
      );
      expect(a, isNot(b));
      expect(a, same);
      expect(a.hashCode, same.hashCode);
    });

    test('a seat type never equals the generic with equal entries', () {
      expect(
        const SpecAgentEnvironment([_fast]),
        isNot(const ModelPreference([_fast])),
      );
      expect(
        const BuildAgentEnvironment([_fast]),
        isNot(const GatherAgentEnvironment([_fast])),
      );
    });
  });

  group('pow-n6n.2 - the lane ASPECT narrows invalidation', () {
    test('a coherence dependent ignores an decision-alignment-only change', () {
      var builds = 0;
      late void Function(CriticAgentEnvironment) publish;
      final owner = TreeOwner();
      owner.mountRoot(
        _LaneHost(
          initial: CriticAgentEnvironment(
            const [_shared],
            lanes: {
              _adr: const [_strong],
              _coherence: const [_fast],
            },
          ),
          onReady: (p) => publish = p,
          child: _LaneProbe(lane: _coherence, onBuild: () => builds++),
        ),
      );
      owner.flush();
      expect(builds, 1);

      // Only the decision-alignment lane moves.
      publish(
        CriticAgentEnvironment(
          const [_shared],
          lanes: {
            _adr: const [_shared],
            _coherence: const [_fast],
          },
        ),
      );
      owner.flush();
      expect(builds, 1, reason: 'the coherence lane did not change');

      // Now the coherence lane moves.
      publish(
        CriticAgentEnvironment(
          const [_shared],
          lanes: {
            _adr: const [_shared],
            _coherence: const [_strong],
          },
        ),
      );
      owner.flush();
      expect(builds, 2, reason: 'the coherence lane changed');
    });
  });
}
