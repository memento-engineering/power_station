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

GraphSnapshot _graph({required List<Bead> beads, required Set<String> ready}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: ready,
      capturedAt: DateTime(2026),
    );

GraphSnapshot _state(List<Bead> beads) => _graph(beads: beads, ready: const {});

const _sid = 'tgdog-sess1';
String _step(String relPath) => '$_sid/tg-1/$relPath';

/// The molecule step-bead id for [relPath] under [_sid] (mirrors `stepBead`'s
/// own id-shape, `asset_fakes.dart`) — the bead itself IS the node now, so a
/// write is identified by its TARGET id, never an embedded cursor key.
String _stepBeadId(String relPath) => '$_sid-${relPath.replaceAll('/', '-')}';

/// Polls [condition] with a REAL short delay, up to [maxTries] — the robust
/// variant the shared [settle] (a bounded `pumpEventQueue` loop) cannot
/// guarantee here: a fresh MOLECULE mint's `createMolecule` pour rides the
/// REAL `BdCliService.applyGraph`, which writes a genuine temp file
/// (`dart:io`) before the FAKE `BdRunner` boundary is ever reached (the same
/// hazard `the_grid`'s own `grid_engine/test/molecule/drain_seam_test.dart`
/// documents) — a microtask-queue pump is not reliably enough turns of the
/// real event loop for that I/O to settle. Bounded, so a genuine regression
/// still fails instead of hanging.
Future<void> _pumpUntilReal(
  bool Function() condition, {
  int maxTries = 500,
}) async {
  for (var i = 0; i < maxTries && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

MountedStation _buildStation(
  Fakes f,
  FakeSnapshotSource work,
  FakeSnapshotSource state,
) {
  final bridge = StationJoinBridge(work: work, state: state);
  return MountedStation(
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

/// True iff some chokepoint `update` TARGETED the step bead for [relPath]
/// with `grid.step.state` == [stateName] — the molecule-model replacement for
/// the retired flat `grid.cursor.tg-1/<relPath>.state` read: the bead itself
/// IS the node now (no `{nodePath}` infix in its metadata), so the write is
/// identified by its target id, not by an embedded key.
bool _wroteCursor(Fakes f, String relPath, String stateName) =>
    f.runner.callsFor('update').any((c) {
      if (c.length < 2 || c[1] != _stepBeadId(relPath)) return false;
      return callMetadata(c)[MoleculeStepKeys.state] == stateName;
    });

/// True iff the station SPAWNED a specify architect — at EITHER node path
/// (`<bead>/specify` or `<bead>/spec_review/specify`).
bool _spawnedSpecify(Fakes f) =>
    f.provider.started.any((s) => s.name.endsWith('/specify'));

/// True iff ANY chokepoint update TARGETED the specify node's OWN step bead —
/// at EITHER path (`specify` or `spec_review/specify`) — the spawn-free half
/// of the control. A `ServiceCapability` runs WITHOUT a provider spawn, so
/// `provider.started` alone cannot prove the spec phase stayed unmounted; a
/// molecule-mode write is identified by its TARGET id (the bead IS the node),
/// never an embedded cursor key, so this checks the update's target rather
/// than scanning its metadata keys.
bool _touchedSpecifyNode(Fakes f) => f.runner
    .callsFor('update')
    .any(
      (c) =>
          c.length >= 2 &&
          (c[1] == _stepBeadId(kSpecHeadSpecifyNode) ||
              c[1] == _stepBeadId(kSpecifyNode)),
    );

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

/// The node universe every `code`-circuit shape (legacy, spec-head, folded,
/// laddered, discovery) mounts IDENTICALLY once its own spec phase clears —
/// the review committee, landing, and the terminal deliver route
/// (`circuit_migration.dart`: a frozen shape's `code_review`/`landing`
/// sub-circuits are the SAME registry entries the current circuit uses, so an
/// adopted survivor continues exactly as it would have). [kAgentNode] is
/// deliberately NOT included — every survivor's OWN node set below names it
/// explicitly (it sits BEFORE this tail, not after).
///
/// This tail tracks the CURRENT review shape ON PURPOSE, and ratified A16
/// (`a16-bead-pow-3p4-the-kcodecircuit-migration-guard-is-pure-be`, surface
/// `packages/**`, which names this file in its own Affects list) is what says
/// so: what A16 freezes is the SPEC HEAD — "the frozen spec-head shape gets its
/// OWN registered sub-circuit (`spec_review_v1`)" — while "the legacy shape
/// needs no such entry: its `code_review`/`landing` sub-circuits are the
/// CURRENT ones (neither reshape touched them)". So a new deterministic review
/// step ([kFormatCleanNode], bead `pow-jicn`) belongs in this set: every frozen
/// shape's `review` inflates the live `code_review` body, and
/// `CapabilityHost._stepBeadId` refuses LOUD if a node it MOUNTS has no staged
/// step bead. Carving the step out of the frozen universe would not pin the
/// frozen shape — it would break it.
const Set<String> _kSharedTailNodes = {
  ...kCodeReviewNodes,
  ...kLandingNodes,
  kDeliverNode,
};

/// A MOLECULE session fast-forwarded onto a BESPOKE node universe [ownNodes]
/// — a frozen shape's OWN spec-phase node paths (`circuit_migration.dart`),
/// which [kAllCodeCircuitNodes] cannot represent (shape-2's `specify` lives at
/// the ROOT path, never `spec_review/specify`; shape-1 has no spec phase at
/// all) — PLUS the shared post-spec tail every shape mounts identically
/// ([_kSharedTailNodes]). The local-helper escape hatch this suite's bespoke
/// survivor shapes need (`asset_fakes.dart` stays unedited): mirrors
/// [committeeSession]'s own shape (the molecule-stamped session bead first,
/// then one `type=step` bead per staged node), restricted to a node set that
/// falls OUTSIDE the current circuit's universe.
///
/// A node in [completed] stages [StepState.complete]; every other staged node
/// stages [StepState.pending] — the same "every node the live circuit might
/// reach needs its own bead" contract [committeeSession] documents
/// (`CapabilityHost._stepBeadId` refuses LOUD otherwise). [completed] must be
/// a subset of `ownNodes ∪ _kSharedTailNodes` — asserted, so a caller can
/// never silently drive a node this fixture never staged.
List<Bead> _survivorSession({
  required Set<String> ownNodes,
  required Set<String> completed,
}) {
  final staged = {...ownNodes, ..._kSharedTailNodes};
  assert(
    completed.every(staged.contains),
    '_survivorSession: a completed node must be staged: '
    '${completed.difference(staged)}',
  );
  return [
    sessionBead(
      id: _sid,
      workBeadId: 'tg-1',
      metadata: const {SessionBeadKeys.model: kSessionModelMolecule},
    ),
    for (final node in staged)
      stepBead(
        node,
        sessionId: _sid,
        workBeadId: 'tg-1',
        state: completed.contains(node)
            ? StepState.complete
            : StepState.pending,
      ),
  ];
}

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
      final station = _buildStation(f, work, state);
      addTearDown(station.dispose);
      addTearDown(f.provider.close);
      addTearDown(work.close);
      addTearDown(state.close);

      await station.start();
      await pumpEventQueue();

      // The persisted survivor lands BEFORE the work bead — the restoration
      // ADOPT seam (a mint would defeat the whole test).
      state.push(
        _state(_survivorSession(ownNodes: survivor, completed: survivor)),
      );
      await pumpEventQueue();
      work.push(_graph(beads: [bead('tg-1')], ready: {'tg-1'}));
      // The adopted session drives the review phase's hygiene step for
      // real — bounded-conditional (the molecule mint/adopt chain is longer
      // than one pump); still fails (exhausts at maxPumps) if a genuine
      // regression never writes it.
      await settle(() => _wroteCursor(f, kClearCritiqueNode, 'complete'));

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
      // The DETERMINISTIC FRONTIER (format-clean + declared-tests-present, bead
      // `pow-jicn`) is projected complete alongside the hygiene + scope-pinning
      // steps — every frozen shape's `review` is the CURRENT `code_review`
      // registry entry (`circuit_migration.dart`), so the frontier the live
      // critics `dependsOn` gates a survivor exactly as it gates a fresh round.
      state.push(
        _state(
          _survivorSession(
            ownNodes: survivor,
            completed: {
              ...survivor,
              kClearCritiqueNode,
              kPinDiffNode,
              kFormatCleanNode,
              'review/declared-tests-present',
            },
          ),
        ),
      );
      await settle(
        () => kProcessCriticNodes.every(
          (n) => f.provider.started.map((s) => s.name).contains(_step(n)),
        ),
      );
      final started = f.provider.started.map((s) => s.name).toSet();
      for (final n in kProcessCriticNodes) {
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
        final station = _buildStation(f, work, state);
        addTearDown(station.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        await station.start();
        await pumpEventQueue();

        state.push(
          _state(
            _survivorSession(
              ownNodes: _legacyMidReview(),
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
        await pumpEventQueue();
        work.push(_graph(beads: [bead('tg-1')], ready: {'tg-1'}));
        // The terminal `deliver` route runs BARE (no delivery method bound)
        // and writes complete — bounded-conditional, so a genuine regression
        // still fails instead of racing a fixed pump count.
        await settle(() => _wroteCursor(f, kDeliverNode, 'complete'));

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
            _survivorSession(
              ownNodes: _legacyMidReview(),
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
        await settle(
          () => f.runner
              .callsFor('close')
              .any((c) => c.length > 1 && c[1] == _sid),
        );

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
        final station = _buildStation(f, work, state);
        addTearDown(station.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        await station.start();
        await pumpEventQueue();

        work.push(_graph(beads: [bead('tg-1')], ready: {'tg-1'}));
        // Let the fresh-work MINT (molecule: mint session → stamp model →
        // dedup probe → pour steps) land before adopting the ladder-done
        // re-projection below — waiting for the pour (the LAST hop) avoids a
        // race where the re-projection lands mid-chain, interleaving
        // unpredictably with the real (here, id-less and discarded) mint.
        await _pumpUntilReal(() => f.runner.graphApplyCalls.isNotEmpty);

        // Fresh work roots the CURRENT (laddered) circuit, so the readiness
        // ladder's zero-agent `intake` head runs first (bead `pow-q7n`).
        // Re-project it complete → the architect spawns, exactly as before.
        state.push(_state(ladderDoneSession(id: _sid)));
        await settle(() => f.provider.started.isNotEmpty);

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
        final station = _buildStation(f, work, state);
        addTearDown(station.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        await station.start();
        await pumpEventQueue();

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
        await pumpEventQueue();
        work.push(_graph(beads: [bead('tg-1')], ready: {'tg-1'}));
        await settle(
          () => kSpecCriticNodes.every(
            (n) => f.provider.started.map((s) => s.name).contains(_step(n)),
          ),
        );

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
