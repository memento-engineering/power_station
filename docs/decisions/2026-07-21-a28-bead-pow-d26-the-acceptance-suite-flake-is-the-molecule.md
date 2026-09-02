---
status: accepted
date: 2026-07-21
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a28-bead-pow-d26-the-acceptance-suite-flake-is-the-molecule
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A28"
---
## A28 (2026-07-21) — bead `pow-d26`: the acceptance-suite flake is the molecule pour's REAL filesystem hop BELOW the fake `BdRunner` seam, not the_grid `f2b79bf`; the shared `settle` primitive gains a real wall-clock slice per unsatisfied round

**Decision:** the ~25%-per-run wedge in `station_kernel_test.dart` ("specify spawned" reads 0 spawns) and `acceptance/circuit_acceptance_test.dart:753` ("a gating-F parks the route (state=gated)") is root-caused, and the fix is homed HERE (power_station's test harness), not upstream. Instrumenting the failing assertion to dump the fake bd runner's call log showed it frozen at exactly `[create --json, update <sid>, export --all]` on every captured failure — the session mint, the `grid.session.model` stamp, and the mint-dedup export probe — with the next hop, the molecule POUR, never reaching the runner at all. That hop is `BdCliService.applyGraph` (beads_dart `lib/src/services/bd_cli_service.dart:288-307`), which writes the graph-apply plan to a REAL temp file (`Directory.systemTemp.createTemp` → `File.writeAsString` → `Directory.delete`) AROUND the injected `BdRunner` call. Those `dart:io` round trips sit ABOVE the runner seam, so a fake runner does not make the pour offline: every molecule mint in this pack's offline suites crosses the filesystem. `settle` (`packages/grid_assets/test/support/asset_fakes.dart`) waited by pumping the event queue only, and `pumpEventQueue` advances event-loop turns while granting microseconds of wall clock — it cannot wait out an OS completion, and to a plateau-based fixed-point wrapper an in-flight filesystem call is indistinguishable from quiescence. That is why raising `maxPumps` 20→1000 and `stableRounds` 50→250 never moved the rate. `settle` now sleeps a real `ioSlice` (default 1ms) per UNSATISFIED round and evaluates its condition exactly once per round; `test/settle_test.dart` pins that contract so a revert to a pump-only wait fails LOUD there rather than reappearing as an acceptance flake.

**The `f2b79bf` suspicion is CLEARED, not merely unconfirmed:** the wedge lands before any process is spawned (the failing `station_kernel` assertion is that the FIRST spawn never happened), so the held-terminal latch-before-emit rework cannot be on the path. No the_grid change is required by this diagnosis.

**Why:** real filesystem IO in a production write path is legitimate; what was wrong is the harness's model of what a WAIT is. Fixing the shared primitive every suite already routes through is one edit for four suites, and it EXTENDS rather than reverses A27(7)(b)'s observable-targeted waits — the targets stay, and the wait underneath them can now actually reach them. The three identical private `_settle` fixed-point wrappers (`acceptance/circuit_acceptance_test.dart`, `acceptance/discovery_acceptance_test.dart`, `acceptance/spec_stage_acceptance_test.dart`) are deliberately NOT deduped here: they are unchanged by this fix and hoisting them is an unrelated refactor that would widen a station-health diff.

**Measured** at power_station `697f0d3` + the_grid `709dc93`, `-j1`, both named files: 5/15 failing before (and 4/15, 4/25 in the prior spec run); 0/40 after. The full `grid_assets` offline suite passes and `dart analyze` is clean.

**Affects (if promoted):** `packages/grid_assets/test/support/asset_fakes.dart` (`settle`), `packages/grid_assets/test/settle_test.dart` (new). Closes the residual A27(7)(b) filed ("the residual sits in the gating-F/Escalate path this bead does not touch, and is filed").
**Status:** pending.

