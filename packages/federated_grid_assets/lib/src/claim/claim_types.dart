/// Shared value types for the claim protocol (`claim_broadcaster.dart` /
/// `claim_responder.dart` / `claim_lease_capability.dart`).
library;

import 'package:meta/meta.dart';

import '../membership.dart';

/// A settled claim: [claimId]'s unclaimed requirement is now owned by
/// [station], reachable at [peer] (the lease-bus address a
/// [ClaimLeaseCapability] dials to acquire + dispatch), offering [kind].
@immutable
class ConfirmedClaim {
  /// Creates a confirmed claim.
  const ConfirmedClaim({
    required this.claimId,
    required this.station,
    required this.peer,
    required this.kind,
  });

  /// The claim id (== the unclaimed step's `nodePath` — see
  /// [ClaimBroadcaster.claimIdFor]).
  final String claimId;

  /// The peer station that won arbitration.
  final String station;

  /// The peer's lease-bus address (host/port/token) — how a
  /// [ClaimLeaseCapability] reaches it.
  final Peer peer;

  /// The resource kind to request on the peer's lease bus (this
  /// implementation's convention: kind == the claimed step's `capabilityId` —
  /// see the library doc on `claim_broadcaster.dart`).
  final String kind;

  @override
  bool operator ==(Object other) =>
      other is ConfirmedClaim &&
      other.claimId == claimId &&
      other.station == station &&
      other.peer == peer &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(claimId, station, peer, kind);

  @override
  String toString() => 'ConfirmedClaim($claimId -> $station @ ${peer.address})';
}
