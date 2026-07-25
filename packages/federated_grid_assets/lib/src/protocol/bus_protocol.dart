/// The concrete, VERSIONED method/topic surface over the ACP-shaped envelope
/// (`acp_envelope.dart`) — presence, initialize-time capability negotiation,
/// and the claim protocol's methods (D-B3). "Advertisement" is not a separate
/// method: the claim protocol's retained `grid/claim/unclaimed/<claimId>`
/// messages ARE the advertisement (D-B1 — retained IS the advertising
/// mechanism, so a distinct method would only duplicate it).
library;

import 'dart:typed_data';

import 'package:grid_engine/grid_engine.dart' show Presence;

import '../broker/broker.dart';
import 'acp_envelope.dart';

/// The bus protocol version — bumped on a breaking method/param shape change.
/// Carried in [InitializeParams]/[InitializeResult] so two stations can refuse
/// (or degrade) a mismatched peer at negotiation time rather than fail
/// opaquely mid-claim.
const int kBusProtocolVersion = 1;

/// The namespaced methods this bus speaks (D-B3: "the concrete method surface
/// extends `protocol.dart` (claims + presence + advertisement, versioned)").
/// Namespacing mirrors ACP's `session/...`-shaped methods, scoped under
/// `grid/` instead.
abstract final class BusMethods {
  /// Initialize-time capability negotiation (borrowed from ACP's own
  /// `initialize` handshake shape) — a peer states [kBusProtocolVersion] +
  /// its capabilities before either side relies on the other.
  static const String initialize = 'grid/initialize';

  /// Presence: retained on [BusTopics.presence] + registered as this
  /// broker's [LastWill] content (D-B1 — presence = broker liveness + LWT).
  static const String presence = 'grid/presence';

  /// Broadcast-unclaimed — a NOTIFICATION, retained on
  /// [BusTopics.claimUnclaimed] (D-A3: whatever is unclaimed at the end of a
  /// reconciliation phase is broadcast for pickup).
  static const String claimUnclaimed = 'grid/claim/unclaimed';

  /// Claim-respond — a REQUEST, published by the RESPONDING peer on its OWN
  /// broker ([BusTopics.claimRespond]), minted with a fresh [AcpRequest.id].
  static const String claimRespond = 'grid/claim/respond';

  /// Claim-confirm — the RESPONSE to a [claimRespond] request, published by
  /// the CLAIM'S OWNER on ITS OWN broker ([BusTopics.claimConfirm]), echoing
  /// the request's `id` (D-B3: "correlated by id across two brokers").
  static const String claimConfirm = 'grid/claim/confirm';
}

/// The topic layout — every topic is relative to its OWNING broker (D-B1:
/// publish-own means a [Broker] instance already identifies the station; no
/// topic needs to re-embed a station id).
abstract final class BusTopics {
  /// The retained presence topic.
  static const String presence = 'grid/presence';

  /// The RESPOND topic a peer publishes its claim-resp requests to (its OWN
  /// broker).
  static const String claimRespond = 'grid/claim/respond';

  /// The CONFIRM topic a claim's owner publishes its confirm/deny responses
  /// to (its OWN broker).
  static const String claimConfirm = 'grid/claim/confirm';

  /// The retained per-claim advertisement topic — one retained message per
  /// still-unclaimed requirement, cleared (empty retained publish) once
  /// confirmed/retracted. [claimId] is a `nodePath`, which itself contains
  /// `/` levels (`<workBeadId>/<stepId>` or deeper for a nested sub-circuit) —
  /// so [claimUnclaimedAll] uses `#`, not `+` (a single-level wildcard would
  /// silently miss it).
  static String claimUnclaimed(String claimId) =>
      'grid/claim/unclaimed/$claimId';

  /// The wildcard filter matching every advertised claim on a broadcaster's
  /// broker (subscribe here to see the FULL current advertisement set,
  /// retained-replayed on subscribe). `#` (not `+`) because a claimId spans
  /// MULTIPLE topic levels — see [claimUnclaimed].
  static const String claimUnclaimedAll = 'grid/claim/unclaimed/#';
}

/// The initialize-time capability-negotiation REQUEST params (borrowed shape,
/// D-B3) — a peer states its protocol version + a flat capability tag set
/// (reserved for future negotiation; empty this pass).
class InitializeParams {
  /// Creates initialize params for [station] declaring [protocolVersion].
  const InitializeParams({
    required this.station,
    this.protocolVersion = kBusProtocolVersion,
    this.capabilities = const {},
  });

  /// The initiating station's id.
  final String station;

  /// The protocol version the initiator speaks.
  final int protocolVersion;

  /// Reserved capability flags (empty this pass — no negotiable capability
  /// exists yet beyond the version itself).
  final Set<String> capabilities;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'station': station,
    'protocolVersion': protocolVersion,
    'capabilities': capabilities.toList()..sort(),
  };

  /// Parses [json].
  static InitializeParams fromJson(Map<String, dynamic> json) =>
      InitializeParams(
        station: json['station'] as String,
        protocolVersion: json['protocolVersion'] as int? ?? kBusProtocolVersion,
        capabilities: {
          for (final c in (json['capabilities'] as List? ?? const []))
            c as String,
        },
      );
}

/// The initialize-time RESULT — whether the responder accepts negotiation
/// (today: version equality; a future depth may accept a compatible range).
class InitializeResult {
  /// Creates an initialize result.
  const InitializeResult({
    required this.station,
    this.protocolVersion = kBusProtocolVersion,
    this.accepted = true,
  });

  /// The responding station's id.
  final String station;

  /// The protocol version the responder speaks.
  final int protocolVersion;

  /// Whether the responder accepts this peer (a version mismatch this pass
  /// always fails closed — see [negotiate]).
  final bool accepted;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'station': station,
    'protocolVersion': protocolVersion,
    'accepted': accepted,
  };

  /// Parses [json].
  static InitializeResult fromJson(Map<String, dynamic> json) =>
      InitializeResult(
        station: json['station'] as String,
        protocolVersion: json['protocolVersion'] as int? ?? kBusProtocolVersion,
        accepted: json['accepted'] as bool? ?? false,
      );
}

/// The negotiation decision: accepts iff the initiator's declared
/// [InitializeParams.protocolVersion] equals [kBusProtocolVersion] — a strict
/// match, fail-closed (no cross-version compatibility promised this pass; a
/// later depth may widen this to a compatible range).
InitializeResult negotiate(String station, InitializeParams params) =>
    InitializeResult(
      station: station,
      accepted: params.protocolVersion == kBusProtocolVersion,
    );

/// Encodes [presence] as the retained payload for [BusTopics.presence] — an
/// [AcpNotification] carrying the SAME flat profile shape [Presence.toJson]
/// already produces (no second serialization invented).
Uint8List presenceOnline(Presence presence) => encodeAcp(
  AcpNotification(
    method: BusMethods.presence,
    params: {...presence.toJson(), 'online': true},
  ),
);

/// The [LastWill] a station registers at broker-start: the SAME presence
/// topic, transitioning to `online: false` (D-B1's "presence = broker
/// liveness + LWT" — see `../broker/broker.dart`'s library doc for why a
/// graceful [Broker.close] is what actually fires it).
LastWill presenceWill(String station) => LastWill(
  topic: BusTopics.presence,
  payload: encodeAcp(
    AcpNotification(
      method: BusMethods.presence,
      params: {'station': station, 'online': false},
    ),
  ),
);
