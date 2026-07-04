/// The OWNER side of the claim flow (D-A3/D-B1/D-B3) — the asset-side
/// consumer of the engine's AL-6a hooks (`docs/SCRATCH-grid-alignment.md`,
/// the honesty pass, 2026-07-03).
///
/// A [ClaimBroadcaster] wraps ONE station's own [Broker]. Give
/// [onUnclaimedFrontier] directly to `StationKernel`'s constructor param of
/// the same name (`grid_engine`'s D-B5 hook #1) — it is called once per
/// reconciliation phase with the CURRENT station-wide unclaimed set:
///
/// 1. Every still-unclaimed requirement is published as a RETAINED
///    [AcpNotification] on `grid/claim/unclaimed/<claimId>` (D-B1:
///    advertisement = retained) — a late-subscribing peer sees the CURRENT
///    set immediately, no separate catch-up query.
/// 2. A requirement no longer in the frontier (locally satisfied, or the
///    session ended) is RETRACTED (an empty retained publish clears it) —
///    unless it is already [ConfirmedClaim]ed (see 4; that clears eagerly,
///    at confirm time, not on the next scan).
///
/// A responding peer (`claim_responder.dart`) publishes a claim-resp
/// [AcpRequest] on ITS OWN broker; [listenToPeer] wires this station to
/// listen for it (per topology). [_handleRespond] arbitrates DETERMINISTICALLY
/// — first valid responder wins, full stop, no re-litigation once a claim
/// commits (D-A3: "deterministic arbitration at the work's owner") — and
/// publishes the [AcpResultResponse] CONFIRM on THIS station's OWN broker,
/// echoing the request's `id` (D-B3: correlated by id across two brokers).
///
/// 3. Once confirmed, the retained advertisement is cleared IMMEDIATELY (not
///    on the next [onUnclaimedFrontier] scan — a step whose cursor state is
///    `running` STAYS in the engine's eligible/unclaimed frontier, so waiting
///    for the next scan to retract would never happen).
/// 4. [claimCapabilityFor] is `DefaultCapabilityRegistry`'s
///    `claimCapabilityFor` factory (D-B5 hook #2): once [nodePath] has a
///    [ConfirmedClaim], it resolves to a [ClaimLeaseCapability] that leases +
///    dispatches on the confirmed peer over the ALREADY-BUILT lease bus
///    (`station_client.dart`/`station_server.dart`) — "claim → LEASE is
///    two-phase" (D-A4). A mount arriving BEFORE confirmation returns null
///    (fails soft to `Idle`, same as any other unfulfilled step — the
///    registry re-resolves on the next flush once confirmed).
///
/// Kind convention (this implementation's own choice, since neither
/// `CapabilityStep` nor `CapabilityFacts` carries a resource `kind`): a
/// confirmed peer is expected to run a [StationServer] OFFERING the claimed
/// step's `capabilityId` AS its `kind` — i.e. `kind == capabilityId`. A
/// responder that has not composed a matching lessor is simply denied by the
/// ALREADY-EXISTING `LeaseManager` kind check (fail-closed, no new mechanism
/// needed).
///
/// [_confirmed] is retained for this object's LIFETIME (no eviction this
/// pass) — a bounded, documented scope cut: nothing in the AL-6a hooks
/// signals "this session ended," so a safe eviction point is deferred to a
/// later depth (flagged for review, matching the engine commit's own habit of
/// calling out scope cuts explicitly).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:grid_engine/grid_engine.dart';

import '../broker/broker.dart';
import '../membership.dart';
import '../protocol/acp_envelope.dart';
import '../protocol/bus_protocol.dart';
import '../station_client.dart';
import 'claim_lease_capability.dart';
import 'claim_types.dart';

void _noLog(String _) {}

/// The claim id for [req] — its unclaimed step's `nodePath`, which (per
/// `grid_engine`'s own construction — `stationUnclaimedFrontier` seeds the
/// recursive scan at `session.workBeadId`) is IDENTICAL to the `nodePath` the
/// SAME step mounts under once eligible. One id, no separate correlation
/// table needed between "unclaimed" and "mount."
String claimIdFor(UnclaimedRequirement req) => req.step.nodePath;

/// The owner role of the claim protocol — see the library doc.
class ClaimBroadcaster {
  /// Creates a broadcaster over this station's OWN [broker] (every publish
  /// this object makes lands there — D-B1 single-writer). [clientFor] builds
  /// the [StationClient] a [ClaimLeaseCapability] dials for a confirmed
  /// [Peer]; defaults to [HttpStationClient]. [onLog] observes events (the
  /// lib stays print-free).
  ClaimBroadcaster({
    required Broker broker,
    StationClient Function(Peer peer)? clientFor,
    void Function(String)? onLog,
  })  : _broker = broker,
        _clientFor = clientFor ??
            ((p) => HttpStationClient(host: p.host, port: p.port, token: p.token)),
        _onLog = onLog ?? _noLog;

  final Broker _broker;
  final StationClient Function(Peer peer) _clientFor;
  final void Function(String) _onLog;

  /// claimId -> still advertised, awaiting a responder.
  final Set<String> _pending = {};

  /// claimId -> settled (a peer won arbitration).
  final Map<String, ConfirmedClaim> _confirmed = {};

  final Map<String, StreamSubscription<BrokerMessage>> _peerSubs = {};

  /// `StationKernel`'s `onUnclaimedFrontier` hook (D-B5 hook #1) — call this
  /// directly as that constructor param. Advertises every NEWLY unclaimed
  /// requirement (retained) and retracts any no-longer-unclaimed one that
  /// isn't already confirmed (see the library doc, points 1-2).
  void onUnclaimedFrontier(List<UnclaimedRequirement> requirements) {
    final live = <String>{};
    for (final req in requirements) {
      final claimId = claimIdFor(req);
      live.add(claimId);
      if (_confirmed.containsKey(claimId) || _pending.contains(claimId)) {
        continue; // already advertised/settled — no re-broadcast
      }
      _pending.add(claimId);
      _broker.publish(
        BusTopics.claimUnclaimed(claimId),
        encodeAcp(
          AcpNotification(
            method: BusMethods.claimUnclaimed,
            params: {
              'claimId': claimId,
              'workBeadId': req.workBeadId,
              'sessionId': req.sessionId,
              'nodePath': req.step.nodePath,
              'stepId': req.step.stepId,
              'capabilityId': req.step.capabilityId,
              'requires': req.step.requires.toProfile(),
            },
          ),
        ),
        retain: true,
      );
      _onLog('broadcast unclaimed $claimId (${req.step.capabilityId})');
    }
    for (final claimId in List<String>.of(_pending)) {
      if (!live.contains(claimId)) {
        _retract(claimId);
        _onLog('retracted unclaimed $claimId (no longer unclaimed)');
      }
    }
  }

  void _retract(String claimId) {
    _pending.remove(claimId);
    _broker.publish(BusTopics.claimUnclaimed(claimId), Uint8List(0), retain: true);
  }

  /// Subscribes this station to [peerBroker]'s claim-resp requests (per
  /// topology — call once for every peer this station listens to).
  /// Idempotent: re-calling for the same [peerStation] replaces the prior
  /// subscription.
  void listenToPeer(String peerStation, Broker peerBroker) {
    unawaited(_peerSubs.remove(peerStation)?.cancel());
    _peerSubs[peerStation] = peerBroker.subscribe(BusTopics.claimRespond).listen(
      (msg) {
        final AcpMessage decoded;
        try {
          decoded = decodeAcp(msg.payload);
        } on FormatException {
          return; // a foreign/malformed payload on the topic — ignore it
        }
        if (decoded is AcpRequest && decoded.method == BusMethods.claimRespond) {
          _handleRespond(peerStation, decoded);
        }
      },
    );
  }

  /// Stops listening to [peerStation] (e.g. it left the topology).
  Future<void> stopListening(String peerStation) async {
    await _peerSubs.remove(peerStation)?.cancel();
  }

  void _handleRespond(String peerStation, AcpRequest req) {
    final claimId = req.params['claimId'] as String?;
    if (claimId == null || !_pending.remove(claimId)) {
      _deny(req, claimId); // already confirmed/retracted — tell it no
      return;
    }
    final peerJson = req.params['peer'];
    if (peerJson is! Map) {
      _deny(req, claimId);
      return;
    }
    final peer = Peer.fromJson(peerJson.cast<String, dynamic>());
    final kind = req.params['kind'] as String? ?? kDefaultKind;
    _confirmed[claimId] = ConfirmedClaim(
      claimId: claimId,
      station: peerStation,
      peer: peer,
      kind: kind,
    );
    // Clear the retained ad EAGERLY (do not wait for the next scan — a
    // running step stays in the engine's frontier, see the library doc).
    _broker.publish(BusTopics.claimUnclaimed(claimId), Uint8List(0), retain: true);
    _broker.publish(
      BusTopics.claimConfirm,
      encodeAcp(
        AcpResultResponse(id: req.id, result: {'claimId': claimId, 'confirmed': true}),
      ),
    );
    _onLog('confirmed $claimId -> $peerStation');
  }

  void _deny(AcpRequest req, String? claimId) {
    _broker.publish(
      BusTopics.claimConfirm,
      encodeAcp(
        AcpResultResponse(
          id: req.id,
          result: {'claimId': claimId ?? '', 'confirmed': false},
        ),
      ),
    );
  }

  /// `DefaultCapabilityRegistry`'s `claimCapabilityFor` factory (D-B5 hook
  /// #2) — see the library doc, point 4.
  Capability? claimCapabilityFor(StepMount mount) {
    final confirmed = _confirmed[mount.nodePath];
    if (confirmed == null) return null;
    return ClaimLeaseCapability(
      client: _clientFor(confirmed.peer),
      kind: confirmed.kind,
      capabilityId: mount.step.capabilityId,
      params: mount.step.params,
      onLog: _onLog,
    );
  }

  /// The current confirmed-claim table (introspection/tests).
  Map<String, ConfirmedClaim> get confirmed => Map.unmodifiable(_confirmed);

  /// The current still-advertised claim ids (introspection/tests).
  Set<String> get pending => Set.unmodifiable(_pending);

  /// Cancels every peer subscription (does NOT close [broker] — this object
  /// doesn't own its lifecycle).
  Future<void> dispose() async {
    for (final sub in _peerSubs.values) {
      await sub.cancel();
    }
    _peerSubs.clear();
  }
}
