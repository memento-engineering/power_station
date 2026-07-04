/// The mDNS/DNS-SD advertise half of AL-7 (D-B1/D-Z8) — the dual to
/// [MdnsBrowser] ('mdns_browser.dart').
library;

import 'dart:async';
import 'dart:io';

import 'station_ad.dart';
import 'wire.dart';

/// The mDNS multicast group (RFC 6762 §3); the well-known mDNS port.
final InternetAddress _mdnsGroup = InternetAddress('224.0.0.251');
const int _mdnsPort = 5353;

/// Advertises this station as a `_grid._tcp` service instance on the LAN —
/// the dual to [MdnsBrowser]. The advertise/browse round trip is the "live
/// office proof" this bead leaves to the operator (offline tests exercise the
/// pure `wire.dart` encoder + the topology/trust logic downstream instead).
abstract class MdnsAdvertiser {
  /// Starts advertising [ad]. Calling again while already advertising
  /// replaces the announced [StationAd] (e.g. its capacity/substation facts
  /// changed) without needing an explicit [stop] first.
  Future<void> advertise(StationAd ad);

  /// Withdraws the advertisement and releases any held socket.
  Future<void> stop();
}

/// The real implementation: a bounded mDNS RESPONDER (RFC 6762) that never
/// parses incoming queries — it only ever sends its OWN unsolicited
/// ("gratuitous") announcement on a fixed cadence (§8.3), so any listening
/// [MulticastDnsBrowser] (or standard `dns-sd`/`avahi-browse`) observes it
/// whether or not it happened to be querying at that instant. `dart:io` only;
/// no external process, no daemon (D-B2's posture, applied to discovery).
class MulticastDnsAdvertiser implements MdnsAdvertiser {
  /// Creates an advertiser that re-announces every [announceEvery] — well
  /// inside the record TTL (`wire.dart`'s default 120s) so one lost packet
  /// never lets the advertisement lapse.
  MulticastDnsAdvertiser({this.announceEvery = const Duration(seconds: 30)});

  /// How often the unsolicited announcement repeats.
  final Duration announceEvery;

  RawDatagramSocket? _socket;
  Timer? _timer;

  @override
  Future<void> advertise(StationAd ad) async {
    final socket = _socket ??= await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
    );
    final packet = encodeGridAnnouncement(ad);
    void announce() => socket.send(packet, _mdnsGroup, _mdnsPort);
    _timer?.cancel();
    announce(); // an immediate first announcement; then periodic renewal.
    _timer = Timer.periodic(announceEvery, (_) => announce());
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}
