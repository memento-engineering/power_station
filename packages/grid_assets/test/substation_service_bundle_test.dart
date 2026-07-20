// ADR-0008 D5 — source control is a PER-SUBSTATION responsibility.
//
// The ServiceBundle (the SourceControl a CapabilityHost provisions/lands through)
// is provided by each `SubstationScope`, NOT above the `Station`. So when two
// substations run side by side, each substation's work resolves the NEAREST
// bundle — its OWN SourceControl — never a station-wide one. This is the capability
// the re-home unlocks: a project dictates its own SCM (root/head/remote/land).
//
// The proof drives the REAL kernel with two substations, two ready owned beads
// (one per substation, routed by id-prefix ownership), and two DISTINCT recording
// SourceControls. Each host materializes its workspace before the agent spawns
// (the host owns provisioning, D5) — so the recorded provision is the observable
// routing signal. If a single shared station bundle still existed, BOTH beads
// would hit ONE SourceControl; the per-substation isolation is exactly that they
// do not. Zero I/O — offline fakes (no live tg/gc/claude/git).
import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

GraphSnapshot _graph({
  required List<Bead> beads,
  required Set<String> ready,
}) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: ready,
  capturedAt: DateTime(2026),
);

/// A recording [SourceControl] that captures the bead ids it was asked to
/// provision. NO delivery is bound on the bundle, so nothing ever leaves the
/// station; the test never reaches delivery anyway.
///
/// ROOTED at a real temp dir: the molecule model's live process allocation
/// runs `assertProvisionedCheckout` (ADR-0009 D3, bead `tg-6jn`) before EVERY
/// agent spawn, which fail-closed REFUSES a workspace with no on-disk
/// `.git` — a real check the retired flat model's capability mount never
/// performed. So [provisionWorkspace] MATERIALIZES the `.git` marker it
/// claims to provision, exactly like the recorded bead id, so a live mount
/// can actually spawn. Call [dispose] to clean up the temp root.
class _RecordingSourceControl implements SourceControl {
  _RecordingSourceControl() : _root = Directory.systemTemp.createTempSync('grid-svc-bundle');

  final Directory _root;

  /// Every bead id passed to [provisionWorkspace], in call order.
  final List<String> provisioned = [];

  @override
  String workspaceFor(String beadId) => '${_root.path}/$beadId';
  @override
  String branchFor(String beadId) => 'grid/$beadId';
  @override
  String get baseBranch => 'main';

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async {
    provisioned.add(beadId);
    Directory('$workspaceDir/.git').createSync(recursive: true);
  }

  /// Removes the real temp checkout root (test hygiene).
  void dispose() {
    if (_root.existsSync()) _root.deleteSync(recursive: true);
  }
}

void main() {
  test(
    'each substation\'s CapabilityHost resolves ITS OWN ServiceBundle — two '
    'substations get isolated SourceControl (ADR-0008 D5)',
    () async {
      final f = buildFakes();
      final scA = _RecordingSourceControl();
      final scB = _RecordingSourceControl();
      addTearDown(scA.dispose);
      addTearDown(scB.dispose);

      // Adopted sessions (carried on the STATE axis) so each SessionScope
      // resolves synchronously and the agent spawns under the kernel's flush —
      // distinct session ids, no mint race. The session's own rig is the_grid's
      // state partition; the work beads route by id-prefix ownership.
      //
      // Each carries the READINESS LADDER complete (bead `pow-q7n`), so the
      // ladder never mounts and `specify` is again the head that spawns — this
      // suite's focus (per-substation ServiceBundle isolation) is downstream of
      // the ladder and unchanged by it.
      final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
      final state = FakeSnapshotSource(
        _graph(
          beads: [
            ...ladderDoneSession(id: 'tgdog-a', workBeadId: 'sa-1'),
            ...ladderDoneSession(id: 'tgdog-b', workBeadId: 'sb-1'),
          ],
          ready: const {},
        ),
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
              const SubstationConfig(substationId: 'sa', ownedSubstations: {'sa'}),
            ),
            services: ServiceBundle(sourceControl: scA),
            key: const ValueKey('scope.sa'),
          ),
          SubstationScope(
            configNotifier: SubstationConfigNotifier(
              const SubstationConfig(substationId: 'sb', ownedSubstations: {'sb'}),
            ),
            services: ServiceBundle(sourceControl: scB),
            key: const ValueKey('scope.sb'),
          ),
        ],
      );
      addTearDown(kernel.dispose);
      addTearDown(f.provider.close);
      addTearDown(work.close);
      addTearDown(state.close);

      kernel.start();
      await pumpEventQueue();

      // One ready owned bead per substation (sa-1 → substation sa, sb-1 → sb).
      work.push(
        _graph(beads: [bead('sa-1'), bead('sb-1')], ready: {'sa-1', 'sb-1'}),
      );
      await pumpEventQueue();

      // Sanity (non-vacuous): both circuit heads (specify, bead `pow-6ao`)
      // actually mounted + spawned, so both hosts ran their provision step.
      expect(
        f.provider.started.map((s) => s.name),
        unorderedEquals(
          <String>['tgdog-a/sa-1/spec_review/specify', 'tgdog-b/sb-1/spec_review/specify'],
        ),
        reason: 'one head step per substation spawned through the real code '
            'circuit',
      );

      // The routing proof: each substation provisioned ONLY its own bead's
      // workspace, through its OWN SourceControl. A shared station-wide bundle
      // would have funnelled BOTH beads into one SourceControl.
      expect(scA.provisioned, equals(<String>['sa-1']));
      expect(scB.provisioned, equals(<String>['sb-1']));
      // Explicit isolation: neither substation ever saw the other's bead.
      expect(scA.provisioned, isNot(contains('sb-1')));
      expect(scB.provisioned, isNot(contains('sa-1')));
    },
  );

  test(
    'a substation with no ServiceBundle resolves the empty default — provisioning '
    'no-ops, the agent still spawns (the offline-build posture)',
    () async {
      final f = buildFakes();
      final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
      final state = FakeSnapshotSource(
        _graph(
          // Ladder complete (bead `pow-q7n`) — `specify` stays the head that
          // spawns, so the offline-build posture is what this asserts.
          beads: ladderDoneSession(id: 'tgdog-a', workBeadId: 'sa-1'),
          ready: const {},
        ),
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
              const SubstationConfig(substationId: 'sa', ownedSubstations: {'sa'}),
            ),
            // No services — the scope provides the empty default (D5: an offline
            // build wires no SourceControl ⇒ provisioning is a no-op).
            key: const ValueKey('scope.sa'),
          ),
        ],
      );
      addTearDown(kernel.dispose);
      addTearDown(f.provider.close);
      addTearDown(work.close);
      addTearDown(state.close);

      kernel.start();
      await pumpEventQueue();
      work.push(_graph(beads: [bead('sa-1')], ready: {'sa-1'}));
      await pumpEventQueue();

      // The circuit head spawned even with no SourceControl wired (provision
      // no-op).
      expect(f.provider.started.map((s) => s.name), ['tgdog-a/sa-1/spec_review/specify']);
    },
  );
}
