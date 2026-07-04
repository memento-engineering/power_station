/// The GENERIC (kind-agnostic) claim+lease [Capability] — what
/// `ClaimBroadcaster.claimCapabilityFor` (D-B5 hook #2) returns once a
/// station's unclaimed requirement is CONFIRMED to a peer.
///
/// Unlike a DOMAIN capability (an asset-package `LeaseCapability` that knows
/// its own payload/result shapes), this one is FEDERATION CORE:
/// it dispatches the claimed step's OPAQUE `capabilityId` + `params` to the
/// confirmed peer exactly as `StationServer`'s `DispatchHandler` receives
/// them kind-agnostically on the wire (`station_server.dart`'s own doc: "what
/// a payload MEANS + what 'use' runs is defined by the asset domain that owns
/// the kind"). It records ONLY the durable "who claimed this" bridge
/// (`leaseGrantToResultPayload`, D-B5 hook #3) — never a domain result: the
/// confirmed peer's OWN capability registry is what interprets/executes the
/// payload; whatever richer result IT wants to carry back is that peer's
/// asset's concern, a depth this pass does not reach (flagged for review, like
/// the engine commit's own `ttlSeconds`/`heartbeatSeconds` scope cut).
///
/// A dispatch that throws (`FederationException` — denied/invalid/
/// unreachable) is a domain-agnostic [Failed]; the federation-generic
/// capability cannot interpret a domain-specific failure inside a
/// successfully-returned payload (it has none to interpret), so ANY
/// non-throwing dispatch is treated as [Ok] — the same posture
/// `DispatchHandler` takes on the SERVER side (kind-agnostic in, kind-agnostic
/// out).
library;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';

/// The bus-backed lease handle THIS capability holds: a [StationClient] to
/// the confirmed peer + the [LeaseGrant] it issued. (Distinct from — but
/// structurally identical to — `grid_assets`' `BusLease`; that package sits
/// ABOVE this one, so this capability carries its own opaque handle rather
/// than importing downward.)
typedef ClaimLeaseHandle = ({StationClient client, LeaseGrant grant});

void _noLog(String _) {}

/// The claim+lease [Capability] — see the library doc.
class ClaimLeaseCapability extends LeaseCapability<ClaimLeaseHandle> {
  /// Creates a claim+lease capability over the confirmed peer's [client],
  /// requesting [kind] (this implementation's convention: `kind ==
  /// capabilityId` — see `claim_broadcaster.dart`'s library doc) and
  /// dispatching the claimed step's [capabilityId] + [params] opaquely.
  /// [lessee] defaults to the work bead id at mount.
  ClaimLeaseCapability({
    required this.client,
    required this.kind,
    required this.capabilityId,
    required this.params,
    this.lessee = '',
    void Function(String)? onLog,
  }) : _onLog = onLog ?? _noLog;

  /// The bus client to the confirmed peer.
  final StationClient client;

  /// The resource kind requested on the peer's lease bus.
  final String kind;

  /// The claimed step's capability id (opaque — carried through, never
  /// interpreted here).
  final String capabilityId;

  /// The claimed step's params (opaque — carried through verbatim).
  final Map<String, String> params;

  /// The lessee station id (empty ⇒ the work bead id at mount).
  final String lessee;

  final void Function(String) _onLog;

  /// A stable per-node idempotency key so a retried lease/dispatch dedups at
  /// the owner (never a second grant or a second run — the lossy-bus hazard).
  String _idem(StepArgs args) =>
      '${lessee.isEmpty ? args.beadId : lessee}/${args.nodePath}';

  @override
  Future<LeaseResolution<ClaimLeaseHandle>> acquire(
    TreeContext context,
    StepArgs args,
  ) async {
    final who = lessee.isEmpty ? args.beadId : lessee;
    final LeaseGrant grant;
    try {
      grant = await client.requestLease(
        LeaseRequest(lessee: who, kind: kind, idempotencyKey: _idem(args)),
      );
    } on LeaseDeniedException catch (e) {
      return LeaseUnavailable('claim lease denied: ${e.message}');
    }
    _onLog(
      'claimed lease ${grant.leaseId} on ${grant.station} for $capabilityId '
      '(fence ${grant.fencingToken})',
    );
    return LeaseBound((client: client, grant: grant));
  }

  @override
  Future<StepOutcome> dispatchOn(
    ClaimLeaseHandle handle,
    TreeContext context,
    StepArgs args,
  ) async {
    try {
      await handle.client.dispatch(
        handle.grant,
        {'capabilityId': capabilityId, 'params': params},
        idempotencyKey: _idem(args),
      );
    } on FederationException catch (e) {
      return Failed('claim dispatch failed: ${e.message}');
    }
    // The durable "who claimed this" bridge (D-B5 hook #3) — see the library
    // doc for why no domain result rides along here.
    return Ok(leaseGrantToResultPayload(handle.grant));
  }

  @override
  Future<void> release(ClaimLeaseHandle handle) async {
    try {
      await handle.client.release(handle.grant);
      _onLog('released claimed lease ${handle.grant.leaseId}');
    } on FederationException {
      // Already reaped/invalid — release is idempotent for the holder.
    }
  }
}
