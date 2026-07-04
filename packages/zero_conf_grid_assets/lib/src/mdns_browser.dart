/// The mDNS/DNS-SD browse half of AL-7 (D-B1/D-Z8) — the dual to
/// [MdnsAdvertiser] ('mdns_advertiser.dart').
library;

import 'package:multicast_dns/multicast_dns.dart';

import 'station_ad.dart';

/// Browses the LAN for `_grid._tcp` service instances. Pure seam:
/// [MulticastDnsBrowser] is the real, multicast-socket-backed implementation;
/// offline tests inject a FAKE (a canned [Stream]) instead of touching a real
/// socket — "Offline tests fake the mDNS browser" is this bead's test
/// strategy for the topology/trust logic that consumes it
/// ([TopologyResolver]).
abstract class MdnsBrowser {
  /// Browses for [kGridServiceType] instances for [timeout], yielding one
  /// [StationAd] per instance that answers with a decodable TXT record.
  Stream<StationAd> browse({Duration timeout = const Duration(seconds: 5)});
}

/// The real implementation: `package:multicast_dns`'s one-shot mDNS querier
/// (RFC 6762 §5.1) — a PTR lookup for [kGridServiceType], then a TXT lookup
/// per discovered instance. The D-Z8 wire (station id, broker endpoint,
/// hosted substations, trust hint) lives entirely in TXT
/// ([StationAd.fromTxt]); SRV/A are advertised (`wire.dart`) for interop with
/// standard `dns-sd`/`avahi-browse` tooling but are not needed to build a
/// [StationAd] here.
class MulticastDnsBrowser implements MdnsBrowser {
  /// Creates a browser; [client] defaults to a fresh [MDnsClient].
  MulticastDnsBrowser({MDnsClient? client}) : _client = client ?? MDnsClient();

  final MDnsClient _client;

  @override
  Stream<StationAd> browse({
    Duration timeout = const Duration(seconds: 5),
  }) async* {
    await _client.start();
    try {
      await for (final ptr in _client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(kGridServiceType),
        timeout: timeout,
      )) {
        final txt = await _firstTxt(ptr.domainName, timeout);
        if (txt == null) continue;
        final ad = StationAd.fromTxt(_parseTxt(txt));
        if (ad.station.isNotEmpty) yield ad;
      }
    } finally {
      _client.stop();
    }
  }

  Future<String?> _firstTxt(String instance, Duration timeout) async {
    await for (final rec in _client.lookup<TxtResourceRecord>(
      ResourceRecordQuery.text(instance),
      timeout: timeout,
    )) {
      return rec.text;
    }
    return null;
  }

  /// Splits the decoder's newline-joined character strings back into
  /// `key=value` pairs (the inverse of `wire.dart`'s `_encodeTxt`).
  static Map<String, String> _parseTxt(String raw) {
    final map = <String, String>{};
    for (final line in raw.split('\n')) {
      if (line.isEmpty) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      map[line.substring(0, eq)] = line.substring(eq + 1);
    }
    return map;
  }
}
