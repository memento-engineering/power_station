// The SPEC-READINESS INTAKE LENS, offline end-to-end (bead `pow-q7n`).
//
// Drives the readiness LADDER — the cheap head of the spec circuit
// (`intake` → `readiness` → `readiness-route`) — through the REAL StationKernel
// + CodeCircuitResolver + buildCodeRegistry, advancing the per-node cursor via
// the fake STATE source (the bridge re-projecting each chokepoint write) and
// feeding the lens's grade through the same source's `grid.result.*` keys.
//
// Four proofs — the bead's acceptance criteria:
//  - NEVER SPAWNS: a NON-DRIVEABLE bead (type `decision` — which a NON-resident
//    station really does mount) gates at `intake` and starts ZERO processes. Not
//    even the readiness lens runs, let alone specify + the 4-critic committee.
//  - HOLDS BEFORE SPECIFY: a bead the lens grades `D` parks at `readiness-route`
//    with the lens's rationale VERBATIM as the refinement ask — and `specify`
//    never spawns. This is the ~18-agent round the 2026-07-11 wide run burned
//    per coarse bead, withheld for the cost of ONE agent.
//  - DRIVES: a refined bead passes intake with zero findings and, on grade `A`,
//    routes `Ok` — `specify` spawns.
//  - PRE-LADDER (the MIGRATION negative control): a session minted under the
//    pre-ladder folded shape and surviving a station BOUNCE roots the FROZEN
//    pre-ladder circuit — the ladder NEVER mounts, its agent NEVER spawns, and
//    the lens can never PARK a bead whose build is already running.
//
// Offline — FAKES, no live tg/gc/claude/bd/git/network.
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

GraphSnapshot _graph({
  required List<Bead> beads,
  required Set<String> ready,
}) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: ready,
  capturedAt: DateTime(2026),
);

GraphSnapshot _state(Bead session) => _graph(beads: [session], ready: const {});

const _sid = 'tgdog-sess1';
String _step(String relPath) => '$_sid/tg-1/$relPath';

/// A NON-DRIVEABLE work bead carrying a REAL brief — the live `pow-p94` shape
/// (type `decision`). Its description is substantive on purpose: the ONLY thing
/// that may hold it is the type, so this proof can never pass for the wrong
/// reason.
///
/// It is a CORE type, so a NON-resident station (the default, and the shape this
/// kernel mounts) really does dispatch it — grid_engine narrows to
/// `driveableTypes` only under RESIDENT arming. Without tier 1 it would drive a
/// specify agent and the full committee today.
Bead _decisionBead() => Bead(
  id: 'tg-1',
  issueType: IssueType.decision,
  status: BeadStatus.open,
  description:
      'A real, substantive brief — but what it asks for is a RULING, not a '
      'coding job. Only the TYPE may hold this bead.',
);

/// A session minted under the PRE-LADDER folded shape (`pow-ui8`): its cursor
/// carries `spec_review/specify` and the whole spec committee, but NO ladder key
/// (`spec_review/intake` is absent). That absence IS the migration signal —
/// `classifyCodeShape` reads it as `folded` and roots the FROZEN pre-ladder
/// circuit. The bead is already PAST the spec phase and into its build.
Bead _preLadderSession() => committeeSession(
  id: _sid,
  workBeadId: 'tg-1',
  completed: {
    kSpecifyNode,
    kSpecClearCritiqueNode,
    kSpecGateNode,
    ...kSpecCriticNodes,
    kSpecRouteNode,
  },
  grades: {
    kSpecGateNode: 'A',
    for (final n in kSpecCriticNodes) n: 'A',
  },
);

StationKernel _buildKernel(
  Fakes f,
  FakeSnapshotSource work,
  FakeSnapshotSource state,
) {
  final bridge = StationJoinBridge(work: work, state: state);
  return StationKernel(
    bridge: bridge,
    stationServices: f.ctx,
    resolver: kCodeResolver,
    registry: buildCodeRegistry(
      rubrics: (id) => '($id rubric bands)',
      gitRunner: f.git,
      shellRunner: RecordingShellRunner(),
      critiqueDirClearer: (_) {},
    ),
    substations: [
      SubstationScope(
        configNotifier: SubstationConfigNotifier(
          const SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'}),
        ),
        key: const ValueKey('scope.tg'),
      ),
    ],
  );
}

/// True iff some chokepoint `update` wrote `grid.cursor.tg-1/<relPath>.state`
/// == [stateName].
bool _wroteCursor(Fakes f, String relPath, String stateName) =>
    f.runner.callsFor('update').any((c) {
      final i = c.indexOf('--metadata');
      if (i < 0 || i + 1 >= c.length) return false;
      final md = jsonDecode(c[i + 1]) as Map<String, dynamic>;
      return md['grid.cursor.tg-1/$relPath.state'] == stateName;
    });

/// The `reason` the chokepoint stamped on the minted gate bead (the refinement
/// ask a governor reads).
String? _gateReason(Fakes f) {
  for (final c in f.runner.callsFor('update')) {
    final i = c.indexOf('--metadata');
    if (i < 0 || i + 1 >= c.length) continue;
    final md = jsonDecode(c[i + 1]) as Map<String, dynamic>;
    final reason = md['reason'];
    if (reason is String) return reason;
  }
  return null;
}

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await pumpEventQueue();
  }
}

void main() {
  group('the readiness ladder — a NON-DRIVEABLE bead never spawns ANYTHING', () {
    test(
      'a `decision` bead gates at intake and starts ZERO processes — no '
      'readiness lens, no specify agent, no spec committee',
      () async {
        final f = buildFakes(createdId: _sid);
        final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
        final state = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
        final kernel = _buildKernel(f, work, state);
        addTearDown(kernel.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        kernel.start();
        await _settle();

        work.push(_graph(beads: [_decisionBead()], ready: {'tg-1'}));
        await _settle();

        // The WHOLE point of tier 1: the saving IS the un-spawned agent.
        expect(
          f.provider.started,
          isEmpty,
          reason: 'a non-driveable bead must not reach ANY agent — not even the '
              'cheap readiness lens',
        );
        expect(_wroteCursor(f, kIntakeNode, 'gated'), isTrue);

        // Guards LOUD: the hold NAMES the finding, so a governor never has to
        // diff the bead by hand to learn why it parked.
        final reason = _gateReason(f);
        expect(reason, isNotNull);
        expect(reason, contains('INTAKE HOLD'));
        expect(reason, contains('not a driveable type'));
        expect(reason, contains('decision'));
        expect(
          reason,
          contains('HELD for refinement, not rejected'),
          reason: 'a hold is a refinement ask, not a ruling',
        );
      },
    );
  });

  group('the readiness ladder — a NOT-READY bead holds before specify', () {
    test(
      'the lens grades D → the route parks with the rationale VERBATIM and '
      'specify NEVER spawns',
      () async {
        final f = buildFakes(createdId: _sid);
        final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
        final state = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
        final kernel = _buildKernel(f, work, state);
        addTearDown(kernel.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        kernel.start();
        await _settle();

        // 1) A driveable bead with a real brief PASSES the deterministic intake
        //    contract — and `intake` spawns nothing (it is a ServiceCapability).
        work.push(_graph(beads: [workBead('tg-1')], ready: {'tg-1'}));
        await _settle();
        expect(f.provider.started, isEmpty, reason: 'intake is deterministic');
        expect(_wroteCursor(f, kIntakeNode, 'complete'), isTrue);

        // 2) Re-project intake complete → the readiness LENS mounts. It is the
        //    ONE agent the ladder ever spawns.
        state.push(_state(committeeSession(completed: {kIntakeNode})));
        await _settle();
        expect(f.provider.started.map((s) => s.name), [_step(kReadinessNode)]);

        f.provider.emit(Exited(name: _step(kReadinessNode), exitCode: 0));
        await _settle();

        // 3) The lens graded D, with a rationale that IS the refinement ask.
        const rationale =
            'no acceptance shape — name the surfaces it touches and decide the '
            'layering before an architect can plan this';
        state.push(_state(committeeSession(
          completed: {kIntakeNode, kReadinessNode},
          results: {
            kReadinessNode: {'grade': 'D', 'rationale': rationale},
          },
        )));
        await _settle();

        // The HOLD: parked at the route, carrying the lens's own words.
        expect(_wroteCursor(f, kReadinessRouteNode, 'gated'), isTrue);
        final reason = _gateReason(f);
        expect(reason, isNotNull);
        expect(reason, contains('SPEC-READINESS HOLD'));
        expect(
          reason,
          contains(rationale),
          reason: 'the rationale rides VERBATIM — it is the governor\'s working '
              'material, not a summary',
        );

        // The saving, asserted: the expensive fan-out never happened.
        final started = f.provider.started.map((s) => s.name);
        expect(
          started,
          isNot(contains(_step(kSpecifyNode))),
          reason: 'a coarse bead must not reach the specify architect',
        );
        for (final critic in kSpecCriticNodes) {
          expect(started, isNot(contains(_step(critic))));
        }
        expect(
          started,
          [_step(kReadinessNode)],
          reason: 'exactly ONE agent ran — the lens itself',
        );
      },
    );
  });

  group('the readiness ladder — a REFINED bead drives', () {
    test('intake finds nothing and the lens grades A → the bead DRIVES into '
        'DISCOVERY, and only with discovery done does specify spawn', () async {
      final f = buildFakes(createdId: _sid);
      final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
      final state = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
      final kernel = _buildKernel(f, work, state);
      addTearDown(kernel.dispose);
      addTearDown(f.provider.close);
      addTearDown(work.close);
      addTearDown(state.close);

      kernel.start();
      await _settle();

      work.push(_graph(beads: [workBead('tg-1')], ready: {'tg-1'}));
      await _settle();
      expect(_wroteCursor(f, kIntakeNode, 'complete'), isTrue);
      expect(
        _wroteCursor(f, kIntakeNode, 'gated'),
        isFalse,
        reason: 'a driveable bead with a real brief has ZERO intake findings',
      );

      state.push(_state(committeeSession(completed: {kIntakeNode})));
      await _settle();
      expect(f.provider.started.map((s) => s.name), [_step(kReadinessNode)]);
      f.provider.emit(Exited(name: _step(kReadinessNode), exitCode: 0));
      await _settle();

      // Grade A ⇒ the route ADVANCES (no gate).
      state.push(_state(committeeSession(
        completed: {kIntakeNode, kReadinessNode},
        grades: {kReadinessNode: 'A'},
      )));
      await _settle();
      expect(_wroteCursor(f, kReadinessRouteNode, 'complete'), isTrue);
      expect(_wroteCursor(f, kReadinessRouteNode, 'gated'), isFalse);

      // And the bead DRIVES — but into DISCOVERY, not into `specify`: the
      // discovery circuit now heads the spec circuit between the ladder and the
      // architect. Its deterministic gather (`anchors`) mounts first and spawns
      // NOTHING; the architect is still withheld.
      state.push(_state(committeeSession(
        completed: kReadinessLadderNodes,
        grades: kReadinessGradeA,
      )));
      await _settle();
      expect(_wroteCursor(f, kAnchorsNode, 'complete'), isTrue,
          reason: 'the ladder released the bead into the deterministic gather');
      expect(
        f.provider.started.map((s) => s.name),
        [_step(kReadinessNode)],
        reason: 'the gather is a ServiceCapability — still ONE agent so far',
      );

      // The gather complete → the three READ-ONLY explorers fan out. The
      // architect is STILL withheld: discovery gates before it.
      state.push(_state(committeeSession(
        completed: {...kReadinessLadderNodes, kAnchorsNode},
        grades: kReadinessGradeA,
      )));
      await _settle();
      final exploring = f.provider.started.map((s) => s.name);
      expect(exploring, containsAll(kDiscoveryLensNodes.map(_step)));
      expect(
        exploring,
        isNot(contains(_step(kSpecifyNode))),
        reason: 'the architect is withheld until the discovery route advances',
      );

      // …and with the whole discovery circuit complete, `specify` is the next
      // agent to spawn: the ladder's job is to let the bead PROCEED, and what it
      // proceeds into is the gather.
      state.push(_state(committeeSession(
        completed: kSpecHeadNodes,
        grades: kReadinessGradeA,
      )));
      await _settle();
      expect(
        f.provider.started.map((s) => s.name),
        contains(_step(kSpecifyNode)),
        reason: 'the lens ran, the gather ran, then the architect',
      );
    });
  });

  group('the readiness ladder — the MIGRATION negative control', () {
    test(
      'a PRE-LADDER in-flight session surviving a bounce roots the FROZEN '
      'circuit: the ladder never mounts, its agent never spawns, and it can '
      'never park a bead that is already building',
      () async {
        final f = buildFakes(createdId: _sid);
        final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
        // The BOUNCE: the station restarts and ADOPTS an in-flight session whose
        // cursor was minted under the pre-ladder shape (no `intake` key).
        final state = FakeSnapshotSource(_state(_preLadderSession()));
        final kernel = _buildKernel(f, work, state);
        addTearDown(kernel.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        kernel.start();
        await _settle();

        work.push(_graph(beads: [workBead('tg-1')], ready: {'tg-1'}));
        await _settle();

        final started = f.provider.started.map((s) => s.name);

        // The ladder NEVER mounts for a survivor — the agent that would have
        // been spawned (and billed) never is.
        expect(
          started,
          isNot(contains(_step(kReadinessNode))),
          reason: 'a pre-ladder survivor must NEVER spawn the readiness agent',
        );
        expect(_wroteCursor(f, kIntakeNode, 'complete'), isFalse);
        expect(_wroteCursor(f, kIntakeNode, 'gated'), isFalse);
        expect(
          _wroteCursor(f, kReadinessRouteNode, 'gated'),
          isFalse,
          reason: 'the lens can never PARK a bead that is already building',
        );

        // Non-vacuous: the session CONTINUES where it left off — the frozen
        // circuit's spec phase is complete, so the BUILD agent is what mounts.
        expect(
          started,
          contains(_step(kAgentNode)),
          reason: 'the survivor resumes its build, proving the kernel is live',
        );
      },
    );
  });
}
