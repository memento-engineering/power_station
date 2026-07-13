// M5 "The Circuit" — Track E2: the verify-first committee, offline end-to-end.
//
// Drives the FULL committee-wired `code` path through the REAL StationKernel +
// CircuitResolver + buildCodeRegistry (agent → review[4 critics ∥ → route] →
// land), advancing the per-node cursor via the fake STATE source (the bridge
// re-projecting each chokepoint write) and feeding the critics' grades through
// the same STATE source's `grid.result.*` keys (what the host's result() would
// have persisted; the route reads them via the threaded SiblingView, D-5).
//
// Three proofs: the happy path (agent → 4 critics IN PARALLEL → route advances →
// land → session close); the gating-F path (code-validation F → route parks at a
// GATE — a `type=gate` bead minted, land NEVER runs, the session NEVER closes);
// and flares emitted on the transitions. Offline — FAKES, no live
// tg/gc/claude/git/network.
import 'dart:convert';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

// A recording, emit-only exploration transport (D-8): captures every flare.
class _RecordingTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];

  @override
  void flare(String name, Map<String, String> data) =>
      flares.add((name: name, data: data));
}

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

// The committee critic provider names, in committee order.
final List<String> _criticSteps = [for (final n in kCriticNodes) _step(n)];

/// The committee session with the SPEC phase (bead `pow-6ao`) fast-forwarded
/// (fully complete + all-A — cursor adoption: already-complete steps never
/// mount). This test's focus is the CODE committee; the spec phase's own
/// choreography is `spec_stage_acceptance_test.dart`.
Bead _session({
  Set<String> completed = const {},
  Set<String> gated = const {},
  Map<String, String> grades = const {},
  bool closed = false,
}) => committeeSession(
  completed: {...kSpecPhaseNodes, ...completed},
  gated: gated,
  grades: {...kSpecGradesAllA, ...grades},
  closed: closed,
);

StationKernel _buildKernel(
  Fakes f,
  FakeSnapshotSource work,
  FakeSnapshotSource state, {
  ExplorationTransport? transport,
  ShellRunner? shellRunner,
}) {
  final bridge = StationJoinBridge(work: work, state: state);
  return StationKernel(
    bridge: bridge,
    stationServices: f.ctx,
    resolver: kCodeResolver,
    // Inject an inline rubric source so the committee is hermetic (no disk read);
    // the on-disk Packaged-AI-Asset loader is exercised by track_d_assets_test.
    // The landing circuit's rebase/revalidate (`tg-rm5`) reuse the SAME
    // recording git fake `land` already lands through, plus a recording shell
    // fake so `revalidate` never spawns a real process.
    registry: buildCodeRegistry(
      rubrics: (id) => '($id rubric bands)',
      gitRunner: f.git,
      shellRunner: shellRunner ?? RecordingShellRunner(),
      // A no-op clearer (gate-integrity #3): offline — fakes only, never a
      // real filesystem touch at the synthetic `/grid/worktrees/...` path.
      critiqueDirClearer: (_) {},
    ),
    substations: [
      SubstationScope(
        configNotifier: SubstationConfigNotifier(
          const SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'}),
        ),
        // The land SourceControl + the flare transport are provided AT THE SCOPE
        // (ADR-0008 D5 / D-8).
        services: ServiceBundle(
          // The source control PROVISIONS; the bound DELIVERY METHOD is what a
          // terminal advance actuates (M5 D-4a). gitRunner: the SAME recording
          // fake gitOps wraps, so the force-with-lease push records offline
          // (never real git).
          sourceControl: const GitSourceControl(),
          delivery: GitHubPrDelivery(
            gitOps: GitOps(f.git),
            prOpener: f.pr,
            gitRunner: f.git,
          ),
          transport: transport,
        ),
        key: const ValueKey('scope.tg'),
      ),
    ],
  );
}

/// True iff some chokepoint `update` wrote `grid.cursor.tg-1/<relPath>.state` ==
/// [stateName] (the host's terminal cursor write — proof a step's host decided).
bool _wroteCursor(Fakes f, String relPath, String stateName) =>
    f.runner.callsFor('update').any((c) {
      final i = c.indexOf('--metadata');
      if (i < 0 || i + 1 >= c.length) return false;
      final md = jsonDecode(c[i + 1]) as Map<String, dynamic>;
      return md['grid.cursor.tg-1/$relPath.state'] == stateName;
    });

/// True iff a `type=gate` bead was minted through the chokepoint (createGate).
bool _gateMinted(Fakes f) =>
    f.runner.callsFor('create').any((c) => c.join(' ').contains('gate'));

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await pumpEventQueue();
  }
}

void main() {
  group('The Circuit — happy path (agent → committee → route → land → close)', () {
    test(
      'the four critics fan out IN PARALLEL; all-pass routes to land; the '
      'session closes',
      () async {
        final f = buildFakes(createdId: _sid);
        f.pr.url = 'https://github.com/memento/genesis/pull/9';
        final transport = _RecordingTransport();
        final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
        final state = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
        final kernel = _buildKernel(f, work, state, transport: transport);
        addTearDown(kernel.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        kernel.start();
        await _settle();

        // 1) a ready owned task → the READINESS LADDER's `intake` head mounts
        //    (bead `pow-q7n`, a zero-agent ServiceCapability — nothing spawns);
        //    re-project it complete → SPECIFY spawns (bead `pow-6ao`);
        //    fast-forward its phase (an all-pass spec committee via cursor
        //    adoption) → the build agent swaps in.
        work.push(_graph(beads: [workBead('tg-1')], ready: {'tg-1'}));
        await _settle();
        expect(
          f.provider.started,
          isEmpty,
          reason: 'the ladder head spawns NO agent — intake is deterministic',
        );
        state.push(_state(ladderDoneSession(id: _sid)));
        await _settle();
        expect(f.provider.started.map((s) => s.name), [_step(kSpecifyNode)]);
        f.provider.emit(Exited(name: _step(kSpecifyNode), exitCode: 0));
        await _settle();
        state.push(_state(_session()));
        await _settle();
        expect(f.provider.started.map((s) => s.name).last, _step('agent'));

        // 2) agent completes → its host writes agent=complete (+ flares); the
        //    STATE source surfaces the advance → the `review` sub-circuit inflates
        //    its FOUR critic lanes IN PARALLEL.
        f.provider.emit(Exited(name: _step('agent'), exitCode: 0));
        await _settle();
        state.push(_state(_session(completed: {kAgentNode})));
        await _settle();

        // clear-critique (gate-integrity #3, dep-free) mounted + ran for real
        // — no provider spawn (a ServiceCapability, like rebase/revalidate);
        // the bridge re-projects its completion so pin-diff (which `dependsOn`
        // it) becomes ready.
        state.push(_state(_session(
          completed: {kAgentNode, kClearCritiqueNode},
        )));
        await _settle();

        // pin-diff (scope-pinning, bead pow-6wo) then ran for real — another
        // ServiceCapability, no provider spawn; the synthetic worktree does not
        // exist on disk so it no-ops to Ok. Re-project its completion before
        // the four critics (which now `dependsOn` it) become ready.
        state.push(_state(_session(
          completed: {kAgentNode, kClearCritiqueNode, kPinDiffNode},
        )));
        await _settle();

        final startedAfterAgent =
            f.provider.started.map((s) => s.name).toSet();
        for (final critic in _criticSteps) {
          expect(
            startedAfterAgent.contains(critic),
            isTrue,
            reason: 'critic $critic fanned out after the agent',
          );
        }
        // Both lanes spawn `sh` (FT-2 wraps claude for usage capture): the
        // gating lane runs the Validation Plan, an LLM lane exec's claude.
        final gating = f.provider.started
            .firstWhere((s) => s.name == _step(kCriticNodes.first));
        expect(gating.config.command, 'sh');
        expect(
          gating.config.args[1],
          contains('.grid/critique/code-validation.rc'),
        );
        final llm = f.provider.started
            .firstWhere((s) => s.name == _step(kCriticNodes[1]));
        expect(llm.config.command, 'sh');
        expect(llm.config.args, contains('claude'));

        // 3) all four critics complete with PASSING grades → the route joins
        //    (await-all), reads the grades via the SiblingView, and advances (Ok).
        for (final critic in _criticSteps) {
          f.provider.emit(Exited(name: critic, exitCode: 0));
        }
        await _settle();
        state.push(_state(_session(
          completed: {kAgentNode, ...kCriticNodes},
          grades: {for (final n in kCriticNodes) n: 'A'},
        )));
        await _settle();
        expect(
          _wroteCursor(f, kRouteNode, 'complete'),
          isTrue,
          reason: 'all-pass → the route advanced (Ok), never gated',
        );
        expect(_gateMinted(f), isFalse, reason: 'no gate on the happy path');

        // 4) route complete → the `land` SubCircuitStep inflates (`tg-rm5`):
        //    rebase → revalidate → land, each a ServiceCapability (no
        //    provider spawn) running for real through the fakes.
        state.push(_state(_session(
          completed: {kAgentNode, ...kCriticNodes, kRouteNode},
          grades: {for (final n in kCriticNodes) n: 'A'},
        )));
        await _settle();
        expect(
          _wroteCursor(f, kRebaseNode, 'complete'),
          isTrue,
          reason: 'rebase ran clean (the recording git fake is ok by default)',
        );

        state.push(_state(_session(
          completed: {kAgentNode, ...kCriticNodes, kRouteNode, kRebaseNode},
          grades: {for (final n in kCriticNodes) n: 'A'},
        )));
        await _settle();
        expect(
          _wroteCursor(f, kRevalidateNode, 'complete'),
          isTrue,
          reason: 'revalidate ran clean (the recording shell fake is ok by default)',
        );

        state.push(_state(_session(
          completed: {
            kAgentNode,
            ...kCriticNodes,
            kRouteNode,
            kRebaseNode,
            kRevalidateNode,
          },
          grades: {for (final n in kCriticNodes) n: 'A'},
        )));
        await _settle();
        expect(
          f.git.subcommands,
          containsAll(<String>['fetch', 'rebase', 'add', 'commit', 'push']),
        );
        expect(f.pr.opened, isNotEmpty, reason: 'the terminal advance delivered');
        // The PR TITLE is composed by the terminal route and crosses the
        // value-only DeliveryRequest payload, so it rides this offline drive.
        expect(f.pr.opened.last.title, isNotEmpty);
        // The BODY does NOT: it crosses a WORKTREE LEDGER (`.grid/pr-body.md`,
        // M5 D-4a — a multi-KB body must not ride the terminal payload into the
        // session bead's metadata), and this drive's worktree is the SYNTHETIC
        // `/grid/worktrees/...` path that never exists on disk, so the route
        // skips the write and delivery opens with an EMPTY body. That is the
        // documented fail-SAFE posture — a land never fails over PR prose — and
        // it is exactly what this harness's other I/O (the critique clearer, the
        // pinned diff) already does offline. The receipt actually REACHING the
        // PR body is proven over a REAL worktree, route → method, in
        // `delivery_test.dart`'s end-to-end group.
        expect(f.pr.opened.last.body, isEmpty);

        // 5) land complete (the terminal step) → SessionScope closes the session.
        state.push(_state(_session(
          completed: {
            kAgentNode,
            ...kCriticNodes,
            kRouteNode,
            kRebaseNode,
            kRevalidateNode,
            kDeliverNode,
          },
          grades: {for (final n in kCriticNodes) n: 'A'},
        )));
        await _settle();
        expect(
          f.runner.callsFor('close').where((c) => c[1] == _sid),
          hasLength(1),
          reason: 'land is the terminalStepId → the session closes',
        );

        // 6) flares fired on the transitions (non-blocking, D-8).
        expect(
          transport.flares.map((e) => e.name),
          containsAll(<String>['step.complete']),
        );
        expect(
          transport.flares.every((e) => e.data['sessionId'] == _sid),
          isTrue,
          reason: 'every flare carries the session id',
        );
      },
    );
  });

  group('The Circuit — gating-F parks at a GATE (no auto-advance to land)', () {
    test(
      'code-validation F → the route mints a type=gate bead, writes the route '
      'GATED, and land NEVER runs nor closes the session',
      () async {
        final f = buildFakes(createdId: _sid);
        final transport = _RecordingTransport();
        final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
        final state = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
        final kernel = _buildKernel(f, work, state, transport: transport);
        addTearDown(kernel.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        kernel.start();
        await _settle();
        work.push(_graph(beads: [workBead('tg-1')], ready: {'tg-1'}));
        await _settle();
        // Fast-forward the spec phase (bead `pow-6ao`): specify exits, the
        // spec committee all-passes via cursor adoption → the agent swaps in.
        f.provider.emit(Exited(name: _step(kSpecifyNode), exitCode: 0));
        await _settle();
        state.push(_state(_session()));
        await _settle();
        f.provider.emit(Exited(name: _step('agent'), exitCode: 0));
        await _settle();
        state.push(_state(_session(completed: {kAgentNode})));
        await _settle();
        // clear-critique (gate-integrity #3) then pin-diff (scope-pinning, bead
        // pow-6wo) ran for real; re-project both completions so the four
        // critics — which now transitively dependsOn them — mount.
        state.push(_state(_session(
          completed: {kAgentNode, kClearCritiqueNode, kPinDiffNode},
        )));
        await _settle();
        for (final critic in _criticSteps) {
          f.provider.emit(Exited(name: critic, exitCode: 0));
        }
        await _settle();

        // The gating lane (code-validation) graded F (a non-zero Validation Plan);
        // the others passed → the route's matrix is a HARD BLOCK.
        state.push(_state(_session(
          completed: {kAgentNode, ...kCriticNodes},
          grades: {
            kCriticNodes.first: 'F', // code-validation
            for (final n in kCriticNodes.skip(1)) n: 'A',
          },
        )));
        await _settle();

        expect(
          _wroteCursor(f, kRouteNode, 'gated'),
          isTrue,
          reason: 'a gating-F parks the route (state=gated), never complete',
        );
        expect(
          _wroteCursor(f, kRouteNode, 'complete'),
          isFalse,
          reason: 'the route did NOT advance',
        );
        expect(_gateMinted(f), isTrue, reason: 'a real type=gate bead was minted');
        expect(
          transport.flares.map((e) => e.name),
          contains('step.gated'),
        );

        // Surface the gated cursor (as the store would re-project it) → the route
        // parks, land's dep is never satisfied → land NEVER runs, the session
        // NEVER closes. (Positive control: the happy-path test proves land DOES
        // run + close when the route advances.)
        state.push(_state(_session(
          completed: {kAgentNode, ...kCriticNodes},
          gated: {kRouteNode},
          grades: {
            kCriticNodes.first: 'F',
            for (final n in kCriticNodes.skip(1)) n: 'A',
          },
        )));
        await _settle();
        expect(f.git.subcommands, isEmpty, reason: 'land never committed');
        expect(f.pr.opened, isEmpty, reason: 'land never opened a PR');
        expect(_wroteCursor(f, kDeliverNode, 'complete'), isFalse);
        expect(
          f.runner.callsFor('close'),
          isEmpty,
          reason: 'a parked session never closes',
        );
      },
    );
  });
}
