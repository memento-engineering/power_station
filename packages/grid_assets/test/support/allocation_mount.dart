// The lifecycle-driven inputs pattern grid_engine 0.4.0-dev.3 requires
// (the_grid#417): an `Allocation` no longer holds a `TreeContext`, so its
// ambient values (`ServiceBundle`, `Workspace`) arrive through
// `didChangeDependencies` while it is MOUNTED under a `LifecycleProvider`, and
// the call-scoped context is handed to `startOrAdopt` instead.
//
// Driving an allocation straight off a `FakeTreeContext` would leave both
// watched values unset — the workspace containment check and the provisioning
// leg would silently stop running — so the fixtures mount first. The mount
// mirrors whatever the fake context provides, exactly as the_grid's own engine
// fixtures do (`grid_engine/test/track_c_process_allocation_test.dart`).
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

/// Mounts [allocation] under a [LifecycleProvider] carrying the ambient values
/// [treeContext] provides, then kicks it with that call-scoped context.
Future<void> mountAndStart(Allocation allocation, TreeContext treeContext) {
  final owner = TreeOwner();
  Seed child = LifecycleProvider<Allocation>.value(
    allocation,
    child: const Idle(),
  );
  if (treeContext.getInheritedSeedOfExactType<Workspace>() case final value?) {
    child = InheritedSeed<Workspace>(value: value, child: child);
  }
  if (treeContext.getInheritedSeedOfExactType<ServiceBundle>()
      case final value?) {
    child = InheritedSeed<ServiceBundle>(value: value, child: child);
  }
  owner.mountRoot(ProviderScope(child: child));
  addTearDown(owner.dispose);
  return allocation.startOrAdopt(treeContext);
}

/// The fixture-facing verb: mount, then kick.
extension AllocationMount on Allocation {
  /// Mounts this allocation and kicks it with [treeContext].
  Future<void> startMounted(TreeContext treeContext) =>
      mountAndStart(this, treeContext);
}
