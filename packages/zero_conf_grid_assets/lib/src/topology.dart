/// The TOPOLOGY OPINIONS (`SCRATCH-grid-alignment.md` D-B1) applied AS
/// CONFIGURATION over `federated_grid_assets`' seams: every station publishes
/// only on its own broker and subscribes to others per topology — the
/// subscribe-to-whom choice is the opinion this file ships, never the engine's
/// (D-B5: "no MQTT in the engine, ever").
library;

import 'package:federated_grid_assets/federated_grid_assets.dart';

import 'station_ad.dart';
import 'trust_gate.dart';

/// The subscribe-to-whom opinion (D-B1).
enum Topology {
  /// Subscribe to every discovered (and trust-gated) peer — O(N²)
  /// connections; the office runs this at N=5.
  mesh,

  /// Subscribe only to a hub: a station "running nothing but federation
  /// assets" ([StationAd.isHubCandidate]). Spokes never subscribe to each
  /// other — same binary, same primitive, topology by configuration.
  gridHub,
}

/// Resolves a discovered peer set into a `federated_grid_assets` [Membership]
/// — the topology opinion applied AFTER the [trust] gate (D-Z6: an untrusted
/// peer never reaches the subscribe-to-whom decision at all).
class TopologyResolver {
  /// Creates a resolver applying [topology] over ads admitted by [trust].
  const TopologyResolver({required this.topology, required this.trust});

  /// The configured topology opinion.
  final Topology topology;

  /// The discovered-is-not-TRUSTED gate (D-Z6) run before [topology] ever
  /// sees an ad.
  final TrustGate trust;

  /// Builds the [Membership] this station should subscribe to from [ads] —
  /// one entry per discovered station id (a repeated announcement overwrites
  /// the prior one; [selfStation] is always excluded).
  Membership resolve(Iterable<StationAd> ads, {required String selfStation}) {
    final byStation = <String, StationAd>{};
    for (final ad in ads) {
      if (ad.station == selfStation) continue;
      byStation[ad.station] = ad;
    }
    final admitted = byStation.values.where(trust.admits);
    final selected = switch (topology) {
      Topology.mesh => admitted,
      Topology.gridHub => admitted.where((ad) => ad.isHubCandidate),
    };
    return Membership(peers: [for (final ad in selected) ad.toPeer()]);
  }
}
