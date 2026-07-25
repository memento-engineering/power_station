/// The D-B2 shield — the abstract single-writer broker seam
/// (`docs/SCRATCH-grid-alignment.md` D-B1/D-B2, the honesty pass, 2026-07-03).
///
/// Nico: in-process; pub.dev "[has] not a lot of good/maintained options" — so
/// `federated_grid_assets` defines its OWN abstract broker interface to shield
/// the dependency: try an existing package behind the seam first, write our
/// own single-writer subset only if it fails the vet, swap freely later. The
/// vet (2026-07-03, recorded here + in the landing commit): `mqtt_server`
/// (pub points 135, 7 likes, 108 weekly downloads, unverified publisher),
/// `mqtt_broker` (pub points 120, 0 likes, 14 weekly downloads, v0.1.0),
/// `dart_mqtt_broker` (pub points 140, 2 likes, 34 weekly downloads, v1.0.0) —
/// all three are single-digit-to-low-double-digit-likes, sub-150-weekly-
/// download packages with no evidence of production use at any real scale.
/// VERDICT: none adequate — this package implements its OWN bounded
/// single-writer subset behind this seam ([InMemoryBroker] this pass; a real
/// wire transport is a follow-up, exactly as `HttpStationClient` shipped as
/// impl #1 of the [StationClient] seam and MQTT was always the "droppable in
/// later" plan).
///
/// **Publish-own is single-writer (D-B1):** a [Broker] instance IS one
/// station's own broker. The ONLY writer to it is the local process that owns
/// it (this collapses a broker to "a retained-topic map + subscriber fan-out +
/// LWT — no fan-in races, no cross-publisher arbitration," D-B2); a peer only
/// ever [subscribe]s to it, over a SEPARATE [Broker] instance/connection it
/// does not write to. There is no PUBLISH-from-a-remote-client verb in this
/// seam at all — that asymmetry (never a `mqtt_server`-shaped multi-writer
/// broker) is what makes single-writer a structural guarantee, not a
/// convention peers must honor.
///
/// **Presence = broker liveness + LWT (D-B1):** [Broker] does not represent
/// presence as a special primitive — a composer publishes a retained "online"
/// message on a presence topic at start, and registers a [LastWill] whose
/// content is the "offline" transition. [close] publishes the will BEFORE
/// tearing down (an explicit, honest goodbye — the presence topic's retained
/// value transitions cleanly). A REAL crash cannot call [close] — for an
/// in-process, single-writer broker, "station-dark = broker-dark," so an
/// abrupt death is instead signalled the honest way: every subscriber's
/// [subscribe] stream simply ends, no lingering "online" retained ad
/// outliving the station (unlike an out-of-process daemon broker, which could
/// keep serving a zombie retained ad for a station that already died).
///
/// **Advertisement = retained (D-B1):** the claim protocol's
/// `grid/claim/unclaimed/<claimId>` messages (`../claim/claim_broadcaster.dart`)
/// are published with `retain: true` — a late-joining subscriber sees the
/// CURRENT advertisement set immediately, with no separate "catch-up" query.
///
/// QoS 0/1 is carried through [publish]/[subscribe] as a plain integer (the
/// bounded subset this seam targets, "CONNECT/SUB/PUB, QoS 0-1, retained,
/// will, ping") but [InMemoryBroker] delivers every message reliably in-process
/// regardless of the requested QoS — there is no network to drop a QoS-0
/// message over. The distinction becomes load-bearing only for a future WIRE
/// transport behind this SAME seam; it is threaded through now so that impl
/// is additive, not a signature break.
library;

import 'dart:async';
import 'dart:typed_data';

/// An MQTT-shaped last-will: the retained [topic]/[payload] a [Broker]
/// publishes on [Broker.close] (an explicit goodbye) — see the library doc for
/// why this is the presence mechanism (D-B1).
class LastWill {
  /// Creates a will publishing [payload] to [topic] (retained) at [qos].
  const LastWill({required this.topic, required this.payload, this.qos = 0});

  /// The topic the will is published to.
  final String topic;

  /// The will's payload (the "offline"/"gone" transition content).
  final Uint8List payload;

  /// The QoS the will is published at.
  final int qos;
}

/// One message delivered to a [Broker.subscribe] stream: the concrete [topic]
/// it landed on (a subscription may be a wildcard filter), the raw [payload],
/// the [qos] it carries, and whether it is a REPLAYED retained message
/// (delivered immediately on subscribe) vs. a live publish.
class BrokerMessage {
  /// Creates a delivered message.
  const BrokerMessage({
    required this.topic,
    required this.payload,
    required this.qos,
    this.retained = false,
  });

  /// The exact topic the message was published to.
  final String topic;

  /// The raw payload bytes.
  final Uint8List payload;

  /// The QoS this message carries (0 or 1, this pass).
  final int qos;

  /// Whether this is a retained message replayed at subscribe time (vs. a
  /// message published while already subscribed).
  final bool retained;

  @override
  String toString() =>
      'BrokerMessage($topic, ${payload.length}B, qos: $qos'
      '${retained ? ', retained' : ''})';
}

/// The abstract single-writer broker seam (D-B2). One instance is one
/// station's OWN broker — see the library doc for the publish-own/single-writer
/// discipline this interface structurally enforces (no publish-from-subscriber
/// verb exists here at all).
abstract interface class Broker {
  /// This broker's owning station id (the presence identity; a subscriber
  /// knows WHO it is subscribed to by which [Broker] instance/connection it
  /// used — never from a field on [BrokerMessage]).
  String get station;

  /// Publishes [payload] to [topic]. [retain] stores it as the topic's CURRENT
  /// retained value (replayed to every future [subscribe] match immediately);
  /// an EMPTY [payload] with [retain] CLEARS the retained store for [topic]
  /// (standard MQTT retained-clear semantics — the advertisement-retraction
  /// path the claim protocol uses). [qos] is carried through to subscribers.
  /// A no-op once [close]d (a torn-down broker accepts no further writes).
  void publish(
    String topic,
    Uint8List payload, {
    bool retain = false,
    int qos = 0,
  });

  /// Subscribes to [topicFilter] (MQTT wildcards: `+` matches exactly one
  /// topic level, `#` matches all remaining levels and must be the final
  /// segment). Replays every CURRENTLY retained message matching the filter
  /// immediately (in filter-match order), then streams live publishes. The
  /// stream ENDS when this broker is [close]d — a subscriber's stream ending
  /// is the honest disconnect signal (D-B1); it never receives an explicit
  /// "error", just a clean stream close.
  Stream<BrokerMessage> subscribe(String topicFilter);

  /// A liveness no-op (the MQTT PINGREQ/PINGRESP analogue) — an in-process
  /// broker has no round trip to prove; a wire-transport impl behind this same
  /// seam drives its own keepalive timer through this method. Throws
  /// [StateError] once [close]d (a ping against a dead broker fails).
  Future<void> ping();

  /// Gracefully tears this broker down: publishes its registered will (if any
  /// — an explicit goodbye, see the library doc), then ends every subscriber
  /// stream. Idempotent.
  Future<void> close();
}

/// Whether MQTT-style [filter] matches [topic] — `+` matches exactly one
/// `/`-delimited level, `#` matches all remaining levels (only valid as the
/// final segment). Pure; both single-level and multi-level wildcards compose
/// (`grid/+/claim/#`).
bool topicMatches(String filter, String topic) {
  final f = filter.split('/');
  final t = topic.split('/');
  var fi = 0;
  var ti = 0;
  while (fi < f.length) {
    final seg = f[fi];
    if (seg == '#') return true; // matches everything remaining
    if (ti >= t.length) return false; // filter longer than topic, no # left
    if (seg != '+' && seg != t[ti]) return false;
    fi++;
    ti++;
  }
  return ti == t.length; // exact length match (no leftover topic levels)
}
