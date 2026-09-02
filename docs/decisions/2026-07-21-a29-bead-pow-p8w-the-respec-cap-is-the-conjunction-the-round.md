---
status: accepted
date: 2026-07-21
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a29-bead-pow-p8w-the-respec-cap-is-the-conjunction-the-round
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A29"
---
## A29 (2026-07-21) — bead `pow-p8w`: the respec CAP is the conjunction "the rounds are spent AND the CURRENT join still fails"; the cap flare quotes the FRESH grade vector; and EVERY escalate arm SPENDS the guidance ledger, so a human ruling RESETS the auto-respec counter

**Decision:** live on 2026-07-21 (lenny-iav round 1, gate `houston-k42v`) a spec that ran
its two auto-respec rounds and CONVERGED (final on-disk critique A/A/A/A, `adr-alignment`
included) was flared to a human anyway — `respec-cap: 2 auto-respec round(s) already ran
(cap 2) and the spec still fails (adr-alignment=D)` — and then RE-flared within seconds of
every governor resolve, because the ledger it counts off outlived the flare. The only exit
was a rework re-key that WIPED the converged spec. The autonomous calls:

1. **The cap arm becomes the FALL-THROUGH of the respec arm.** `decideSpecRoute`'s arms 5
   and 6 swap: `priorRound < maxRounds` now guards the `SpecRespec`, and the `respec-cap`
   `SpecEscalate` is what a still-fixable join falls through to. The ordering was already
   behaviourally correct (arm 3 advances an empty fixable set before the cap is read), but
   the conjunction lived in the arm ORDER rather than in an expression, so the flare could
   be read — and on the live gate WAS read — as "consumed rounds alone condemn the spec".
   It is now the shape `decideDiscovery`'s regather arm already uses (`missing.isNotEmpty
   && priorRound < maxRounds`), and a converged join is STRUCTURALLY unable to reach the
   flare.
2. **The flare quotes the FRESH grade vector, from the SAME `lanes` binding the matrix
   decided on.** `gradesCsv` is hoisted to one binding at the top of the matrix; both the
   advance provenance and the cap reason read it, and the reason now names the whole
   current join rather than only the fixable subset, so a human reading the parked gate
   can check the cited grade against the critique on disk. The ledger's recorded lanes are
   NOT a candidate source — that is exactly the "separate stale channel" this bead closes.
3. **EVERY `SpecEscalate` arm SPENDS the ledger** — not just `respec-cap`, and no longer
   only `SpecAdvance`. This is the load-bearing behaviour change and it REFINES ratified
   A14(6) ("Auto-respec is BOUNDED at `kMaxRespecRounds` = 2 … the cap flares to a
   human"): the cap still flares at 2, but the flare SPENDS the counter instead of leaving
   it armed. Leaving it armed is what made the flare deterministic — D-7's gate-resolve
   re-arms the parked node back to `pending` (the transition A16(4) names), the re-armed
   route re-read the same consumed `round`, and it re-gated in seconds regardless of the
   current grades (observed: a re-gate 20s after a ruled resolve, plus the mint-dedup
   duplicate pair `houston-yzkc`/`houston-dfml`). With the counter spent, the human's
   ruling is the reset: the re-armed route decides on the CURRENT join alone — a converged
   join advances, a still-failing one gets one more BOUNDED wave. The loop stays bounded on
   both belts: two auto rounds per human ruling, under A27(3)'s engine-derived
   `kMaxReworkRounds` generation cap off the `supersedes` chain depth, which is graph
   structure and needs no asset I/O. It also closes a second, independent hole
   `clearRespecLedger`'s own doc already named ("so a LATER rework round can never
   re-inject a stale spec correction into a fresh specify brief"): an escalate PARKS a
   gate, and a governor's `grid rework` off that gate IS a later rework round — before this
   bead the spent ledger survived it and re-injected a "RESPEC round 2 of 2" correction
   into a fresh brief.
4. **`DiscoveryRouteCapability`'s `DiscoveryHold` arm is left ALONE.** It has the same
   shape (an `Escalate` that does not clear its regather ledger) but not the same defect: a
   hold is a bead-REFINEMENT ask raised before any regather round is consumed, and its
   ledger counts lane ABSENCE rather than a grade loop. Carving it here would be an
   unrequested behaviour change to a circuit this bead never observed failing.

**Why:** the bead names the fix shape ("the cap check must be (ledger.round >= cap) AND
(the CURRENT join actually fails) … and the flare must key off the same fresh verdict
source the respec decision itself uses"). (1) and (2) implement it literally and make it
unreadable-as-anything-else. (3) is the call the bead's SECOND defect forces and the only
one that changes behaviour; it is recorded because it refines the meaning of a RATIFIED
clause — the cap bounds the AUTOMATIC loop, and is not a permanent condemnation that
outlives the human ruling it raised.

**Affects (if promoted):** power_station code:
`packages/grid_assets/lib/src/code/respec.dart` (`decideSpecRoute` arms 5/6 swap + the
hoisted `gradesCsv` + the cap reason; `SpecRouteCapability.route`'s `SpecEscalate` arm
clears the ledger; the matrix, `clearRespecLedger` and class docs). Tests:
`packages/grid_assets/test/respec_test.dart` (five new cases; every pre-existing cap proof
unchanged). NO public symbol is added, renamed or removed. REFINES ratified A14(6);
consumes pending A27(3)'s ledger counter unchanged. the_grid: none. Out of scope:
`discovery.dart`'s `DiscoveryHold` arm, per (4).

**Status:** Pending.

