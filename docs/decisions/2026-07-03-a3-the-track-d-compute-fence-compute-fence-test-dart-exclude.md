---
status: accepted
date: 2026-07-03
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a3-the-track-d-compute-fence-compute-fence-test-dart-exclude
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A3"
---
## A3 (2026-07-03) — the Track D compute-fence (`compute_fence_test.dart`) excludes `federated_grid_assets`'s CLI Commands from its kind-agnostic grep

**Decision:** at AL-5b (D-A9), `grid_cli`'s `ServeCommand`/`LeaseCommand` moved into `packages/federated_grid_assets` alongside the federation bus/protocol impls (`StationServer`/`HttpStationClient`/`LeaseManager`/`Membership*`/`GitSyncService`) that used to live in the_grid's now-deleted `grid_federation`. The pre-existing structural fence test (`grid_assets/test/compute/compute_fence_test.dart`, ADR-0011 D3, "the federation core must name no compute-specific detail") previously grepped the whole of `grid_federation/lib` — safe at the time because that package held only the bus core, never a CLI adapter. `ServeCommand`/`LeaseCommand`'s doc comments illustrate their generic factory params with the compute reference app by name ("the reference app supplies the compute one") and mention `CommandResult` in prose. Rather than reword those illustrative docs to dodge the grep, the fence now excludes `serve_command.dart`/`lease_command.dart` by filename from the scanned source and still scans every other file in the package (the actual bus/protocol core the invariant is about).
**Why:** the doc comments in the moved Commands describe a CONSUMER example (an asset domain a station runner might parameterize them with), not a compile-time coupling from the bus/protocol core into the compute domain — the Commands take the dispatch handler/payload codec as constructor closures and name no compute type. Reworking working, accurate prose to satisfy a grep felt like optimizing for the test instead of the invariant; narrowing the fence's scope to the files that actually constitute "the federation core" preserves the invariant's real meaning post-merge.
**Affects (if promoted):** `packages/grid_assets/test/compute/compute_fence_test.dart` (the `isCliCommand` exclusion + its comment) — an alternative resolution (e.g. splitting the CLI Commands into a separate pack, or rewording the docs) would look different.
**Status:** pending.

