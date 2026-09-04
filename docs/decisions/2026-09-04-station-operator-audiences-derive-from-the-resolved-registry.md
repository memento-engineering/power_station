---
status: accepted
date: 2026-09-04
decision-makers: ["Nico Spencer"]
consulted: []
informed: []
register:
  spec: 1
  slug: station-operator-audiences-derive-from-the-resolved-registry
  surfaces:
    - "packages/grid_assets/lib/src/assets/vended_assets.dart"
    - "packages/grid_assets/lib/src/code/code_capabilities.dart"
  obsoletes: []
  updates:
    - a24-bead-pow-a74-the-operator-install-leg-discovers-its-over
    - the-grid-block-is-the-single-asset-authority
    - one-asset-resolution-defines-tree-and-writers
  obsoleted-by: null
  updated-by: []
  bead: pow-vtts
  legacy-id: null
---

# Station operator audiences derive from the resolved registry

## Context and Problem Statement

The package-local `GridAssetsPack.assets` can describe only grid_assets. A
composing station's generated `GridAssetRegistry` already contains every pack
from its resolved Dart package closure, but `AgentCapability` filtered the
build brief with only grid_assets's operator declarations. A downstream pack's
declared `audience: human` was therefore installed into the worktree and still
offered in the build brief, contrary to A24's deny-list rule.

## Decision Outcome

`vendedSkillIds` remains the sorted package-local index over
`GridAssetsPack.assets` because it serves grid_assets's own by-id render and
structural surfaces. `operatorSkillIds(GridAssetRegistry registry)` instead
returns the sorted ids of every `AssetKind.skill` in `registry.assets` whose
declared audience is `AssetAudience.human`.

`AgentCapability` passes the same station-generated registry that it already
passes to `resolveGridAssets` and `OverlayMaterializer`. The materializer's
installed-id report still decides which skills can be offered; the registry
projection is only the deny-list applied to those installed ids. No package
graph scan, YAML parse, filesystem discovery, selector evaluation, or parallel
registry is added at runtime.

This updates the package-local mechanism recorded by
`power_station#the-grid-block-is-the-single-asset-authority` while preserving
its single-authored-`grid:` rule. It implements
`power_station#a24-bead-pow-a74-the-operator-install-leg-discovers-its-over`
for every pack in the station closure and composes the registry and resolution
established by `power_station#station-registries-use-resolved-package-closures`
and `power_station#one-asset-resolution-defines-tree-and-writers`.

### Consequences

* Good, because every downstream `audience: human` declaration withholds its
  installed skill from a build brief.
* Good, because an undeclared downstream skill remains offerable; the guard
  stays a deny-list rather than becoming an allow-list.
* Good, because `vendedSkillIds` and grid_assets's own operator set remain
  byte-for-byte stable.
* Bad, because callers of the former zero-argument `operatorSkillIds` getter
  must now pass their station registry. All in-repository callers migrate in
  this change.
