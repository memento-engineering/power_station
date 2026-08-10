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
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart' show ProviderScope;
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
}) => ProviderScope(
  // The availability registry the production root (StationKernel.start)
  // always mounts — watch<T>() misses park here instead of asserting.
  child: InheritedSeed<JoinedSnapshotNotifier>(
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
}
