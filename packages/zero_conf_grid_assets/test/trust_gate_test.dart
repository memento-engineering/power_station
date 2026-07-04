// Pure-logic proof of the discovered-is-not-blessed TRUST GATE (D-Z6): an
// allow-list decision, LOUD both ways, always naming the claimed station id.
import 'package:test/test.dart';
import 'package:zero_conf_grid_assets/zero_conf_grid_assets.dart';

void main() {
  group('TrustGate', () {
    const knownNoToken = StationAd(
      station: 'studio',
      host: 'studio.local',
      port: 8080,
    );
    const knownWithToken = StationAd(
      station: 'the-dashboard',
      host: 'linux-dashboard.local',
      port: 8080,
      trustHint: 'sekret',
    );
    const stranger = StationAd(
      station: 'unknown-laptop',
      host: '10.0.0.9',
      port: 8080,
    );

    test('refuses a station absent from the allow-list', () {
      final log = <String>[];
      final gate = TrustGate(allowed: {'studio': null}, onLog: log.add);

      expect(gate.admits(stranger), isFalse);
      expect(log, hasLength(1));
      expect(log.single, contains('REFUSED'));
      expect(log.single, contains('unknown-laptop')); // names the claimed id
      expect(log.single, contains('not on the allow-list'));
    });

    test('admits an allow-listed station requiring no token', () {
      final log = <String>[];
      final gate = TrustGate(allowed: {'studio': null}, onLog: log.add);

      expect(gate.admits(knownNoToken), isTrue);
      expect(log.single, contains('ADMITTED'));
      expect(log.single, contains('studio'));
    });

    test('admits an allow-listed station whose trust hint matches', () {
      final log = <String>[];
      final gate = TrustGate(
        allowed: {'the-dashboard': 'sekret'},
        onLog: log.add,
      );

      expect(gate.admits(knownWithToken), isTrue);
      expect(log.single, contains('ADMITTED "the-dashboard"'));
    });

    test('refuses an allow-listed station whose trust hint mismatches', () {
      final log = <String>[];
      final gate = TrustGate(
        allowed: {'the-dashboard': 'a-different-secret'},
        onLog: log.add,
      );

      expect(gate.admits(knownWithToken), isFalse);
      expect(log.single, contains('REFUSED "the-dashboard"'));
      expect(log.single, contains('trust hint mismatch'));
    });

    test('a missing onLog is a silent no-op (never throws)', () {
      final gate = TrustGate(allowed: const {});
      expect(() => gate.admits(stranger), returnsNormally);
    });
  });
}
