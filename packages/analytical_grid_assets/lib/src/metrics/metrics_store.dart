/// The ANALYTICAL domain's STORE SET — the grid state stores a station metrics
/// report rolls up over, resolved from the resident-station context at run
/// time and NEVER hardcoded (the `search` command's ratified posture, A11).
library;

import 'package:grid_assets/grid_assets.dart' show mountedRosterOf;
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;

/// The name the composing grid's own state store reports under.
const String kGridStoreName = '(grid)';

/// One named grid STATE store a report reads.
///
/// Session and step beads are written to the grid's own state store
/// (`<gridRoot>/.grid/.beads/`) so the work source stays pristine (the_grid
/// A37) — a metrics store is therefore a grid root, not a substation work
/// root.
class MetricsStore {
  /// Names the state store of the grid rooted at [gridRoot] (absolute; a
  /// relative root is refused LOUD by `GridStateStore.forGridRoot`).
  MetricsStore({required this.name, required String gridRoot})
    : store = sdk.GridStateStore.forGridRoot(gridRoot);

  /// The roster name of the station this store belongs to.
  final String name;

  /// The located state store.
  final sdk.GridStateStore store;

  /// The directory a `bd` read runs in — `<gridRoot>/.grid/`.
  String get runtimeDir => store.runtimeDir;

  /// The beads dir whose absence makes this store ABSENT.
  String get beadsDir => store.beadsDir;

  @override
  String toString() => 'MetricsStore($name, ${store.gridRoot})';
}

/// Resolves the station's metrics STORE SET: the composing grid's own state
/// store first, then one per mounted roster seat in roster order,
/// de-duplicated by canonical grid root (the dual-role repo whose seat root IS
/// the grid home is read once).
///
/// The set is an INPUT to `StationMetricsService.report`; this function is
/// only the default resolution the Command uses.
List<MetricsStore> stationMetricsStores({
  required String gridHome,
  required List<sdk.SubstationScope> roster,
}) {
  final seen = <String>{};
  final stores = <MetricsStore>[];
  void add(String name, String gridRoot) {
    if (!seen.add(p.canonicalize(gridRoot))) return;
    stores.add(MetricsStore(name: name, gridRoot: gridRoot));
  }

  add(kGridStoreName, gridHome);
  for (final scope in roster) {
    add(scope.name, scope.root);
  }
  return List<MetricsStore>.unmodifiable(stores);
}

/// Resolves the store set from the composing station's [delegate] — ONE
/// offline mount of its authored tree, reusing `mountedRosterOf` from
/// `package:grid_assets` rather than re-deriving roster resolution here.
List<MetricsStore> stationMetricsStoresOf(
  sdk.GridDelegate delegate, {
  required String gridHome,
}) =>
    stationMetricsStores(gridHome: gridHome, roster: mountedRosterOf(delegate));
