// Bead `pow-q6bq` — the PROTECTIVE RELAY asset: a cheap-model brief plus a
// read-only tool set that inspects one stuck session and answers absorb-with-
// horizon or escalate.
//
// Six tables:
//
//  - AC-1  the asset arms exactly one observer from the tree — exact seat, the
//          seat's OWN entries, the seat's independent ceiling, the four readers
//          once each, the loud tool-set guard, the identity-bound registration
//          lifetime, and a source boundary that reaches no writer, store or
//          process;
//  - AC-2  a healthy thirty-hour build absorbs for six hours;
//  - AC-3  a paused session two days stale escalates;
//  - AC-4  a session parked on a human gate absorbs for a day;
//  - AC-5  an erroring lane escalates;
//  - AC-6  a read, inference or decode failure reaches the REAL engine as one
//          `relay.error` flare with no horizon written — never an absorb.
//
// Fakes, not mocks: the four readers and the inference seam are hand-written
// recorders. No process is spawned, no model is called, and the only file this
// suite reads is the asset's own source (off `packageRoot()`, never the process
// working directory).
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_root.dart';

/// Ends every probe tree (the `typed_environment_test.dart` idiom).
class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const []);
}

/// Records that it built — the leaf that proves the asset passed its child on.
class _Probe extends StatelessSeed {
  const _Probe(this.onBuild);
  final void Function() onBuild;

  @override
  Seed build(TreeContext context) {
    onBuild();
    return const _Leaf();
  }
}

/// A rebuildable root: `swap` re-describes the subtree in place, so an ambient
/// value can change without a second `mountRoot` (the
/// `track_f_composition_assets_test.dart` idiom).
class _Host extends StatefulSeed {
  const _Host({required this.onCreate, required this.describe});
  final void Function(_HostState) onCreate;
  final Seed Function() describe;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  Seed Function()? _next;

  @override
  void initState() => seed.onCreate(this);

  void swap(Seed Function() describe) => setState(() => _next = describe);

  @override
  Seed build(TreeContext context) => (_next ?? seed.describe)();
}

/// One mount this registrar handed out, and the log position it took.
class _Mount implements RelayRegistration {
  _Mount(this.observer, this.ceiling, this._log);

  final RelayObserver observer;
  final int ceiling;
  final List<String> _log;
  var disposals = 0;
  bool get disposed => disposals > 0;

  @override
  void dispose() {
    disposals++;
    _log.add('dispose');
  }
}

/// A Fake [RelayRegistrar] that enforces the engine's own one-relay-at-a-time
/// rule, so "disposed BEFORE the replacement mounts" is proven by construction
/// rather than by reading the log alone.
class _RecordingRegistrar implements RelayRegistrar {
  final List<_Mount> mounts = <_Mount>[];
  final List<String> log = <String>[];

  Iterable<_Mount> get live => mounts.where((mount) => !mount.disposed);

  @override
  RelayRegistration mountRelay({
    required RelayObserver observer,
    required int ceiling,
  }) {
    if (live.isNotEmpty) throw StateError('A relay is already mounted');
    log.add('mount:$ceiling');
    final mount = _Mount(observer, ceiling, log);
    mounts.add(mount);
    return mount;
  }
}

/// The four read tools over ONE recorded snapshot, counting every call. A
/// reader named in [failing] throws instead of answering.
class _RecordingTools {
  _RecordingTools(this.snapshot, {this.failing = const <String>{}});

  final RelaySessionSnapshot snapshot;
  final Set<String> failing;
  final List<String> calls = <String>[];

  RelayReadTools get tools => RelayReadTools(
    readWorktree: (observation) async {
      calls.add(kRelayWorktreeReadTool);
      _maybeFail(kRelayWorktreeReadTool);
      return snapshot.worktree;
    },
    readFlareTail: (observation) async {
      calls.add(kRelayFlaresReadTool);
      _maybeFail(kRelayFlaresReadTool);
      return snapshot.flares;
    },
    readTelemetry: (observation) async {
      calls.add(kRelayTelemetryReadTool);
      _maybeFail(kRelayTelemetryReadTool);
      return snapshot.telemetry;
    },
    readGate: (observation) async {
      calls.add(kRelayGatesReadTool);
      _maybeFail(kRelayGatesReadTool);
      return snapshot.openGate;
    },
  );

  void _maybeFail(String tool) {
    if (failing.contains(tool)) throw StateError('$tool is unreachable');
  }
}

/// The inference seam: records what it was asked and answers a RECORDED string
/// (or throws, for the failure table).
class _FakeRelayRunner implements RelayInferenceRunner {
  _FakeRelayRunner({this.answer = '', this.failure});

  final String answer;
  final Object? failure;
  final List<AgentBrief> briefs = <AgentBrief>[];
  final List<AgentEnvironment> environments = <AgentEnvironment>[];

  @override
  Future<String> run({
    required AgentEnvironment environment,
    required AgentBrief brief,
  }) async {
    environments.add(environment);
    briefs.add(brief);
    final blow = failure;
    if (blow != null) throw blow;
    return answer;
  }
}

/// Records every flare the engine emits.
class _RecordingTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares =
      <({String name, Map<String, String> data})>[];

  @override
  void flare(String name, Map<String, String> data) =>
      flares.add((name: name, data: Map<String, String>.of(data)));
}

const AgentEnvironment _cheap = AgentEnvironment(
  command: 'claude',
  model: 'haiku',
  target: InferenceTarget.providerManaged,
);
const AgentEnvironment _strong = AgentEnvironment(
  command: 'claude',
  model: 'opus',
  target: InferenceTarget.providerManaged,
);

const String _mission =
    'Sense one work session and decide whether the station must change its '
    'desired state for it.';

/// The ARMED relay: cheap first, the exact allow list, its own ceiling.
const RelayAgentEnvironment _seat = RelayAgentEnvironment(
  [_cheap, _strong],
  mission: _mission,
  tools: kRelayToolAllowList,
  ceiling: 3,
);

final DateTime _observedAt = DateTime.utc(2026, 9, 15, 12);

RelayObservation _observation({DateTime? startedAt}) => RelayObservation(
  sessionId: 'tgdog-sess1',
  workBeadId: 'pow-1',
  startedAt: startedAt,
  deadline: _observedAt.subtract(const Duration(minutes: 5)),
  observedAt: _observedAt,
);

/// One recorded session snapshot.
RelaySessionSnapshot _snapshot({
  required RelayObservation observation,
  required Map<String, DateTime> mtimes,
  required String lastCommit,
  required DateTime lastCommitAt,
  List<RelayFlareRecord> flares = const <RelayFlareRecord>[],
  List<RelayTelemetryRecord> telemetry = const <RelayTelemetryRecord>[],
  RelayGateRecord? openGate,
}) => RelaySessionSnapshot(
  observation: observation,
  worktree: RelayWorktreeSnapshot(
    mtimes: mtimes,
    lastCommit: lastCommit,
    lastCommitAt: lastCommitAt,
  ),
  flares: flares,
  telemetry: telemetry,
  openGate: openGate,
);

/// Every brief this relay ever renders owes the same contract, whatever the
/// evidence: the mission, the complete canonical evidence, the exact allow
/// list, the absorb default, the breaker prohibition, the failure rule, and the
/// two answer shapes.
void _assertBriefContract(AgentBrief brief, RelaySessionSnapshot snapshot) {
  final rendered = brief.render();
  expect(rendered, contains(_mission));
  expect(
    rendered,
    contains(jsonEncode(snapshot.toJson())),
    reason: 'the brief carries the COMPLETE canonical evidence',
  );
  for (final tool in kRelayToolAllowList) {
    expect(rendered, contains(tool));
  }
  expect(rendered, contains('ABSORB IS THE DEFAULT'));
  expect(rendered, contains('ESCALATION IS EXCEPTIONAL'));
  expect(rendered, contains('NEVER the breaker'));
  expect(rendered, contains('IF YOU CANNOT ANSWER, FAIL'));
  expect(
    rendered,
    contains('{"verdict":"absorb","nextHorizonSeconds":<positive integer>}'),
  );
  expect(
    rendered,
    contains('{"verdict":"escalate","reason":"<nonblank string>"}'),
  );
}

/// The subtree under test: a scope, the registrar provider (unless
/// [registrar] is null), the presence set, a generic preference that prefers
/// the OTHER environment, the arming, and the asset.
Seed _armed({
  required _RecordingRegistrar? registrar,
  required RelayReadTools tools,
  required RelayInferenceRunner runner,
  RelayAgentEnvironment? seat = _seat,
  Set<AgentEnvironment>? available,
  Seed below = const _Leaf(),
}) {
  final Seed armed = InheritedSeed<AvailableEnvironments>(
    value: AvailableEnvironments(available ?? {_cheap, _strong}),
    child: InheritedSeed<ModelPreference>(
      // The station default, present and preferring the OTHER model: a relay
      // must never be manufactured out of it.
      value: const ModelPreference([_strong]),
      child: Nest(
        children: [
          for (final seat in <SeatPreference>[if (seat != null) seat])
            seat.provider(),
        ],
        child: RelayAssets(tools: tools, runner: runner, child: below),
      ),
    ),
  );
  return registrar == null
      ? armed
      : Provider<RelayRegistrar>.value(registrar, child: armed);
}

/// Lets every pending microtask and zero-duration timer settle.
Future<void> _drain() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('AC-1 — the relay asset arms exactly one observer from the tree', () {
    test('a generic preference alone arms nothing', () {
      final registrar = _RecordingRegistrar();
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        ProviderScope(
          child: _armed(
            registrar: registrar,
            tools: _RecordingTools(
              _snapshot(
                observation: _observation(),
                mtimes: {'lib/a.dart': _observedAt},
                lastCommit: 'abc',
                lastCommitAt: _observedAt,
              ),
            ).tools,
            runner: _FakeRelayRunner(),
            // No EXACT relay in the arming; the generic ModelPreference above
            // is still mounted and still prefers a PRESENT environment.
            seat: null,
          ),
        ),
      );
      owner.flush();
      expect(registrar.mounts, isEmpty);
      expect(registrar.log, isEmpty);
    });

    test('an armed seat whose own entries are absent arms nothing', () {
      final registrar = _RecordingRegistrar();
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        ProviderScope(
          child: _armed(
            registrar: registrar,
            tools: _RecordingTools(
              _snapshot(
                observation: _observation(),
                mtimes: {'lib/a.dart': _observedAt},
                lastCommit: 'abc',
                lastCommitAt: _observedAt,
              ),
            ).tools,
            runner: _FakeRelayRunner(),
            seat: const RelayAgentEnvironment(
              [_cheap],
              mission: _mission,
              tools: kRelayToolAllowList,
              ceiling: 1,
            ),
            // Only the environment the GENERIC prefers is present.
            available: {_strong},
          ),
        ),
      );
      owner.flush();
      expect(
        registrar.mounts,
        isEmpty,
        reason: 'the walk runs over the SEAT\'s own entries',
      );
    });

    test('an armed seat with no registrar above arms nothing', () {
      final tools = _RecordingTools(
        _snapshot(
          observation: _observation(),
          mtimes: {'lib/a.dart': _observedAt},
          lastCommit: 'abc',
          lastCommitAt: _observedAt,
        ),
      );
      final runner = _FakeRelayRunner();
      var built = false;
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        ProviderScope(
          child: _armed(
            registrar: null,
            tools: tools.tools,
            runner: runner,
            below: _Probe(() => built = true),
          ),
        ),
      );
      // The tree STANDS — the child below the asset still builds — and nothing
      // was armed to absorb the signal, so the engine's `relay.absent` path
      // stays live all the way to the governor.
      expect(owner.flush, returnsNormally);
      expect(built, isTrue, reason: 'the asset passes its child through');
      expect(tools.calls, isEmpty);
      expect(runner.briefs, isEmpty);
    });

    test(
      'an armed seat mounts ONE observer under the seat ceiling, and that '
      'observer reaches the selected environment through every reader once',
      () async {
        final registrar = _RecordingRegistrar();
        final observation = _observation(
          startedAt: _observedAt.subtract(const Duration(hours: 2)),
        );
        final snapshot = _snapshot(
          observation: observation,
          mtimes: {
            'lib/a.dart': _observedAt.subtract(const Duration(minutes: 1)),
          },
          lastCommit: 'feat: a thing',
          lastCommitAt: _observedAt.subtract(const Duration(minutes: 3)),
        );
        final tools = _RecordingTools(snapshot);
        final runner = _FakeRelayRunner(
          answer: '{"verdict":"absorb","nextHorizonSeconds":900}',
        );
        final owner = TreeOwner();
        addTearDown(owner.dispose);
        owner.mountRoot(
          ProviderScope(
            child: _armed(
              registrar: registrar,
              tools: tools.tools,
              runner: runner,
            ),
          ),
        );
        owner.flush();

        expect(registrar.mounts, hasLength(1));
        expect(
          registrar.mounts.single.ceiling,
          3,
          reason: 'the relay rides the SEAT\'s independent ceiling',
        );

        final verdict = await registrar.mounts.single.observer.observe(
          observation,
        );
        expect(
          verdict,
          const RelayVerdict.absorb(nextHorizon: Duration(minutes: 15)),
        );
        expect(runner.environments, [_cheap]);
        expect(tools.calls..sort(), [
          kRelayFlaresReadTool,
          kRelayGatesReadTool,
          kRelayTelemetryReadTool,
          kRelayWorktreeReadTool,
        ]);
        _assertBriefContract(runner.briefs.single, snapshot);
      },
    );

    test('a snapshot copies its collections and refuses mutation', () {
      final mtimes = <String, DateTime>{'lib/a.dart': _observedAt};
      final flares = <RelayFlareRecord>[
        RelayFlareRecord(
          occurredAt: _observedAt,
          name: 'step.start',
          data: <String, String>{'node': 'pow-1/agent'},
        ),
      ];
      final telemetry = <RelayTelemetryRecord>[
        RelayTelemetryRecord(
          nodePath: 'pow-1/agent',
          usage: <String, String>{'input_tokens': '10'},
        ),
      ];
      final snapshot = _snapshot(
        observation: _observation(),
        mtimes: mtimes,
        lastCommit: 'abc',
        lastCommitAt: _observedAt,
        flares: flares,
        telemetry: telemetry,
      );

      // Mutating the SOURCES after construction cannot reach the value.
      mtimes['lib/b.dart'] = _observedAt;
      flares.clear();
      telemetry.clear();
      expect(snapshot.worktree.mtimes.keys, ['lib/a.dart']);
      expect(snapshot.flares, hasLength(1));
      expect(snapshot.telemetry, hasLength(1));

      // And the value itself refuses every mutation.
      expect(
        () => snapshot.worktree.mtimes['lib/c.dart'] = _observedAt,
        throwsUnsupportedError,
      );
      expect(() => snapshot.flares.clear(), throwsUnsupportedError);
      expect(() => snapshot.telemetry.clear(), throwsUnsupportedError);
      expect(
        () => snapshot.flares.single.data['x'] = 'y',
        throwsUnsupportedError,
      );
      expect(
        () => snapshot.telemetry.single.usage['x'] = 'y',
        throwsUnsupportedError,
      );
    });

    test('inspect refuses a tool set that is not the allow list, '
        'before any read', () async {
      final tools = _RecordingTools(
        _snapshot(
          observation: _observation(),
          mtimes: {'lib/a.dart': _observedAt},
          lastCommit: 'abc',
          lastCommitAt: _observedAt,
        ),
      );
      final short = {...kRelayToolAllowList}..remove(kRelayGatesReadTool);
      await expectLater(
        tools.tools.inspect(observation: _observation(), toolNames: short),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        tools.tools.inspect(
          observation: _observation(),
          toolNames: {...kRelayToolAllowList, 'session.close'},
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        tools.calls,
        isEmpty,
        reason: 'the guard refuses BEFORE a reader runs',
      );
    });

    test('a changed identity disposes the old registration before the '
        'replacement mounts, and disposes exactly once', () {
      final registrar = _RecordingRegistrar();
      final tools = _RecordingTools(
        _snapshot(
          observation: _observation(),
          mtimes: {'lib/a.dart': _observedAt},
          lastCommit: 'abc',
          lastCommitAt: _observedAt,
        ),
      ).tools;
      final runner = _FakeRelayRunner();
      late _HostState host;
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        ProviderScope(
          child: _Host(
            onCreate: (state) => host = state,
            describe: () =>
                _armed(registrar: registrar, tools: tools, runner: runner),
          ),
        ),
      );
      owner.flush();
      expect(registrar.log, ['mount:3']);

      // An EQUAL seat re-provided is not a new identity: nothing churns.
      host.swap(
        () => _armed(registrar: registrar, tools: tools, runner: runner),
      );
      owner.flush();
      expect(registrar.log, ['mount:3']);

      // A DIFFERENT seat is: the registrar admits one relay at a time, so a
      // replacement that mounted before the dispose would throw here.
      const replacement = RelayAgentEnvironment(
        [_cheap],
        mission: 'A narrower charter.',
        tools: kRelayToolAllowList,
        ceiling: 1,
      );
      host.swap(
        () => _armed(
          registrar: registrar,
          tools: tools,
          runner: runner,
          seat: replacement,
        ),
      );
      owner.flush();
      expect(registrar.log, ['mount:3', 'dispose', 'mount:1']);
      expect(registrar.mounts, hasLength(2));
      expect(registrar.mounts.first.disposals, 1);
      expect(registrar.live, hasLength(1));

      // Disarming the seat unmounts and leaves nothing behind.
      host.swap(
        () => _armed(
          registrar: registrar,
          tools: tools,
          runner: runner,
          seat: null,
        ),
      );
      owner.flush();
      expect(registrar.live, isEmpty);
      expect(registrar.mounts.last.disposals, 1);

      // Tearing the tree down disposes no second time.
      owner.dispose();
      expect(registrar.mounts.map((mount) => mount.disposals), [1, 1]);
    });

    test('the asset source reaches no writer, store, process or file', () {
      final source = File(
        p.join(packageRoot(), 'lib', 'src', 'agent', 'relay_assets.dart'),
      ).readAsStringSync();
      expect(source, isNot(contains("import 'dart:io'")));
      expect(source, isNot(contains('beads_dart')));
      for (final banned in const [
        'StationBeadWriter',
        'BdCliService',
        'BdRunner',
        'writeAsString',
        'Process.start',
      ]) {
        expect(
          source,
          isNot(contains(banned)),
          reason: 'a relay decides; it is never the breaker ($banned)',
        );
      }
    });
  });

  group('AC-2 — a healthy long build absorbs', () {
    test('thirty hours in, with a two-minute-old worktree and continuing '
        'usage, the verdict is absorb for six hours', () async {
      final observation = _observation(
        startedAt: _observedAt.subtract(const Duration(hours: 30)),
      );
      final snapshot = _snapshot(
        observation: observation,
        mtimes: {
          'lib/src/feature.dart': _observedAt.subtract(
            const Duration(minutes: 2),
          ),
          'test/feature_test.dart': _observedAt.subtract(
            const Duration(minutes: 9),
          ),
        },
        lastCommit: 'feat(feature): land the third slice',
        lastCommitAt: _observedAt.subtract(const Duration(minutes: 41)),
        telemetry: [
          RelayTelemetryRecord(
            nodePath: 'pow-1/agent',
            usage: const {'input_tokens': '412003', 'output_tokens': '18220'},
          ),
        ],
      );
      final runner = _FakeRelayRunner(
        answer: '{"verdict":"absorb","nextHorizonSeconds":21600}',
      );
      final tools = _RecordingTools(snapshot);
      final verdict = await RelayAgentObserver(
        seat: _seat,
        environment: _cheap,
        tools: tools.tools,
        runner: runner,
      ).observe(observation);

      expect(runner.environments, [_cheap]);
      _assertBriefContract(runner.briefs.single, snapshot);
      switch (verdict) {
        case RelayAbsorb(:final nextHorizon):
          expect(nextHorizon, const Duration(hours: 6));
        case RelayEscalate(:final reason):
          fail('a healthy long build must absorb; it escalated: $reason');
      }
    });
  });

  group('AC-3 — a two-day-stale paused worktree escalates', () {
    test('nothing has moved in the worktree or the log for two days', () async {
      final twoDaysAgo = _observedAt.subtract(const Duration(days: 2));
      final observation = _observation(
        startedAt: _observedAt.subtract(const Duration(days: 3)),
      );
      final snapshot = _snapshot(
        observation: observation,
        mtimes: {
          'lib/src/feature.dart': twoDaysAgo,
          'README.md': twoDaysAgo.subtract(const Duration(hours: 6)),
        },
        lastCommit: 'wip: half a slice',
        lastCommitAt: twoDaysAgo,
        flares: [
          RelayFlareRecord(
            occurredAt: twoDaysAgo,
            name: 'session.paused',
            data: const {'sessionId': 'tgdog-sess1'},
          ),
        ],
      );
      const reason =
          'the newest worktree mtime and the last commit are both two days '
          'old: this session is stopped, not slow';
      final runner = _FakeRelayRunner(
        answer: jsonEncode(<String, Object?>{
          'verdict': 'escalate',
          'reason': reason,
        }),
      );
      final verdict = await RelayAgentObserver(
        seat: _seat,
        environment: _cheap,
        tools: _RecordingTools(snapshot).tools,
        runner: runner,
      ).observe(observation);

      expect(runner.environments, [_cheap]);
      _assertBriefContract(runner.briefs.single, snapshot);
      switch (verdict) {
        case RelayAbsorb(:final nextHorizon):
          fail('a stopped session must escalate; it absorbed for $nextHorizon');
        case RelayEscalate(:final reason):
          expect(reason.trim(), isNotEmpty);
          expect(reason, contains('two days'));
      }
    });
  });

  group('AC-4 — a session parked on a human absorbs', () {
    test('an open gate awaiting a human absorbs for a day', () async {
      final observation = _observation(
        startedAt: _observedAt.subtract(const Duration(hours: 50)),
      );
      final snapshot = _snapshot(
        observation: observation,
        mtimes: {
          'lib/src/feature.dart': _observedAt.subtract(
            const Duration(hours: 20),
          ),
        },
        lastCommit: 'feat(feature): the round under review',
        lastCommitAt: _observedAt.subtract(const Duration(hours: 20)),
        openGate: const RelayGateRecord(
          id: 'pow-1/gate',
          reason: 'breaker exhausted; a human owns this round',
          awaitingHuman: true,
        ),
      );
      final runner = _FakeRelayRunner(
        answer: '{"verdict":"absorb","nextHorizonSeconds":86400}',
      );
      final verdict = await RelayAgentObserver(
        seat: _seat,
        environment: _cheap,
        tools: _RecordingTools(snapshot).tools,
        runner: runner,
      ).observe(observation);

      expect(runner.environments, [_cheap]);
      _assertBriefContract(runner.briefs.single, snapshot);
      expect(
        runner.briefs.single.render(),
        contains('"awaitingHuman":true'),
        reason: 'the gate is evidence the relay must see',
      );
      switch (verdict) {
        case RelayAbsorb(:final nextHorizon):
          expect(nextHorizon, const Duration(hours: 24));
        case RelayEscalate(:final reason):
          fail('a parked human gate must absorb; it escalated: $reason');
      }
    });
  });

  group('AC-5 — an erroring lane escalates', () {
    test('a lane-error flare plus error telemetry escalates with its '
        'reason', () async {
      final observation = _observation(
        startedAt: _observedAt.subtract(const Duration(hours: 4)),
      );
      final snapshot = _snapshot(
        observation: observation,
        mtimes: {
          'lib/src/feature.dart': _observedAt.subtract(
            const Duration(hours: 3),
          ),
        },
        lastCommit: 'wip: the lane that will not run',
        lastCommitAt: _observedAt.subtract(const Duration(hours: 3)),
        flares: [
          RelayFlareRecord(
            occurredAt: _observedAt.subtract(const Duration(minutes: 30)),
            name: 'step.error',
            data: const {
              'node': 'pow-1/code-validation',
              'reason': 'the harness exited 127',
            },
          ),
        ],
        telemetry: [
          RelayTelemetryRecord(
            nodePath: 'pow-1/code-validation',
            usage: const {'error': 'spawn failed', 'output_tokens': '0'},
          ),
        ],
      );
      const reason =
          'the code-validation lane is erroring: the harness exits 127 and no '
          'output is produced';
      final runner = _FakeRelayRunner(
        answer: jsonEncode(<String, Object?>{
          'verdict': 'escalate',
          'reason': reason,
        }),
      );
      final verdict = await RelayAgentObserver(
        seat: _seat,
        environment: _cheap,
        tools: _RecordingTools(snapshot).tools,
        runner: runner,
      ).observe(observation);

      expect(runner.environments, [_cheap]);
      _assertBriefContract(runner.briefs.single, snapshot);
      switch (verdict) {
        case RelayAbsorb(:final nextHorizon):
          fail('an erroring lane must escalate; it absorbed for $nextHorizon');
        case RelayEscalate(:final reason):
          expect(reason.trim(), isNotEmpty);
          expect(reason, contains('erroring'));
      }
    });
  });

  group('AC-6 — a relay that cannot answer FAILS, and the engine escalates '
      'it', () {
    final snapshot = _snapshot(
      observation: _observation(),
      mtimes: {'lib/a.dart': _observedAt},
      lastCommit: 'abc',
      lastCommitAt: _observedAt,
    );

    RelayAgentObserver observerOver({
      Set<String> failing = const <String>{},
      String answer = '',
      Object? runnerFailure,
    }) => RelayAgentObserver(
      seat: _seat,
      environment: _cheap,
      tools: _RecordingTools(snapshot, failing: failing).tools,
      runner: _FakeRelayRunner(answer: answer, failure: runnerFailure),
    );

    test('a failing reader completes the observation with an error', () {
      expect(
        observerOver(
          failing: const {kRelayWorktreeReadTool},
        ).observe(_observation()),
        throwsA(isA<StateError>()),
      );
    });

    test('a failing inference call completes the observation with an '
        'error', () {
      expect(
        observerOver(
          runnerFailure: StateError('the model never answered'),
        ).observe(_observation()),
        throwsA(isA<StateError>()),
      );
    });

    test('malformed and wrong-arm answers are refused, never absorbed', () {
      for (final malformed in const [
        'not json at all',
        '[]',
        '"absorb"',
        '{}',
        '{"verdict":"maybe","nextHorizonSeconds":60}',
        '{"verdict":"absorb"}',
        '{"verdict":"absorb","reason":"stale"}',
        '{"verdict":"absorb","nextHorizonSeconds":0}',
        '{"verdict":"absorb","nextHorizonSeconds":-60}',
        '{"verdict":"absorb","nextHorizonSeconds":"60"}',
        '{"verdict":"absorb","nextHorizonSeconds":60,"reason":"stale"}',
        '{"verdict":"escalate"}',
        '{"verdict":"escalate","nextHorizonSeconds":60}',
        '{"verdict":"escalate","reason":"   "}',
        '{"verdict":"escalate","reason":7}',
        '{"verdict":"escalate","reason":"stale","nextHorizonSeconds":60}',
        '```json\n{"verdict":"absorb","nextHorizonSeconds":60}\n```',
      ]) {
        expect(
          () => decodeRelayVerdict(malformed),
          throwsFormatException,
          reason: 'a relay never manufactures a verdict out of "$malformed"',
        );
      }
    });

    test('a strict answer decodes to the engine verdict', () {
      expect(
        decodeRelayVerdict('{"verdict":"absorb","nextHorizonSeconds":21600}'),
        const RelayVerdict.absorb(nextHorizon: Duration(hours: 6)),
      );
      expect(
        decodeRelayVerdict('{"verdict":"escalate","reason":" stale "}'),
        const RelayVerdict.escalate(reason: 'stale'),
      );
    });

    test('a malformed answer reaching the observer fails the observation', () {
      expect(
        observerOver(answer: 'I think it is fine?').observe(_observation()),
        throwsFormatException,
      );
    });

    test('mounted in the real engine, that failure is ONE relay.error flare '
        'with no horizon written', () async {
      final transport = _RecordingTransport();
      final horizons = <({String sessionId, DateTime at})>[];
      final now = _observedAt;
      final liveness = WorkSessionLiveness(
        writeHorizon: (sessionId, at) async =>
            horizons.add((sessionId: sessionId, at: at)),
        transport: transport,
        clock: () => now,
      );
      addTearDown(liveness.dispose);
      liveness.mountRelay(
        observer: observerOver(failing: const {kRelayTelemetryReadTool}),
        ceiling: _seat.ceiling,
      );
      liveness.refresh(
        JoinedSnapshot(
          graph: GraphSnapshot.fromParts(
            beads: const <Bead>[],
            dependencies: const <BeadDependency>[],
            readyIds: const <String>[],
            capturedAt: now,
          ),
          sessionsByWorkBead: {
            'pow-1': SessionProjection(
              workBeadId: 'pow-1',
              sessionId: 'tgdog-sess1',
              startedAt: now.subtract(const Duration(days: 3)),
              relayNextObservationAt: now.subtract(const Duration(hours: 1)),
            ),
          },
        ),
      );
      liveness.activate();
      liveness.onFencedTick();
      await _drain();

      expect(transport.flares.map((flare) => flare.name), [kRelayErrorFlare]);
      expect(transport.flares.single.data['sessionId'], 'tgdog-sess1');
      expect(horizons, isEmpty, reason: 'a failure writes NO horizon');
      expect(
        transport.flares.map((flare) => flare.name),
        isNot(contains(kRelayAbsentFlare)),
      );
    });
  });
}
