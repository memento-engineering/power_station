---
status: accepted
date: 2026-08-12
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: adr-0004-station-throughput-outranks-staging-ceremony
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "ADR-0004"
---
# ADR-0004 — Station throughput outranks staging ceremony

**Status:** **Accepted — ratified by Nico, 2026-08-12** (directive, given verbatim during a live
governor session). Supersedes the deferral-as-staging clauses accumulated in the AI register:
ADR-0000 A30's retained clause and A11(6)/A12(6)'s `--defer <~1 week>` filing idiom, **as a staging
mechanism only** — see D1.

## Context

An idle station had been treated as a safe state. It is not; it is a failure state, and three
ceremonies were reliably producing it.

Measured on lunar, 2026-08-11:

* **214 deferred beads. 76 behind a defer date that had already elapsed. 14 of those P1.** The dates
  lapsed with no status change, so the work became invisible rather than pending.
* Two concrete losses: `tg-zc6x` (state-store hygiene) sat behind a date that expired 2026-08-02
  while the state store grew from 6.6GB to 18GB; the `pow-b1l` epic sat deferred while every child
  had already landed and its final child's PR was merged but never closed.
* The station spent ~11 hours idle on one occasion and ~20 on another while reporting `mode: LIVE`
  with a responding control door. Every blocker in those windows was a ceremony question, not a
  technical one — a rework cap that mis-charged readiness holds, a dead adjudication verb, and
  beads parked behind lapsed dates.

Nico, 2026-08-11: *"I'm not going to fucking 'yes, --beyond-cap' all the time."*
Nico, 2026-08-12: *"we also need to stop gating on ready p0s and p1 that halt the station… it's more
important to get the station working even if we make a decisions outside the ADR."*

## Decision

### D1 — Deferral is not the pending mechanism.

A date is a TIMER, not a decision: it cannot say why, and it fires whether or not anyone approved.
Work is filed OPEN with the fields that make it driveable, or the reason it is not ready is stated
plainly. Readiness is a property of the bead's FIELDS — which is what the mount-eligibility
predicate (`pow-50l` + the_grid `tg-8900`) exists to compute.

**Scope, stated precisely because two different uses share one flag.** This retires deferral as a
PENDING/QUEUEING mechanism — the "park it until someone gets to it" idiom that produced the 76
lapsed dates. It does **not** retire the ATOMIC CREATE-THEN-WIRE GUARD in `discover` /
`intake-refinement`, where `--defer` closes a seconds-wide mount race while dependencies are wired
against a live station. That guard is load-bearing until an enforcement path exists; removing it
early reopens the race with nothing in its place, and an attempt to do exactly that was caught and
graded F on 2026-08-11. The guard retires when `space-05g` mounts the predicate and updates both
skills in the same change. Until then, a bead created under the guard is opened in the same
operator turn once its dependencies are wired, and is never left sitting on a date.

### D2 — A ready P0 or P1 never waits on a human when the station is halted.

If the board has no live work and a driveable P0/P1 is ready, the governor drives it. Approval
ceremony must never be the reason a station sits idle.

The human gates that remain are the ones with OUTWARD or IRREVERSIBLE effect: merging into a
substation's main, the first live arm of a new composition, persistence and credential changes,
anything outward-facing beyond a branch push and PR. Letting approved-in-substance work START is
not one of them.

### D3 — An ADR departure is recorded, not blocking.

Aligning with the decision record stays the default and the first move: read it, cite it, comply.
But when compliance would halt the station and the correct action lies outside a ratified decision,
the governor TAKES the action, records it as an ADR-0000 amendment naming the clause departed from
and why, and moves on.

ADR-0000 A21(2) still governs HOW a clause is cited — quote it from the file actually read; pending
amendments bind. What changes is that an unresolved conflict is no longer a stop.

### D4 — `ready > 0` with `mounted 0` is an incident.

A station reporting ready work and zero mounted sessions is not a quiet board. It is diagnosed with
the same urgency as a red one. This is the signal whose absence cost 11 hours on 2026-08-12, when a
reconciler retry loop starved the mint while `/status` answered 200 and reported `mode: LIVE`.

## Consequences

* The governor's instructions (`grid_assets/extension/station_overlay/claude/agents/governor.md`)
  drop "Approving deferred intake" from the human-gate list and lead the mandate with D1–D4.
* `discover` and `intake-refinement` still teach `--defer` staging and must stop once the
  enforcement path exists — tracked by `pow-50l` (the supplying half) and `space-05g` (the wiring
  plus the skill updates), deliberately ordered so the skills never tell an operator to drop
  `--defer` before the approval marker is enforced.
* AI decisions continue to land in ADR-0000 pending Nico's promotion. **Nico's own directives are
  ratified on arrival and belong in a numbered ADR — never in the AI register.** This ADR exists
  because that rule was violated when the directive was first recorded as an A31 amendment.

## What this does NOT decide

* The mechanism of the approval marker itself (label vs metadata key vs field) — that is `pow-50l`'s
  to settle.
* Migration for beads currently parked by date. They stay parked until touched; nothing sweeps them
  automatically.
* Whether the rework cap's value should change. It should not — the cap was mis-CHARGING readiness
  holds, which is a separate defect and was fixed by the_grid `tg-04tj`.
