@Tags(['integration'])
library;

// The BURN end-to-end LIVE-LOCAL (the away-run M-C milestone): every seam that
// burn_test.dart drives with a fake is REAL here, on one box —
//
//   * a REAL loopback grid_federation `StationServer` (the lessor bus),
//     handler = `burnDispatchHandler` over a real `ButaneFollowerRunner`;
//   * a REAL spawned follower daemon (`tool/follower_daemon.dart` under its own
//     VM service, in its OWN process group — the pipeline-proof app-under-test;
//     butane stays untouched);
//   * lenny's REAL credential-free `leonard_drive` as the direct perception
//     channel (`ProcessLeonardDrive` — zero model calls, A40/tg-e28);
//   * a REAL collected `TestReport`.
//
// The drive shape mirrors burn_test.dart exactly: the follower order runs as a
// daemon `LeaseAllocation` (createAllocation → startOrAdopt → `ready` publishes
// the endpoint), the host order reads the endpoint pull-free through a
// `SiblingView` and runs the SCRIPTED scenario, then teardown: host closes the
// drive, `alloc.dispose()` releases the lease over the REAL bus, and the
// spawned daemon process is asserted ACTUALLY GONE.
//
// The one deliberate seam-gap workaround: `StationServer` exposes NO
// on-release/lease-reaped hook (see burn_dispatch_handler.dart), so after the
// release this test calls `runner.teardown()` itself — the lessor-composition
// half the fake `_FollowerStation.release` models in burn_test.dart.
//
// SELF-SKIPS when `leonard_drive` is not discoverable (lenny not checked out /
// no $LEONARD_DRIVE) — never fails the suite for a missing sibling.
//
// Safety rails held: loopback (127.0.0.1) only; no .beads/bd anywhere (the
// daemon's snapshot is in-memory); teardown kills ONLY the exact pid/pgid this
// test spawned, in finally.

import 'dart:io';

import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:grid_assets/grid_assets.dart' show BusLease;
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart' show FakeRuntimeProvider, bead;
import 'package:grid_federation/grid_federation.dart';
import 'package:grid_runtime/grid_runtime.dart'
    show ProcessGroupController, SystemProcessGroupController;
import 'package:test/test.dart';

const String _station = 'the-studio-local';
const String _followerPath = 'tg-burn/$kBurnFollowerStep';
const String _hostPath = 'tg-burn/$kBurnHostStep';

/// This box is a macOS studio, not a linux/ble peer — the live-local arm
/// requires only `system-os=macos` by containment (the mac+iPad BLE arm keeps
/// the default linux/ble requires and stays the human gate).
const CapabilityFacts _macRequires = CapabilityFacts(
  sets: {
    kSystemOs: {'macos'},
  },
);

const Map<String, Object?> _macProfile = {
  'system-os': 'macos',
  'dart-target': ['macos'],
};

/// The launch payload — the local launcher runs the pipeline-proof daemon in
/// place of a butane build (the spec stays descriptive of the intent).
const LaunchSpec _spec = LaunchSpec(
  app: 'follower_daemon',
  target: 'macos',
  scenario: 'live-local-smoke',
);

/// The SCRIPTED live scenario — mirrors the attach test's shapes against what
/// the daemon's host actually serves (the fixed 3-beads/2-ready snapshot with
/// `readPath: 'cli'`): observe the grid fragment under
/// `observation.extensions.grid.data`, then invoke `grid.ready`.
const DriveScenario _liveScenario = DriveScenario(
  name: 'live-local-smoke',
  steps: [
    DriveStep.observe('extensions.grid.data', expectContains: '"readyCount":2'),
    DriveStep.observe('extensions.grid.data', expectContains: '"readPath":"cli"'),
    DriveStep.invoke('grid.ready', expectContains: '"tg-2"'),
  ],
);

CapabilityContext _ctx({
  required String nodePath,
  SiblingView siblings = const SiblingView(),
}) => CapabilityContext(
  params: const {},
  bead: bead('tg-burn'),
  workspaceDir: '/w/tg-burn',
  branch: 'grid/tg-burn',
  baseBranch: 'main',
  services: const ServiceBundle(),
  cancel: CancelToken(),
  nodePath: nodePath,
  siblings: siblings,
);

/// Polls until [pid] is gone, or fails after [within].
Future<void> _expectDead(
  ProcessGroupController processes,
  int pid, {
  Duration within = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(within);
  while (processes.processAlive(pid)) {
    if (DateTime.now().isAfter(deadline)) {
      fail('daemon pid $pid still alive ${within.inSeconds}s after teardown');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  test(
    'the burn runs end-to-end LIVE-LOCAL: real bus, real spawned daemon, '
    'real leonard_drive, real report — and the daemon is actually reaped',
    () async {
      final argv = await ProcessLeonardDrive.discover();
      if (argv == null) {
        markTestSkipped(
          r'leonard_drive not found (set $LEONARD_DRIVE or check out lenny at '
          '~/development/com.nicospencer/lenny) — the live-local burn skipped.',
        );
        return;
      }

      final logs = <String>[];
      void log(String m) => logs.add(m);

      const processes = SystemProcessGroupController();
      final launcher = LocalDartFollowerLauncher(
        daemonEntrypoint:
            '${Directory.current.path}/tool/follower_daemon.dart',
        station: _station,
        onLog: log,
      );
      final runner = ButaneFollowerRunner(
        launcher: launcher,
        processes: processes,
        onLog: log,
      );

      StationServer? server;
      HttpStationClient? client;
      LeaseAllocation<BusLease>? alloc;
      try {
        // A REAL loopback lessor: one burn slot, the burn dispatch handler over
        // the real runner, advertising this box's (macos) capability profile.
        server = await StationServer.start(
          station: _station,
          offered: 1,
          kind: kBurnKind,
          host: '127.0.0.1',
          handler: burnDispatchHandler(runner: runner, onLog: log),
          profile: _macProfile,
          onLog: log,
        );
        client = HttpStationClient(host: '127.0.0.1', port: server.port);
        final peer = FollowerPeer(id: _station, client: client);

        // The burn registry composes with the REAL pieces (the formula is the
        // one declared shape; the drive is burn-order turf below).
        final registry = buildBurnRegistry(
          peers: [peer],
          launchSpec: _spec,
          drive: ProcessLeonardDrive(),
          scenario: _liveScenario,
          requires: _macRequires,
          onLog: log,
        );
        expect(registry.formula('burn'), kBurnFormula);

        // ORDER 1 — burn-follower as a daemon LeaseAllocation over the REAL
        // bus: containment-match this box → lease the slot → dispatch → the
        // spawned daemon publishes a REAL ws:// endpoint on `ready`.
        final follower = BurnFollowerCapability(
          peers: [peer],
          launchSpec: _spec,
          requires: _macRequires,
          lessee: 'the-studio-host',
          onLog: log,
        );
        final reports = <AllocationReport>[];
        final fCtx = _ctx(nodePath: _followerPath);
        alloc = follower.createAllocation(
          AllocationContext(
            capContext: fCtx,
            transport: FakeRuntimeProvider(),
            address: AllocationAddress('tgdog-s', fCtx.nodePath),
            env: const {},
            sink: reports.add,
            kind: StepKind.daemon,
          ),
        ) as LeaseAllocation<BusLease>;
        await alloc.startOrAdopt();

        final ready = reports.whereType<AllocationReady>().toList();
        expect(
          ready,
          hasLength(1),
          reason: 'the daemon lease must reach ready — log:\n${logs.join('\n')}'
              '\nreports: $reports',
        );
        expect(reports.whereType<AllocationCompleted>(), isEmpty,
            reason: 'a held daemon lease must not complete/retire');
        final payload = ready.single.payload;
        expect(payload, isNotNull, reason: 'ready carries the rendezvous');
        final published = payload!;
        expect(published['endpoint'], startsWith('ws://127.0.0.1:'),
            reason: 'a REAL loopback VM-service endpoint was published');
        expect(published['endpoint'], endsWith('/ws'));
        expect(published['station'], _station);
        expect(runner.isRunning, isTrue, reason: 'the follower daemon is up');

        final daemon = launcher.lastLaunched!;
        expect(processes.processAlive(daemon.pid), isTrue,
            reason: 'the spawned daemon process is live');

        // ORDER 2 — burn-host: endpoint via the SiblingView (pull-free, D-5) →
        // attach the REAL leonard_drive → run the SCRIPTED scenario.
        final drive = ProcessLeonardDrive();
        final host = BurnHostCapability(
          drive: drive,
          scenario: _liveScenario,
          onLog: log,
        );
        final hCtx = _ctx(
          nodePath: _hostPath,
          siblings: SiblingView(results: {_followerPath: published}),
        );
        final out = await host.run(hCtx);
        final report = host.reportFor(hCtx);
        expect(
          out,
          isA<Ok>(),
          reason: 'the live scenario must pass — report: $report\n'
              'log:\n${logs.join('\n')}',
        );
        expect(report, isNotNull);
        expect(report!.passed, isTrue);
        expect(report.total, greaterThan(0),
            reason: 'the report ran real steps');
        expect(report.total, _liveScenario.steps.length);
        expect(report.failures, 0);
        expect(report.endpoint, published['endpoint']);

        // TEARDOWN under test — host closes the drive channel; the follower
        // allocation's dispose RELEASES the lease over the REAL bus.
        await host.teardown(hCtx);
        await alloc.dispose();
        expect(server.leases.available, 1,
            reason: 'the released slot is free again on the lessor');

        // The serve-side gap (documented in burn_dispatch_handler.dart):
        // StationServer has no on-release hook, so the lessor composition —
        // this test — reaps the launched daemon itself (idempotent).
        await runner.teardown();
        expect(runner.isRunning, isFalse);

        // THE MILESTONE ASSERT: the spawned daemon process is ACTUALLY gone.
        await _expectDead(processes, daemon.pid);
      } finally {
        // Guaranteed teardown — idempotent, exact pids/groups only.
        await runner.teardown();
        final last = launcher.lastLaunched;
        if (last != null && processes.processAlive(last.pid)) {
          // Last resort: kill EXACTLY the pid this test spawned.
          Process.killPid(last.pid, ProcessSignal.sigkill);
        }
        await alloc?.dispose();
        await client?.close();
        await server?.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
