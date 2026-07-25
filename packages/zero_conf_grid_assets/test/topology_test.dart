// Pure-logic proof of the TOPOLOGY OPINIONS (D-B1) applied as configuration
// over `federated_grid_assets`' Membership seam, downstream of the trust gate
// (D-Z6: an unblessed ad never reaches the topology decision at all).
import 'package:test/test.dart';
import 'package:zero_conf_grid_assets/zero_conf_grid_assets.dart';

void main() {
  const self = StationAd(station: 'self', host: 'self.local', port: 8080);
  const spokeA = StationAd(
    station: 'studio',
    host: 'studio.local',
    port: 8080,
    substations: ['power_station'],
  );
  const spokeB = StationAd(
    station: 'the-dashboard',
    host: 'linux-dashboard.local',
    port: 8080,
    substations: ['dash'],
  );
  const hub = StationAd(station: 'hub', host: 'hub.local', port: 9000);
  const stranger = StationAd(
    station: 'unknown-laptop',
    host: '10.0.0.9',
    port: 8080,
  );

  TrustGate allowAllBut(Set<String> refused) => TrustGate(
    allowed: {
      for (final ad in [self, spokeA, spokeB, hub, stranger])
        if (!refused.contains(ad.station)) ad.station: null,
    },
  );

  group('Topology.mesh', () {
    test('subscribes to every admitted, non-self peer regardless of kind', () {
      final resolver = TopologyResolver(
        topology: Topology.mesh,
        trust: allowAllBut({}),
      );
      final m = resolver.resolve([
        self,
        spokeA,
        spokeB,
        hub,
      ], selfStation: 'self');

      expect(m.peers.map((p) => p.id).toSet(), {
        'studio',
        'the-dashboard',
        'hub',
      });
    });

    test('a refused (unblessed) peer never reaches membership', () {
      final resolver = TopologyResolver(
        topology: Topology.mesh,
        trust: allowAllBut({'unknown-laptop'}),
      );
      final m = resolver.resolve([spokeA, stranger], selfStation: 'self');

      expect(m.peers.map((p) => p.id), ['studio']);
    });
  });

  group('Topology.gridHub', () {
    test('subscribes only to hub-candidate peers (no hosted substations)', () {
      final resolver = TopologyResolver(
        topology: Topology.gridHub,
        trust: allowAllBut({}),
      );
      final m = resolver.resolve([
        self,
        spokeA,
        spokeB,
        hub,
      ], selfStation: 'self');

      expect(m.peers.map((p) => p.id), ['hub']);
    });

    test('a spoke never subscribes to another spoke, only the hub', () {
      final resolver = TopologyResolver(
        topology: Topology.gridHub,
        trust: allowAllBut({}),
      );
      final m = resolver.resolve([spokeA, spokeB], selfStation: 'self');
      expect(m.peers, isEmpty); // no hub discovered — no subscriptions
    });
  });

  test('never includes self, and de-dups repeated announcements', () {
    final resolver = TopologyResolver(
      topology: Topology.mesh,
      trust: allowAllBut({}),
    );
    const spokeARenamed = StationAd(
      station: 'studio',
      host: 'studio-new-ip.local',
      port: 8080,
      substations: ['power_station'],
    );
    final m = resolver.resolve([
      self,
      spokeA,
      spokeARenamed, // a re-announcement of the same station id
    ], selfStation: 'self');

    expect(m.peers, hasLength(1));
    expect(m.peers.single.host, 'studio-new-ip.local'); // the latest wins
  });
}
