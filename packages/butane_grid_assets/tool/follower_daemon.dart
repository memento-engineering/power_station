// The live-local BURN follower daemon (the PIPELINE-PROOF app-under-test;
// butane stays untouched): a minimal pure-Dart program that registers the
// `ext.exploration.*` host over a HERMETIC, in-memory [GridControllerRuntime]
// — no .beads workspace, no bd, no dolt, no network beyond its own loopback VM
// service. Mirrors grid_exploration's `tool/attach_target.dart` (the target the
// PROVEN leonard_drive attach test spawns): the same fixed snapshot (3 beads,
// 2 ready — tg-2/tg-3), plus `readPath: 'cli'` (the A40 live-proof shape).
//
// Run under a VM service (the LocalDartFollowerLauncher does exactly this):
//
//   dart run --enable-vm-service=0 --disable-service-auth-codes \
//     tool/follower_daemon.dart
//
// Prints `GRID_VM_URI=<ws://…/ws>` AFTER the host is registered (the readiness
// sentinel the launcher scrapes — the first drive call can never race the
// extension registration), then idles until killed (SIGTERM → exit 0).
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_exploration/grid_exploration.dart';

class _FixedReader implements SnapshotReader {
  @override
  Future<GraphSnapshot> read() async => GraphSnapshot.fromParts(
    beads: [
      Bead(id: 'tg-1', title: 'tron', issueType: IssueType.molecule),
      const Bead(id: 'tg-2', title: 'ready one'),
      const Bead(id: 'tg-3', title: 'ready two'),
    ],
    dependencies: const [],
    readyIds: {'tg-2', 'tg-3'},
    capturedAt: DateTime.utc(2026, 6, 15, 12),
  );
}

Future<void> main() async {
  final info = await developer.Service.getInfo();
  final serverUri = info.serverUri;
  if (serverUri == null) {
    print('FAIL: VM service not enabled — run with --enable-vm-service');
    exit(1);
  }

  final runtime = GridControllerRuntime(
    reader: _FixedReader(),
    dirtySources: const [],
  );
  await runtime.start();
  GridExplorationHost(
    runtime,
    plugin: GridControllerPlugin(runtime, readPath: () => 'cli'),
  ).register();

  // Sentinel AFTER registration — the launcher's readiness barrier.
  print('GRID_VM_URI=${_toWs(serverUri)}');

  // Idle until the lessor reaps us (the lease-release teardown).
  final never = Completer<void>();
  ProcessSignal.sigterm.watch().listen((_) => exit(0));
  await never.future;
}

/// `http://…/` → `ws://…/ws` (the attach-test URI form, hand-converted so the
/// daemon needs no vm_service dep).
String _toWs(Uri serverUri) {
  final path = serverUri.path.endsWith('/')
      ? '${serverUri.path}ws'
      : '${serverUri.path}/ws';
  return serverUri
      .replace(scheme: serverUri.scheme == 'https' ? 'wss' : 'ws', path: path)
      .toString();
}
