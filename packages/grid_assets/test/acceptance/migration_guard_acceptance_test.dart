// The pow-3p4 migration guard, offline end-to-end: bouncing the live station
// onto the FOLDED `code` circuit (pow-ui8) must NOT spawn a spurious specify
// architect for a session minted under EITHER older shape — the legacy 3-step
// (shape 1) or the pow-6ao spec-head (shape 2).
//
// The bounce is simulated the way a real remount happens: the STATE source
// already carries the persisted session bead (an old-shape cursor) BEFORE the
// work source surfaces the ready bead, so the freshly-mounted SessionScope
// ADOPTS (never mints) and the frontier is computed over the adopted cursor.
//
// The negative control covers BOTH spurious-entry channels: the specify SPAWN
// (a process) and the spec-phase SERVICE lanes (`clear-critique` /
// `spec-validation` run with NO spawn — only a cursor/result write betrays
// them), so `provider.started` alone is not trusted. It matches ANY node path
// ending in `/specify`, so it cannot be fooled by the fold moving the key.
//
// Offline — FAKES, no live tg/gc/claude/bd/git/network.
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

/// The shape-2 (`pow-6ao`) specify cursor key, relative to the work bead — the
/// ROOT-circuit path the fold MOVED to [kSpecifyNode]. No const exists for it
/// any more; that is the whole hazard, so the test names it literally.
const String kSpecHeadSpecifyNode = 'specify';

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

/// Every `--metadata` object the chokepoint wrote, decoded.
Iterable<Map<String, dynamic>> _updates(Fakes f) sync* {
  for (final c in f.runner.callsFor('update')) {
    final i = c.indexOf('--metadata');
    if (i < 0 || i + 1 >= c.length) continue;
    yield jsonDecode(c[i + 1]) as Map<String, dynamic>;
  }
}

/// True iff some chokepoint `update` wrote `grid.cursor.tg-1/<relPath>.state`
/// == [stateName].
bool _wroteCursor(Fakes f, String relPath, String stateName) => _updates(
  f,
).any((md) => md['grid.cursor.tg-1/$relPath.state'] == stateName);

/// True iff the station SPAWNED a specify architect — at EITHER node path
/// (`<bead>/specify` or `<bead>/spec_review/specify`).
bool _spawnedSpecify(Fakes f) =>
    f.provider.started.any((s) => s.name.endsWith('/specify'));

/// True iff ANY chokepoint update touched a specify node — the spawn-free half
/// of the control. A `ServiceCapability` runs WITHOUT a provider spawn, so
/// `provider.started` alone cannot prove the spec phase stayed unmounted.
bool _touchedSpecifyNode(Fakes f) => _updates(f).any(
  (md) => md.keys.any(
    (k) =>
        k.startsWith('grid.cursor.tg-1/specify') ||
        k.startsWith('grid.result.tg-1/specify') ||
        k.startsWith('grid.cursor.tg-1/spec_review/specify') ||
        k.startsWith('grid.result.tg-1/spec_review/specify'),
  ),
);

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await pumpEventQueue();
  }
}

/// The mid-review cursor of a shape-1 LEGACY survivor: past the legacy head,
/// with NO spec-phase node at either path.
Set<String> _legacyMidReview() => {kAgentNode};

/// The mid-review cursor of a shape-2 SPEC-HEAD survivor: `specify` complete at
/// the ROOT path, its pre-fold spec committee complete, `agent` complete — and
/// NO `spec_review/specify` node, which is exactly what the folded circuit would
/// read as `pending`.
Set<String> _specHeadMidReview() => {
  kSpecHeadSpecifyNode,
  kSpecClearCritiqueNode,
  kSpecGateNode,
  ...kSpecCriticNodes,
  kSpecRouteNode,
  kAgentNode,
};

void main() {
  group('the migration guard — bouncing onto the folded circuit (pow-3p4)', () {
    /// Drives one bounce: the STATE store already holds [survivor]'s session
    /// when the work bead surfaces. Asserts the guard held, then advances the
    /// SAME shape one more cursor tick and asserts the code committee fans out
    /// for real — proving the classification is stable across ticks (nothing is
    /// snapshot-cached — D-H) and that the adopted session keeps driving.
    Future<void> bounceHoldsFor(
      Set<String> survivor, {
      required String shape,
    }) async {
      final f = buildFakes(createdId: _sid);
      final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
      final state = FakeSnapshotSource(
        _graph(beads: const [], ready: const {}),
      );
      final kernel = _buildKernel(f, work, state);
      addTearDown(kernel.dispose);
      addTearDown(f.provider.close);
      addTearDown(work.close);
      addTearDown(state.close);

      kernel.start();
      await _settle();

      // The persisted survivor lands BEFORE the work bead — the restoration
      // ADOPT seam (a mint would defeat the whole test).
      state.push(_state(committeeSession(completed: survivor)));
      await _settle();
      work.push(_graph(beads: [bead('tg-1')], ready: {'tg-1'}));
      await _settle();

      // THE GATE — no spurious architect, by EITHER channel.
      expect(
        _spawnedSpecify(f),
        isFalse,
        reason: 'a $shape in-flight session must never enter the spec phase',
      );
      expect(
        _touchedSpecifyNode(f),
        isFalse,
        reason:
            'no specify node may run (spawned OR service) for a $shape session',
      );
      // ADOPTED, never re-minted.
      expect(
        f.runner.callsFor('create'),
        isEmpty,
        reason: 'the bounce adopts the persisted session — no new mint',
      );
      // The session CONTINUES under its frozen shape: the review phase's
      // hygiene step ran for real and wrote its cursor terminal.
      expect(
        _wroteCursor(f, kClearCritiqueNode, 'complete'),
        isTrue,
        reason: 'the adopted $shape session keeps driving mid-review',
      );

      // One more SAME-SHAPE cursor tick: the code committee fans out for real.
      state.push(
        _state(
          committeeSession(
            completed: {...survivor, kClearCritiqueNode, kPinDiffNode},
          ),
        ),
      );
      await _settle();
      final started = f.provider.started.map((s) => s.name).toSet();
      for (final n in kCriticNodes) {
        expect(
          started,
          contains(_step(n)),
          reason: 'the $shape review committee drives on ($n)',
        );
      }
      expect(_spawnedSpecify(f), isFalse);
      expect(_touchedSpecifyNode(f), isFalse);
    }

    test(
      'a shape-(1) LEGACY bounce adopts mid-review WITHOUT entering the spec '
      'phase — no specify spawn, no specify cursor/result write, no re-mint; '
      'the legacy review phase keeps driving',
      () => bounceHoldsFor(_legacyMidReview(), shape: 'legacy'),
    );

    test(
      'a shape-(2) SPEC-HEAD bounce adopts mid-review WITHOUT re-entering '
      'specify — the pow-6ao cursor has no key at the FOLDED specify path, and '
      'the guard roots the frozen spec-head shape so nothing mounts there',
      () => bounceHoldsFor(_specHeadMidReview(), shape: 'spec-head'),
    );

    test(
      'a shape-(1) bounce mid-LAND completes the legacy circuit and closes the '
      'session — still zero spec-phase activity',
      () async {
        final f = buildFakes(createdId: _sid);
        final work = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final state = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final kernel = _buildKernel(f, work, state);
        addTearDown(kernel.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        kernel.start();
        await _settle();

        state.push(
          _state(
            committeeSession(
              completed: {
                kAgentNode,
                kClearCritiqueNode,
                kPinDiffNode,
                ...kCriticNodes,
                kRouteNode,
                kRebaseNode,
                kRevalidateNode,
              },
            ),
          ),
        );
        await _settle();
        work.push(_graph(beads: [bead('tg-1')], ready: {'tg-1'}));
        await _settle();

        expect(_spawnedSpecify(f), isFalse);
        expect(_touchedSpecifyNode(f), isFalse);
        expect(
          _wroteCursor(f, kDeliverNode, 'complete'),
          isTrue,
          reason:
              'the terminal route ran under the legacy shape (offline: it '
              'advances BARE with no delivery method bound)',
        );

        // The chokepoint write does not feed back into the fake STATE source,
        // so re-project the now-terminal cursor — the same tick the committee
        // path takes to close (`circuit_acceptance_test.dart`). `land` is the
        // FROZEN legacy circuit's terminalStepId, so SessionScope closes here.
        state.push(
          _state(
            committeeSession(
              completed: {
                kAgentNode,
                kClearCritiqueNode,
                kPinDiffNode,
                ...kCriticNodes,
                kRouteNode,
                kRebaseNode,
                kRevalidateNode,
                kDeliverNode,
              },
            ),
          ),
        );
        await _settle();

        expect(
          f.runner.callsFor('close').where((c) => c[1] == _sid),
          hasLength(1),
          reason: 'the completed legacy circuit closes its session',
        );
        expect(
          _spawnedSpecify(f),
          isFalse,
          reason: 'the legacy session terminated without ever spec-ing',
        );
        expect(_touchedSpecifyNode(f), isFalse);
      },
    );

    test(
      'POSITIVE control: a fresh bead still enters the LADDERED specify — the '
      'guard is inert for new work, and the harness DOES detect a specify '
      'spawn (the negative controls are non-vacuous)',
      () async {
        final f = buildFakes(createdId: _sid);
        final work = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final state = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final kernel = _buildKernel(f, work, state);
        addTearDown(kernel.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        kernel.start();
        await _settle();

        work.push(_graph(beads: [bead('tg-1')], ready: {'tg-1'}));
        await _settle();

        // Fresh work roots the CURRENT (laddered) circuit, so the readiness
        // ladder's zero-agent `intake` head runs first (bead `pow-q7n`).
        // Re-project it complete → the architect spawns, exactly as before.
        state.push(_state(ladderDoneSession(id: _sid)));
        await _settle();

        expect(f.provider.started.map((s) => s.name), [_step(kSpecifyNode)]);
        expect(_spawnedSpecify(f), isTrue);
      },
    );

    test(
      'an adopted CURRENT-SHAPE session stays on the current circuit — the spec '
      'critics fan out, specify does not respawn, the build agent stays held',
      () async {
        final f = buildFakes(createdId: _sid);
        final work = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final state = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final kernel = _buildKernel(f, work, state);
        addTearDown(kernel.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        kernel.start();
        await _settle();

        // A CURRENT-shape survivor: the whole cheap head's keys ARE present — the
        // ladder AND the discovery circuit (that is what makes it CURRENT, not a
        // pre-discovery survivor rooted on the frozen circuit), and it is already
        // past `specify`.
        state.push(
          _state(
            committeeSession(
              completed: {
                ...kSpecHeadNodes,
                kSpecifyNode,
                kSpecClearCritiqueNode,
              },
              grades: kReadinessGradeA,
            ),
          ),
        );
        await _settle();
        work.push(_graph(beads: [bead('tg-1')], ready: {'tg-1'}));
        await _settle();

        final started = f.provider.started.map((s) => s.name).toSet();
        for (final n in kSpecCriticNodes) {
          expect(
            started,
            contains(_step(n)),
            reason: 'a laddered session keeps its spec committee ($n)',
          );
        }
        expect(
          _spawnedSpecify(f),
          isFalse,
          reason: 'specify already complete — retired, never respawned',
        );
        expect(
          started,
          isNot(contains(_step(kAgentNode))),
          reason: 'the spec gate still holds the build',
        );
      },
    );
  });
}
