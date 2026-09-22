// Bead `pow-u1bi` — the station diagnoses its own agent environment.
//
// THE MEASURED INCIDENT (2026-09-21 23:22-23:50Z, lunar epoch 93): the global
// codex CLI moved to 0.155.1 at 23:22Z, and from 23:3xZ every codex session
// setup refused its pinned model. The station closed each affected session
// `held`, flared `failureClass=work`, and let the wedge counter read
// `0 running` — it attributed an ENVIRONMENT change to the WORK, one bead at a
// time. Every fact that actually diagnosed it (the binary version, its mtime
// five minutes before the first failure, the resolver's verdict on the offered
// catalog) a human read by hand.
//
// Fakes only; nothing here touches a machine, spawns a process, or mutates a
// bead, a gate or an operator surface.
import 'dart:async';
import 'dart:convert';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart'
    show
        CapabilityFailureKind,
        ProcessSessionCommand,
        ProcessSessionFailed;
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart' show Lifecycle, RuntimeConfig;
import 'package:test/test.dart';

/// Wraps a real coordinator and records WHEN each setup failure reached it, so
/// the ordering the session edge promises is asserted rather than assumed.
class _RecordingHealth implements LaneEnvironmentHealth {
  _RecordingHealth(this.inner);

  final CorrelatingLaneEnvironmentHealth inner;
  final List<LaneEnvironmentSetupFailure> recorded =
      <LaneEnvironmentSetupFailure>[];

  /// Whether the record completed while the session's terminal was still
  /// unpublished — the invariant that stops a third spawn.
  var recordedBeforeTerminal = false;
  var _terminalSeen = false;

  void sawTerminal() => _terminalSeen = true;

  @override
  Stream<LaneEnvironmentCondition> get conditions => inner.conditions;

  @override
  Future<LaneEnvironmentDiagnosis> recordSetupFailure(
    LaneEnvironmentSetupFailure failure, {
    LaneFlare? flare,
  }) async {
    recorded.add(failure);
    final diagnosis = await inner.recordSetupFailure(failure, flare: flare);
    recordedBeforeTerminal = !_terminalSeen;
    return diagnosis;
  }

  @override
  Future<bool> confirmScheduledRecovery({
    required String lane,
    required bool present,
  }) => inner.confirmScheduledRecovery(lane: lane, present: present);
}

/// Ends every probe tree (the `availability_seed_test.dart` idiom).
class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const []);
}

/// The codex lane as the builtins arm it: an `npx` launcher whose REAL binary
/// is `codex`, pinning the bare base id the seat's rung qualifies.
const AgentEnvironment _codex = AgentEnvironment(
  command: 'npx',
  args: <String>['-y', '@agentclientprotocol/codex-acp@1.6.2'],
  pathCheck: 'codex',
  promptMode: PromptMode.none,
  target: InferenceTarget.providerManaged,
  model: 'gpt-5.6-sol',
  sessionAdapter: kAcpSessionAdapterId,
);

/// A second lane, so a park can be shown to be a LANE and not the station.
const AgentEnvironment _claude = AgentEnvironment(
  command: 'claude',
  model: 'opus',
  target: InferenceTarget.providerManaged,
);

const EnvironmentRegistry _registry = EnvironmentRegistry(
  custom: <String, AgentEnvironment>{'codex': _codex, 'claude': _claude},
);

const LaneEnvironmentTarget _codexLane = LaneEnvironmentTarget(
  lane: 'codex',
  environment: _codex,
  tier: AgentTier.frontier,
  pin: 'gpt-5.6-sol',
);

/// The catalog codex-acp 0.155.1 actually offered: one id per reasoning effort
/// for the pinned base, and NOT the bare id the environment pins.
const List<String> _offered = <String>[
  'gpt-5.6-sol[low]',
  'gpt-5.6-sol[medium]',
  'gpt-5.6-sol[high-ish]',
  'gpt-5.6-sol[ultra]',
];

/// The binary as it was at 23:22Z — the moment the environment changed, five
/// minutes ahead of the first failure the station could see.
final LaneBinaryFingerprint _upgraded = LaneBinaryFingerprint(
  path: '/opt/homebrew/bin/codex',
  version: '0.155.1',
  mtime: DateTime.utc(2026, 9, 21, 23, 22),
);

LaneEnvironmentSetupFailure _setupRefusal() => const LaneEnvironmentSetupFailure(
  target: _codexLane,
  offered: _offered,
  pin: 'gpt-5.6-sol',
  resolverVerdict:
      'ACP agent does not offer pinned model "gpt-5.6-sol" at the '
      '"frontier" tier',
);

/// A scripted diagnostic probe: it answers whatever the test has armed, and
/// RECORDS every request so the targeted/scheduled split can be asserted.
class _FakeLaneProbe {
  _FakeLaneProbe({required this.binary});

  LaneBinaryFingerprint binary;
  var passes = false;
  var at = DateTime.utc(2026, 9, 21, 23, 35);
  final List<LaneEnvironmentProbeRequest> requests =
      <LaneEnvironmentProbeRequest>[];

  Future<LaneEnvironmentDiagnosis> call(
    LaneEnvironmentProbeRequest request,
  ) async {
    requests.add(request);
    return LaneEnvironmentDiagnosis(
      lane: request.target.lane,
      observedAt: at,
      binary: binary,
      pin: request.pin ?? request.target.pin,
      offered: request.offered,
      resolverVerdict: passes
          ? 'the pinned model resolves to "gpt-5.6-sol[high]"'
          : 'ACP agent does not offer pinned model "gpt-5.6-sol" at the '
                '"frontier" tier',
      passed: passes,
    );
  }
}

/// The ordinary boolean presence probe. It says YES throughout, which is the
/// whole point: in the live incident the binary was installed and the provider
/// was reachable the entire time.
class _PresentProbe {
  final List<String> calls = <String>[];

  Future<bool> call(EnvironmentProbeRequest request) async {
    calls.add(request.name);
    return true;
  }
}

/// A Fake schedule: captures the tick so the bounded re-probe FIRES on demand.
class _FakeSchedule implements ProbeTicker {
  void Function()? _onTick;

  ProbeTicker start(Duration period, void Function() onTick) {
    _onTick = onTick;
    return this;
  }

  void fire() => _onTick!();

  @override
  void cancel() {}
}

/// One supervision ROUND: bumping it is what asks the tree for another spawn.
class _Round {
  const _Round(this.number);
  final int number;

  @override
  bool operator ==(Object other) => other is _Round && other.number == number;

  @override
  int get hashCode => number;
}

/// Mounts [_Round] and lets the test ask for the next one.
class _RoundHost extends SingleChildStatefulSeed {
  const _RoundHost({required this.onCreate, super.child});
  final void Function(_RoundHostState) onCreate;

  @override
  SingleChildState<_RoundHost> createState() => _RoundHostState();
}

class _RoundHostState extends SingleChildState<_RoundHost> {
  var _round = 1;

  @override
  void initState() => seed.onCreate(this);

  void nextRound() => setState(() => _round += 1);

  @override
  Seed buildWithChild(TreeContext context, Seed child) =>
      InheritedSeed<_Round>(value: _Round(_round), child: child);
}

/// The WORK held behind the codex lane: a branch that SUBSCRIBES to the ambient
/// presence set and mints a spawn for its round when its seat resolves.
///
/// It performs no bead, gate or operator mutation — it records what it WOULD
/// have spawned, which is exactly the question the incident got wrong.
class _HeldWork extends StatelessSeed {
  const _HeldWork(this.mints, this.observed);

  /// The round number of each spawn this branch minted, one per round.
  final List<int> mints;

  /// What the seat resolved to on every build, null when nothing is available.
  final List<AgentEnvironment?> observed;

  @override
  Seed build(TreeContext context) {
    final round = context.dependOnInheritedSeedOfExactType<_Round>()!.number;
    final available =
        context.dependOnInheritedSeedOfExactType<AvailableEnvironments>() ??
        AvailableEnvironments.none;
    final seat = firstAvailableFrom(
      const ModelPreference(<AgentEnvironment>[_codex]),
      available,
    );
    observed.add(seat);
    if (seat != null && (mints.isEmpty || mints.last != round)) {
      mints.add(round);
    }
    return const _Leaf();
  }
}

typedef _Mounted = ({
  TreeOwner owner,
  List<int> mints,
  List<AgentEnvironment?> observed,
  _RoundHostState rounds,
});

Future<_Mounted> _mount({
  required _PresentProbe presence,
  required _FakeSchedule schedule,
  required LaneEnvironmentHealth health,
}) async {
  final mints = <int>[];
  final observed = <AgentEnvironment?>[];
  late final _RoundHostState rounds;
  final owner = TreeOwner();
  owner.mountRoot(
    InheritedSeed<EnvironmentRegistry>(
      value: _registry,
      child: AvailabilityAssets(
        probe: presence.call,
        schedule: schedule.start,
        laneHealth: health,
        child: _RoundHost(
          onCreate: (state) => rounds = state,
          child: _HeldWork(mints, observed),
        ),
      ),
    ),
  );
  owner.flush();
  await _settle(owner);
  return (owner: owner, mints: mints, observed: observed, rounds: rounds);
}

/// Drains the in-flight probe pass and flushes what it dirtied.
///
/// THREE pumps because a lane condition adds one more asynchronous hop than a
/// plain probe pass: the coordinator publishes on a broadcast stream, the
/// availability seed's subscription mints a new pass marker, and only the pass
/// that marker delivers republishes the narrowed set.
Future<void> _settle(TreeOwner owner) async {
  for (var i = 0; i < 3; i++) {
    owner.flush();
    await pumpEventQueue();
    owner.flush();
  }
}

void main() {
  group('pow-u1bi - the lane is the unit of diagnosis', () {
    test('two setup failures park one lane and flare one diagnosis', () async {
      final probe = _FakeLaneProbe(binary: _upgraded);
      final health = CorrelatingLaneEnvironmentHealth(
        probe: probe.call,
        now: () => DateTime.utc(2026, 9, 21, 23, 40),
      );
      addTearDown(health.dispose);
      final presence = _PresentProbe();
      final schedule = _FakeSchedule();
      final mounted = await _mount(
        presence: presence,
        schedule: schedule,
        health: health,
      );
      addTearDown(mounted.owner.dispose);
      final flares = <({String name, Map<String, String> data})>[];
      void flare(String name, Map<String, String> data) =>
          flares.add((name: name, data: data));

      // ROUND 1 minted, and the boolean probe is happy about BOTH lanes — the
      // live incident's starting state exactly.
      expect(mounted.mints, <int>[1]);
      expect(presence.calls, containsAll(<String>['codex', 'claude']));

      // ONE refusal is not a lane. It can be one bad pin on one bead, and
      // parking a whole lane on it would be the same over-attribution pointing
      // the other way.
      await health.recordSetupFailure(_setupRefusal(), flare: flare);
      await _settle(mounted.owner);
      expect(flares, isEmpty);
      mounted.rounds.nextRound();
      await _settle(mounted.owner);
      expect(
        mounted.mints,
        <int>[1, 2],
        reason: 'the lane is still up, so round 2 still mints',
      );

      // THE SECOND refusal, inside the window, IS the lane.
      await health.recordSetupFailure(_setupRefusal(), flare: flare);
      await _settle(mounted.owner);

      // ONE flare, with the WHOLE record — exactly nine keys, every one of them
      // present, because a reader that has to test for a key is back to
      // correlating logs.
      expect(flares, hasLength(1));
      expect(flares.single.name, kLaneDownFlare);
      expect(flares.single.data.keys.toSet(), <String>{
        'lane',
        'since',
        'binaryPath',
        'binaryVersion',
        'binaryMtime',
        'pin',
        'offered',
        'resolverVerdict',
        'summary',
      });
      expect(flares.single.data['lane'], 'codex');
      // SINCE is the binary's mtime, not the first failure: 23:22Z is when the
      // environment actually changed, five minutes before anything failed.
      expect(flares.single.data['since'], '2026-09-21T23:22:00.000Z');
      expect(flares.single.data['binaryMtime'], '2026-09-21T23:22:00.000Z');
      expect(flares.single.data['binaryVersion'], '0.155.1');
      expect(flares.single.data['binaryPath'], '/opt/homebrew/bin/codex');
      expect(flares.single.data['pin'], 'gpt-5.6-sol');
      expect(flares.single.data['offered'], _offered.join(', '));
      expect(
        flares.single.data['resolverVerdict'],
        contains('does not offer pinned model'),
      );
      // THE ONE LINE an operator reads the incident from.
      expect(
        flares.single.data['summary'],
        'codex lane down since 2026-09-21T23:22:00.000Z: '
        'binary 0.155.1 at /opt/homebrew/bin/codex '
        '(changed 2026-09-21T23:22:00.000Z), '
        'pin gpt-5.6-sol not resolvable against '
        '[gpt-5.6-sol[low], gpt-5.6-sol[medium], gpt-5.6-sol[high-ish], '
        'gpt-5.6-sol[ultra]]',
      );

      // THE PARK: the lane is gone from the presence set even though its
      // boolean probe never stopped saying yes.
      expect(mounted.observed.last, isNull);
      // ...and the OTHER lane is untouched. This is a LANE condition, not a
      // station one.
      expect(presence.calls, contains('claude'));

      // THE THIRD SPAWN IS PREVENTED. Supervision asks for another round and
      // the seat resolves to nothing, so no bead is charged for a refusal the
      // station already understands.
      final mintsBefore = mounted.mints.length;
      mounted.rounds.nextRound();
      await _settle(mounted.owner);
      expect(mounted.mints, hasLength(mintsBefore));
      expect(mounted.observed.last, isNull);

      // THE PARK WAS EARNED BY SETUP EVIDENCE, not by the tick: exactly two
      // TARGETED diagnoses, each carrying the catalog the agent actually
      // offered. The scheduled rechecks that follow a park only ever re-confirm
      // it — they can never be what established it.
      final targeted = probe.requests
          .where((request) => !request.scheduled)
          .toList(growable: false);
      expect(targeted, hasLength(2));
      expect(targeted.first.offered, _offered);
      expect(targeted.first.pin, 'gpt-5.6-sol');
    });

    test('a passing probe unparks the lane and remints held work', () async {
      final probe = _FakeLaneProbe(binary: _upgraded);
      final health = CorrelatingLaneEnvironmentHealth(
        probe: probe.call,
        now: () => DateTime.utc(2026, 9, 21, 23, 40),
      );
      addTearDown(health.dispose);
      final presence = _PresentProbe();
      final schedule = _FakeSchedule();
      final mounted = await _mount(
        presence: presence,
        schedule: schedule,
        health: health,
      );
      addTearDown(mounted.owner.dispose);

      // TWO setup mints, each ending in a refusal — the live shape.
      expect(mounted.mints, <int>[1]);
      await health.recordSetupFailure(_setupRefusal());
      await _settle(mounted.owner);
      mounted.rounds.nextRound();
      await _settle(mounted.owner);
      expect(mounted.mints, <int>[1, 2]);
      await health.recordSetupFailure(_setupRefusal());
      await _settle(mounted.owner);
      expect(mounted.observed.last, isNull);

      // NO MINT WHILE THE CONDITION IS DOWN. Supervision asks for round 3 and
      // the seat resolves to nothing — the work is HELD, not failed: this is
      // the one bead the live station would have burned an attempt on next.
      mounted.rounds.nextRound();
      await _settle(mounted.owner);
      expect(mounted.mints, <int>[1, 2]);
      expect(mounted.observed.last, isNull);

      // ...and the bounded tick does not lift the park by itself while the
      // environment still refuses.
      schedule.fire();
      await _settle(mounted.owner);
      expect(mounted.observed.last, isNull);
      expect(
        mounted.mints,
        <int>[1, 2],
        reason: 'a failing recheck re-confirms the park; it never re-admits',
      );
      expect(probe.requests.last.scheduled, isTrue);
      expect(
        probe.requests.last.priorBinary,
        _upgraded,
        reason:
            'the scheduled leg carries the down record so a REPLACED binary '
            'is distinguishable from the same broken one',
      );

      // RECOVERY. The environment answers correctly again — a config change, a
      // rollback, or the resolver defect landing. Nothing an operator did to
      // the bead.
      probe.passes = true;
      schedule.fire();
      await _settle(mounted.owner);

      // The lane is back, and the round that was held mints its SUCCESSOR off
      // the availability change alone — no operator edit, no rework round.
      expect(mounted.observed.last, _codex);
      expect(
        mounted.mints,
        <int>[1, 2, 3],
        reason: 'the held round 3 mints the instant the lane returns',
      );
    });

    test('a passing TARGETED diagnosis never accrues toward a park', () async {
      final probe = _FakeLaneProbe(binary: _upgraded)..passes = true;
      final health = CorrelatingLaneEnvironmentHealth(
        probe: probe.call,
        now: () => DateTime.utc(2026, 9, 21, 23, 40),
      );
      addTearDown(health.dispose);
      final flares = <String>[];

      // The environment answers correctly RIGHT NOW, so whatever refused these
      // two spawns was not the lane — and a lane is never parked on evidence
      // that does not implicate it.
      for (var i = 0; i < 3; i++) {
        await health.recordSetupFailure(
          _setupRefusal(),
          flare: (name, _) => flares.add(name),
        );
      }
      expect(flares, isEmpty);
    });

    test('failures outside the correlation window do not correlate', () async {
      final probe = _FakeLaneProbe(binary: _upgraded);
      var clock = DateTime.utc(2026, 9, 21, 23, 35);
      final health = CorrelatingLaneEnvironmentHealth(
        probe: probe.call,
        now: () => clock,
      );
      addTearDown(health.dispose);
      final flares = <String>[];
      void flare(String name, Map<String, String> data) => flares.add(name);

      probe.at = clock;
      await health.recordSetupFailure(_setupRefusal(), flare: flare);
      // An hour later: a different incident, not a second data point in this
      // one. The stale diagnosis is dropped and this failure starts over.
      clock = clock.add(const Duration(hours: 1));
      probe.at = clock;
      await health.recordSetupFailure(_setupRefusal(), flare: flare);
      expect(flares, isEmpty);
      // The one after it, inside the window, is the second — and parks.
      clock = clock.add(const Duration(minutes: 5));
      probe.at = clock;
      await health.recordSetupFailure(_setupRefusal(), flare: flare);
      expect(flares, <String>[kLaneDownFlare]);
    });
  });

  group('pow-u1bi - the real probe inspects the AGENT', () {
    /// The probe's IO composed over Fakes: the composition is pure, only the
    /// defaults touch the box (A38(7)'s rule for the boolean probe, applied to
    /// this one).
    ({ProcessLaneEnvironmentProbe probe, List<String> located})
    build({
      String? path = '/opt/homebrew/bin/codex',
      String? version = '0.155.1',
      DateTime? mtime,
    }) {
      final located = <String>[];
      return (
        probe: ProcessLaneEnvironmentProbe(
          locateBinary: (command) async {
            located.add(command);
            return path;
          },
          readVersion: (_) async => version,
          readMtime: (_) async =>
              mtime ?? DateTime.utc(2026, 9, 21, 23, 22),
          now: () => DateTime.utc(2026, 9, 21, 23, 35),
        ),
        located: located,
      );
    }

    test('it inspects pathCheck, not the npx launcher', () async {
      final fixture = build();
      final diagnosis = await fixture.probe(
        const LaneEnvironmentProbeRequest(
          target: _codexLane,
          offered: _offered,
          scheduled: false,
        ),
      );
      // `npx` is on every box with node; it proves nothing about codex.
      expect(fixture.located, <String>['codex']);
      expect(diagnosis.binary.path, '/opt/homebrew/bin/codex');
      expect(diagnosis.binary.version, '0.155.1');
      expect(diagnosis.binary.mtime, DateTime.utc(2026, 9, 21, 23, 22));
      // The RESOLVER's own verdict, not a re-implementation of it: six effort
      // variants and none at the frontier rung.
      expect(diagnosis.passed, isFalse);
      expect(
        diagnosis.resolverVerdict,
        allOf(
          contains('gpt-5.6-sol'),
          contains('frontier'),
          contains('gpt-5.6-sol[high]'),
        ),
      );
    });

    test('a catalog the resolver accepts passes', () async {
      final fixture = build();
      final diagnosis = await fixture.probe(
        const LaneEnvironmentProbeRequest(
          target: _codexLane,
          offered: <String>['gpt-5.6-sol[low]', 'gpt-5.6-sol[high]'],
          scheduled: false,
        ),
      );
      expect(diagnosis.passed, isTrue);
      expect(diagnosis.resolverVerdict, contains('gpt-5.6-sol[high]'));
    });

    test(
      'a scheduled recheck re-admits a REPLACED binary and nothing else',
      () async {
        // The SAME binary against the SAME catalog: still broken.
        final same = build();
        expect(
          (await same.probe(
            LaneEnvironmentProbeRequest(
              target: _codexLane,
              offered: _offered,
              scheduled: true,
              priorBinary: _upgraded,
            ),
          )).passed,
          isFalse,
        );
        // A ROLLBACK. The catalog on file is the OLD binary's, so only the live
        // agent can say whether the replacement is good — this re-admits
        // exactly one handshake, and two fresh refusals re-park it.
        final rolledBack = build(version: '0.154.0');
        expect(
          (await rolledBack.probe(
            LaneEnvironmentProbeRequest(
              target: _codexLane,
              offered: _offered,
              scheduled: true,
              priorBinary: _upgraded,
            ),
          )).passed,
          isTrue,
        );
        // A TARGETED probe gets no such benefit: a refusal that just happened
        // is answered by the resolver alone.
        final targeted = build(version: '0.154.0');
        expect(
          (await targeted.probe(
            LaneEnvironmentProbeRequest(
              target: _codexLane,
              offered: _offered,
              scheduled: false,
              priorBinary: _upgraded,
            ),
          )).passed,
          isFalse,
        );
      },
    );

    test('the version token is the LAST semantic one', () {
      expect(semanticVersionToken('0.155.1'), '0.155.1');
      expect(semanticVersionToken('codex-acp 1.6.2 (protocol 1)'), '1.6.2');
      expect(semanticVersionToken('no version here'), isNull);
    });
  });

  group('pow-u1bi - the session edge', () {
    test('half a lane-health pair refuses LOUDLY', () {
      expect(
        () => AgentSession(
          runtime: FakeRuntimeProvider(),
          name: 'session-1/work-1/agent',
          adapter: const AcpSessionAdapter(),
          brief: const AgentBrief(task: 'work'),
          commands: const Stream<ProcessSessionCommand>.empty(),
          attemptId: 'attempt-1',
          instanceFence: 'fence-1',
          laneTarget: _codexLane,
        ),
        throwsArgumentError,
      );
    });

    test(
      'a setup frame reaches the coordinator BEFORE the engine sees it',
      () async {
        final probe = _FakeLaneProbe(binary: _upgraded);
        final health = _RecordingHealth(
          CorrelatingLaneEnvironmentHealth(
            probe: probe.call,
            now: () => DateTime.utc(2026, 9, 21, 23, 40),
          ),
        );
        addTearDown(health.inner.dispose);
        const name = 'session-lane/work-1/agent';
        final runtime = FakeRuntimeProvider();
        await runtime.start(
          name,
          const RuntimeConfig(
            workDir: '.',
            command: 'probe',
            lifecycle: Lifecycle.longLived,
          ),
        );
        final session = AgentSession(
          runtime: runtime,
          name: name,
          adapter: const AcpSessionAdapter(),
          brief: const AgentBrief(task: 'lane probe'),
          commands: const Stream<ProcessSessionCommand>.empty(),
          attemptId: 'attempt-1',
          instanceFence: 'fence-1',
          laneHealth: health,
          laneTarget: _codexLane,
        );
        addTearDown(session.close);
        final terminal = session.updates.first;
        await session.start();
        // The exact frame the bridge writes for the measured refusal.
        runtime.emitInteraction(
          name,
          utf8.encode(
            '${jsonEncode(<String, Object?>{
              'kind': 'failed',
              'reason': 'acp session setup failed [acp]: …',
              'failureKind': CapabilityFailureKind.noResult.name,
              'fields': setupFailureFields(
                AcpModelResolutionFailure(
                  pin: 'gpt-5.6-sol',
                  offered: _offered,
                  tier: AgentTier.frontier,
                ),
              ),
            })}\n',
          ),
        );
        final update = await terminal.timeout(const Duration(seconds: 5));

        // THE ORDER IS THE POINT: supervision asks for the next spawn off this
        // report, so the evidence must already be recorded when it arrives.
        expect(health.recordedBeforeTerminal, isTrue);
        expect(update, isA<ProcessSessionFailed>());
        expect(
          (update as ProcessSessionFailed).kind,
          CapabilityFailureKind.noResult,
          reason: 'the harness\'s own declaration is forwarded UNCHANGED',
        );
        // The coordinator got STRUCTURE off the wire, not prose off the reason.
        expect(health.recorded, hasLength(1));
        expect(health.recorded.single.target, _codexLane);
        expect(health.recorded.single.pin, 'gpt-5.6-sol');
        expect(health.recorded.single.offered, _offered);
        expect(probe.requests.single.scheduled, isFalse);
      },
    );

    test(
      'an ORDINARY failure never reaches the coordinator',
      () async {
        final probe = _FakeLaneProbe(binary: _upgraded);
        final health = _RecordingHealth(
          CorrelatingLaneEnvironmentHealth(probe: probe.call),
        );
        addTearDown(health.inner.dispose);
        const name = 'session-midturn/work-1/agent';
        final runtime = FakeRuntimeProvider();
        await runtime.start(
          name,
          const RuntimeConfig(
            workDir: '.',
            command: 'probe',
            lifecycle: Lifecycle.longLived,
          ),
        );
        final session = AgentSession(
          runtime: runtime,
          name: name,
          adapter: const AcpSessionAdapter(),
          brief: const AgentBrief(task: 'lane probe'),
          commands: const Stream<ProcessSessionCommand>.empty(),
          attemptId: 'attempt-1',
          instanceFence: 'fence-1',
          laneHealth: health,
          laneTarget: _codexLane,
        );
        addTearDown(session.close);
        final terminal = session.updates.first;
        await session.start();
        runtime.emitInteraction(
          name,
          utf8.encode(
            '${jsonEncode(<String, Object?>{
              'kind': 'failed',
              'reason': 'prompt stopped with refusal',
            })}\n',
          ),
        );
        expect(
          await terminal.timeout(const Duration(seconds: 5)),
          isA<ProcessSessionFailed>().having(
            (f) => f.kind,
            'kind',
            CapabilityFailureKind.work,
          ),
        );
        // A mid-turn failure IS the bead's, and diagnosing the lane for it is
        // the same over-attribution pointing the other way.
        expect(health.recorded, isEmpty);
        expect(probe.requests, isEmpty);
      },
    );

    test('the setup phase decodes off the FIELDS, never the prose', () {
      final refusal = AcpModelResolutionFailure(
        pin: 'gpt-5.6-sol',
        offered: _offered,
        tier: AgentTier.frontier,
      );
      final fields = setupFailureFields(refusal);
      expect(fields[kAgentFailurePhaseField], kAgentSetupPhase);
      expect(fields[kAgentFailurePinField], 'gpt-5.6-sol');
      expect(decodeOfferedField(fields[kAgentFailureOfferedField]), _offered);
      expect(fields[kAgentFailureResolverVerdictField], refusal.message);
      // A setup failure that is NOT a model refusal still declares the PHASE,
      // and carries no catalog nobody observed.
      final other = setupFailureFields(StateError('the child never started'));
      expect(other, <String, String>{
        kAgentFailurePhaseField: kAgentSetupPhase,
      });
      // An absent or corrupt catalog is the EMPTY one, never a throw:
      // diagnostic evidence may not break a failure already on its way out.
      expect(decodeOfferedField(null), isEmpty);
      expect(decodeOfferedField('not json'), isEmpty);
    });
  });
}
