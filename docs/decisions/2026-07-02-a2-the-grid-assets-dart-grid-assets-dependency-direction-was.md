---
status: accepted
date: 2026-07-02
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a2-the-grid-assets-dart-grid-assets-dependency-direction-was
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A2"
---
## A2 (2026-07-02) — the grid_assets ↔ dart_grid_assets dependency direction was already settled; no change needed

**Decision:** `grid_assets` depends on `dart_grid_assets` (declared `dart_grid_assets: any` in `packages/grid_assets/pubspec.yaml` since the repo split) — that direction stands; this bead just becomes its first real consumer (`AgentCapability` now imports `package:dart_grid_assets/dart_grid_assets.dart`). No new dependency edge, no reverse edge, no ADR needed for the direction itself.
**Why:** the bead brief asked to "settle the grid_assets ↔ dart_grid_assets dependency direction explicitly" as if it were open; grepping the checked-in pubspecs showed it was already decided and simply unused (`dart_grid_assets` shipped its envelope codec + `DartLinkService` + `DartCommand` with no caller in `grid_assets` yet). Recorded here only so the (non-)decision has a paper trail, per the "any autonomous API/placement decision" instruction — it is not itself a new design choice.
**Affects (if promoted):** none — descriptive only.
**Status:** pending.

