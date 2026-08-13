// Pure-logic proof of the [ZeroConfMembership] discovery loop: browse → gate
// (D-Z6) → shape per topology (D-B1) → a `federated_grid_assets` [Membership].
// A FAKE [MdnsBrowser] stands in for the real multicast socket ("Offline
// tests fake the mDNS browser" — the real advertise/browse interop is the
// live office proof, an operator step, not an automated one).
import 'package:test/test.dart';
import 'package:zero_conf_grid_assets/zero_conf_grid_assets.dart';

/// A canned [MdnsBrowser]: yields [answers] on every [browse] call, never
/// touching a real socket.
class FakeMdnsBrowser implements MdnsBrowser {
  FakeMdnsBrowser(this.answers);

  final List<StationAd> answers;
  int browseCalls = 0;

  @override
  Stream<StationAd> browse({Duration timeout = const Duration(seconds: 5)}) {
    browseCalls++;
    return Stream.fromIterable(answers);
  }
}

void main() {
  const hub = StationAd(station: 'hub', host: 'hub.local', port: 9000);
  const spoke = StationAd(
    station: 'studio',
    host: 'studio.local',
    port: 8080,
    substations: ['power_station'],
  );

  group('ZeroConfMembership.discover', () {
    test('resolves one browse pass into a Membership (mesh)', () async {
      final browser = FakeMdnsBrowser([hub, spoke]);
      final loop = ZeroConfMembership(
        browser: browser,
        resolver: TopologyResolver(
          topology: Topology.mesh,
          trust: TrustGate(allowed: {'hub': null, 'studio': null}),
        ),
        selfStation: 'self',
      );

      final membership = await loop.discover();
      expect(membership.peers.map((p) => p.id).toSet(), {'hub', 'studio'});
      expect(browser.browseCalls, 1);
    });

    test(
      'gridHub topology narrows the same discovery to just the hub',
      () async {
        final browser = FakeMdnsBrowser([hub, spoke]);
        final loop = ZeroConfMembership(
          browser: browser,
          resolver: TopologyResolver(
            topology: Topology.gridHub,
            trust: TrustGate(allowed: {'hub': null, 'studio': null}),
          ),
          selfStation: 'self',
        );

        expect((await loop.discover()).peers.map((p) => p.id), ['hub']);
      },
    );

    test('an untrusted discovery never reaches the Membership', () async {
      final log = <String>[];
      final browser = FakeMdnsBrowser([hub, spoke]);
      final loop = ZeroConfMembership(
        browser: browser,
        resolver: TopologyResolver(
          topology: Topology.mesh,
          trust: TrustGate(allowed: {'hub': null}, onLog: log.add),
        ),
        selfStation: 'self',
      );

      final membership = await loop.discover();
      expect(membership.peers.map((p) => p.id), ['hub']);
      expect(log.any((l) => l.contains('REFUSED "studio"')), isTrue);
    });
  });

  test('watch() re-browses on every refresh tick', () async {
    final browser = FakeMdnsBrowser([hub]);
    final loop = ZeroConfMembership(
      browser: browser,
      resolver: TopologyResolver(
        topology: Topology.mesh,
        trust: TrustGate(allowed: {'hub': null}),
      ),
      selfStation: 'self',
    );

    final snapshots = await loop
        .watch(refreshEvery: Duration.zero)
        .take(3)
        .toList();
    expect(snapshots, hasLength(3));
    expect(browser.browseCalls, 3); // one browse per emitted snapshot
  });
}
