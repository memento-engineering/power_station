// Pure-logic proof of the [StationAd] wire shape (D-Z8): the TXT codec
// round-trips, the hub signal is exactly "no hosted substations" (D-B1), and
// an admitted ad converts into `federated_grid_assets`' [Peer] shape.
import 'package:test/test.dart';
import 'package:zero_conf_grid_assets/zero_conf_grid_assets.dart';

void main() {
  group('StationAd', () {
    test('toTxt/fromTxt round-trips the D-Z8 fields', () {
      const ad = StationAd(
        station: 'the-dashboard',
        host: 'linux-dashboard.local',
        port: 8080,
        substations: ['dash', 'butane_flutter'],
        trustHint: 'sekret',
      );
      final txt = ad.toTxt();
      expect(txt['id'], 'the-dashboard');
      expect(txt['broker'], 'linux-dashboard.local:8080');
      expect(txt['substations'], 'dash,butane_flutter');
      expect(txt['trust'], 'sekret');
      expect(StationAd.fromTxt(txt), ad);
    });

    test('a hub advertises an empty substations list', () {
      const hub = StationAd(station: 'hub', host: 'hub.local', port: 9000);
      expect(hub.substations, isEmpty);
      expect(hub.isHubCandidate, isTrue);
      expect(hub.toTxt()['substations'], '');
      expect(StationAd.fromTxt(hub.toTxt()).isHubCandidate, isTrue);
    });

    test('a spoke hosting substations is never a hub candidate', () {
      const spoke = StationAd(
        station: 'studio',
        host: 'studio.local',
        port: 8080,
        substations: ['power_station'],
      );
      expect(spoke.isHubCandidate, isFalse);
    });

    test('omits the trust field from TXT when there is no hint', () {
      const ad = StationAd(station: 'x', host: 'h', port: 1);
      expect(ad.toTxt().containsKey('trust'), isFalse);
      expect(StationAd.fromTxt(ad.toTxt()).trustHint, isNull);
    });

    test('fromTxt on a missing/malformed broker yields port 0', () {
      final ad = StationAd.fromTxt({'id': 'x'});
      expect(ad.station, 'x');
      expect(ad.host, '');
      expect(ad.port, 0);
    });

    test('control-door endpoint round-trips through TXT', () {
      const ad = StationAd(
        station: 'the-dashboard',
        host: 'linux-dashboard.local',
        port: 8080,
        controlDoor: 'linux-dashboard.local:4400',
        substations: ['dash'],
        trustHint: 'sekret',
      );
      final txt = ad.toTxt();
      expect(txt['door'], 'linux-dashboard.local:4400');
      final decoded = StationAd.fromTxt(txt);
      expect(decoded.controlDoor, 'linux-dashboard.local:4400');
      expect(decoded, ad); // the door is part of the ad's value identity
    });

    test('omits the door field from TXT when no control door is exposed', () {
      const ad = StationAd(station: 'x', host: 'h', port: 1);
      expect(ad.toTxt().containsKey('door'), isFalse);
      expect(StationAd.fromTxt(ad.toTxt()).controlDoor, isNull);
    });

    test('rc.1 TXT without a control door remains wire-compatible', () {
      // The record shape already on the wire from stations running the
      // released pack: four keys, in this order, no `door`.
      const shipped = <String, String>{
        'id': 'studio',
        'broker': 'studio.local:8080',
        'substations': 'power_station',
        'trust': 'sekret',
      };
      final decoded = StationAd.fromTxt(shipped);
      expect(decoded.controlDoor, isNull);
      // Re-encoding an ad that carries no door changes neither the key set nor
      // the wire order — an already-shipped ad decodes exactly as it did.
      expect(
        decoded.toTxt().entries.map((e) => '${e.key}=${e.value}').toList(),
        shipped.entries.map((e) => '${e.key}=${e.value}').toList(),
      );
    });

    test(
      'toPeer carries the control-door endpoint as nullable Peer metadata',
      () {
        const withDoor = StationAd(
          station: 'the-dashboard',
          host: 'linux-dashboard.local',
          port: 8080,
          controlDoor: 'linux-dashboard.local:4400',
        );
        expect(withDoor.toPeer().controlDoor, 'linux-dashboard.local:4400');
        // The bus address is untouched by the door — they are two endpoints.
        expect(withDoor.toPeer().address, 'linux-dashboard.local:8080');

        const noDoor = StationAd(
          station: 'studio',
          host: 'studio.local',
          port: 1,
        );
        expect(noDoor.toPeer().controlDoor, isNull);
      },
    );

    test('toPeer carries the trust hint as the Peer token', () {
      const ad = StationAd(
        station: 'the-dashboard',
        host: 'linux-dashboard.local',
        port: 8080,
        trustHint: 'sekret',
      );
      expect(
        ad.toPeer(),
        const Peer(
          id: 'the-dashboard',
          host: 'linux-dashboard.local',
          port: 8080,
          token: 'sekret',
        ),
      );
    });

    test('address is host:port and equality is value-based', () {
      const a = StationAd(station: 'x', host: 'h', port: 1);
      const b = StationAd(station: 'x', host: 'h', port: 1);
      const c = StationAd(station: 'x', host: 'h', port: 2);
      expect(a.address, 'h:1');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
