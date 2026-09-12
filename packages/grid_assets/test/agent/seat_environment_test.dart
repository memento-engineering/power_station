// Bead `pow-n6n.2` (epic `pow-n6n`) - the four SEAT preference types at the six
// spawn sites, and the critics' lane routing (ADR-0006 D2/D4) - plus the OPEN
// seat set: a seat type declared OUTSIDE the pack mounts and resolves through
// the same collection, and the four vended ones still compose byte-for-byte.
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
    // The discovery lens reads the session generation at its spawn edge (the
    // third freshness stamp it is told to copy into its report).
    SessionHandle: const SessionHandle('session-current'),
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

/// Runs [read] once, at build, over the mounted context (the
/// `typed_environment_test.dart` probe idiom).
class _Probe extends StatelessSeed {
  const _Probe(this.read);

  final void Function(TreeContext) read;

  @override
  Seed build(TreeContext context) {
    read(context);
    return const _Leaf();
  }
}

/// A FIFTH seat type, declared ENTIRELY here: `grid_assets` does not know it
/// exists and no field on `AgentArming` names it. It is the whole proof that
/// the seat set is open - it vends its own provider seed and rides the same
/// armed collection the four vended seats do.
class _FifthAgentEnvironment extends SeatPreference {
  const _FifthAgentEnvironment(super.entries);

  @override
  SingleChildSeed provider() => SeatProvider<_FifthAgentEnvironment>(this);
}

/// Every [SeatPreference] actually MOUNTED under [root], outermost first, read
/// off the branch spine itself rather than off any field map - so the probe
/// cannot re-encode the four seat names the provider just stopped enumerating.
///
/// One `SeatProvider` builds exactly one `InheritedSeed<T>`, and
/// `CriticEnvironmentSeed` IS an `InheritedSeed<CriticAgentEnvironment>`, so
/// the single covariant test below sees every armed seat and nothing else (a
/// generic `InheritedSeed<ModelPreference>` is a SUPERtype and does not match).
List<SeatPreference> _mountedSeats(Branch root) {
  final found = <SeatPreference>[];
  void walk(Branch branch) {
    final seed = branch.seed;
    if (seed is InheritedSeed<SeatPreference>) found.add(seed.value);
    branch.visitChildren(walk);
  }

  walk(root);
  return found;
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

/// Hosts a SWAPPABLE [CriticAgentEnvironment] over a REAL
/// [TypedEnvironmentProvider]: `TreeOwner` has no `updateRoot`, so the
/// republish rides `setState`. Routing through the provider is the point -
/// a plain `InheritedSeed` link would fail the aspect contract below.
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
  Seed build(TreeContext context) => TypedEnvironmentProvider(
    arming: <SeatPreference>[_value],
    child: seed.child,
  );
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

  group('pow-ycoi - the seat set is OPEN', () {
    // The four vended seats, authored exactly as a station cans them.
    const vended = AgentArming(
      build: BuildAgentEnvironment([_strong]),
      spec: SpecAgentEnvironment([_strong]),
      critic: CriticAgentEnvironment([_shared]),
      gather: GatherAgentEnvironment([_fast]),
    );
    const fifth = _FifthAgentEnvironment([_fast]);

    test('a fifth seat type mounts through the open collection', () {
      AgentEnvironment? observed;
      final owner = TreeOwner();
      owner.mountRoot(
        InheritedSeed<AvailableEnvironments>(
          value: AvailableEnvironments({_fast}),
          child: TypedEnvironmentProvider(
            arming: const <SeatPreference>[fifth],
            child: _Probe(
              (context) => observed =
                  resolveEnvironment<_FifthAgentEnvironment>(context),
            ),
          ),
        ),
      );
      owner.flush();
      expect(observed, _fast);
    });

    test('AgentArming and Nest preserve declaration order and type names', () {
      final owner = TreeOwner();
      final root = owner.mountRoot(
        TypedEnvironmentProvider(
          // A vended arming SPREAD beside a seat the pack never heard of.
          arming: <SeatPreference>[...vended, fifth],
          child: const _Leaf(),
        ),
      );
      owner.flush();
      final mounted = _mountedSeats(root);
      expect(mounted, <SeatPreference>[
        vended.build!,
        vended.spec!,
        vended.critic!,
        vended.gather!,
        fifth,
      ]);
      expect(
        mounted.map((seat) => seat.runtimeType.toString()).toList(),
        <String>[
          'BuildAgentEnvironment',
          'SpecAgentEnvironment',
          'CriticAgentEnvironment',
          'GatherAgentEnvironment',
          '_FifthAgentEnvironment',
        ],
      );
    });

    test('four-seat AgentArming preserves the vended composition', () {
      SeatEnvironments? observed;
      final owner = TreeOwner();
      owner.mountRoot(
        InheritedSeed<EnvironmentRegistry>(
          value: _registry,
          child: TypedEnvironmentProvider(
            arming: vended,
            child: _Probe((context) => observed = SeatEnvironments.of(context)),
          ),
        ),
      );
      owner.flush();
      expect(
        observed,
        const SeatEnvironments(
          build: _strong,
          spec: _strong,
          critic: _shared,
          gather: _fast,
        ),
      );
    });
  });

  group('pow-n6n.2 - the lane ASPECT narrows invalidation', () {
    test('the provider preserves critic lane-scoped invalidation', () {
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
