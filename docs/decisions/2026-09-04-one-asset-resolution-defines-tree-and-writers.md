---
status: accepted
date: 2026-09-04
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: one-asset-resolution-defines-tree-and-writers
  surfaces:
    - "packages/grid_assets/**"
    - "packages/github_grid_assets/**"
  obsoletes: []
  updates:
    - a24-bead-pow-a74-the-operator-install-leg-discovers-its-over
  obsoleted-by: null
  updated-by: []
  bead: pow-4peu
  legacy-id: null
---

# One asset resolution defines tree availability and both writers

## Context and Problem Statement

The station registry describes potential assets, but overlay discovery made
checkout installation, worktree provision, landing restoration, and mounted
substation availability answer selection through different mechanisms.

## Decision Outcome

One pure `resolveGridAssets` evaluation over the station-generated
`GridAssetRegistry`, an immutable `SubstationFactsSnapshot`, render values,
and an optional validated roster override is authoritative. It returns the
original selected `GridAssetDefinition` values and the exact Claude/agents
artifact source and target paths. Registry membership is potential
availability; a definition is actually available exactly when that same Seed
is mounted in the selected substation assets list.

A repository observes configured substation roots outside build and emits
immutable snapshots. A stateful asset projects those snapshots through
`InheritedModelSeed<SubstationFactsSnapshot, SubstationKey>`; each substation
build watches one constructor-stable key and performs no I/O.

`assets install`, worktree provision through `OverlayMaterializer`, and the
landing pre-rebase guard consume the same resolved artifacts. Writers do not
enumerate an overlay source. This updates A24(1): runtime
`extension_discovery` is retired from installation. A24's explicit command,
offline posture, no-commit rule, and audience deny-list remain. A26's
worktree scope, provenance, synchronous core, and non-destructive behavior
remain.

Check mode reports `IN SYNC`, `DRIFTED`, `HAND-EDITED`, `MISSING`, or
`STALE`, writes nothing, and succeeds only when all paths are `IN SYNC`.
Hand-edited and stale paths are reported and never repaired or deleted.

### Consequences

* Good, because mounted availability and both materialized views cannot
  select different asset sets.
* Good, because selector evaluation remains pure and root observation stays
  outside build.
* Bad, because a selected artifact whose source package root is absent from
  facts now refuses loudly instead of disappearing from a source walk.
* Bad, because a composing station must now mount `SubstationFactsAssets` and
  hand its generated registry to `SubstationSeed`; a station that does not
  refuses loudly rather than mounting an empty asset set.
