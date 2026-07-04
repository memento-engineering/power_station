/// Zero-conf discovery + topology opinions for the office grid (AL-7,
/// the_grid docs/SCRATCH-grid-alignment.md D-B1 +
/// SCRATCH-multi-root-federation.md D-Z6/D-Z8).
///
/// Three pieces:
///
/// 1. **mDNS/DNS-SD advertise + browse** ([MdnsAdvertiser]/[MdnsBrowser],
///    service type [kGridServiceType] = `_grid._tcp`; the TXT wire is
///    [StationAd]: station id, broker endpoint, hosted substations, trust
///    hints). [MulticastDnsAdvertiser]/[MulticastDnsBrowser] are the real,
///    `dart:io`-backed implementations — a bounded RFC 6762 responder that
///    only ever sends unsolicited announcements, and `package:multicast_dns`'s
///    one-shot querier, respectively.
/// 2. **The TOPOLOGY OPINIONS as configuration over `federated_grid_assets`'
///    seams** ([Topology]/[TopologyResolver]): MESH (subscribe to every
///    discovered peer) and GRIDHUB (subscribe to a hub only — a hub is just a
///    station running nothing but federation assets,
///    [StationAd.isHubCandidate]). The output is a plain
///    `federated_grid_assets` [Membership] — nothing downstream needs to know
///    discovery produced it.
/// 3. **The discovered-is-not-blessed TRUST GATE** ([TrustGate], D-Z6):
///    allow-list this round, matching [Peer.token]'s LAN-trust posture; LOUD
///    both ways, naming the claimed identity.
///
/// [ZeroConfMembership] wires all three into a discovery loop a station
/// runner can wire alongside its `ServeCommand`/`LeaseCommand`.
///
/// Offline tests fake [MdnsBrowser]; a live office proof (real advertise ↔
/// browse interop) is the operator's step, not an automated one.
library;

export 'package:federated_grid_assets/federated_grid_assets.dart'
    show Membership, Peer;

export 'src/mdns_advertiser.dart';
export 'src/mdns_browser.dart';
export 'src/station_ad.dart';
export 'src/topology.dart';
export 'src/trust_gate.dart';
export 'src/wire.dart' show encodeGridAnnouncement;
export 'src/zero_conf_membership.dart';
