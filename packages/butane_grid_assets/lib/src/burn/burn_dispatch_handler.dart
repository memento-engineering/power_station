/// The SERVER-side burn dispatch handler — what a lessor station plugs into
/// `grid_federation`'s [StationServer] to OWN the `burn` kind (ADR-0011 D3):
/// decode the opaque bus payload as a [LaunchSpec], launch the follower app via
/// the [ButaneFollowerRunner], and return the published [FollowerEndpoint] as
/// the opaque dispatch result (the rendezvous handoff).
///
/// **The release seam — a documented gap.** The lessor's GUARANTEED teardown
/// ("release the lease → the peer reaps the launched app") needs the server to
/// tell the runner when the lease is released or reaped. Today
/// `StationServer.start` exposes NO on-release/lease-reaped hook, and
/// `LeaseManager.release`/`_reap` free the slot silently — so this handler can
/// wire the LAUNCH half only. Until the hook exists in `grid_federation`, the
/// lessor composition (a serve command / an integration test) must call
/// [ButaneFollowerRunner.teardown] itself after the release (it is idempotent —
/// a double reap is a no-op). The offline `burn_test.dart` fake lessor shows the
/// intended shape: its `release` calls `runner.teardown()`.
library;

import 'package:grid_federation/grid_federation.dart';

import 'follower.dart';

void _noLog(String _) {}

/// Builds the `burn`-kind [DispatchHandler] over [runner]: parse the payload as
/// a [LaunchSpec], `launch` it (provision + build + launch the follower app,
/// publishing its endpoint), and return the endpoint's JSON as the dispatch
/// result. A launch failure throws — [StationServer] surfaces it to the lessee
/// as a failed dispatch (the `burn-follower` order fails closed).
///
/// [onLog] observes events (lib stays print-free; a CLI wires stdout).
DispatchHandler burnDispatchHandler({
  required ButaneFollowerRunner runner,
  void Function(String)? onLog,
}) {
  final log = onLog ?? _noLog;
  return (Map<String, dynamic> payload) async {
    final spec = LaunchSpec.fromJson(payload);
    log('burn dispatch: launch ${spec.app} for ${spec.target}');
    final endpoint = await runner.launch(spec);
    log('burn dispatch: published ${endpoint.vmServiceUri}');
    return endpoint.toJson();
  };
}
