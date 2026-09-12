// Bead `pow-n6n.2` (epic `pow-n6n`) - the four SEAT preference types at the six
// spawn sites, and the critics' lane routing (ADR-0006 D2/D4) - plus the OPEN
// seat set: a seat type declared OUTSIDE the pack mounts and resolves through
// the same collection, and the four vended ones still compose byte-for-byte.
//
// Pure-Dart, offline: the synthetic workspace dir never exists on disk, so the
// spawners' filesystem probes no-op (the documented offline posture of
// `model_ladder_test.dart`) - the lone exception is the GATING lane, which
// stamps its Validation Plan to a file at spawn and so rides a temp dir. The
// models below are deliberately NOT the tier defaults (opus/sonnet/haiku), so a
// typed win is distinguishable from the tier floor by the `--model` argv alone.
import 'dart:io';

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

/// The four VENDED seats, authored exactly as a station cans them.
const AgentArming _vended = AgentArming(
  build: BuildAgentEnvironment([_strong]),
  spec: SpecAgentEnvironment([_strong]),
  critic: CriticAgentEnvironment([_shared]),
  gather: GatherAgentEnvironment([_fast]),
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
      // A REAL workspace: unlike every seat probe above, this lane stamps the
      // bead's Validation Plan to a file at spawn.
      final dir = Directory.systemTemp.createTempSync('seat-gating-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final gating = const CriticCapability().spawn(
        FakeTreeContext(
          values: {
            Bead: bead(
              'tg-1',
            ).copyWith(metadata: const {'validation_plan': 'dart analyze'}),
            Workspace: testWorkspace(
              'tg-1',
              workspaceDir: dir.path,
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
          arming: <SeatPreference>[..._vended, fifth],
          child: const _Leaf(),
        ),
      );
      owner.flush();
      final mounted = _mountedSeats(root);
      expect(mounted, <SeatPreference>[
        _vended.build!,
        _vended.spec!,
        _vended.critic!,
        _vended.gather!,
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
            arming: _vended,
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

  group('pow-dbss - the relay seat is armed by presence', () {
    const mission =
        'Sense one session and decide whether to absorb or escalate.';
    const tools = {
      'worktree.read',
      'flares.read',
      'telemetry.read',
      'gates.read',
      'verdict.write',
    };
    const relay = RelayAgentEnvironment(
      [_fast],
      mission: mission,
      tools: tools,
      ceiling: 2,
    );

    test('a mounted relay is present and resolves only its own entries', () {
      RelayAgentEnvironment? seat;
      AgentEnvironment? resolved;
      final owner = TreeOwner();
      owner.mountRoot(
        InheritedSeed<AvailableEnvironments>(
          value: AvailableEnvironments({_fast, _strong}),
          child: InheritedSeed<ModelPreference>(
            // The station default, present and preferring the OTHER model.
            value: const ModelPreference([_strong]),
            child: TypedEnvironmentProvider(
              arming: <SeatPreference>[..._vended, relay],
              child: _Probe((context) {
                seat = RelayAgentEnvironment.of(context);
                resolved = RelayAgentEnvironment.environmentOf(context);
              }),
            ),
          ),
        ),
      );
      owner.flush();
      expect(seat, relay);
      expect(resolved, _fast, reason: 'the relay walked its OWN entries');
    });

    test('an absent relay is null even with a generic mounted', () {
      var read = false;
      RelayAgentEnvironment? seat;
      AgentEnvironment? resolved;
      AgentEnvironment? manufactured;
      final owner = TreeOwner();
      owner.mountRoot(
        InheritedSeed<AvailableEnvironments>(
          value: AvailableEnvironments({_fast, _strong}),
          child: InheritedSeed<ModelPreference>(
            value: const ModelPreference([_strong]),
            child: TypedEnvironmentProvider(
              // Every VENDED seat armed, and no relay among them.
              arming: _vended,
              child: _Probe((context) {
                read = true;
                seat = RelayAgentEnvironment.of(context);
                resolved = RelayAgentEnvironment.environmentOf(context);
                // What the GENERIC fallback would have handed back, had the
                // relay been read the way a resolved seat is.
                manufactured = resolveEnvironment<RelayAgentEnvironment>(
                  context,
                );
              }),
            ),
          ),
        ),
      );
      owner.flush();
      expect(read, isTrue, reason: 'the probe never built');
      expect(seat, isNull);
      expect(resolved, isNull);
      expect(
        manufactured,
        _strong,
        reason: 'the generic WOULD have manufactured a relay',
      );
    });

    test('arming a relay leaves the four-seat projection unchanged', () {
      SeatEnvironments? observed;
      final owner = TreeOwner();
      owner.mountRoot(
        InheritedSeed<EnvironmentRegistry>(
          value: _registry,
          child: TypedEnvironmentProvider(
            arming: <SeatPreference>[..._vended, relay],
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

    test('declaration order ends with the relay type', () {
      final owner = TreeOwner();
      final root = owner.mountRoot(
        TypedEnvironmentProvider(
          arming: <SeatPreference>[..._vended, relay],
          child: const _Leaf(),
        ),
      );
      owner.flush();
      final mounted = _mountedSeats(root);
      expect(mounted, <SeatPreference>[
        _vended.build!,
        _vended.spec!,
        _vended.critic!,
        _vended.gather!,
        relay,
      ]);
      expect(
        mounted.map((seat) => seat.runtimeType.toString()).toList(),
        <String>[
          'BuildAgentEnvironment',
          'SpecAgentEnvironment',
          'CriticAgentEnvironment',
          'GatherAgentEnvironment',
          'RelayAgentEnvironment',
        ],
      );
    });

    test('value equality includes entries, mission, tools and ceiling', () {
      // A DISTINCT instance: the same value with the tools authored in the
      // other order, so the equality below cannot ride const canonicalization.
      final reordered = RelayAgentEnvironment(
        const [_fast],
        mission: mission,
        tools: {
          'verdict.write',
          'gates.read',
          'telemetry.read',
          'flares.read',
          'worktree.read',
        },
        ceiling: 2,
      );
      expect(identical(reordered, relay), isFalse);
      expect(reordered, relay);
      expect(reordered.hashCode, relay.hashCode);

      const varied = <String, RelayAgentEnvironment>{
        'entries': RelayAgentEnvironment(
          [_strong],
          mission: mission,
          tools: tools,
          ceiling: 2,
        ),
        'mission': RelayAgentEnvironment(
          [_fast],
          mission: 'Escalate everything.',
          tools: tools,
          ceiling: 2,
        ),
        'tools': RelayAgentEnvironment(
          [_fast],
          mission: mission,
          tools: {'worktree.read'},
          ceiling: 2,
        ),
        'ceiling': RelayAgentEnvironment(
          [_fast],
          mission: mission,
          tools: tools,
          ceiling: 3,
        ),
      };
      varied.forEach((axis, other) {
        expect(relay, isNot(other), reason: 'a $axis-only change is a VALUE');
      });

      expect(relay, isNot(const ModelPreference([_fast])));
    });

    test('the relay ceiling is a carried positive value', () {
      expect(relay.ceiling, 2);
      expect(
        () => RelayAgentEnvironment(
          const [_fast],
          mission: mission,
          tools: tools,
          ceiling: 0,
        ),
        throwsA(isA<AssertionError>()),
        reason: 'an unbounded relay population is its own failure',
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
