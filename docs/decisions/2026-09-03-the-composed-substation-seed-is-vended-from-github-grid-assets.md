---
status: accepted
date: 2026-09-03
decision-makers:
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: the-composed-substation-seed-is-vended-from-github-grid-assets
  surfaces:
    - "packages/github_grid_assets/lib/src/assets/substation_seed.dart"
    - "packages/github_grid_assets/lib/github_grid_assets.dart"
    - "packages/grid_assets/lib/src/agent/seat_environments.dart"
    - "packages/github_grid_assets/test/assets/substation_seed_test.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-lb0
  legacy-id: null
---

# The composed substation seed is vended from github_grid_assets; the arming mechanism from grid_assets

## Context and Problem Statement

Every element of a GitHub-delivering seat was already published from
power_station or the_grid except the COMPOSITION that wires them into one seat,
which lived only in a composing station's own package — one that is
`publish_to: none` and absent from pub.dev. A second, independent station had to
fork that seat or hand-write the stack. Two placements had to be settled: where
the composed seed lands, and where the three arming types it depends on land.

## Decision Outcome

The composed seed lands in `github_grid_assets`
(`lib/src/assets/substation_seed.dart`). It is not a preference: the seed mounts
five github_grid_assets types, `packages/github_grid_assets/pubspec.yaml` already
declares `grid_assets`, and placing the seed in `grid_assets` would need the
reverse edge — a cycle pub cannot resolve. A new station-composition pack was
rejected on cost: its dependency set would be a subset of github_grid_assets' and
its whole content is GitHub-coupled.

The arming MECHANISM — `AgentArming`, `TypedEnvironmentProvider`,
`SeatEnvironments` — is appended to
`packages/grid_assets/lib/src/agent/seat_environments.dart`, the library that
already owns the seat VOCABULARY those three wrap and is already exported. It
touches nothing GitHub. A station's own named environments and ladders are that
station's POSTURE and stay in that station's package: mechanism is vended,
posture is not.

The vended `AgentArming` is the POST-role-retirement shape — four typed seat
fields and no role rung. ADR-0006 D5 and bead `pow-n6n.4` retired the role axis;
this vend carries the surviving one and revives nothing. The prose in the vended
library states that shape WITHOUT naming the retired symbols, because
`test/agent/model_ladder_test.dart` fences them out of lib source including doc
comments.

The seat's delivery identity is vended as a NEW value, `SubstationAppIdentity`,
rather than moved under its origin package's name: `github_grid_assets` already
owns a differently-shaped `GitHubAppConfig` (`lib/src/credentials.dart`), which is
left untouched. `SubstationAppIdentity.installationId` is an `int`, which deletes
the two `int.parse` calls the seat did at mount and moves the parse failure to
authoring time. No `@Deprecated` compatibility typedefs are carried: they were
the origin package's own rename shims and a fresh vend has no legacy consumers.

## Consequences

- A downstream station composes a seat from `the_grid` + `power_station` alone.
  `packages/github_grid_assets/test/assets/substation_seed_test.dart` is the
  proof: its import set names only the framework and this repo's packs, so the
  file compiling IS the claim.
- The composing station adopting the vended seed — raising its
  `github_grid_assets` floor, deleting its local copies, re-pointing its delegate
  — is a SEPARATE bead in that repo, filed after this lands and publishes. This
  bead edits no file outside power_station.
- `grid_assets` goes to `0.6.0-rc.9` and `github_grid_assets` to `0.1.0-rc.9`;
  rc.8 of both is already live on pub.dev. Publishing is not part of this change.
