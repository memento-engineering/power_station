// Wave 4 / Track G — CONFORMANCE: derailment-invariant 2.
//
// "Only the chokepoint writes." (ADR-0006 Decision 2 / A32.) Every bd mutation
// the_grid issues flows through the single StationBeadWriter chokepoint — bd-only,
// `--actor grid-controller`, fail-closed on ownership, never a `bd show` and
// never raw `sql`. And no write EVER happens inside a `build()`: the capability
// hosts act in initState / on a runtime event / dispose; `build()` is a pure
// Idle leaf.
//
// This drives a FULL agent→committee→land cycle through the REAL `runGrid`
// station root + the REAL `code` circuit (CircuitResolver + buildCodeRegistry —
// agent → the four adversarial critics → route → land) with a
// RecordingBdRunner-backed StationBeadWriter (the chokepoint) + the fake
// provider/git/PR, emitting SessionStarted + a clean completion per step and
// advancing the per-node cursor (+ all-pass grades) via the fake STATE source.
// It then asserts the chokepoint discipline over the WHOLE recorded call log.
//
// Offline only — FAKES, no live tg/gc/claude/git/network.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

const _sid = 'tgdog-sess1';

GraphSnapshot _graph({required List<Bead> beads, required Set<String> ready}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: ready,
      capturedAt: DateTime(2026),
    );

/// Stamps [results] (relative nodePath → its `grid.result.*` payload) onto the
/// OWN metadata of each matching `type=step` bead in [beads] — LOCAL to this
/// file (never `asset_fakes.dart`). `committeeSession`'s own `grades:`/
/// `results:` params stamp `grid.result.*` onto the SESSION bead (R1's
/// pre-molecule habit, `nodeResultMetadata`), but a molecule session's
/// `SessionScope` reads `results` EXCLUSIVELY off each `type=step` bead's OWN
/// `grid.result.*` (`session_scope.dart`'s `stepResults` scan) — the session
/// bead's copy is never read. Without this: (a) every critic reads as "no
/// parseable verdict" and fails CLOSED to `F` — a route gate the ORIGINAL
/// flat-cursor test never triggered; (b) the terminal `deliver` step's own
/// `delivery` result key is invisible, so `_deliveryOutcomeReady` never sees
/// it and the session never closes even after `deliver` genuinely ran.
List<Bead> _stampStepResults(
  List<Bead> beads, {
  required String workBeadId,
  required Map<String, Map<String, String>> results,
}) => [
  for (final b in beads)
    if (b.issueType == GridIssueTypes.step &&
        (b.metadata[MoleculeStepKeys.path] as String?)?.startsWith(
              '$workBeadId/',
            ) ==
            true &&
        results.containsKey(
          (b.metadata[MoleculeStepKeys.path] as String).substring(
            workBeadId.length + 1,
          ),
        ))
      b.copyWith(
        metadata: {
          ...b.metadata,
          ...nodeResultMetadata(
            b.metadata[MoleculeStepKeys.path] as String,
            results[(b.metadata[MoleculeStepKeys.path] as String).substring(
              workBeadId.length + 1,
            )],
          ),
        },
      )
    else
      b,
];

/// A one-bead STATE snapshot carrying the committee session for `tg-1` at the
/// given [completed] node set + [grades] (the shared `committeeSession` builds
/// the per-node cursor; [_stampStepResults] re-homes the grades — and, once
/// [deliverDone], the terminal delivery result — onto each node's OWN step
/// bead, see its doc). The SPEC phase (bead `pow-6ao`) rides every push fully
/// complete + all-A — its writes are the same chokepoint mutations this
/// invariant audits, and its choreography is proven in
/// `spec_stage_acceptance_test.dart`.
GraphSnapshot _stateAt({
  Set<String> completed = const {},
  Map<String, String> grades = const {},
  bool deliverDone = false,
}) => _graph(
  beads: _stampStepResults(
    committeeSession(
      id: _sid,
      completed: {...kSpecPhaseNodes, ...completed},
      grades: {...kSpecGradesAllA, ...grades},
    ),
    workBeadId: 'tg-1',
    results: {
      for (final entry in {...kSpecGradesAllA, ...grades}.entries)
        entry.key: {ResultKeys.grade: entry.value},
      if (deliverDone) kDeliverNode: {ResultKeys.delivery: 'github-pr'},
    },
  ),
  ready: const {},
);

/// The committee critic step (provider) name for relative node [rel].
String _step(String rel) => '$_sid/tg-1/$rel';

/// The four critic provider names, in committee order.
final List<String> _criticSteps = [
  for (final n in kProcessCriticNodes) _step(n),
];

/// All-pass grades (the happy committee — the route advances, never gates).
final Map<String, String> _allA = {for (final n in kCriticNodes) n: 'A'};

/// The live `code` registry + a git ServiceBundle so the land capability runs
/// its commit→push→PR through the fakes.
///
/// NO [ServiceBundle.sourceControl] here (`const GitSourceControl()` — the
/// original wiring — was removed): `allocation.dart` calls
/// `assertProvisionedCheckout` unconditionally whenever `sourceControl` is
/// non-null, requiring a REAL `.git` on disk at the workspace path, which
/// `GitSourceControl()` (no provisioner/root — the offline shape) never
/// creates (`provisionWorkspace` no-ops: "Provisioning not wired"). Leaving
/// `sourceControl` null skips that call entirely (`SessionScope` still mounts
/// the SYNTHETIC placeholder `Workspace`, `code_capabilities.dart`), which is
/// also the shape [PinDiffCapability] itself assumes offline — it no-ops the
/// SAME way ("the synthetic worktree does not exist on disk") only when the
/// workspace directory does not exist at all. Land still runs for real through
/// the fake git ops below (`GitOps(f.git)`), independent of `sourceControl`.
ServiceBundle _gitServices(Fakes f) => ServiceBundle(
  delivery: GitHubPrDelivery(
    gitOps: GitOps(f.git),
    prOpener: f.pr,
    gitRunner: f.git,
  ),
);

void main() {
  group('invariant 2 — only the chokepoint writes', () {
    test('a full agent→committee→land cycle through the kernel: EVERY bd write is a '
        'chokepoint mutation (create/update/close), carries --actor '
        'grid-controller, and NO bd show / sql ever appears', () async {
      final f = buildFakes(createdId: _sid);
      f.pr.url = 'https://github.com/memento/genesis/pull/7';
      final shell = RecordingShellRunner();
      final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
      final state = FakeSnapshotSource(
        _graph(beads: const [], ready: const {}),
      );
      final bridge = StationJoinBridge(work: work, state: state);
      final station = MountedStation(
        bridge: bridge,
        stationServices: f.ctx,
        resolver: kCodeResolver,
        // Inline rubrics so the committee critics build their prompts without a
        // disk read (the on-disk loader is exercised by track_d_assets_test).
        // The landing circuit's rebase/revalidate reuse the SAME recording git
        // fake `land` already lands through, plus a recording shell fake so
        // `revalidate` (the bead's Validation Plan) never spawns a real process.
        registry: buildCodeRegistry(
          rubrics: (id) => '($id rubric bands)',
          gitRunner: f.git,
          shellRunner: shell,
          // A no-op clearer (gate-integrity #3): offline — never a real
          // filesystem touch.
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
            // The git services are provided AT THE SCOPE (ADR-0008 D5), so the
            // land capability resolves this substation's SourceControl.
            services: _gitServices(f),
            key: const ValueKey('scope.tg'),
          ),
        ],
      );
      addTearDown(station.dispose);
      addTearDown(f.provider.close);
      addTearDown(work.close);
      addTearDown(state.close);

      await station.start();
      await pumpEventQueue();

      // 1) LADDER → SPECIFY → AGENT — a ready owned task mounts the readiness
      //    ladder's head (`intake`, a zero-agent ServiceCapability — bead
      //    `pow-q7n`); the chokepoint mints the session bead (create + the
      //    birth stamp = one update). Re-project the ladder complete → SPECIFY
      //    is the first agent (bead `pow-6ao`); fast-forward the spec phase (an
      //    all-pass spec committee via cursor adoption) → the build agent swaps
      //    in. The step's provider name is '<sessionId>/<nodePath>'.
      //
      // The molecule mint (tg-eli phase 2: mint → stamp model → dedup export
      // probe → pour steps via `create --graph`) is a LONGER async chain than
      // a fixed small pump count settles — [settle] bounds it on the mint's
      // own `create` call landing.
      work.push(_graph(beads: [workBead('tg-1')], ready: {'tg-1'}));
      await settle(() => f.runner.callsFor('create').isNotEmpty);
      expect(
        f.provider.started,
        isEmpty,
        reason: 'the ladder head spawns NO agent — intake is deterministic',
      );
      state.push(
        _graph(
          beads: [...ladderDoneSession(id: _sid)],
          ready: const {},
        ),
      );
      await settle(() => f.provider.started.isNotEmpty);
      expect(f.provider.started, hasLength(1));
      expect(f.provider.started.single.name, _step(kSpecifyNode));
      f.provider.emit(Exited(name: _step(kSpecifyNode), exitCode: 0));
      await pumpEventQueue();
      state.push(_stateAt());
      await settle(() => f.provider.started.length >= 2);
      expect(f.provider.started.last.name, _step('agent'));

      // SessionStarted → per-node identity stamped through the chokepoint.
      f.provider.emit(
        SessionStarted(name: _step('agent'), pid: 112, pgid: 111),
      );
      await pumpEventQueue();

      // agent completes → its host writes agent=complete (a chokepoint update);
      // the STATE source surfaces the advance → the `review` sub-circuit inflates
      // its four critic lanes IN PARALLEL.
      f.provider.emit(Exited(name: _step('agent'), exitCode: 0));
      await pumpEventQueue();
      state.push(_stateAt(completed: {kAgentNode}));
      await pumpEventQueue();
      // clear-critique (gate-integrity #3), pin-diff (scope-pinning, bead
      // pow-6wo), then the DETERMINISTIC FRONTIER (format-clean +
      // declared-tests-present, bead pow-jicn) each ran for real through the
      // chokepoint (ServiceCapabilities, no provider spawn); re-project every
      // completion so the four critics — which now transitively `dependsOn`
      // them — mount.
      state.push(
        _stateAt(
          completed: {
            kAgentNode,
            kClearCritiqueNode,
            kPinDiffNode,
            kFormatCleanNode,
            'review/declared-tests-present',
          },
        ),
      );
      await settle(() => f.provider.started.length >= 6);
      expect(
        f.provider.started,
        hasLength(6),
        reason:
            'the four committee critics fanned out after specify + '
            'the agent',
      );

      // 2) COMMITTEE — every critic completes; the STATE source surfaces the
      //    advanced cursor + all-pass grades, and the route joins (await-all),
      //    reads the grades, and advances (a chokepoint update; no gate minted).
      //
      // SessionStarted BEFORE Exited for EACH critic — the molecule model's
      // process lifecycle now treats an `Exited` with no prior
      // `SessionStarted` as a crash ("process exited before SessionStarted"),
      // unlike the retired flat model, which never enforced the ordering.
      var pid = 200;
      for (final critic in _criticSteps) {
        f.provider.emit(SessionStarted(name: critic, pid: pid, pgid: pid));
        pid++;
      }
      await pumpEventQueue();
      for (final critic in _criticSteps) {
        f.provider.emit(Exited(name: critic, exitCode: 0));
      }
      await pumpEventQueue();
      // completed sets from here on are CUMULATIVE (never let clear-critique
      // /pin-diff regress complete→pending in a later push — the molecule
      // model persists each node on its OWN step bead, so a push that omits a
      // previously-complete node re-stages it `pending`, a real regression
      // the flat single-cursor model never had a way to express).
      var writesBefore = f.runner.calls.length;
      state.push(
        _stateAt(
          completed: {
            kAgentNode,
            kClearCritiqueNode,
            kPinDiffNode,
            ...kCriticNodes,
          },
          grades: _allA,
        ),
      );
      await settle(() => f.runner.calls.length > writesBefore);

      // 3) LANDING — route complete → the `land` SubCircuitStep inflates
      //    (`tg-rm5`): rebase → revalidate → land, each a ServiceCapability (no
      //    provider spawn) running for real through the fakes.
      writesBefore = f.runner.calls.length;
      state.push(
        _stateAt(
          completed: {
            kAgentNode,
            kClearCritiqueNode,
            kPinDiffNode,
            ...kCriticNodes,
            kRouteNode,
          },
          grades: _allA,
        ),
      );
      await settle(() => f.runner.calls.length > writesBefore);
      writesBefore = f.runner.calls.length;
      state.push(
        _stateAt(
          completed: {
            kAgentNode,
            kClearCritiqueNode,
            kPinDiffNode,
            ...kCriticNodes,
            kRouteNode,
            kRebaseNode,
          },
          grades: _allA,
        ),
      );
      await settle(() => f.runner.calls.length > writesBefore);
      writesBefore = f.runner.calls.length;
      state.push(
        _stateAt(
          completed: {
            kAgentNode,
            kClearCritiqueNode,
            kPinDiffNode,
            ...kCriticNodes,
            kRouteNode,
            kRebaseNode,
            kRevalidateNode,
          },
          grades: _allA,
        ),
      );
      await settle(() => f.runner.calls.length > writesBefore);

      // 4) The terminal (land) is complete; the STATE source surfaces it and
      //    SessionScope closes the session.
      state.push(
        _stateAt(
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
          grades: _allA,
          deliverDone: true,
        ),
      );
      await settle(() => f.runner.callsFor('close').isNotEmpty);

      // --- The chokepoint discipline over the WHOLE recorded log ---

      // The cycle actually produced writes (else the assertions are vacuous).
      // Asserted by SHAPE, not by a bare count (power_station #119's idiom,
      // ported): a hard total flips between a published-dep run and a
      // path-override run, because the `mount-attempt` admission write only
      // exists once grid_engine >= tg-zlfu resolves. The claims below hold
      // under both, and an unrecognised create still fails — by NAME.
      final createdTypes = _createdTypes(f.runner);
      expect(createdTypes.where((t) => t == 'session'), hasLength(1));
      expect(createdTypes.where((t) => t == 'graph'), hasLength(1));
      expect(
        createdTypes.toSet(),
        everyElement(isIn(const ['session', 'mount-attempt', 'graph'])),
      );
      expect(f.runner.callsFor('update'), isNotEmpty);
      expect(f.runner.callsFor('close'), hasLength(1));
      // The land Service really ran its orchestration through the fakes.
      expect(f.git.subcommands, containsAll(<String>['add', 'commit', 'push']));
      expect(f.pr.opened, isNotEmpty);

      // (a) NO bd write bypasses the chokepoint: the ONLY BdRunner in the
      //     system is the one inside the StationBeadWriter, so EVERY recorded bd
      //     call IS a chokepoint call. A `show` or `sql` would mean a bypass.
      expect(
        f.runner.neverShowOrSql,
        isTrue,
        reason: 'no bd show / sql ever issued (the chokepoint forbids them)',
      );

      // (b) every recognised mutation carried --actor grid-controller.
      const mutations = {'create', 'update', 'close', 'delete', 'batch'};
      for (final c in f.runner.calls) {
        if (c.isEmpty || !mutations.contains(c.first)) continue;
        final i = c.indexOf('--actor');
        expect(
          i >= 0 && i + 1 < c.length && c[i + 1] == 'grid-controller',
          isTrue,
          reason: 'mutation $c lacked --actor grid-controller',
        );
      }

      // (c) every bd call is one of the chokepoint's allowed subcommands —
      //     nothing else (a positive whitelist, so an unexpected escape is
      //     caught even if it is not `show`/`sql`). `export` joins the
      //     mutation verbs here (tg-eli phase 2): `StationBeadWriter`'s OWN
      //     molecule mint issues `export --all` as its mint-dedup probe
      //     (`asset_fakes.dart`'s "mint → stamp model → dedup export probe →
      //     pour steps" chain) — still issued FROM INSIDE the one chokepoint,
      //     never a bypass of it, just not a WRITE (so (a)/(b) above rightly
      //     leave it out of `mutations`).
      const allowed = {
        'create',
        'update',
        'close',
        'delete',
        'batch',
        'export',
      };
      for (final c in f.runner.calls) {
        expect(
          c.isNotEmpty && allowed.contains(c.first),
          isTrue,
          reason: 'unexpected bd subcommand bypassing the chokepoint: $c',
        );
      }
    });
  });
}

/// The `--type` of every recorded `create`, in order, with `create --graph`
/// (which carries no `--type`) reported as `graph` — power_station #119's
/// shape-based idiom, shared verbatim with grid_assets' copy of this suite.
List<String> _createdTypes(dynamic runner) => [
  for (final call in runner.callsFor('create') as List<List<String>>)
    if (call.contains('--type'))
      call[call.indexOf('--type') + 1]
    else if (call.contains('--graph'))
      'graph'
    else
      'unknown',
];
