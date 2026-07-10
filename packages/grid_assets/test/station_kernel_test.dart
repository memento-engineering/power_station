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

GraphSnapshot _graph({
  required List<Bead> beads,
  required Set<String> ready,
}) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: ready,
  capturedAt: DateTime(2026),
);

/// A one-bead STATE snapshot carrying the committee session for `tg-1` at the
/// given [completed] node set + [grades] (the shared `committeeSession` builds
/// the per-node cursor + the `grid.result.*` grades the route reads).
GraphSnapshot _stateAt({
  Set<String> completed = const {},
  Map<String, String> grades = const {},
}) => _graph(
  beads: [committeeSession(id: _sid, completed: completed, grades: grades)],
  ready: const {},
);

/// The committee critic step (provider) name for relative node [rel].
String _step(String rel) => '$_sid/tg-1/$rel';

/// The four critic provider names, in committee order.
final List<String> _criticSteps = [for (final n in kCriticNodes) _step(n)];

/// All-pass grades (the happy committee).
final Map<String, String> _allA = {for (final n in kCriticNodes) n: 'A'};

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await pumpEventQueue();
  }
}

void main() {
  group('StationKernel — the reactive loop drives agent→committee→land', () {
    test(
      'a ready owned task spawns the agent; advancing the per-node cursor fans '
      'the four critics out IN PARALLEL, then routes through to land — each a '
      'reconcile transition (stop old + start new), reusing the one session',
      () async {
        final f = buildFakes(createdId: _sid);
        // Empty baselines so the bridge seeds JoinedSnapshot.empty and the first
        // real push is what mounts the work bead.
        final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
        final state = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
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
                const SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'}),
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
        await _settle();
        // No work yet — nothing mounted.
        expect(f.provider.started, isEmpty);

        // 1) A ready owned task arrives on the WORK source → WorkList dirties →
        //    the kernel mints the session + spawns the agent (the 1-wide head of
        //    the `code` circuit). The step's provider name is
        //    '<sessionId>/<nodePath>'.
        work.push(_graph(beads: [bead('tg-1')], ready: {'tg-1'}));
        await _settle();

        expect(f.provider.started, hasLength(1), reason: 'the agent spawned');
        final agentStart = f.provider.started.single;
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

        // 2) The agent exits clean → its host writes agent=complete; advancing
        //    the per-node cursor (A40: the cursor lives on the_grid's own session
        //    bead) via the STATE source re-joins, WorkList dirties, and the flush
        //    SWAPS the frontier: the agent retires (killed) and the `review`
        //    sub-circuit inflates its FOUR critic lanes IN PARALLEL.
        f.provider.emit(Exited(name: _step('agent'), exitCode: 0));
        await _settle();
        state.push(_stateAt(completed: {kAgentNode}));
        await _settle();
        // clear-critique (gate-integrity #3, dep-free) then pin-diff
        // (scope-pinning, bead pow-6wo) each ran for real — no provider spawn
        // (both ServiceCapabilities; pin-diff no-ops to Ok since the synthetic
        // worktree does not exist on disk). Re-project their completions so the
        // four critics, which now transitively `dependsOn` them, become ready.
        state.push(_stateAt(
          completed: {kAgentNode, kClearCritiqueNode, kPinDiffNode},
        ));
        await _settle();

        expect(
          f.provider.stopped,
          contains(_step('agent')),
          reason: 'the agent step was unmounted → killed (the swap)',
        );
        final startedAfterAgent =
            f.provider.started.map((s) => s.name).toSet();
        for (final critic in _criticSteps) {
          expect(
            startedAfterAgent.contains(critic),
            isTrue,
            reason: 'critic $critic fanned out IN PARALLEL after the agent',
          );
        }
        expect(f.provider.started, hasLength(5),
            reason: 'the agent + the four critics started, nothing else');
        // Both lanes spawn `sh` now (FT-2 wraps claude for usage capture): the
        // gating lane runs the Validation Plan, an LLM lane exec's claude.
        final gating = f.provider.started
            .firstWhere((s) => s.name == _step(kCriticNodes.first));
        expect(gating.config.command, 'sh');
        expect(gating.config.args[1], contains('.grid/critique/code-validation.rc'));
        final llm = f.provider.started
            .firstWhere((s) => s.name == _step(kCriticNodes[1]));
        expect(llm.config.command, 'sh');
        expect(llm.config.args, contains('claude'));
        expect(llm.config.args[1], contains('.grid/telemetry/'));

        // 3) All four critics complete with PASSING grades → the route joins
        //    (await-all), reads the grades via the SiblingView, and advances; the
        //    four critic steps retire (killed) — the swap.
        for (final critic in _criticSteps) {
          f.provider.emit(Exited(name: critic, exitCode: 0));
        }
        await _settle();
        state.push(_stateAt(completed: {kAgentNode, ...kCriticNodes}, grades: _allA));
        await _settle();

        expect(
          f.provider.stopped,
          containsAll(_criticSteps),
          reason: 'every critic step was unmounted → killed once the route mounted',
        );
        expect(f.provider.started, hasLength(5),
            reason: 'the route is a ServiceCapability — it never spawns a process');

        // 4) route complete → land (a ServiceCapability — git/PR orchestration)
        //    swaps in. It does not spawn a process either, so the provider start
        //    count is unchanged: route → land swapped through.
        state.push(_stateAt(
          completed: {kAgentNode, ...kCriticNodes, kRouteNode},
          grades: _allA,
        ));
        await _settle();
        expect(f.provider.started, hasLength(5),
            reason: 'land does not spawn a process (it is git/PR orchestration)');

        // The whole committee ran under ONE session: a single mint, never a
        // second createSession across the agent/critic/route/land swaps.
        expect(
          f.runner.callsFor('create'),
          hasLength(1),
          reason: 'the session is REUSED across every swap — no second mint',
        );
      },
    );
  });
}
