/// The low-level mDNS/DNS-SD wire encoder for a `_grid._tcp` announcement
/// (RFC 1035/6762/6763). Pure: no sockets, no clock, no randomness — a
/// [StationAd] in, a `Uint8List` packet out, fully testable without touching
/// a real network. [MulticastDnsAdvertiser] is the only caller; kept a
/// separate file so the wire format is provable on its own (the "pure logic
/// tested before IO is wired" house doctrine).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:multicast_dns/multicast_dns.dart' show ResourceRecordType;

import 'station_ad.dart';

/// One resource record awaiting encoding.
class _Record {
  const _Record({required this.name, required this.type, required this.rdata});
  final String name;
  final int type;
  final Uint8List rdata;
}

/// Encodes an UNSOLICITED mDNS announcement (RFC 6762 §8.3 — a "gratuitous"
/// announcement needs no prior query) advertising [ad]: an answer-only packet
/// (`QDCOUNT` 0) carrying a PTR ([kGridServiceType] → the station's instance),
/// an SRV (the instance → `host:port`, kept for interop with standard
/// `dns-sd`/`avahi-browse` tooling), a TXT (the D-Z8 wire: station id, broker
/// endpoint, hosted substations, trust hint — [StationAd.toTxt]), and — only
/// when [ad]'s host is a literal IPv4 address — an A record.
///
/// `ANCOUNT` counts every record regardless of DNS "section"; the querying
/// side (`package:multicast_dns`'s decoder) sums answer+authority+additional
/// counts identically, so section placement carries no meaning here.
Uint8List encodeGridAnnouncement(StationAd ad, {int ttlSeconds = 120}) {
  final instance = '${ad.station}.$kGridServiceType.local';
  final target = '${ad.station}.local';

  final records = <_Record>[
    _Record(
      name: '$kGridServiceType.local',
      type: ResourceRecordType.serverPointer,
      rdata: _encodeName(instance),
    ),
    _Record(
      name: instance,
      type: ResourceRecordType.service,
      rdata: _encodeSrv(target: target, port: ad.port),
    ),
    _Record(
      name: instance,
      type: ResourceRecordType.text,
      rdata: _encodeTxt(ad.toTxt()),
    ),
  ];
  final ipv4 = _tryParseIPv4(ad.host);
  if (ipv4 != null) {
    records.add(
      _Record(
        name: target,
        type: ResourceRecordType.addressIPv4,
        rdata: Uint8List.fromList(ipv4),
      ),
    );
  }

  final out = BytesBuilder();
  _writeUint16(out, 0); // ID — unused for mDNS.
  _writeUint16(out, 0x8400); // FLAGS: QR=response, AA=authoritative.
  _writeUint16(out, 0); // QDCOUNT — no question section.
  _writeUint16(out, records.length); // ANCOUNT.
  _writeUint16(out, 0); // NSCOUNT.
  _writeUint16(out, 0); // ARCOUNT.
  for (final r in records) {
    out.add(_encodeName(r.name));
    _writeUint16(out, r.type);
    _writeUint16(out, 1); // CLASS — IN.
    _writeUint32(out, ttlSeconds);
    _writeUint16(out, r.rdata.length);
    out.add(r.rdata);
  }
  return out.toBytes();
}

Uint8List _encodeName(String fqdn) {
  final out = BytesBuilder();
  for (final label in fqdn.split('.')) {
    if (label.isEmpty) continue;
    final bytes = utf8.encode(label);
    out.addByte(bytes.length);
    out.add(bytes);
  }
  out.addByte(0); // the root label
  return out.toBytes();
}

Uint8List _encodeSrv({required String target, required int port}) {
  final out = BytesBuilder();
  _writeUint16(out, 0); // priority
  _writeUint16(out, 0); // weight
  _writeUint16(out, port);
  out.add(_encodeName(target));
  return out.toBytes();
}

/// Encodes [txt] as back-to-back length-prefixed `key=value` character
/// strings — DNS-SD's multi-string TXT shape (RFC 6763 §6); the counterpart
/// decoder (`package:multicast_dns`) joins them with newlines on the way out.
Uint8List _encodeTxt(Map<String, String> txt) {
  final out = BytesBuilder();
  txt.forEach((key, value) {
    final bytes = utf8.encode('$key=$value');
    out.addByte(bytes.length);
    out.add(bytes);
  });
  if (txt.isEmpty) out.addByte(0);
  return out.toBytes();
}

List<int>? _tryParseIPv4(String host) {
  final parts = host.split('.');
  if (parts.length != 4) return null;
  final bytes = <int>[];
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return null;
    bytes.add(n);
  }
  return bytes;
}

void _writeUint16(BytesBuilder out, int value) {
  out.addByte((value >> 8) & 0xff);
  out.addByte(value & 0xff);
}

void _writeUint32(BytesBuilder out, int value) {
  out.addByte((value >> 24) & 0xff);
  out.addByte((value >> 16) & 0xff);
  out.addByte((value >> 8) & 0xff);
  out.addByte(value & 0xff);
}
