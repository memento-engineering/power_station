/// The OFFLINE MOUNT of a composing station's authored tree — the ONE walker
/// every "resolve it from the resident-station context" read rides (ADR-0000
/// A11(1): the roster is authored IN the tree, so a Command mounts the
/// delegate rather than attaching to a live station).
///
/// A one-shot enumeration at the EFFECT boundary: mount, one flush, walk,
/// dispose. Never a retained tree, so no reactive state can go stale (the D-H
/// doctrine, ADR-0008 — `dependOn*` is the verb for a Seed's `build`, and this
/// is a CLI's run edge, not a build).
library;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;

/// Every ambient value of type [T] provided in [delegate]'s authored tree, in
/// TREE ORDER (a pre-order walk).
///
/// Mounts the delegate in a bare offline [TreeOwner] (the authoring-only shape:
/// no wiring, no stores armed, no effects — composition Seeds are pure at
/// build), flushes one build pass, collects every `InheritedBranch<T>`'s value,
/// and unmounts.
///
/// [configuration] is the observed value the delegate builds against
/// (config = VALUES in the tree, ADR-0008); defaults to the empty
/// configuration, matching an unarmed mount.
List<T> mountedValuesOf<T extends Object>(
  sdk.GridDelegate delegate, {
  sdk.GridConfiguration configuration = const sdk.GridConfiguration(),
}) {
  final owner = TreeOwner();
  try {
    final root = owner.mountRoot(_DelegateAuthor(delegate, configuration));
    owner.flush();
    final values = <T>[];
    void walk(Branch b) {
      if (b is InheritedBranch<T>) values.add(b.value);
      b.visitChildren(walk);
    }

    walk(root);
    return values;
  } finally {
    owner.dispose();
  }
}

/// The FIRST ambient [T] in [delegate]'s tree (tree order), or null when the
/// tree provides none — the single-value form of [mountedValuesOf]. The caller
/// decides how loud an absence is.
T? mountedValueOf<T extends Object>(
  sdk.GridDelegate delegate, {
  sdk.GridConfiguration configuration = const sdk.GridConfiguration(),
}) {
  final values = mountedValuesOf<T>(delegate, configuration: configuration);
  return values.isEmpty ? null : values.first;
}

/// Calls [sdk.GridDelegate.build] with a live [TreeContext] during mount — the
/// offline stand-in for `runGrid`'s delegate root.
class _DelegateAuthor extends StatelessSeed {
  const _DelegateAuthor(this.delegate, this.configuration);

  final sdk.GridDelegate delegate;
  final sdk.GridConfiguration configuration;

  @override
  Seed build(TreeContext context) => delegate.build(context, configuration);
}
