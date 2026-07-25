// Pure-logic proof of the mDNS/DNS-SD wire encoder ('lib/src/wire.dart'): no
// socket, no clock — a [StationAd] in, a well-formed announcement packet out.
// Decoding is hand-rolled HERE (independent of the encoder under test, and of
// `package:multicast_dns`'s private decoder) so this is a real round-trip
// proof, not a tautology.
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zero_conf_grid_assets/zero_conf_grid_assets.dart';

/// One decoded resource record: name, type, class, ttl, and raw rdata.
class _Rec {
  _Rec(this.name, this.type, this.klass, this.ttl, this.rdata);
  final String name;
  final int type;
  final int klass;
  final int ttl;
  final Uint8List rdata;
}

/// A decoded packet's header + records — no name compression support (the
/// encoder never emits it), which keeps this decoder small and independent.
class _Packet {
  _Packet(
    this.id,
    this.flags,
    this.qd,
    this.an,
    this.ns,
    this.ar,
    this.records,
  );
  final int id;
  final int flags;
  final int qd;
  final int an;
  final int ns;
  final int ar;
  final List<_Rec> records;
}

int _u16(Uint8List d, int o) => (d[o] << 8) | d[o + 1];
int _u32(Uint8List d, int o) =>
    (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3];

/// Decodes a plain (uncompressed) DNS name starting at [offset], returning the
/// name and the number of bytes consumed.
(String, int) _decodeName(Uint8List d, int offset) {
  final labels = <String>[];
  final start = offset;
  while (true) {
    final len = d[offset];
    offset += 1;
    if (len == 0) break;
    labels.add(utf8.decode(d.sublist(offset, offset + len)));
    offset += len;
  }
  return (labels.join('.'), offset - start);
}

_Packet _decodePacket(Uint8List d) {
  var o = 0;
  final id = _u16(d, o);
  o += 2;
  final flags = _u16(d, o);
  o += 2;
  final qd = _u16(d, o);
  o += 2;
  final an = _u16(d, o);
  o += 2;
  final ns = _u16(d, o);
  o += 2;
  final ar = _u16(d, o);
  o += 2;
  final records = <_Rec>[];
  for (var i = 0; i < an + ns + ar; i++) {
    final (name, nameLen) = _decodeName(d, o);
    o += nameLen;
    final type = _u16(d, o);
    o += 2;
    final klass = _u16(d, o);
    o += 2;
    final ttl = _u32(d, o);
    o += 4;
    final rdlen = _u16(d, o);
    o += 2;
    final rdata = Uint8List.fromList(d.sublist(o, o + rdlen));
    o += rdlen;
    records.add(_Rec(name, type, klass, ttl, rdata));
  }
  expect(
    o,
    d.length,
    reason: 'the whole packet was consumed, nothing left over',
  );
  return _Packet(id, flags, qd, an, ns, ar, records);
}

void main() {
  group('encodeGridAnnouncement', () {
    const withIp = StationAd(
      station: 'the-dashboard',
      host: '192.168.1.42',
      port: 8080,
      substations: ['dash'],
      trustHint: 'sekret',
    );
    const withHostname = StationAd(
      station: 'studio',
      host: 'studio.local',
      port: 9090,
    );

    test('is an answer-only, authoritative response packet', () {
      final p = _decodePacket(encodeGridAnnouncement(withHostname));
      expect(p.id, 0);
      expect(p.flags, 0x8400); // QR=response, AA=authoritative
      expect(p.qd, 0); // no question section
      expect(p.ns, 0);
      expect(p.ar, 0);
    });

    test(
      'carries PTR + SRV + TXT (no A record without a literal IPv4 host)',
      () {
        final p = _decodePacket(encodeGridAnnouncement(withHostname));
        expect(p.an, 3);
        expect(p.records.map((r) => r.type), [12, 33, 16]); // PTR, SRV, TXT
      },
    );

    test('adds an A record when the host is a literal IPv4 address', () {
      final p = _decodePacket(encodeGridAnnouncement(withIp));
      expect(p.an, 4);
      expect(p.records.map((r) => r.type), [12, 33, 16, 1]);
    });

    test('the PTR record points from the service type to the instance', () {
      final p = _decodePacket(encodeGridAnnouncement(withHostname));
      final ptr = p.records.first;
      expect(ptr.name, '_grid._tcp.local');
      final (domain, _) = _decodeName(ptr.rdata, 0);
      expect(domain, 'studio._grid._tcp.local');
    });

    test('the SRV record carries the port + target host', () {
      final p = _decodePacket(encodeGridAnnouncement(withHostname));
      final srv = p.records[1];
      expect(srv.name, 'studio._grid._tcp.local');
      expect(_u16(srv.rdata, 0), 0); // priority
      expect(_u16(srv.rdata, 2), 0); // weight
      expect(_u16(srv.rdata, 4), 9090); // port
      final (target, _) = _decodeName(srv.rdata, 6);
      expect(target, 'studio.local');
    });

    test('the TXT record round-trips the D-Z8 fields', () {
      final p = _decodePacket(encodeGridAnnouncement(withIp));
      final txt = p.records[2];
      expect(txt.name, 'the-dashboard._grid._tcp.local');

      // Decode TXT's back-to-back length-prefixed character strings.
      final pairs = <String, String>{};
      var o = 0;
      while (o < txt.rdata.length) {
        final len = txt.rdata[o];
        o += 1;
        final entry = utf8.decode(txt.rdata.sublist(o, o + len));
        o += len;
        final eq = entry.indexOf('=');
        pairs[entry.substring(0, eq)] = entry.substring(eq + 1);
      }
      expect(pairs, {
        'id': 'the-dashboard',
        'broker': '192.168.1.42:8080',
        'substations': 'dash',
        'trust': 'sekret',
      });
    });

    test('the A record carries the raw IPv4 bytes', () {
      final p = _decodePacket(encodeGridAnnouncement(withIp));
      final a = p.records[3];
      expect(a.name, 'the-dashboard.local');
      expect(a.rdata, [192, 168, 1, 42]);
    });

    test('honors a custom TTL on every record', () {
      final p = _decodePacket(
        encodeGridAnnouncement(withHostname, ttlSeconds: 45),
      );
      expect(p.records.map((r) => r.ttl), everyElement(45));
    });
  });
}
