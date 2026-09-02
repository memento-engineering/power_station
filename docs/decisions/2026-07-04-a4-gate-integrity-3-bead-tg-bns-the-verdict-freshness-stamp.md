---
status: accepted
date: 2026-07-04
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a4-gate-integrity-3-bead-tg-bns-the-verdict-freshness-stamp
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A4"
---
## A4 (2026-07-04) — gate-integrity #3 (bead `tg-bns`): the verdict freshness stamp is the STEP'S `nodePath` (round embedded via the rework `#rN` re-key), not a separate session-id+round field

**Decision:** the committee's stale-shadow fix (a rework round reuses the SAME workspace directory, so a prior round's `.grid/critique/<rubric>.json` survives on disk) uses the critic step's OWN `nodePath` (e.g. `tg-1#r3/review/regression-risk`) as the freshness stamp a critic embeds in its verdict JSON and `CriticCapability.result()`'s `_verdictFromFile` validates by exact match — a mismatch (including an absent stamp) is treated as "missing," falling through to the existing tg-291 envelope fallback / fail-closed default. Paired with a NEW dep-free `clear-critique` step (`ClearCritiqueCapability`) every critic lane `dependsOn`, which wipes `.grid/critique/` at the start of every round. The bead's own text asked for a stamp of "session id + round + nodePath" — I used `nodePath` alone because the rework mechanic (`SCRATCH-orchestration-determinism.md` I-5/I-6, this repo's own docs already describe it) re-keys the bead id itself to `<bead>#rN` per round, so `nodePath`'s root segment already carries session+round; inventing a second, separately-plumbed field would duplicate information already available at the effect boundary (`StepArgs.nodePath`) with zero the_grid engine changes required.
**Why:** grid_assets' capabilities only ever see `TreeContext`/`StepArgs` (no direct concept of "session id" as a value distinct from the bead id is exposed at this seam); threading a genuinely separate session-id field would require a the_grid (grid_engine) change, which is out of this bead's worktree scope. `nodePath` was already the round-safe key FT-2's telemetry path (`usageReportPath`) uses for the exact same reason, so this reuses an established, already-proven idiom rather than inventing a new one.
**Affects (if promoted):** `packages/grid_assets/lib/src/code/committee.dart` (`kClearCritiqueStep`, `ClearCritiqueCapability`, `buildCriticPrompt`'s `nodePath` param, `_verdictFromFile`'s `expectedNodePath`, the `transport` result field on every verdict path) + its test files (`track_c_critic_test.dart`, `track_c_committee_test.dart`) + the acceptance/kernel tests updated for the new circuit shape (`circuit_acceptance_test.dart`, `station_kernel_test.dart`, `pdr_s7_acceptance_test.dart`, `invariant_2_only_the_chokepoint_writes_test.dart`). An alternative (a genuine the_grid-plumbed session id) would look different and would land in the_grid, not here.
**Status:** pending.

