---
status: accepted
date: 2026-07-20
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a27-bead-pow-sl5-the-spec-route-stops-actuating-rewind-and-s
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A27"
---
## A27 (2026-07-20) — bead `pow-sl5`: the spec route stops ACTUATING `Rewind` and starts STAMPING an invalidating `grade: 'F'`; backward motion is DERIVED from a `params['validates']` edge declared on the `route` step; the round counter moves back from the node's `rewindCount` to the ledger's `round` (reversing A15(2), restoring A14(5-counter))

**Decision:** the_grid's molecule engine (commit `37cb488`, tg-eli phase 2, per
`DESIGN-tg-pm6` §8/§11 "Decided item 7") REMOVED `Rewind`-verdict actuation:
`CapabilityHost._persistRewindReport` routes EVERY `AllocationRewound` to a supervised
failure ("backward motion is derived there (R4); this circuit must not report a rewind
decision"), pinned by the_grid `rewind_arm_test.dart`. A15's ratified actuation is
therefore NON-FUNCTIONAL against the live engine. The replacement the engine shipped is
a `DependencyType.validates` edge declared in circuit CONTENT (`molecule_schema.dart`
`kValidatesParam`), whose derivation (`live_frontier.dart`) invalidates the named target
∪ its transitive dependents ∪ the source itself whenever the SOURCE step is a positive
terminal carrying `grade == 'F'`, minting a successor incarnation bead per invalidated
node on a `supersedes` chain. Nico ratified the DIRECTION in a live session on
2026-07-20 (receipt on the bead): routes stop emitting `Rewind`; backward motion derives
from `validates` edges + structured stamps. The autonomous calls:

1. **The edge is declared on the `route` step ONLY, not on the critic/gate steps** —
   departing from the bead's own phrasing. The derivation invalidates on a SOURCE grade
   of `F`, and A15/A14(3)'s ratified matrix makes a critic `F` a HUMAN ruling and only a
   `D`/`E` WITH a rationale auto-fixable. Edges on the critics would INVERT that matrix
   — every critic `F` would silently auto-respec instead of escalating. The route is the
   sole decider and is itself inside `transitiveDependents(kSpecReviewCircuit,
   {specify})`, so it is both a legal source and a member of the demoted closure —
   exactly the "self" the retired `Rewind` named.
2. **The RESPEC arm returns `Advance` carrying `grade: 'F'`**, not a new verdict arm.
   `spec_review/route` is a sub-circuit terminal, so `_persistAdvance` short-circuits to
   `_persistComplete(payload)`: one chokepoint write of `state=complete` merged with the
   result payload. `complete` is `isPositiveTerminal`, which is precisely what the
   derivation requires of an invalidating source, so ONE call both terminalises the
   route and lands the stamp. The ADVANCE arm deliberately carries NO `grade` key, so a
   passing round invalidates nothing.
3. **The ROUND COUNTER moves back to the ledger's `round` field — reversing A15(2) and
   restoring A14(5-counter).** A15(2) chose `rewindCount` because "a `Rewind` does not
   re-mint, so the cursor SURVIVES". Under the derivation the cursor no longer carries
   the round at all: `effectiveCursor` sets `rewindCount := derivedGeneration` ONLY
   while a node is currently invalidated, and by the time the route re-runs its
   successor bead is `pending`/`running` with nothing invalidating it, and
   `projectMoleculeCursor` yields `0` (R1) — so the asset's cap would never fire.
   A15(2)'s stated benefit (closing the offline unbounded-loop hole) is preserved by a
   DIFFERENT mechanism: `derivedGeneration` reaches `kMaxReworkRounds` off the successor
   `supersedes` chain depth and the engine sets the node `gated` + surfaces
   `derivedEscalation` — graph structure, zero asset I/O, so it holds offline. The
   ledger counter additionally BOUNDS a spurious re-invalidation; the asset's cap of 2
   fires before the engine's 3.
4. **`kValidatesParam` is MIRRORED, not imported.** `grid_engine.dart` exports
   `molecule_schema.dart` `show MoleculeCircuitKeys, MoleculeStepKeys` only, so the key
   is off this pack's import surface. It is mirrored ONCE as `kValidatesParamKey` (the
   suffix keeps the name free if that export is widened) and the literal is pinned in
   test, so an engine-side rename fails LOUD here instead of silently minting no edge.
5. **A15(1)'s FOLD is retained and re-justified, not undone.** `specify` must stay a
   step of `kSpecReviewCircuit` because a `validates` edge, like the retired `Rewind`,
   may only name a SIBLING of the source's own circuit (`live_frontier.dart`
   `_validatesEdges`).
6. **A16(3)'s frozen shape-2 degradation is re-worded but UNCHANGED in behaviour; the
   frozen shapes 3 and 4 DO gain the edge** — a departure from the bead's "no frozen
   literal changes" instruction, made because the alternative is a fail-OPEN. Shape 2
   runs the pre-fold BINARY `route`, which never stamps an `F`, so it still parks —
   the same fail-SAFE call A16(3) made, now justified by the edge dangling rather than
   by an illegal `Rewind` target. Shapes 3 and 4 KEEP the three-way `spec-route` and
   their ADR-ratified docs promise "no capability degrades": without a declared edge
   their route would stamp an `F` that invalidates NOBODY and then advance a REJECTED
   spec to the build. Adding `params[kValidatesParamKey]` restores the promised
   behaviour; it moves no node path, so A16(4)'s classify-by-cursor-key-PRESENCE is
   untouched and no fifth shape is needed.
7. **Two adjacent concerns are CARVED OUT, not absorbed.** (a) `committee.dart`'s
   `roundOf` (A15(5)-alt-A's verdict round stamp) reads the same dead `rewindCount` and
   is therefore permanently 0 under this engine — writer and reader both read 0, so the
   fence degrades to a consistent-but-vacuous no-op rather than breaking, and
   `ClearCritiqueCapability` plus the successor re-key carry round freshness. It spans
   all three critic families and needs its own bead. (b) The spec-stage acceptance
   suite's flake was DIAGNOSED, not just filed: the tests waited on fake-call
   QUIESCENCE, but the mount→spawn and route→chokepoint chains emit no observable call
   until the spawn/write itself, so quiescence could declare victory a beat early and an
   assertion would read empty. Each wait now targets the observable it is about to
   assert (bounded). Measured over 40 runs: 5–8 failures before, 2 after. The residual
   sits in the gating-F/Escalate path this bead does not touch, and is filed.

**Why:** the bead is the asset-side half of a migration the engine already shipped; the
only real design freedom was WHERE the edge lives and WHAT carries the round, and both
answers are forced — the first by the ratified F-vs-D matrix, the second by the fact
that the engine no longer produces the counter A15(2) chose. Recording (3) explicitly
matters because it reverses a RATIFIED clause on the human-facing grounds A15 itself
gave; recording (6) matters because it edits frozen migration literals the bead's own
plan declared off-limits. Only Nico can promote or reject either.

**Affects (if promoted):** power_station code:
`packages/grid_assets/lib/src/code/respec.dart` (`kValidatesParamKey` NEW;
`respecRewindReason` → `respecStampReason`; `SpecRouteCapability.route` returns `Advance`
with the `grade: 'F'` stamp and reads `priorRound` off the ledger; the `Rewind` emission
is GONE), `specify.dart` (`kSpecReviewCircuit`'s `route` step gains
`params[kValidatesParamKey]`; docs), `circuit_migration.dart` (the two frozen
three-way-route shapes gain the same params entry; docs), `readiness.dart` /
`code_capabilities.dart` (DOC-ONLY). Tests: `respec_test.dart`,
`spec_committee_test.dart`, `acceptance/spec_stage_acceptance_test.dart` (un-skipped;
`_cursorField` deleted; all three waits made observable-targeted). REVERSES ratified
A15(2); RETIRES A15(3)'s `respecRewindReason` name; RE-JUSTIFIES A15(1) and A16(3), and
EXTENDS A16 to keep shapes 3/4 functional. No cursor key moves, so `classifyCodeShape`
needs no fifth shape. the_grid: NONE (the mechanism is already shipped; this bead only
consumes it). Out of scope: `discovery.dart`'s `DiscoveryRegather` (bead `pow-60g`).

**Status:** Pending.

