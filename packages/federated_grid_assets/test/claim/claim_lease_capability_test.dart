// The GENERIC (kind-agnostic) claim+lease Capability (D-B5 hook #2/#3) —
// driven as a LeaseAllocation (ADR-0009 D6) exactly like `grid_assets`'
// ComputeLeaseCapability, but over a FAKE StationClient (Fakes, not mocks;
// zero I/O) using the SAME shared engine fakes (`package:grid_engine/testing.dart`)
// grid_assets' own lease capability test drives itself with.
import 'package:federated_grid_assets/federated_grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

/// A recording fake bus (lessee view) — records every call in order; never
/// touches a socket. Settable to deny a lease, fail a dispatch, or throw on
/// release.
class FakeStationClient implements StationClient {
  FakeStationClient({this.station = 'dashboard'});

  final String station;

  /// Every operation, in call order (e.g. `lease:studio:kind:idem`).
  final List<String> calls = [];

  /// The payload of the most recent dispatch.
  Map<String, dynamic>? lastDispatch;

  /// When true, [requestLease] denies.
  bool denyLease = false;

  /// When true, [dispatch] throws [LeaseInvalidException] (lease gone).
  bool dispatchInvalid = false;

  /// When true, [release] throws [LeaseInvalidException] (already reaped).
  bool releaseThrows = false;

  int _seq = 0;

  @override
  Future<Presence> presence() async => Presence(
    station: station,
    kinds: const ['burn-follower'],
    offered: 1,
    available: 1,
  );

  @override
  Future<LeaseGrant> requestLease(LeaseRequest req) async {
    calls.add('lease:${req.lessee}:${req.kind}:${req.idempotencyKey}');
    if (denyLease) throw const LeaseDeniedException('no capacity');
    return LeaseGrant(
      leaseId: 'lease-${_seq++}',
      station: station,
      ttlSeconds: 300,
      fencingToken: 7,
      kind: req.kind,
    );
  }

  @override
  Future<Map<String, dynamic>> dispatch(
    LeaseGrant lease,
    Map<String, dynamic> payload, {
    String idempotencyKey = '',
  }) async {
    calls.add('dispatch:${lease.leaseId}:$idempotencyKey');
    lastDispatch = payload;
    if (dispatchInvalid) throw const LeaseInvalidException('lease gone');
    return const {'ok': true};
  }

  @override
  Future<void> heartbeat(LeaseGrant lease) async =>
      calls.add('heartbeat:${lease.leaseId}');

  @override
  Future<void> release(LeaseGrant lease) async {
    calls.add('release:${lease.leaseId}');
    if (releaseThrows) throw const LeaseInvalidException('already reaped');
  }

  @override
  Future<void> close() async => calls.add('close');

  bool any(String prefix) => calls.any((c) => c.startsWith(prefix));
  int countWith(String prefix) =>
      calls.where((c) => c.startsWith(prefix)).length;
}

({FakeTreeContext context, StepArgs args}) _ctx({
  CancelToken? cancel,
  String nodePath = 'tg-burn/follower',
}) => (context: FakeTreeContext(), args: stepArgs(nodePath, cancel: cancel));

Future<
  ({List<AllocationReport> reports, LeaseAllocation<ClaimLeaseHandle> alloc})
>
_run(
  ClaimLeaseCapability cap,
  ({FakeTreeContext context, StepArgs args}) c,
) async {
  final reports = <AllocationReport>[];
  final alloc =
      cap.createAllocation(
            AllocationContext(
              treeContext: c.context,
              args: c.args,
              transport: FakeRuntimeProvider(),
              address: AllocationAddress('tgdog-s', c.args.nodePath),
              env: const {},
              sink: reports.add,
              kind: StepKind.job,
            ),
          )
          as LeaseAllocation<ClaimLeaseHandle>;
  await alloc.startOrAdopt();
  return (reports: reports, alloc: alloc);
}

void main() {
  group('ClaimLeaseCapability as a job LeaseAllocation', () {
    test(
      'mount acquires + dispatches the opaque capabilityId/params → Ok('
      'leaseGrantToResultPayload) — never a domain result; dispose releases',
      () async {
        final client = FakeStationClient();
        final cap = ClaimLeaseCapability(
          client: client,
          kind: 'burn-follower',
          capabilityId: 'burn-follower',
          params: const {'target': 'linux'},
          lessee: 'studio',
        );

        final r = await _run(cap, _ctx());
        final done = r.reports.whereType<AllocationCompleted>().single;
        expect(done.payload, {
          ClaimResultKeys.leaseId: 'lease-0',
          ClaimResultKeys.claimedBy: 'dashboard',
          ClaimResultKeys.fencingToken: '7',
          ClaimResultKeys.kind: 'burn-follower',
        });
        expect(
          r.reports.whereType<AllocationReady>(),
          isEmpty,
          reason: 'a job lease completes, it does not stay ready',
        );
        expect(client.calls, [
          'lease:studio:burn-follower:studio/tg-burn/follower',
          'dispatch:lease-0:studio/tg-burn/follower',
        ]);
        expect(client.lastDispatch, {
          'capabilityId': 'burn-follower',
          'params': {'target': 'linux'},
        });

        await r.alloc.dispose();
        expect(client.calls.last, 'release:lease-0');
      },
    );

    test('the lessee defaults to the work bead id when unset', () async {
      final client = FakeStationClient();
      final cap = ClaimLeaseCapability(
        client: client,
        kind: 'k',
        capabilityId: 'k',
        params: const {},
      );
      await _run(cap, _ctx());
      expect(client.calls.first, 'lease:tg-burn:k:tg-burn/tg-burn/follower');
    });

    test('a denied lease → Failed; no dispatch; dispose no-ops', () async {
      final client = FakeStationClient()..denyLease = true;
      final cap = ClaimLeaseCapability(
        client: client,
        kind: 'k',
        capabilityId: 'k',
        params: const {},
      );
      final r = await _run(cap, _ctx());
      expect(r.reports.single, isA<AllocationFailed>());
      expect(client.any('dispatch:'), isFalse);
      await r.alloc.dispose();
      expect(client.any('release:'), isFalse);
    });

    test(
      'a dispatch against a vanished lease → Failed; dispose still releases',
      () async {
        final client = FakeStationClient()..dispatchInvalid = true;
        final cap = ClaimLeaseCapability(
          client: client,
          kind: 'k',
          capabilityId: 'k',
          params: const {},
        );
        final r = await _run(cap, _ctx());
        expect(r.reports.single, isA<AllocationFailed>());
        await r.alloc.dispose();
        expect(client.any('release:'), isTrue);
      },
    );

    test(
      'release on dispose swallows a federation error (idempotent)',
      () async {
        final client = FakeStationClient()..releaseThrows = true;
        final cap = ClaimLeaseCapability(
          client: client,
          kind: 'k',
          capabilityId: 'k',
          params: const {},
        );
        final r = await _run(cap, _ctx());
        await r.alloc.dispose();
        expect(client.any('release:'), isTrue);
      },
    );

    test('dispose releases ONCE (idempotent on a double dispose)', () async {
      final client = FakeStationClient();
      final cap = ClaimLeaseCapability(
        client: client,
        kind: 'k',
        capabilityId: 'k',
        params: const {},
      );
      final r = await _run(cap, _ctx());
      await r.alloc.dispose();
      await r.alloc.dispose();
      expect(client.countWith('release:'), 1);
    });
  });
}
