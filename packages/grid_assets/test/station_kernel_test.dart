// Track E/F — the REACTIVE LOOP through the ALREADY-AUTHORED StationKernel.
//
// This is the integration proof that the M4 tree engine drives agent → committee
// → land as RECONCILE TRANSITIONS: a bridge push marks the sole observer
// (WorkList) dirty, the kernel's microtask flush reconciles the work set, mount =
// spawn (the agent), and a per-node cursor advance swaps the running frontier
// (stop old + start new) — the agent retiring fans the four critics out IN
// PARALLEL, then route + land swap through. The live `code` circuit
// (CircuitResolver + buildCodeRegistry) supplies the capabilities; the
// StationServices is over the offline fakes (no live tg/gc/claude/git).
//
// Unlike Track A's reconcile test (which calls owner.flush() directly), THIS test
// goes through the kernel's real `scheduleMicrotask` flush loop, so every step
// settles the event queue to let the scheduled flush run.
//
// **The molecule model (tg-eli phase 2).** `committeeSession` returns the
// session bead PLUS one `type=step` bead per staged node (BREAKING return-shape
// change: `Bead` → `List<Bead>`), so every state push now SPREADS it into the
// snapshot's `beads` rather than wrapping it as a single element. A mint
// triggered by a fresh (non-adopted) work bead is a LONGER async chain than the
// retired flat model's single `bd create` (mint → stamp model → dedup export
// probe → pour steps via `create --graph`), so the settle right after the push
// that first surfaces the minted, ladder-complete session uses the SHARED
// bounded conditional [settle] helper, not a blind fixed-iteration pump.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

// ---------------------------------------------------------------------------
// Builders.
// ---------------------------------------------------------------------------

const _sid = 'tgdog-sess1';

GraphSnapshot _graph({required List<Bead> beads, required Set<String> ready}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: ready,
      capturedAt: DateTime(2026),
    );

/// Re-homes [grades] (relative nodePath → letter) off `committeeSession`'s
/// SESSION-bead metadata — DEAD for a molecule session, since `SessionScope`'s
/// molecule branch derives `results` SOLELY from `moleculeBeads` (R1 re-homed
/// the write from the session bead to the step bead; the session bead's own
/// `grid.result.*` slice is never consulted there) — onto the GRADED node's
/// OWN `type=step` bead, the shape `CodeRouteCapability`'s ambient
/// `SiblingView` actually reads live. A no-op when [grades] is empty.
List<Bead> _stampStepGrades(
  List<Bead> beads, {
  required String workBeadId,
  required Map<String, String> grades,
}) {
  if (grades.isEmpty) return beads;
  return [
    for (final b in beads)
      if (b.issueType == GridIssueTypes.step)
        _graded(b, workBeadId, grades)
      else
        b,
  ];
}

/// Stamps [b]'s own `grid.result.<path>.grade` when its nodePath (read off
/// its `grid.step.path` metadata, workBeadId-prefixed — the SAME key
/// [CodeRouteCapability] reads through `SiblingView.resultOf`) has a grade in
/// [grades]; returns [b] unchanged otherwise.
Bead _graded(Bead b, String workBeadId, Map<String, String> grades) {
  final path = b.metadata[MoleculeStepKeys.path] as String?;
  if (path == null || !path.startsWith('$workBeadId/')) return b;
  final rel = path.substring(workBeadId.length + 1);
  final grade = grades[rel];
  if (grade == null) return b;
  return b.copyWith(
    metadata: {
      ...b.metadata,
      ...nodeResultMetadata(path, {'grade': grade}),
    },
  );
}

/// A one-bead STATE snapshot carrying the committee session for `tg-1` at the
/// given [completed] node set + [grades] (`committeeSession` builds the
/// session + per-node `type=step` beads; [_stampStepGrades] re-homes the
/// grades onto the graded step's OWN bead — the shape the live route read
/// needs). The SPEC phase (bead `pow-6ao`) rides every push fully complete +
/// all-A — this test's focus is the code committee's reactive loop; the spec
/// phase's own choreography is proven in
/// `acceptance/spec_stage_acceptance_test.dart`.
GraphSnapshot _stateAt({
  Set<String> completed = const {},
  Map<String, String> grades = const {},
}) => _graph(
  beads: _stampStepGrades(
    committeeSession(id: _sid, completed: {...kSpecPhaseNodes, ...completed}),
    workBeadId: 'tg-1',
    grades: {...kSpecGradesAllA, ...grades},
  ),
  ready: const {},
);

/// The committee critic step (provider) name for relative node [rel].
String _step(String rel) => '$_sid/tg-1/$rel';

/// The four critic provider names, in committee order.
final List<String> _criticSteps = [
  for (final n in kProcessCriticNodes) _step(n),
];

/// All-pass grades (the happy committee).
final Map<String, String> _allA = {for (final n in kCriticNodes) n: 'A'};

void main() {
  group('StationKernel — the reactive loop drives agent→committee→land', () {
    test('a ready owned task spawns the agent; advancing the per-node cursor fans '
        'the four critics out IN PARALLEL, then routes through to land — each a '
        'reconcile transition (stop old + start new), reusing the one session', () async {
      final f = buildFakes(createdId: _sid);
      // Empty baselines so the bridge seeds JoinedSnapshot.empty and the first
      // real push is what mounts the work bead.
      final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
      final state = FakeSnapshotSource(
        _graph(beads: const [], ready: const {}),
      );
      final bridge = StationJoinBridge(work: work, state: state);

      final kernel = StationKernel(
        bridge: bridge,
        stationServices: f.ctx,
        resolver: kCodeResolver,
        // Inline rubrics so the committee critics build their prompts without a
        // disk read (the on-disk loader is exercised by track_d_assets_test).
        // A no-op critique-dir clearer (gate-integrity #3): offline — never a
        // real filesystem touch at the synthetic `/grid/workspaces/...` path.
        registry: buildCodeRegistry(
          rubrics: (id) => '($id rubric bands)',
          critiqueDirClearer: (_) {},
        ),
        substations: [
          SubstationScope(
            configNotifier: SubstationConfigNotifier(
              const SubstationConfig(
                substationId: 'tg',
                ownedSubstations: {'tg'},
              ),
            ),
            key: const ValueKey('scope.tg'),
          ),
        ],
      );
      addTearDown(kernel.dispose);
      addTearDown(f.provider.close);
      addTearDown(work.close);
      addTearDown(state.close);

      kernel.start();
      await pumpEventQueue();
      // No work yet — nothing mounted.
      expect(f.provider.started, isEmpty);

      // 1) A ready owned task arrives on the WORK source → WorkList dirties →
      //    the kernel mints the session + mounts the READINESS LADDER's head
      //    (bead `pow-q7n`): `intake` is a deterministic ServiceCapability, so
      //    NOTHING spawns yet. Re-project the ladder complete (cursor adoption)
      //    → SPECIFY swaps in as the first AGENT (bead `pow-6ao`). The step's
      //    provider name is '<sessionId>/<nodePath>'. The ladder's own
      //    choreography is proven in `acceptance/readiness_acceptance_test.dart`.
      work.push(_graph(beads: [workBead('tg-1')], ready: {'tg-1'}));
      await pumpEventQueue();
      expect(
        f.provider.started,
        isEmpty,
        reason: 'the ladder head spawns NO agent — intake is deterministic',
      );

      // The molecule mint chain (mint → stamp model → dedup export probe →
      // pour steps via `create --graph`) is a longer async chain than one
      // pump — settle bounded-conditionally on the mount actually spawning.
      state.push(
        _graph(
          beads: ladderDoneSession(id: _sid),
          ready: const {},
        ),
      );
      await settle(() => f.provider.started.isNotEmpty);

      expect(f.provider.started, hasLength(1), reason: 'specify spawned');
      expect(f.provider.started.single.name, _step(kSpecifyNode));

      // Fast-forward the spec phase (specify complete + an all-pass spec
      // committee — cursor adoption: already-complete steps never mount) →
      // the frontier SWAPS to the build agent.
      f.provider.emit(Exited(name: _step(kSpecifyNode), exitCode: 0));
      await pumpEventQueue();
      state.push(_stateAt());
      await settle(() => f.provider.started.length >= 2);

      expect(f.provider.started, hasLength(2), reason: 'the agent spawned');
      final agentStart = f.provider.started.last;
      // FT-2: the claude invocation is wrapped in `sh -c` for usage capture;
      // claude is exec'd from the positionals (`"$@"`).
      expect(agentStart.config.command, 'sh');
      expect(agentStart.config.args, contains('claude'));
      expect(agentStart.name, _step('agent'));
      // The engine-minted per-incarnation token rides config.env on the spawn.
      expect(
        agentStart.config.env['GRID_INSTANCE_TOKEN'],
        isNotEmpty,
        reason: 'the agent spawn carries GRID_INSTANCE_TOKEN',
      );
      expect(agentStart.config.env['GRID_BEAD_ID'], 'tg-1');
      // The molecule lease's acquire (`stationProcessSpawner`) binds the
      // process handle only once `SessionStarted` lands — without it the
      // lease never binds, so a later unmount's release never reaches
      // `transport.stop` (the swap this suite proves would go unobserved).
      f.provider.emit(SessionStarted(name: _step('agent'), pid: 11, pgid: 11));
      await pumpEventQueue();

      // 2) The agent exits clean → its host writes agent=complete; advancing
      //    the per-node cursor (A40: the cursor lives on the_grid's own session
      //    bead) via the STATE source re-joins, WorkList dirties, and the flush
      //    SWAPS the frontier: the agent retires (killed) and the `review`
      //    sub-circuit inflates its FOUR critic lanes IN PARALLEL.
      f.provider.emit(Exited(name: _step('agent'), exitCode: 0));
      await pumpEventQueue();
      state.push(_stateAt(completed: {kAgentNode}));
      await pumpEventQueue();
      // clear-critique (gate-integrity #3, dep-free) then pin-diff
      // (scope-pinning, bead pow-6wo) each ran for real — no provider spawn
      // (both ServiceCapabilities; pin-diff no-ops to Ok since the synthetic
      // worktree does not exist on disk). Re-project their completions so the
      // four critics, which now transitively `dependsOn` them, become ready.
      state.push(
        _stateAt(completed: {kAgentNode, kClearCritiqueNode, kPinDiffNode}),
      );
      await settle(() => f.provider.started.length >= 6);

      expect(
        f.provider.stopped,
        contains(_step('agent')),
        reason: 'the agent step was unmounted → killed (the swap)',
      );
      final startedAfterAgent = f.provider.started.map((s) => s.name).toSet();
      for (final critic in _criticSteps) {
        expect(
          startedAfterAgent.contains(critic),
          isTrue,
          reason: 'critic $critic fanned out IN PARALLEL after the agent',
        );
      }
      expect(
        f.provider.started,
        hasLength(6),
        reason:
            'specify + the agent + the four critics started, nothing '
            'else',
      );
      // Both lanes spawn `sh` now (FT-2 wraps claude for usage capture): the
      // gating lane runs the Validation Plan, an LLM lane exec's claude.
      final gating = f.provider.started.firstWhere(
        (s) => s.name == _step(kCriticNodes.first),
      );
      expect(gating.config.command, 'sh');
      expect(
        gating.config.args[1],
        contains('.grid/critique/code-validation.rc'),
      );
      final llm = f.provider.started.firstWhere(
        (s) => s.name == _step(kProcessCriticNodes[1]),
      );
      expect(llm.config.command, 'sh');
      expect(llm.config.args, contains('claude'));
      expect(llm.config.args[1], contains('.grid/telemetry/'));
      // The four critics' own leases likewise need their `SessionStarted`
      // before their later unmount can release (see the agent's above).
      for (var i = 0; i < _criticSteps.length; i++) {
        f.provider.emit(
          SessionStarted(name: _criticSteps[i], pid: 20 + i, pgid: 20 + i),
        );
      }
      await pumpEventQueue();

      // 3) All four critics complete with PASSING grades → the route joins
      //    (await-all), reads the grades via the SiblingView, and advances; the
      //    four critic steps retire (killed) — the swap.
      for (final critic in _criticSteps) {
        f.provider.emit(Exited(name: critic, exitCode: 0));
      }
      await pumpEventQueue();
      state.push(
        _stateAt(completed: {kAgentNode, ...kCriticNodes}, grades: _allA),
      );
      await settle(() => _criticSteps.every(f.provider.stopped.contains));

      expect(
        f.provider.stopped,
        containsAll(_criticSteps),
        reason:
            'every critic step was unmounted → killed once the route mounted',
      );
      expect(
        f.provider.started,
        hasLength(6),
        reason: 'the route is a ServiceCapability — it never spawns a process',
      );

      // 4) route complete → land (a ServiceCapability — git/PR orchestration)
      //    swaps in. It does not spawn a process either, so the provider start
      //    count is unchanged: route → land swapped through.
      state.push(
        _stateAt(
          completed: {kAgentNode, ...kCriticNodes, kRouteNode},
          grades: _allA,
        ),
      );
      // land is a ServiceCapability (git/PR orchestration through the
      // fakes) — no crisp started/stopped signal marks its completion, so
      // drain the full bounded budget (still capped — a genuine hang would
      // still surface via the assertions below, never an actual wait).
      await settle(() => false);
      expect(
        f.provider.started,
        hasLength(6),
        reason: 'land does not spawn a process (it is git/PR orchestration)',
      );

      // The whole committee ran under ONE session: a single mint, never a
      // second createSession across the agent/critic/route/land swaps. A
      // molecule mint is now TWO `create` calls (the session bead, then its
      // whole circuit's `type=step` graph via `create --graph`) — so the
      // no-second-mint proof narrows to the SESSION-bead create specifically
      // rather than the raw call count.
      expect(
        f.runner
            .callsFor('create')
            .where((c) => c.contains('session'))
            .toList(),
        hasLength(1),
        reason: 'the session is REUSED across every swap — no second mint',
      );
    });
  });
}
