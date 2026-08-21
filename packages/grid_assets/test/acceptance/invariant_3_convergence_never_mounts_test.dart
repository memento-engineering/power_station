// Wave 4 / Track G — CONFORMANCE: derailment-invariant 3.
//
// "Convergence never mounts." (A41 — the allow-list mount boundary.) A ready
// set may contain an OWNED `type=convergence` root (the M2 two-writer axis),
// infra (agent/rig/role), and every the_grid orchestration noun bd ready leaks
// (convoy/event/step/spec/gate/molecule/message/merge-request) — NONE of them
// mount a work node or spawn an effect. Only plain coding-dispatchable work
// (the upstream core types) does.
//
// Track A's track_a_reconcile_test asserts the predicate at the WorkBead
// child-set level; THIS formalizes it at the kernel/effect-SPAWN level — driven
// through the real StationKernel + the real `code` circuit, the allow-list is
// proven by what does (and does not) reach the provider.
//
// Offline only — FAKES, no live tg/gc/claude/git/network.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

GraphSnapshot _graph({required List<Bead> beads, required Set<String> ready}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: ready,
      capturedAt: DateTime(2026),
    );

/// A typed bead carrying a real brief — non-empty on purpose, so the plain task
/// PASSES the intake contract (bead `pow-q7n`) and this suite's zero-spawn proof
/// stays about the TYPE gate, never about a missing description.
Bead _typed(String id, IssueType type) => Bead(
  id: id,
  issueType: type,
  status: BeadStatus.open,
  description: 'A real brief, so intake holds only on the type.',
);

StationKernel _kernel(StationJoinBridge bridge, Fakes f) => StationKernel(
  bridge: bridge,
  stationServices: f.ctx,
  resolver: kCodeResolver,
  registry: buildCodeRegistry(),
  substations: [
    SubstationScope(
      configNotifier: SubstationConfigNotifier(
        // Own the `tg` prefix so the ONLY thing keeping the customs out is the
        // TYPE allow-list, not ownership (every bead below is `tg-*`).
        const SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'}),
      ),
      key: const ValueKey('scope.tg'),
    ),
  ],
);

void main() {
  group('invariant 3 — convergence (and infra + orchestration nouns) never '
      'mount through the kernel', () {
    test(
      'an OWNED convergence root + infra + every orchestration noun mount ZERO '
      'effects, while a plain owned task DOES spawn — asserted at the '
      'effect-spawn level',
      () async {
        final f = buildFakes(createdId: 'tgdog-sess1');
        final work = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final state = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final bridge = StationJoinBridge(work: work, state: state);
        final kernel = _kernel(bridge, f);
        addTearDown(kernel.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        kernel.start();
        await pumpEventQueue();

        // Every the_grid non-core type, ALL owned (`tg-*`) + ALL ready. The
        // convergence root is the headline; the orchestration nouns a deny-list
        // missed (convoy/event/step/spec/gate/molecule/message/merge-request)
        // and infra (agent/rig/role) ride alongside — plus session.
        final customs = <String, IssueType>{
          'tg-conv': GridIssueTypes.convergence,
          'tg-cvy': GridIssueTypes.convoy,
          'tg-evt': GridIssueTypes.event,
          'tg-step': GridIssueTypes.step,
          'tg-spec': GridIssueTypes.spec,
          'tg-gate': GridIssueTypes.gate,
          'tg-mol': GridIssueTypes.molecule,
          'tg-msg': GridIssueTypes.message,
          'tg-mr': GridIssueTypes.mergeRequest,
          'tg-agent': GridIssueTypes.agent,
          'tg-rig': GridIssueTypes.rig,
          'tg-role': GridIssueTypes.role,
          'tg-sess': GridIssueTypes.session,
        };

        work.push(
          _graph(
            beads: [
              for (final e in customs.entries) _typed(e.key, e.value),
              _typed('tg-1', IssueType.task), // the one plain work bead
            ],
            ready: {...customs.keys, 'tg-1'},
          ),
        );
        await pumpEventQueue();

        // The plain task mounts the READINESS LADDER's head (bead `pow-q7n`) —
        // `intake` is a zero-agent ServiceCapability, so no effect has reached
        // the provider YET. Re-project the ladder complete (cursor adoption) and
        // the plain task's AGENT swaps in; every non-core type stays unmounted
        // throughout, which is what this invariant is about.
        expect(
          f.provider.started,
          isEmpty,
          reason: 'the ladder head is deterministic',
        );
        state.push(
          _graph(
            beads: [
              ...ladderDoneSession(id: 'tgdog-sess1', workBeadId: 'tg-1'),
            ],
            ready: const {},
          ),
        );
        await settle(() => f.provider.started.isNotEmpty);

        // Exactly ONE effect reached the provider — the plain task's agent.
        expect(
          f.provider.started,
          hasLength(1),
          reason: 'only the plain task spawned; nothing else mounted',
        );
        expect(f.provider.started.single.config.env['GRID_BEAD_ID'], 'tg-1');

        // And exactly ONE session was minted — for the plain task only. (A
        // convergence/orchestration mount would have minted its own session.)
        // THREE creates, all for that SAME one session: the session bead, the
        // `mount-attempt` durable remount budget stamped at admission (the_grid
        // tg-zlfu), then `create --graph` pouring its `type=step` beads (the
        // molecule mint's second hop, tg-eli phase 2). Exactly ONE `session`
        // create is the load-bearing claim here, so assert that directly rather
        // than leaning on a total count that any new write would falsify.
        final creates = f.runner.callsFor('create');
        final sessionCreates = creates.where(
          (c) =>
              c.contains('--type') && c[c.indexOf('--type') + 1] == 'session',
        );
        expect(sessionCreates, hasLength(1));
        // No hard TOTAL: the `mount-attempt` hop is present only when
        // grid_engine >= tg-zlfu is resolved, so a total flips between a
        // published-dep run and a path-override run. "Exactly one session"
        // is the claim this invariant actually makes.
        expect(creates.length, inInclusiveRange(2, 3));

        // The birth stamp links the minted session to tg-1, proving the one
        // spawn was the plain task (and not, say, the convergence root).
        expect(f.runner.metadataOfUpdate(0)['work_bead'], 'tg-1');
      },
    );

    test(
      'an OWNED convergence root ALONE (the M2 two-writer axis) mounts nothing '
      '— zero spawn, zero mint',
      () async {
        final f = buildFakes();
        final work = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final state = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final bridge = StationJoinBridge(work: work, state: state);
        final kernel = _kernel(bridge, f);
        addTearDown(kernel.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        kernel.start();
        await pumpEventQueue();

        // A lone OWNED, READY convergence bead — the most adversarial case (it
        // passes ownership; only the type gate stops it).
        work.push(
          _graph(
            beads: [_typed('tg-conv', GridIssueTypes.convergence)],
            ready: {'tg-conv'},
          ),
        );
        await pumpEventQueue();

        expect(f.provider.started, isEmpty, reason: 'convergence never spawns');
        expect(
          f.runner.callsFor('create'),
          isEmpty,
          reason: 'convergence never mints a session',
        );

        // Sanity (non-vacuous): the SAME kernel DOES spawn for a plain task, so
        // the zero-spawn above is the type gate, not a dead kernel. The task
        // mints its session and mounts the ladder's zero-agent head first (bead
        // `pow-q7n`); re-project it complete and the agent swaps in.
        work.push(
          _graph(
            beads: [
              _typed('tg-conv', GridIssueTypes.convergence),
              _typed('tg-1', IssueType.task),
            ],
            ready: {'tg-conv', 'tg-1'},
          ),
        );
        await pumpEventQueue();
        state.push(
          _graph(
            beads: [
              ...ladderDoneSession(id: 'tgdog-sess1', workBeadId: 'tg-1'),
            ],
            ready: const {},
          ),
        );
        await settle(() => f.provider.started.isNotEmpty);
        expect(f.provider.started, hasLength(1));
        expect(f.provider.started.single.config.env['GRID_BEAD_ID'], 'tg-1');
      },
    );
  });
}
