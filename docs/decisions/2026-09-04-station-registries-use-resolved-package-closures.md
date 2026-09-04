---
status: accepted
date: 2026-09-04
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: station-registries-use-resolved-package-closures
  surfaces:
    - "packages/grid_assets/lib/src/assets/station_asset_registry_generator.dart"
    - "packages/grid_assets/lib/station_asset_registry.dart"
    - "packages/grid_assets/tool/generate_station_asset_registry.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-ph58
  legacy-id: null
---

# Station registries use resolved package closures

## Context and Problem Statement

A station must compose every asset pack in its resolved Dart graph, including
transitive packages and workspace members omitted from the lockfile, without
performing graph discovery or YAML parsing after startup. The package-level
`grid:` authority and neutral definition types already exist; the remaining
choice is where closure discovery and validation occur.

## Decision Outcome

Generation enumerates the station's explicit
`.dart_tool/package_config.json`. A package participates exactly when its
pubspec contains a top-level `grid:` key, and the generated registrant
references that package's public `GridAssetsPack.definition`. The lockfile is
a staleness oracle rather than an enumeration source: every lock entry must
exist in package config, while package-config-only workspace members remain in
scope.

The checked-in registrant contains deterministic aliased imports and one
`static final GridAssetRegistry`. It is built through the neutral SDK's
validating factory, not declared `const`, so duplicate identity refuses before
the value is exposed. Runtime consumers receive this value by construction and
perform no graph scan, pubspec parse, YAML parse, reflection, service lookup,
selector evaluation, or root probe.

### Consequences

* Good, because offline CLI and resident composition consume the same complete,
  diffable registry with no bootstrap service.
* Good, because transitive and workspace asset packs cannot disappear merely
  because the lockfile omits workspace membership or the station pubspec names
  only a direct dependency.
* Bad, because dependency changes require regeneration and a checked-in Dart
  diff.
