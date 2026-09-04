// The acceptance harnesses' station root, after the engine retired its kernel
// (`the_grid#run-grid-is-the-single-flush-coordinator`, accepted 2026-09-02):
// `runGrid` is the ONE flush coordinator and `StationDriver` is the off-tree
// work-axis half (the bridge lifecycle, the D-5/F1 cooldown Timer, the
// unclaimed-frontier scan). This composes the two over the SAME ambient stack
// the retired kernel mounted — same providers, same order, same
// `Station(substations)` child — so a migrated suite drives an identical tree
// and no assertion has to move.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart'
    show SubstationFactsAssets, SubstationFactsRepository;
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:grid_sdk/grid_sdk.dart'
    show GridConfiguration, GridDelegate, GridHandle, Provider, runGrid;

import 'asset_resolution_fixture.dart';

/// The ASSET half of a station root, as a live composition mounts it: the ONE
/// facts projection (`SubstationFactsAssets`) plus the substation identity a
/// capability resolves its assets under.
///
/// In production the identity comes from `sdk.Substation` and the projection
/// from the composing station; these harnesses mount the engine's own
/// `SubstationScope` directly, so they supply both explicitly rather than
/// leaving the provision wire without the facts it refuses to guess.
Seed stationAssetProjection({
  required String substation,
  required Seed child,
  SubstationFactsRepository? repository,
}) => SubstationFactsAssets(
  repository:
      repository ??
      StaticSubstationFactsRepository(liveStationFacts(substation: substation)),
  child: InheritedSeed<sdk.SubstationScope>(
    value: sdk.SubstationScope(
      name: substation,
      root: liveAssetPackageRoot(),
      prefix: substation,
    ),
    child: child,
  ),
);

/// The station tree under test: the work-axis ambient stack, as a
/// `GridDelegate`'s master build.
///
/// Impls = DI (the_grid ADR-0008 D-H): every value is built OFF-tree by
/// [MountedStation] and enters the tree only as a provided value — this
/// delegate constructs no service in `build`.
class _StationRootDelegate extends GridDelegate {
  _StationRootDelegate({
    required this.notifier,
    required this.stationServices,
    required this.resolver,
    required this.leaseVendor,
    required this.registry,
    required this.substations,
    required this.assetSubstation,
  }) : super(const GridConfiguration());

  /// The work-axis notifier the mounted `WorkList` observes.
  final JoinedSnapshotNotifier notifier;

  /// The machine's ambient services (transport + the bd write chokepoint + the
  /// owned state rig).
  final StationServices stationServices;

  /// The bead-to-work-Seed seam.
  final SessionResolver resolver;

  /// The molecule model's process-lease seam — the SAME default the retired
  /// kernel installed at its root (tg-h4u), built off-tree.
  final ProcessLeaseVendor leaseVendor;

  /// The reentrant circuit registry; null when the resolver roots a
  /// non-reentrant subtree (a fake returning a plain leaf needs none).
  final CapabilityRegistry? registry;

  /// The station's substation scopes.
  final List<SubstationScope> substations;

  /// The substation identity this station's assets resolve under.
  final String assetSubstation;

  @override
  Seed build(TreeContext context, GridConfiguration configuration) {
    final registry = this.registry;
    return Nest(
      children: [
        Provider<JoinedSnapshotNotifier>.value(notifier),
        Provider<StationServices>.value(stationServices),
        Provider<SessionResolver>.value(resolver),
        Provider<ProcessLeaseVendor>.value(leaseVendor),
        if (registry != null) Provider<CapabilityRegistry>.value(registry),
      ],
      child: stationAssetProjection(
        substation: assetSubstation,
        child: Station(substations),
      ),
    );
  }
}

/// The substation id every acceptance harness composes (`SubstationConfig`'s
/// `substationId`), and therefore the identity its assets resolve under.
const String kAcceptanceSubstation = 'tg';

/// A station mounted for a test — the `runGrid` tree half wired to the
/// [StationDriver] off-tree half exactly as production wires them
/// (`runGrid(onFlushed: driver.afterFlush)`).
///
/// Two-phase on purpose, mirroring the shape the suites already call: the
/// constructor ASSEMBLES (nothing mounts, so a test may assert the pre-mount
/// state), [start] starts the driver and mounts the tree, [dispose] tears the
/// tree down and THEN the driver — the bridge outlives the tree, never the
/// reverse.
class MountedStation {
  /// Assembles the station over [bridge]. Nothing mounts until [start].
  MountedStation({
    required this.bridge,
    required StationServices stationServices,
    required SessionResolver resolver,
    required List<SubstationScope> substations,
    CapabilityRegistry? registry,
    String assetSubstation = kAcceptanceSubstation,
  }) : _driver = StationDriver(bridge: bridge, registry: registry),
       _delegate = _StationRootDelegate(
         notifier: bridge.notifier,
         stationServices: stationServices,
         resolver: resolver,
         leaseVendor: defaultProcessLeaseVendor(stationServices),
         registry: registry,
         substations: substations,
         assetSubstation: assetSubstation,
       );

  /// The join bridge feeding the work axis — the driver owns its lifecycle.
  final StationJoinBridge bridge;

  final StationDriver _driver;
  final _StationRootDelegate _delegate;
  GridHandle? _handle;
  bool _disposed = false;

  /// Starts the driver (seeding the notifier's baseline BEFORE `WorkList`
  /// subscribes, as the kernel did), then mounts the tree through [runGrid] —
  /// the ONE flush coordinator — with `onFlushed` driving the driver's
  /// post-flush re-scans. Idempotent.
  Future<void> start() async {
    if (_handle != null || _disposed) return;
    _driver.start();
    _handle = await runGrid(_delegate, onFlushed: _driver.afterFlush);
  }

  /// Tears the tree down (unmounting every effect, so every spawn is killed)
  /// and then the driver (cancelling the backoff Timer, disposing the bridge).
  /// Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _handle?.teardown();
    _handle = null;
    _driver.dispose();
  }
}
