// A route started from a REAL `genesis_tree` `TreeContext`, so a test can
// UNMOUNT the handle the route is holding across its poll interval.
//
// WHY THIS EXISTS AND THE TWO ANALOGS IT DOES NOT REPLACE. Two fixtures in
// this suite already cover neighbouring ground, and this harness is the
// generalization of the second, not a parallel invention:
//
//  1. `grid_engine`'s `FakeTreeContext` (already the context of every other
//     route test in `respec_test.dart` and `discovery_test.dart`) carries a
//     public, settable `mounted` — "settable so a test drives the unmounted
//     throw path" — and its own `_checkMounted` throws a `StateError` on a
//     post-unmount read. It can therefore drive `!context.mounted` and even
//     distinguish the guard's `kRouteCancelled` from the read's `StateError`.
//     What it CANNOT do is prove the premise the guard rests on: that a real
//     genesis branch handle actually reports `mounted == false` once its
//     subtree is torn down, and that the handle invalidated is the one the
//     route captured at entry. Against the fake, both the tear-down and the
//     flag it is supposed to flip are the SAME assignment the test writes —
//     so a genesis_tree whose real `mounted` outlived its branch would leave
//     the fake test green and production crashing. That is why the coverage
//     this fixture answers asks for a real `TreeContext`, and it is the only
//     thing the fake is short of: everywhere a settable flag is enough, the
//     fake stays the right tool.
//  2. Mounting a real `TreeOwner` around a probe seed is ALREADY this
//     package's per-file idiom — `test/agent/availability_seed_test.dart`'s
//     `_mount()` + `_Watcher` (a `TreeOwner`, `mountRoot`, `flush`, a seed
//     that records every build-time read), and the `_Probe extends
//     StatelessSeed` that `test/agent/typed_environment_test.dart`,
//     `seat_environment_test.dart` and `seat_permission_policy_test.dart`
//     each keep privately ("runs [read] once, at build, over the mounted
//     context"). This file is that idiom hoisted into `test/support` with the
//     two things a ROUTE needs on top: the route's in-flight `Future` held
//     for the caller, and a counting provider that says whether the value was
//     read AGAIN after the unmount. It is deliberately the same shape, so a
//     reader of either file recognises the other.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';

/// Ends the harness tree (the `typed_environment_test.dart` leaf idiom).
class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const []);
}

/// The mutable read tally, owned by [MountedRouteHarness] and incremented by
/// [_CountingSiblingViewBranch]. A plain box so the seed can stay immutable.
class _Reads {
  int value = 0;
}

/// Starts a route ONCE, at build, over the mounted context — the shared
/// generalization of the per-file `_Probe` idiom.
///
/// The context is PASSED to [start] and never captured: nothing here outlives
/// the synchronous build, so the harness stores a `Future`, never a handle.
class _RouteStartSeed extends StatelessSeed {
  const _RouteStartSeed(this.start);

  /// Runs the route over the freshly mounted handle.
  final void Function(TreeContext context) start;

  @override
  Seed build(TreeContext context) {
    start(context);
    return const _Leaf();
  }
}

/// An `InheritedSeed<SiblingView>` that TALLIES every lookup of its own value
/// type.
class _CountingSiblingView extends InheritedSeed<SiblingView> {
  _CountingSiblingView({
    required super.value,
    required super.child,
    required this.reads,
  });

  /// The tally this provider increments.
  final _Reads reads;

  @override
  InheritedBranch<SiblingView> createBranch() =>
      _CountingSiblingViewBranch(this);
}

class _CountingSiblingViewBranch extends InheritedBranch<SiblingView> {
  _CountingSiblingViewBranch(_CountingSiblingView super.seed);

  @override
  U? getValueAs<U extends Object>() {
    // The provider walk asks EVERY inherited ancestor for EVERY type it is
    // resolving, so only a lookup for this provider's own value type counts.
    if (U == SiblingView) (seed as _CountingSiblingView).reads.value++;
    return super.getValueAs<U>();
  }
}

/// A route running against a real mounted tree, with the handle's lifetime in
/// the test's hands.
///
/// Retains exactly three things — the route's [future], the [TreeOwner], and
/// the [siblingViewReads] tally. Never a [TreeContext]: a stored handle is the
/// bug the route guards against, and a fixture that stashed one could not
/// honestly prove the guard.
class MountedRouteHarness {
  MountedRouteHarness._(this._owner, this._reads, this.future);

  final TreeOwner _owner;
  final _Reads _reads;

  /// The route's in-flight result — completed, or thrown, by the route itself.
  ///
  /// A route unwound by [unmount] completes with `kRouteCancelled`, so a test
  /// asserts on this with `throwsA(same(kRouteCancelled))`.
  final Future<RouteVerdict> future;

  /// How many times the ambient `SiblingView` has been resolved through this
  /// harness's provider since the mount.
  ///
  /// Snapshot it before [unmount] and compare after: an unwound route must
  /// read the value no further.
  int get siblingViewReads => _reads.value;

  /// Tears the tree down under the running route, invalidating the handle it
  /// captured at entry.
  ///
  /// Idempotent — `TreeOwner.unmountRoot` clears its own root.
  void unmount() => _owner.unmountRoot();

  /// Releases the owner. Idempotent, and safe after [unmount] (the owner
  /// unmounts a root only while one is mounted), so it is the `addTearDown`
  /// hook on every path.
  void dispose() => _owner.dispose();
}

/// The default [mountRouteHarness] ambient wrapper: no extra providers.
Seed _noAmbientValues(Seed child) => child;

/// Mounts [route] under a real [TreeOwner] with [siblings] provided above it,
/// and returns with the route already started.
///
/// SYNCHRONOUS on purpose. A `ComponentBranch` builds its subtree during
/// `mountRoot`, and an `async` route body runs to its first `await` on the
/// call — so by the time this returns, the route has read its ambient values
/// and parked on its poll interval. The caller therefore gets control with NO
/// event-loop turn in between, and an [MountedRouteHarness.unmount] on the
/// next line lands inside the route's first park rather than racing a poll
/// iteration that would move [MountedRouteHarness.siblingViewReads].
///
/// [ambient] wraps the route seed in whatever else it needs in scope (its
/// `Bead`, `Workspace`, `SessionHandle`), mounted BELOW the counted
/// `SiblingView` provider and ABOVE the route — so each caller composes its
/// own values without a second harness.
MountedRouteHarness mountRouteHarness({
  required Future<RouteVerdict> Function(TreeContext context) route,
  required SiblingView siblings,
  Seed Function(Seed child) ambient = _noAmbientValues,
}) {
  final reads = _Reads();
  final owner = TreeOwner();
  Future<RouteVerdict>? started;
  owner.mountRoot(
    _CountingSiblingView(
      value: siblings,
      reads: reads,
      child: ambient(
        _RouteStartSeed((context) {
          // LOUD: the harness holds ONE future, so a second build would leave
          // a route running that no test can see, let alone unwind. Nothing
          // subscribes here (the route reads with the effect verb, ADR-0008
          // D3), so a rebuild means the fixture has grown a dependency and
          // the shape needs rethinking — not a silently dropped route.
          if (started != null) {
            throw StateError(
              'mountRouteHarness rebuilt its route seed; the harness supports '
              'exactly one route per mount',
            );
          }
          started = route(context);
        }),
      ),
    ),
  );
  owner.flush();
  return MountedRouteHarness._(owner, reads, started!);
}
