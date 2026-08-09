---
name: asset-author
description: >
  Author and install grid assets through B-style in-tree providers. Use when
  adding a grid capability, choosing provider ownership or placement, handling
  an unavailable dependency, or deciding whether code belongs in GridDelegate.boot.
compatibility: >
  Requires Dart, the genesis_tree substrate, and the grid_engine provider APIs
  (Provider / ProviderScope / watch — re-exported through grid_sdk).
metadata:
  author: memento-engineering
---

# Asset author

New grid capability composes in the tree. Author an asset as a const seed,
place it at the narrowest scope that owns its policy, and let the tree rebuild
it when an observed dependency changes. `GridDelegate.boot` is transitional
assembly only (`the_grid/docs/STYLE.md` rule 5 — boot is an assembly ratchet);
it may assemble existing assets but is never the home for new functionality.

## The B-style shape

```dart
class ReviewAssets extends SingleChildStatelessSeed {
  const ReviewAssets({super.child, super.key});

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    final services = context.watch<ReviewServices>();
    // Derived FRESH on every rebuild — held by no owner — so it rides an
    // InheritedSeed over a VALUE type, never `Provider<T>.value` (rule 3).
    return InheritedSeed<ReviewCapability>(
      value: services == null
          ? ReviewCapability.refused(
              'review unavailable: no ReviewServices at this scope',
            )
          : ReviewCapability.live(services),
      child: child,
    );
  }
}
```

`ReviewCapability` here is a VALUE: immutable, with `==`/`hashCode` over its
derivation inputs (identity for the watched services, value equality for the
refusal message). The seed re-derives it on every rebuild — that re-derivation
is the point; it is how a later provider mount flips the posture live — and
value equality is what keeps an input-equal re-description from notifying
every dependent (`InheritedSeed.updateShouldNotify` compares the old and new
values). The landed `_DerivedBundleSeed` in space_station_assets exists for
exactly this: its `ServiceBundle` has no value equality, so the wrapper
compares the derivation inputs instead.

The rules are load-bearing:

1. Assets are const seeds. In `build`, call `context.watch<T>()` for every
   dependency. `watch<T>()` always returns `T?`, registers the dependency even
   while it is absent (the enclosing `ProviderScope`'s availability registry
   parks the miss; production roots — `StationKernel.start`, `runGrid` —
   always mount the scope), and notification is bidirectional:
   appearance, replacement, and disappearance all rebuild the watcher. The
   timing differs by transition: appearance and disappearance are
   availability-registry announcements whose delivery is DEFERRED past the
   announcing flush pass (a microtask marks the watcher, and the rebuild
   lands in the owner's next flush); a replacement — a changed `.value` or a
   re-derived
   inherited value — propagates through the ordinary inherited-update path
   (`InheritedSeed.updateShouldNotify`) and rebuilds dependents in the SAME
   flush pass. Never snapshot or `??=`-cache reactive state, and
   never publish a synchronous accessor over `StateNotifier` state. On an
   effect path, use `context.read<T>()` — the non-binding snapshot verb; it
   registers no dependency, live or pending.
2. Unavailability is a designed posture, not an exception. The null arm
   provides a value that renders a refusal into diagnostics. Never throw for a
   missing optional provider, and do not search for a throwing `of()` variant;
   none is part of this composition model. Guards are LOUD for genuine
   authoring invariants or absent entirely.
3. Ownership follows construction. `Provider<T>(create: ...)` constructs a
   tree-owned value — `create` runs exactly once per mount, in `initState`,
   and the tree disposes the value at unmount, after the subtree is fully
   down. `Provider<T>.value` exposes an owner-held, pre-built value and never
   takes ownership. A pre-built instance never passes through `create:`. And
   a value DERIVED in `build` passes through NEITHER — it is held by no
   owner, so `.value` (which ADOPTS an instance another owner holds) is wrong
   for it; project it as an `InheritedSeed` over a value-equal type, as the
   example above does. The value is positional
   (`Provider<T>.value(theValue, child: ...)`), and a
   provider's kind (create vs `.value`) is fixed for the life of a mounted
   branch — change the type or key to remount.
4. Placement is scoping. The nearest provider wins. Put station defaults above
   the seat fan-out; put a per-seat override inside that seat so it shadows the
   default only for that subtree. Configuration is VALUES in the tree;
   implementations enter through dependency injection.
5. No provider is universal. A station is not only code, git is not the only
   source-control system, and an asset is never entitled to `GitServices` —
   the landed seat stack SPLIT that bundle, watching `StationGitService` and
   `GitOps` individually. Watch the faculty actually needed, accept null, and
   make the unavailable arm visible in diagnostics.

## The landed exemplar: SubstationSeat

Per-seat composition is landed, not aspirational: space_station's
`SubstationSeat` (space-47t) is the worked example of every rule above. It is
ONE value-configured seat class (`name` / `root` / `prefix` /
`GitHubAppConfig?`), and a seat's delivery posture is what its OWN subtree
mounts:

- a null `app` mounts NO `PrOpener` provider at all — the commit-only posture
  is that ABSENCE, structural in the tree, never a null-valued provider
  (rule 2);
- effect creation is gated on a watched `GitOps`: a dry arm authors no
  `GitOps`, so the seat constructs no opener object either — inertness is
  declared by absence and visible in the projection (rules 1 and 5);
- the opener is constructed in-tree via `create:` (tree-owned — rule 3),
  while the seat's own config value rides `Provider<GitHubAppConfig>.value`
  (adopted — there is nothing to own or dispose);
- the seat-scoped opener shadows any station-level one — the per-seat
  override of rule 4, resolved by tree position, never by a name keyed into
  a registry.

## Installation checklist

- Compose the new const seed in the station or seat asset list at its intended
  scope.
- Use `create:` only when the tree constructs and owns the value; use `.value`
  for injected or otherwise owner-held instances; mount a `build`-derived
  value as an `InheritedSeed` over a value-equal type.
- Exercise dependency absent, present, replaced, and removed states.
- Exercise a seat-local provider shadowing a station default.
- Keep effects out of `build`; the seed projects values and implementations for
  effect-boundary consumers.
- Leave `GridDelegate.boot` as assembly-only transitional code. Move policy and
  every new capability into the in-tree asset.
