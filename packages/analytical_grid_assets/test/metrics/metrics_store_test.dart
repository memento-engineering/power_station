// The STORE SET — resolved from the roster at run time, never hardcoded
// (the `search` domain's A11 posture). Pure: no store need exist on disk.
import 'package:analytical_grid_assets/analytical_grid_assets.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:test/test.dart';

void main() {
  group('stationMetricsStores — the set is an INPUT, never hardcoded', () {
    test('an empty roster yields only the composing grid', () {
      final stores = stationMetricsStores(gridHome: '/g', roster: const []);
      expect(stores.map((s) => s.name), ['(grid)']);
      expect(stores.single.beadsDir, '/g/.grid/.beads');
    });

    test('every roster seat contributes a store, in roster order', () {
      final stores = stationMetricsStores(
        gridHome: '/g',
        roster: const [
          sdk.SubstationScope(
            name: 'power_station',
            root: '/w/pow',
            prefix: 'pow',
          ),
          sdk.SubstationScope(name: 'the_grid', root: '/w/tg', prefix: 'tg'),
        ],
      );
      expect(stores.map((s) => s.name), [
        '(grid)',
        'power_station',
        'the_grid',
      ]);
      expect(stores[1].runtimeDir, '/w/pow/.grid');
    });

    test('a dual-role seat rooted at the grid home is read once', () {
      final stores = stationMetricsStores(
        gridHome: '/g',
        roster: const [sdk.SubstationScope(name: 'g', root: '/g', prefix: 'g')],
      );
      expect(stores, hasLength(1));
      expect(stores.single.name, kGridStoreName);
    });

    test('a relative grid root is refused LOUD', () {
      expect(
        () => MetricsStore(name: 'x', gridRoot: 'relative/root'),
        throwsA(isA<Object>()),
      );
    });
  });
}
