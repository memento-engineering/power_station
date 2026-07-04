/// The PEER side of the claim flow (D-A3/D-B1/D-B3) — the mirror of
/// `claim_broadcaster.dart`'s owner role. A real station composes BOTH: one
/// [ClaimBroadcaster] over its own broker (for ITS OWN unclaimed work) and one
/// [ClaimResponder] over the SAME broker (to fulfill OTHERS' broadcasts).
///
/// [listenToBroadcaster] subscribes to a broadcaster's retained
/// `grid/claim/unclaimed/+` advertisements (per topology — this station must
/// already be configured to subscribe to that peer) AND its
/// `grid/claim/confirm` responses (to learn the arbitration outcome for
/// requests THIS responder sent). On each advertisement, [CapabilityFacts]
/// containment (ADR-0011 D6) decides fulfillability locally; if fulfillable
/// and not already responded to, a claim-resp [AcpRequest] is published on
/// THIS station's OWN broker (D-B1: the only place it may write) carrying
/// this station's lease-bus [Peer] address, so the confirmed owner's
/// [ClaimLeaseCapability] can dial it.
///
/// A responder never blocks on the outcome — [onConfirmed] (optional) is an
/// observability hook; the ACTUAL lease grant happens later, independently,
/// when the confirmed owner's [ClaimLeaseCapability] calls
/// `StationClient.requestLease` against this station's ALREADY-RUNNING
/// [StationServer] (D-A4: "claim → lease is two-phase" — this responder makes
/// no lessor-side commitment beyond stating its address).
library;

import 'dart:async';

import 'package:grid_engine/grid_engine.dart';

import '../broker/broker.dart';
import '../membership.dart';
import '../protocol/acp_envelope.dart';
import '../protocol/bus_protocol.dart';

void _noLog(String _) {}

/// The peer role of the claim protocol — see the library doc.
class ClaimResponder {
  /// Creates a responder over this station's OWN [broker] (every claim-resp
  /// this object sends lands there). [stationFacts] is this station's own
  /// capability profile (checked by containment against each advertisement's
  /// `requires`); [myAddress] is the lease-bus [Peer] a confirmed owner will
  /// dial. [onConfirmed] (optional) observes the arbitration outcome for a
  /// request this responder sent — `(claimId, confirmed)`.
  ClaimResponder({
    required Broker broker,
    required this.station,
    required CapabilityFacts stationFacts,
    required this.myAddress,
    this.onConfirmed,
    void Function(String)? onLog,
  })  : _broker = broker,
        _facts = stationFacts,
        _onLog = onLog ?? _noLog;

  /// This station's own id.
  final String station;

  /// This station's lease-bus address — handed to a claim's owner so a
  /// confirmed [ClaimLeaseCapability] can dial it.
  final Peer myAddress;

  /// Observes `(claimId, confirmed)` for a request THIS responder sent.
  final void Function(String claimId, bool confirmed)? onConfirmed;

  final Broker _broker;
  final CapabilityFacts _facts;
  final void Function(String) _onLog;

  /// claimId -> already responded to (never re-respond to the SAME live ad).
  final Set<String> _responded = {};

  /// My own outstanding claim-resp request ids -> the claimId they concern —
  /// how [_handleConfirm] recognizes a confirm addressed to ME (JSON-RPC id
  /// correlation), distinct from a confirm/deny meant for a different
  /// responder on the SAME broadcaster's `claim/confirm` topic.
  final Map<String, String> _outstandingByRequestId = {};

  final Map<String, StreamSubscription<BrokerMessage>> _adSubs = {};
  final Map<String, StreamSubscription<BrokerMessage>> _confirmSubs = {};
  int _seq = 0;

  /// Subscribes this station to [broadcasterBroker]'s advertisements + confirms
  /// (per topology — call once per broadcaster peer). Idempotent: re-calling
  /// for the same [broadcasterStation] replaces the prior subscriptions.
  void listenToBroadcaster(String broadcasterStation, Broker broadcasterBroker) {
    unawaited(_adSubs.remove(broadcasterStation)?.cancel());
    unawaited(_confirmSubs.remove(broadcasterStation)?.cancel());
    _adSubs[broadcasterStation] =
        broadcasterBroker.subscribe(BusTopics.claimUnclaimedAll).listen(
              _handleAdvertisement,
            );
    _confirmSubs[broadcasterStation] =
        broadcasterBroker.subscribe(BusTopics.claimConfirm).listen(
              _handleConfirm,
            );
  }

  /// Stops listening to [broadcasterStation] (e.g. it left the topology).
  Future<void> stopListening(String broadcasterStation) async {
    await _adSubs.remove(broadcasterStation)?.cancel();
    await _confirmSubs.remove(broadcasterStation)?.cancel();
  }

  void _handleAdvertisement(BrokerMessage msg) {
    if (msg.payload.isEmpty) {
      // A retraction (locally satisfied elsewhere, or confirmed to a peer) —
      // allow a future re-advertisement of the SAME claimId to be considered
      // again.
      _responded.remove(_claimIdFromTopic(msg.topic));
      return;
    }
    final AcpMessage decoded;
    try {
      decoded = decodeAcp(msg.payload);
    } on FormatException {
      return; // a foreign/malformed payload on the topic — ignore it
    }
    if (decoded is! AcpNotification || decoded.method != BusMethods.claimUnclaimed) {
      return;
    }
    final claimId = decoded.params['claimId'] as String?;
    if (claimId == null || _responded.contains(claimId)) return;
    final requiresJson = decoded.params['requires'];
    final requires = requiresJson is Map
        ? CapabilityFacts.fromProfile(requiresJson.cast<String, Object?>())
        : const CapabilityFacts();
    if (!CapabilityFacts.matches(_facts, requires)) {
      return; // cannot fulfill — never respond
    }
    _responded.add(claimId);
    final id = '$station-${_seq++}';
    final capabilityId = decoded.params['capabilityId'] as String? ?? kDefaultKind;
    _outstandingByRequestId[id] = claimId;
    _broker.publish(
      BusTopics.claimRespond,
      encodeAcp(
        AcpRequest(
          id: id,
          method: BusMethods.claimRespond,
          params: {
            'claimId': claimId,
            'station': station,
            'kind': capabilityId, // this impl's kind == capabilityId convention
            'peer': myAddress.toJson(),
          },
        ),
      ),
    );
    _onLog('responded to $claimId ($capabilityId)');
  }

  void _handleConfirm(BrokerMessage msg) {
    final AcpMessage decoded;
    try {
      decoded = decodeAcp(msg.payload);
    } on FormatException {
      return;
    }
    if (decoded is! AcpResultResponse) return;
    final claimId = _outstandingByRequestId.remove(decoded.id);
    if (claimId == null) return; // not one of MY outstanding requests
    final confirmedFlag = decoded.result['confirmed'] as bool? ?? false;
    _onLog('$claimId ${confirmedFlag ? 'CONFIRMED' : 'denied'} for $station');
    onConfirmed?.call(claimId, confirmedFlag);
  }

  /// Recovers the claimId from a `grid/claim/unclaimed/<claimId>` topic by
  /// stripping the fixed prefix — NOT the last `/`-segment, since a claimId is
  /// itself a `nodePath` that spans multiple levels (see
  /// `BusTopics.claimUnclaimedAll`'s doc).
  static String _claimIdFromTopic(String topic) =>
      topic.substring(BusTopics.claimUnclaimed('').length);

  /// Cancels every subscription (does NOT close any [Broker] — this object
  /// doesn't own their lifecycle).
  Future<void> dispose() async {
    for (final sub in _adSubs.values) {
      await sub.cancel();
    }
    for (final sub in _confirmSubs.values) {
      await sub.cancel();
    }
    _adSubs.clear();
    _confirmSubs.clear();
  }
}
