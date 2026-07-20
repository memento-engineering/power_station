// Wave 4 / Track G — CONFORMANCE: the PDR §7 P0 acceptance, tied together
// through the REAL kernel/tree + the REAL `code` extension capabilities.
//
// The six criteria (M4-PDR §7 / M4-P0-BUILD-ORDER), in the reentrant model:
//  (a) a bead runs agent→committee→land as RECONCILE TRANSITIONS — the running
//      frontier SWAPS (stop old / start new — the agent retiring fans the four
//      critics out, then route + land swap through) while the WorkBead branch +
//      its bead-keyed subtree root persist (progress is the per-node cursor
//      INSIDE the subtree, not a WorkBead-level swap);
//  (b) sibling work is untouched across a transition (no spurious spawn/kill);
//  (c) config build() does NOT run on a work tick (the WorkList branch identity
//      is stable);
//  (d) a controller restart respawn-or-skips correctly (terminal SKIPPED, live
//      orphan killed, then re-mount respawns the non-skipped — no double-work,
//      no orphan);
//  (e) risk 5 — spawn-in-flight vs unmount: a SessionScope disposed during the
//      async mint never inflates → never leaks a SPAWN (the cancel-flag
//      contract); the mid-mint session bead is intentionally reaped later;
//  (f) risk 4 — stale-post-restart: a stale prior-incarnation completion is
//      dropped — pinned guard-by-guard on the CapabilityHost (the
//      per-incarnation subscription-cancel AND the _cancelled/mounted handler
//      guard, each isolated + combined).
//
// (a)/(b)/(c) drive the real Station→…→WorkBead→SessionScope→CircuitScope→
// CapabilityHost tree (CircuitResolver + buildCodeRegistry, an StationServices +
// git ServiceBundle over the offline fakes) under a TreeOwner so branch identity
// is walkable; (d)/(e)/(f) re-drive the Track C/D/E mechanisms through the same
// integrated path.
//
// Offline only — FAKES, no live tg/gc/claude/git/network.
import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

// ---------------------------------------------------------------------------
// Builders + branch-walk helpers (the integrated tree, REAL capabilities).
// ---------------------------------------------------------------------------

GraphSnapshot _graph({required List<Bead> beads, required Set<String> ready}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: ready,
      capturedAt: DateTime(2026),
    );

Bead _bead(String id) =>
    Bead(id: id, issueType: IssueType.task, status: BeadStatus.open);

/// Polls [condition] with a REAL short delay, up to [maxTries] — the robust
/// variant the shared [settle] (a bounded `pumpEventQueue` loop, default
/// `maxPumps: 20`) cannot guarantee for a FRESH molecule mint: the mint's
/// `createMolecule` pour rides the REAL `BdCliService.applyGraph`, which
/// writes a genuine temp file (`dart:io`) before the FAKE `BdRunner` boundary
/// is ever reached (`migration_guard_acceptance_test.dart`'s `_pumpUntilReal`
/// documents the same hazard) — a fixed microtask-queue pump count is not
/// reliably enough turns of the REAL event loop for that I/O to settle,
/// especially under full-suite CPU contention (many parallel isolates'
/// dart:io ops competing for the same background thread pool). Bounded, so a
/// genuine regression still FAILS (its [condition] stays false) instead of
/// hanging.
Future<void> _pumpUntilReal(
  bool Function() condition, {
  int maxTries = 500,
}) async {
  for (var i = 0; i < maxTries && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

JoinedSnapshot _joined({
  required List<Bead> beads,
  required Set<String> ready,
  Map<String, SessionProjection> sessions = const {},
}) => JoinedSnapshot(
  graph: _graph(beads: beads, ready: ready),
  sessionsByWorkBead: sessions,
);

/// An adopted MOLECULE session for [workBead] (sessionId [id]) at the given
/// [completed] node set + [grades] (relative nodePath → letter) — the JOIN row
/// the bridge would surface, built DIRECTLY (this suite talks straight to a
/// `JoinedSnapshotNotifier`, bypassing the join bridge / `GraphSnapshot`, so
/// `isMolecule`/`moleculeBeads` are populated here rather than via
/// `committeeSession`'s Bead-list shape). Every node in
/// [kAllCodeCircuitNodes] gets its own `type=step` bead — the whole universe
/// a live molecule mount might reach (`CapabilityHost._stepBeadId` refuses
/// LOUD otherwise) — staged COMPLETE for the whole SPEC phase (bead `pow-6ao`)
/// plus [completed], PENDING everywhere else, so the adopted sessions resolve
/// straight to the BUILD agent and this test's frontier counts stay focused
/// on the code committee (the spec phase's own choreography is
/// `spec_stage_acceptance_test.dart`).
///
/// [grades] stamp `grid.result.<path>.grade` on the GRADED node's OWN step
/// bead, never a session-bead slice: `SessionScope`'s molecule branch derives
/// `results` SOLELY from `moleculeBeads` (R1 re-homed the write off the
/// session bead), so that is the only shape `CodeRouteCapability`'s ambient
/// `SiblingView` actually reads live.
SessionProjection _session(
  String workBead,
  String id, {
  Set<String> completed = const {},
  Map<String, String> grades = const {},
}) {
  final done = {...kSpecPhaseNodes, ...completed};
  final allGrades = {...kSpecGradesAllA, ...grades};
  return SessionProjection(
    workBeadId: workBead,
    sessionId: id,
    isMolecule: true,
    moleculeBeads: [
      for (final node in kAllCodeCircuitNodes)
        _gradedStep(
          stepBead(
            node,
            sessionId: id,
            workBeadId: workBead,
            state: done.contains(node) ? StepState.complete : StepState.pending,
          ),
          node,
          workBead,
          allGrades,
        ),
    ],
  );
}

/// Stamps [b]'s own `grid.result.<workBead>/<node>.grade` when [node] carries
/// a grade in [grades] (the shape [CodeRouteCapability]'s ambient
/// `SiblingView` reads live); returns [b] unchanged otherwise.
Bead _gradedStep(
  Bead b,
  String node,
  String workBead,
  Map<String, String> grades,
) {
  final grade = grades[node];
  if (grade == null) return b;
  return b.copyWith(
    metadata: {
      ...b.metadata,
      ...nodeResultMetadata('$workBead/$node', {'grade': grade}),
    },
  );
}

/// The integrated root: the work-axis notifier + the StationServices + the live
/// `code` registry + the CircuitResolver above the Station; one rig owning `tg`.
/// The git ServiceBundle is provided AT THE SubstationScope (ADR-0008 D5: source
/// control is a per-substation responsibility). `ProcessLeaseVendor` is
/// mounted automatically by `StationKernel`; this manual TreeOwner-driven
/// tree bypasses the kernel entirely, so the molecule process path needs its
/// own vendor here — the SAME default the kernel installs at its root.
Seed _root({
  required JoinedSnapshotNotifier joined,
  required StationServices ctx,
  required CapabilityRegistry registry,
  required ServiceBundle services,
}) => InheritedSeed<JoinedSnapshotNotifier>(
  value: joined,
  child: InheritedSeed<StationServices>(
    value: ctx,
    child: InheritedSeed<ProcessLeaseVendor>(
      value: defaultProcessLeaseVendor(ctx),
      child: InheritedSeed<CapabilityRegistry>(
        value: registry,
        child: InheritedSeed<SessionResolver>(
          value: kCodeResolver,
          child: Station([
            SubstationScope(
              configNotifier: SubstationConfigNotifier(_tgConfig),
              services: services,
              key: const ValueKey('scope.tg'),
            ),
          ]),
        ),
      ),
    ),
  ),
);

List<Branch> _all(Branch root) {
  final out = <Branch>[];
  void walk(Branch b) {
    out.add(b);
    b.visitChildren(walk);
  }

  walk(root);
  return out;
}

Branch _branchWhere(Branch root, bool Function(Seed seed) test) =>
    _all(root).firstWhere((b) => test(b.seed));

Branch? _workBead(Branch root, String beadId) {
  for (final b in _all(root)) {
    final seed = b.seed;
    if (seed is WorkBead && seed.bead.id == beadId) return b;
  }
  return null;
}

/// The live [CapabilityHostState] beneath [root] (the single mounted step host
/// in the isolated mounts). Captured BEFORE dispose so the test can force a stale
/// event into its handler post-unmount (PDR §7 (f) guard-(ii) isolation).
CapabilityHostState capabilityHostState(Branch root) {
  for (final b in _all(root)) {
    if (b is StatefulBranch && b.seed is CapabilityHost) {
      // ignore: invalid_use_of_protected_member
      return b.state as CapabilityHostState;
    }
  }
  throw StateError('no CapabilityHost branch beneath root');
}

/// The WorkList branchId — a config-ancestor rebuild RE-CREATES the WorkList
/// branch (a new branchId), so a STABLE id across a work tick proves the config
/// ancestors did not rebuild.
String _workListId(Branch root) =>
    _branchWhere(root, (s) => s is WorkList).branchId;

/// ROOTED at a real temp dir ([workspaceRoot], [_provisionCheckout]'d with a
/// `.git` marker BEFORE the kernel ever mounts an agent step) rather than the
/// bare `/grid/worktrees/...` synthetic placeholder: the molecule model's live
/// process allocation now runs `assertProvisionedCheckout` (ADR-0009 D3, bead
/// `tg-6jn`) before EVERY agent spawn, which fail-closed REFUSES a workspace
/// with no on-disk `.git` — a real check the retired flat model's capability
/// mount never performed. The land STAGE's own git calls still ride the
/// recording fake (`f.git`), never real git.
ServiceBundle _gitServices(Fakes f, String workspaceRoot) => ServiceBundle(
  // The source control PROVISIONS; the bound DELIVERY METHOD is what a terminal
  // advance actuates (M5 D-4a). gitRunner: the SAME recording fake gitOps wraps
  // — the force-with-lease push records offline (never real git).
  sourceControl: GitSourceControl(
    root: RootCheckout(
      path: workspaceRoot,
      substation: 'tg',
      defaultBranch: 'main',
    ),
  ),
  delivery: GitHubPrDelivery(
    gitOps: GitOps(f.git),
    prOpener: f.pr,
    gitRunner: f.git,
  ),
);

/// Pre-provisions a FAKE git checkout for [beadId] under [root] — a bare
/// `.git` marker directory at the exact path a real [RootCheckout] resolves
/// (`WorktreeLayout.worktreePath`) — so `assertProvisionedCheckout` (ADR-0009
/// D3) sees a real checkout and lets an agent capability mount, instead of
/// fail-closed refusing the offline synthetic worktree. Only the on-disk
/// marker is real; every git INVOCATION still rides the recording fake
/// (`f.git`), never real git.
void _provisionCheckout(String root, String beadId) {
  final path = WorktreeLayout.worktreePath(root, 'tg', beadId);
  Directory('$path/.git').createSync(recursive: true);
}

const _tgConfig = SubstationConfig(
  substationId: 'tg',
  ownedSubstations: {'tg'},
);

void main() {
  group('PDR §7 (a)+(b)+(c) — transitions, sibling isolation, config quiet', () {
    test(
      'a bead runs agent→committee→land as reconcile transitions (the running '
      'frontier swaps, the WorkBead branch + its subtree root persist), a sibling '
      'is untouched, and the config subtree does NOT rebuild on a work tick',
      () async {
        final f = buildFakes(createdId: 'tgdog-sess1');
        f.pr.url = 'https://github.com/memento/genesis/pull/7';
        final shell = RecordingShellRunner();
        final tmp = Directory.systemTemp.createTempSync('pdr-s7-acc');
        addTearDown(() => tmp.deleteSync(recursive: true));
        _provisionCheckout(tmp.path, 'tg-1');
        _provisionCheckout(tmp.path, 'tg-2');
        // The four tg-1 committee critic step names, in declaration order.
        final tg1Critics = [for (final n in kCriticNodes) 'tgdog-1/tg-1/$n'];
        final allA = {for (final n in kCriticNodes) n: 'A'};
        // ADOPTED sessions so the SessionScope resolves synchronously (the manual
        // owner has no kernel self-flush): the agents spawn under one flush.
        final joined = JoinedSnapshotNotifier(
          _joined(
            beads: [_bead('tg-1'), _bead('tg-2')],
            ready: {'tg-1', 'tg-2'},
            sessions: {
              'tg-1': _session('tg-1', 'tgdog-1'),
              'tg-2': _session('tg-2', 'tgdog-2'),
            },
          ),
        );
        final owner = TreeOwner();
        addTearDown(owner.dispose);
        addTearDown(f.provider.close);
        final root = owner.mountRoot(
          _root(
            joined: joined,
            ctx: f.ctx,
            // Inline rubrics so the committee critics build their prompts without
            // a disk read (the on-disk loader is exercised by track_d_assets_test).
            // The landing circuit's rebase/revalidate reuse the SAME recording
            // git fake `land` already lands through, plus a recording shell
            // fake so `revalidate` (the bead's Validation Plan) never spawns a
            // real process (`tg-rm5`).
            registry: buildCodeRegistry(
              rubrics: (id) => '($id rubric bands)',
              gitRunner: f.git,
              shellRunner: shell,
              // A no-op clearer (gate-integrity #3): offline — never a real
              // filesystem touch.
              critiqueDirClearer: (_) {},
            ),
            services: _gitServices(f, tmp.path),
          ),
        );
        await pumpEventQueue();

        // Both beads mounted + spawned their agent (the live `code` capability).
        // FT-2 wraps claude in `sh -c` for usage capture, so the command is `sh`
        // and claude is exec'd from the positionals.
        expect(f.provider.started, hasLength(2));
        expect(f.provider.started.map((s) => s.config.command), ['sh', 'sh']);
        expect(
          f.provider.started.every((s) => s.config.args.contains('claude')),
          isTrue,
        );
        // The molecule lease's own acquire (`stationProcessSpawner`) binds
        // the process handle ONLY once a `SessionStarted` event lands (fails
        // LOUD on Exited/Died first) — unlike the retired flat model, whose
        // `_started` flag went true synchronously at the `transport.start`
        // call. Without it the lease never binds (`_hasHandle` stays false),
        // so a later unmount's release never reaches `transport.stop` — the
        // swap this test proves would go unobserved. Emit it for both
        // spawned agents before driving either further.
        f.provider.emit(
          const SessionStarted(name: 'tgdog-1/tg-1/agent', pid: 101, pgid: 101),
        );
        f.provider.emit(
          const SessionStarted(name: 'tgdog-2/tg-2/agent', pid: 102, pgid: 102),
        );
        await pumpEventQueue();
        final wb1Id = _workBead(root, 'tg-1')!.branchId;
        final wb2Id = _workBead(root, 'tg-2')!.branchId;
        final workListId = _workListId(root);
        // The bead-keyed SessionScope subtree root beneath the WorkBead. Since
        // the context rip-out, WorkBead first mounts the ambient
        // `InheritedSeed<Bead>` (unkeyed), so the session root is the first
        // KEYED descendant, no longer the immediate child.
        Branch effectChild(Branch wb) {
          Branch? found;
          void walk(Branch b) {
            if (found != null) return;
            if (b.key != null) {
              found = b;
              return;
            }
            b.visitChildren(walk);
          }

          wb.visitChildren(walk);
          return found!;
        }

        final sessionRootId = effectChild(_workBead(root, 'tg-1')!).branchId;
        expect(
          effectChild(_workBead(root, 'tg-1')!).key,
          const ValueKey('tg-1:session'),
        );

        // --- (a) agent → committee (a reconcile transition: the agent retires
        // and the four critic lanes fan out IN PARALLEL) ---
        // Advance tg-1's per-node cursor (A40), keep tg-2 untouched.
        joined.push(
          _joined(
            beads: [_bead('tg-1'), _bead('tg-2')],
            ready: {'tg-1', 'tg-2'},
            sessions: {
              'tg-1': _session('tg-1', 'tgdog-1', completed: {kAgentNode}),
              'tg-2': _session('tg-2', 'tgdog-2'),
            },
          ),
        );
        owner.flush();
        await pumpEventQueue();

        // clear-critique (gate-integrity #3, dep-free) then pin-diff
        // (scope-pinning, bead pow-6wo) each ran for real — no provider spawn
        // (both ServiceCapabilities; pin-diff no-ops to Ok since the synthetic
        // worktree does not exist on disk). Re-project both completions so the
        // four critics, which now transitively `dependsOn` them, become ready.
        joined.push(
          _joined(
            beads: [_bead('tg-1'), _bead('tg-2')],
            ready: {'tg-1', 'tg-2'},
            sessions: {
              'tg-1': _session(
                'tg-1',
                'tgdog-1',
                completed: {kAgentNode, kClearCritiqueNode, kPinDiffNode},
              ),
              'tg-2': _session('tg-2', 'tgdog-2'),
            },
          ),
        );
        owner.flush();
        // The unmount's kill is a fire-and-forget Future chain (cancel → lease
        // release → `transport.stop` → clear the breadcrumb) `CapabilityHost
        // .dispose()` never awaits — settle bounded-conditionally on the swap's
        // own signal rather than a single pump.
        await settle(
          () =>
              f.provider.started.length >= 6 &&
              f.provider.stopped.contains('tgdog-1/tg-1/agent'),
        );

        // The running frontier SWAPPED: the agent step was killed and the four
        // critics spawned; the WorkBead branch + its bead-keyed subtree root
        // PERSISTED.
        expect(
          f.provider.started,
          hasLength(6),
          reason: 'the four committee critics fanned out (the swap)',
        );
        for (final critic in tg1Critics) {
          expect(
            f.provider.started.map((s) => s.name),
            contains(critic),
            reason: 'critic $critic fanned out IN PARALLEL',
          );
        }
        // Both lanes spawn `sh` (FT-2 wraps claude for usage capture): the
        // gating lane runs the Validation Plan, an LLM lane exec's claude.
        expect(
          f.provider.started
              .firstWhere((s) => s.name == tg1Critics.first)
              .config
              .command,
          'sh',
          reason: 'the gating critic runs the bead\'s Validation Plan',
        );
        final tg1Llm = f.provider.started
            .firstWhere((s) => s.name == tg1Critics[1])
            .config;
        expect(tg1Llm.command, 'sh');
        expect(
          tg1Llm.args,
          contains('claude'),
          reason: 'an LLM critic exec\'s claude from the sh wrapper',
        );
        expect(
          f.provider.stopped,
          contains('tgdog-1/tg-1/agent'),
          reason: 'the agent step was unmounted → killed',
        );
        expect(
          _workBead(root, 'tg-1')!.branchId,
          wb1Id,
          reason: 'WorkBead branch persists across the transition',
        );
        expect(
          effectChild(_workBead(root, 'tg-1')!).branchId,
          sessionRootId,
          reason: 'the bead-keyed subtree root persists (config threaded down)',
        );
        // No new mint (the sessions are adopted; the happy path mints no gate).
        expect(f.runner.callsFor('create'), isEmpty);

        // --- (b) the sibling tg-2 was untouched across tg-1's transition ---
        expect(
          _workBead(root, 'tg-2')!.branchId,
          wb2Id,
          reason: 'sibling WorkBead branch unchanged',
        );
        // No spurious sibling fan-out: tg-2 started exactly once (its agent) and
        // never appears in stopped. The new starts are all tg-1's critics.
        expect(
          f.provider.started.where((s) => s.name.startsWith('tgdog-2')),
          hasLength(1),
          reason: 'tg-2 did not fan out a committee of its own',
        );
        expect(f.provider.stopped, isNot(contains('tgdog-2/tg-2/agent')));

        // --- (c) the config subtree did NOT rebuild on the work tick ---
        expect(
          _workListId(root),
          workListId,
          reason: 'a work tick does not rebuild the config ancestors',
        );

        // The four critics' own leases likewise need their `SessionStarted`
        // before their later unmount can release (see the agent's above).
        for (var i = 0; i < tg1Critics.length; i++) {
          f.provider.emit(
            SessionStarted(name: tg1Critics[i], pid: 200 + i, pgid: 200 + i),
          );
        }
        await pumpEventQueue();

        // --- (a) continued: committee → route (the critics retire, the route
        // joins on all four, reads the all-pass grades, and advances) ---
        joined.push(
          _joined(
            beads: [_bead('tg-1'), _bead('tg-2')],
            ready: {'tg-1', 'tg-2'},
            sessions: {
              'tg-1': _session(
                'tg-1',
                'tgdog-1',
                completed: {kAgentNode, ...kCriticNodes},
                grades: allA,
              ),
              'tg-2': _session('tg-2', 'tgdog-2'),
            },
          ),
        );
        owner.flush();
        await settle(() => tg1Critics.every(f.provider.stopped.contains));

        // The four critic steps were killed on the swap; the route is a
        // ServiceCapability (no provider spawn), so no new start lands.
        expect(
          f.provider.stopped,
          containsAll(tg1Critics),
          reason: 'every critic step was unmounted → killed once the route ran',
        );
        expect(
          f.provider.started,
          hasLength(6),
          reason: 'the route does not spawn a process',
        );

        // --- (a) continued: route → land (the final transition — `tg-rm5`'s
        // landing sub-circuit: rebase → revalidate → land, each a
        // ServiceCapability, so no NEW provider spawn lands at any hop) ---
        joined.push(
          _joined(
            beads: [_bead('tg-1'), _bead('tg-2')],
            ready: {'tg-1', 'tg-2'},
            sessions: {
              'tg-1': _session(
                'tg-1',
                'tgdog-1',
                completed: {kAgentNode, ...kCriticNodes, kRouteNode},
                grades: allA,
              ),
              'tg-2': _session('tg-2', 'tgdog-2'),
            },
          ),
        );
        owner.flush();
        await pumpEventQueue();

        joined.push(
          _joined(
            beads: [_bead('tg-1'), _bead('tg-2')],
            ready: {'tg-1', 'tg-2'},
            sessions: {
              'tg-1': _session(
                'tg-1',
                'tgdog-1',
                completed: {
                  kAgentNode,
                  ...kCriticNodes,
                  kRouteNode,
                  kRebaseNode,
                },
                grades: allA,
              ),
              'tg-2': _session('tg-2', 'tgdog-2'),
            },
          ),
        );
        owner.flush();
        await pumpEventQueue();

        joined.push(
          _joined(
            beads: [_bead('tg-1'), _bead('tg-2')],
            ready: {'tg-1', 'tg-2'},
            sessions: {
              'tg-1': _session(
                'tg-1',
                'tgdog-1',
                completed: {
                  kAgentNode,
                  ...kCriticNodes,
                  kRouteNode,
                  kRebaseNode,
                  kRevalidateNode,
                },
                grades: allA,
              ),
              'tg-2': _session('tg-2', 'tgdog-2'),
            },
          ),
        );
        owner.flush();
        await pumpEventQueue();

        // land is a ServiceCapability (git/PR orchestration) — NOT a provider
        // spawn (still 6 starts); the land Service ran its real orchestration
        // through the fakes; the WorkBead branch still persists.
        expect(
          f.provider.started,
          hasLength(6),
          reason: 'land does not spawn a process',
        );
        expect(
          _workBead(root, 'tg-1')!.branchId,
          wb1Id,
          reason: 'the WorkBead branch still persists at land',
        );
        expect(
          f.git.subcommands,
          containsAll(<String>['add', 'commit', 'push']),
        );
        expect(f.pr.opened, isNotEmpty);
      },
    );
  });

  group('PDR §7 (d) — controller restart respawn-or-skip', () {
    test(
      'a terminal bead is SKIPPED (reaped, no respawn); a live orphan is killed; '
      'then the re-mounted tree respawns the non-skipped — no double-work',
      () async {
        // --- the restart reconciler pass (Track D), through the real type ---
        // Built FIRST (not just for the re-mount below) — the molecule lease
        // sweep needs a real `StationBeadWriter` chokepoint (the vendor's
        // breadcrumb clear) via `f.ctx`.
        final f = buildFakes(createdId: 'tgdog-l');
        final reaped = <String>[];
        final signals = <int>[];
        final reconciler = RestartReconciler(
          listWorktrees: (root) async => [
            BeadWorktree(
              beadId: 'tg-done',
              path: '/tmp/grid/.grid/worktrees/tg/tg-done',
              branch: 'grid/tg-done',
            ),
            BeadWorktree(
              beadId: 'tg-live',
              path: '/tmp/grid/.grid/worktrees/tg/tg-live',
              branch: 'grid/tg-live',
            ),
          ],
          reapWorktree: ({required root, required worktree}) async {
            reaped.add(worktree.beadId);
            return ReapOutcome.removed();
          },
          workRoot: const RootCheckout(
            path: '/tmp/grid',
            defaultBranch: 'main',
            substation: 'tg',
          ),
          groups: _RecordingGroups(signals, alivePids: {4243}),
          freshnessBarrier: () async {},
          // The molecule model is the ONE process-identity reconciliation
          // (tg-eli phase 2 retired the flat per-session scalar `pgid`/`pid`
          // kill walk `_reconcileWorktree` used to drive — `RestartDisposition
          // .killed` is HISTORICAL and no pass emits it any more): the
          // reconciler's own `sweepOrphanedLeases` pass needs a vendor.
          leaseVendor: defaultProcessLeaseVendor(f.ctx),
          stateSnapshot: () => _graph(
            beads: [
              // tg-done: terminal owned session ⇒ SKIP.
              Bead(
                id: 'tgdog-d',
                issueType: IssueType.session,
                status: BeadStatus.closed,
                metadata: const {'rig': 'tgdog', 'work_bead': 'tg-done'},
              ),
              // tg-live: a live MOLECULE session backing a surviving worktree.
              Bead(
                id: 'tgdog-l',
                issueType: IssueType.session,
                status: BeadStatus.open,
                metadata: const {
                  'rig': 'tgdog',
                  'work_bead': 'tg-live',
                  SessionBeadKeys.model: kSessionModelMolecule,
                },
              ),
              // Its OWN `type=step` bead carries the vendor's `grid.lease.*`
              // breadcrumb (Decided item 5) for a still-RUNNING job whose
              // process group nothing will re-adopt (a job lease never
              // adopts, D5) — a live orphan the sweep kills + clears.
              Bead(
                id: 'tgdog-l-agent',
                issueType: IssueType.step,
                status: BeadStatus.open,
                metadata: const {
                  'rig': 'tgdog',
                  MoleculeStepKeys.stepId: 'agent',
                  MoleculeStepKeys.capability: 'agent',
                  MoleculeStepKeys.kind: 'job',
                  MoleculeStepKeys.path: 'tg-live/agent',
                  MoleculeStepKeys.session: 'tgdog-l',
                  MoleculeStepKeys.state: 'running',
                  'grid.lease.pgid': '4242',
                  'grid.lease.pid': '4243',
                  'grid.lease.token': 'restart-tok-1',
                },
              ),
            ],
            ready: const {},
          ),
        );
        final report = await reconciler.reconcile();

        expect(report.skipped.map((e) => e.beadId), ['tg-done']);
        // The lease sweep — not `report.killed` (HISTORICAL, always empty
        // since tg-eli phase 2) — is the molecule kill proof.
        final swept = report.sweptLeases;
        expect(
          swept.map((g) => g.stepBeadId),
          ['tgdog-l-agent'],
          reason: "the live orphan's OWN step bead was swept",
        );
        expect(swept.single.disposition.name, 'killed');
        expect(reaped, ['tg-done'], reason: 'only the done bead is reaped');
        expect(signals, [4242], reason: 'only the live orphan is signalled');
        // The breadcrumb clear rides the SAME chokepoint every other molecule
        // write does.
        expect(
          f.runner.callsFor('update').any((c) => c.contains('tgdog-l-agent')),
          isTrue,
          reason:
              'the swept lease\'s breadcrumb was cleared through the '
              'chokepoint',
        );
        // The done bead does NOT respawn; the live (swept) bead does.
        expect(report.respawnCount, 1);

        // --- the re-mount (the tree comes back) ---
        // The kernel re-mounts: only the non-skipped bead is still in the work
        // graph (the done bead's work is complete). The respawn is a single fresh
        // spawn — no double-work (the orphan group was killed first).
        final work = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final state = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final bridge = StationJoinBridge(work: work, state: state);
        final kernel = StationKernel(
          bridge: bridge,
          stationServices: f.ctx,
          resolver: kCodeResolver,
          registry: buildCodeRegistry(),
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
        // Post-restart the live bead is still ready; the done bead is gone. The
        // readiness ladder's `intake` head is deterministic (bead `pow-q7n`, zero
        // agents), so re-project it complete before the first AGENT can spawn.
        work.push(_graph(beads: [_bead('tg-live')], ready: {'tg-live'}));
        await pumpEventQueue();
        state.push(
          _graph(
            beads: ladderDoneSession(id: 'tgdog-l', workBeadId: 'tg-live'),
            ready: const {},
          ),
        );
        // The molecule mint chain (mint → stamp model → dedup export probe →
        // pour steps via `create --graph`) is a longer async chain than one
        // pump, and its `applyGraph` leg does REAL `dart:io` temp-file I/O —
        // a bounded `pumpEventQueue` loop (the shared [settle]) is not
        // reliably enough turns of the real event loop under full-suite CPU
        // load (the exact `_pumpUntilReal` hazard `migration_guard_acceptance_
        // test.dart` documents), so poll on REAL wall-clock ticks instead.
        await _pumpUntilReal(() => f.provider.started.isNotEmpty);

        expect(
          f.provider.started,
          hasLength(1),
          reason: 'the non-skipped bead respawns exactly once (no double-work)',
        );
        expect(f.provider.started.single.config.env['GRID_BEAD_ID'], 'tg-live');
      },
    );
  });

  group('PDR §7 (e) — risk 5: spawn-in-flight vs unmount', () {
    test(
      'a SessionScope disposed DURING the async createSession never inflates the '
      'circuit → never leaks a SPAWN (the cancel-flag contract); the mid-mint '
      'session bead is intentionally reaped later by the RestartReconciler',
      () async {
        // Gate the create so dispose lands mid-mint.
        final runner = GatedCreateBdRunner();
        final provider = FakeRuntimeProvider();
        final ctx = StationServices(
          provider: provider,
          writer: StationBeadWriter(
            bd: BdCliService(runner),
            ownership: BeadOwnershipPredicate(const {stateSubstation}),
          ),
          stateSubstation: stateSubstation,
        );
        addTearDown(provider.close);

        // Mount the real reentrant subtree root (a SessionScope rooting the
        // `code` circuit) with NO existing session ⇒ it MINTS. The ambient
        // Bead is mounted above (as WorkBead does since the context rip-out)
        // so a leaked spawn WOULD succeed — keeping the no-leak assertion
        // non-vacuous.
        final owner = TreeOwner();
        owner.mountRoot(
          InheritedSeed<StationServices>(
            value: ctx,
            child: InheritedSeed<CapabilityRegistry>(
              value: buildCodeRegistry(),
              child: InheritedSeed<Bead>(
                value: bead('tg-1'),
                child: kCodeResolver.sessionFor(bead: bead('tg-1')),
              ),
            ),
          ),
        );

        // The mint is parked awaiting createSession. Dispose now (the unmount).
        await pumpEventQueue();
        expect(runner.createPending, isTrue, reason: 'create is in-flight');
        owner.dispose();

        // Resolve the create — the post-create guard must abort before the
        // SessionScope resolves, so the circuit never inflates and no leaf spawns.
        runner.releaseCreate('tgdog-sess1');
        await pumpEventQueue();

        expect(
          provider.started,
          isEmpty,
          reason: 'spawn never leaks after a mid-mint dispose',
        );
        expect(
          provider.stopped,
          isEmpty,
          reason: 'never spawned ⇒ dispose issues no stop',
        );
        // NB: the `bd create` of the session bead is ALREADY issued to the runner
        // before the post-create dispose guard fires — by design. A mid-mint
        // dispose intentionally leaves an orphan session bead that the
        // RestartReconciler reaps later (PDR §7 (d)). The P0 risk this test
        // guards is the leaked SUBPROCESS, asserted above.
      },
    );
  });

  group('PDR §7 (f) — risk 4: stale-post-restart completion is dropped', () {
    // Defense-in-depth on the CapabilityHost: a stale prior-incarnation
    // completion is stopped by TWO independent guards — (i) the per-incarnation
    // subscription is cancelled on dispose, so the event is never even
    // delivered; AND (ii) even if the event WERE delivered (a regression in
    // cancellation), the _cancelled/mounted guard in the handler drops it. Each
    // is pinned by its own assertion.

    /// Mounts the agent step host (an ADOPTED session so it resolves + spawns
    /// synchronously), returning the owner + root. The ambient Bead is mounted
    /// above the sessionFor subtree (as WorkBead does since the context
    /// rip-out) — the agent capability reads it with the effect verb.
    ({TreeOwner owner, Branch root}) mountAgent(Fakes f) {
      final owner = TreeOwner();
      final root = owner.mountRoot(
        InheritedSeed<StationServices>(
          value: f.ctx,
          // Mounted automatically by StationKernel; this manual TreeOwner-driven
          // tree bypasses the kernel entirely, so the molecule process path
          // needs its own vendor here — the SAME default the kernel installs.
          child: InheritedSeed<ProcessLeaseVendor>(
            value: defaultProcessLeaseVendor(f.ctx),
            child: InheritedSeed<CapabilityRegistry>(
              value: buildCodeRegistry(),
              child: InheritedSeed<Bead>(
                value: bead('tg-1'),
                child: kCodeResolver.sessionFor(
                  bead: bead('tg-1'),
                  session: _session('tg-1', 'tgdog-sess1'),
                ),
              ),
            ),
          ),
        ),
      );
      return (owner: owner, root: root);
    }

    test('(i) the per-incarnation event subscription is CANCELLED on dispose — '
        'no event is delivered to the disposed host at all', () async {
      final f = buildFakes(createdId: 'tgdog-sess1');
      final m = mountAgent(f);
      addTearDown(f.provider.close);
      await pumpEventQueue();
      expect(f.provider.started, hasLength(1));
      // The live host holds exactly ONE subscription to the event stream.
      expect(
        f.provider.eventListenerCount,
        1,
        reason: 'the mounted host subscribes to its step events',
      );
      // The molecule lease's acquire (`stationProcessSpawner`) binds the
      // process handle only once `SessionStarted` lands — without it the
      // lease never binds, so dispose's release path (which cancels the
      // tap) never reaches it either. Emit it before the restart boundary.
      f.provider.emit(
        const SessionStarted(name: 'tgdog-sess1/tg-1/agent', pid: 9, pgid: 8),
      );
      await pumpEventQueue();

      // The restart boundary: the prior incarnation's branch is disposed.
      m.owner.dispose();
      await pumpEventQueue();

      // The subscription is gone — a future edit that drops the dispose-time
      // `_sub.cancel()` would leave this at 1 and fail HERE.
      expect(
        f.provider.eventListenerCount,
        0,
        reason: 'dispose cancels the per-incarnation subscription',
      );
    });

    test(
      '(ii) even if a stale event is delivered, the _cancelled/mounted guard in '
      'the handler drops it — no cursor write',
      () async {
        final f = buildFakes(createdId: 'tgdog-sess1');
        final m = mountAgent(f);
        addTearDown(f.provider.close);
        await pumpEventQueue();
        expect(f.provider.started, hasLength(1));
        final updatesBefore = f.runner.callsFor('update').length;

        // Reach the live CapabilityHostState so we can invoke its handler
        // directly AFTER dispose (modelling a delivery that bypassed
        // cancellation). This isolates the SECOND guard.
        final hostState = capabilityHostState(m.root);
        m.owner.dispose();
        await pumpEventQueue();

        // Force-deliver a stale completion straight into the handler. The
        // _cancelled/mounted guard must drop it.
        hostState.deliverEventForTest(
          const Exited(name: 'tgdog-sess1/tg-1/agent', exitCode: 0),
        );
        await expectLater(pumpEventQueue(), completes);

        expect(
          f.runner.callsFor('update'),
          hasLength(updatesBefore),
          reason: 'the handler guard drops a delivered stale completion',
        );
      },
    );

    test(
      'combined: a stale Exited + SessionStarted reaching a disposed host writes '
      'nothing and never throws (both guards together)',
      () async {
        final f = buildFakes(createdId: 'tgdog-sess1');
        final m = mountAgent(f);
        addTearDown(f.provider.close);
        await pumpEventQueue();
        expect(f.provider.started, hasLength(1));
        final updatesBefore = f.runner.callsFor('update').length;

        // Simulate the restart boundary: the prior incarnation's branch is gone
        // (dispose cancels its per-incarnation subscription). A STALE completion
        // for that incarnation then arrives on the shared event stream.
        m.owner.dispose();
        f.provider.emit(
          const Exited(name: 'tgdog-sess1/tg-1/agent', exitCode: 0),
        );
        f.provider.emit(
          const SessionStarted(name: 'tgdog-sess1/tg-1/agent', pid: 1, pgid: 2),
        );

        // No throw escapes (an unhandled async error would fail the test), and
        // the stale completion advanced NO cursor.
        await expectLater(pumpEventQueue(), completes);
        expect(
          f.runner.callsFor('update'),
          hasLength(updatesBefore),
          reason: 'a stale prior-incarnation completion writes nothing',
        );
      },
    );
  });
}

/// A process-group seam that records signalled pgids and kills the group on
/// SIGTERM/SIGKILL (so the REAL terminateGroup observes the exit and returns
/// exitedOnTerm) — the PDR §7 (d) live-orphan-kill arm.
class _RecordingGroups implements ProcessGroupController {
  _RecordingGroups(this.signals, {Set<int> alivePids = const {}})
    : _alive = {...alivePids};

  final List<int> signals;
  final Set<int> _alive;

  @override
  int currentGroupId() => 999;

  @override
  bool processAlive(int pid) => _alive.contains(pid);

  @override
  Future<int?> resolvePgid(int pid) async => null;

  @override
  bool signalGroup(int pgid, ProcessSignal signal) {
    signals.add(pgid);
    if (signal == ProcessSignal.sigterm || signal == ProcessSignal.sigkill) {
      _alive.clear();
    }
    return true;
  }
}
