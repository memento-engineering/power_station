/// The wire shape a `_grid._tcp` service instance carries — the D-Z8 pin:
/// "one discovery asset ... service instance carrying station id, control
/// endpoint, offered substation prefixes, trust hints." [StationAd] is that
/// shape, transport-free: the mDNS TXT record encodes/decodes it
/// ([StationAd.toTxt]/[StationAd.fromTxt]), and once a [TrustGate] approves one
/// it converts directly into `federated_grid_assets`' [Peer]
/// ([StationAd.toPeer]) — the seam D-Z8 promises ("slots behind the
/// `Membership` seam").
library;

import 'package:federated_grid_assets/federated_grid_assets.dart';
import 'package:meta/meta.dart';

/// The DNS-SD service type every station advertises under (D-B1/AL-7):
/// `_grid._tcp` — one instance per station, discovered on `.local`.
const String kGridServiceType = '_grid._tcp';

/// A station's `_grid._tcp` service instance — either what THIS station
/// advertises ([MdnsAdvertiser.advertise]) or what a browse observed
/// ([MdnsBrowser.browse]). [substations] is empty for a hub (D-B1: "a hub is
/// just a station running nothing but federation assets") — the signal
/// [Topology.gridHub] filters on. [trustHint] is a self-claimed identity
/// marker (never a secret to trust blindly — [TrustGate] cross-checks it
/// against a LOCAL allow-list before this ad reaches membership, D-Z6).
@immutable
class StationAd {
  /// Creates a service-instance advertisement.
  const StationAd({
    required this.station,
    required this.host,
    required this.port,
    this.substations = const [],
    this.trustHint,
  });

  /// The station id (the PTR instance name and the TXT `id` field).
  final String station;

  /// The federation bus host this station's broker/lessor answers on.
  final String host;

  /// The federation bus port.
  final int port;

  /// The substation prefixes this station hosts (D-A1); empty = a hub
  /// candidate (D-B1).
  final List<String> substations;

  /// The self-claimed trust hint (e.g. a token fingerprint); `null` when the
  /// station advertises none. Never trusted on its own — see [TrustGate].
  final String? trustHint;

  /// `host:port` — the federation bus address ([Peer.address]'s shape).
  String get address => '$host:$port';

  /// A hub runs nothing but federation assets — no hosted substations
  /// (D-B1: "the hub is just a station running nothing but federation
  /// assets"). [Topology.gridHub] subscribes to these and only these.
  bool get isHubCandidate => substations.isEmpty;

  /// The TXT record this ad publishes: station id, broker endpoint, hosted
  /// substations, trust hint (D-Z8's four fields) as `key=value` character
  /// strings.
  Map<String, String> toTxt() => {
    'id': station,
    'broker': address,
    'substations': substations.join(','),
    if (trustHint != null) 'trust': trustHint!,
  };

  /// Parses a decoded TXT record ([toTxt]'s inverse). An unparsable/missing
  /// `broker` field yields port `0` — callers should treat a `station.isEmpty`
  /// result as "not a grid ad" and discard it.
  static StationAd fromTxt(Map<String, String> txt) {
    final broker = txt['broker'] ?? '';
    final colon = broker.lastIndexOf(':');
    final host = colon > 0 ? broker.substring(0, colon) : broker;
    final port = colon > 0 ? int.tryParse(broker.substring(colon + 1)) ?? 0 : 0;
    final subs = txt['substations'];
    return StationAd(
      station: txt['id'] ?? '',
      host: host,
      port: port,
      substations: (subs == null || subs.isEmpty) ? const [] : subs.split(','),
      trustHint: txt['trust'],
    );
  }

  /// Converts an ADMITTED ad into a `federated_grid_assets` [Peer] — the D-Z8
  /// seam back into the lease bus's static [Membership] shape. Callers only
  /// reach this after a [TrustGate] has approved the ad (discovered ≠ trusted,
  /// D-Z6); this method itself performs no trust check.
  Peer toPeer() => Peer(id: station, host: host, port: port, token: trustHint);

  @override
  bool operator ==(Object other) =>
      other is StationAd &&
      other.station == station &&
      other.host == host &&
      other.port == port &&
      _listEq(other.substations, substations) &&
      other.trustHint == trustHint;

  @override
  int get hashCode =>
      Object.hash(station, host, port, Object.hashAll(substations), trustHint);

  @override
  String toString() =>
      'StationAd($station @ $address'
      '${substations.isEmpty ? ', hub' : ', hosts ${substations.join(',')}'}'
      '${trustHint != null ? ', +trust' : ''})';

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
