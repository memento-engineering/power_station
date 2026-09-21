---
status: accepted
date: 2026-09-18
decision-makers:
  - "Nico"
consulted: []
informed: []
register:
  spec: 1
  slug: the-vended-seat-roles-carry-no-compaction-watermark
  surfaces:
    - "packages/grid_assets/extension/station_overlay/claude/agents/governor.md"
    - "packages/grid_assets/extension/station_overlay/claude/agents/refiner.md"
    - "packages/grid_assets/test/assets/governor_posture_test.dart"
  obsoletes: []
  updates:
    - "the-governor-carries-a-cost-posture-ranked-under-throughput"
  obsoleted-by: null
  updated-by: []
  bead: pow-ttwr
  legacy-id: null
---

# The vended seat roles carry no compaction watermark

## Context and Problem Statement

Both vended CLAUDE-leg seat roles carried the same named watermark, **Compact
at 150k, not at the ceiling**. Only one of them had a number behind it. The
governor's copy cited the curve it was derived from — compaction floors at
57-65k across 40 measured events (p50 57,385) while the seat compacts at
400-860k and averages 347k — and
`power_station#the-governor-carries-a-cost-posture-ranked-under-throughput`
records that derivation. The refiner's copy cited nothing, and the refiner role
says so in its own words: the measurements were taken on the governor seat and
this seat has not been measured separately. The accepted entry's surfaces name
the governor role and its posture test and never name the refiner, so the
number reached the second seat by propagation rather than by a decision.

It then failed as a check. A watermark fires mid-session, and on 2026-09-18 the
refiner cited it as the reason to hand off at 246k — reading a cost check as
the clean-boundary handoff rule printed beside it. The accepted entry predicted
exactly this pressure in its own Consequences: "150k is a judgement against one
seat's measured curve, not a derived optimum; it will want re-measuring once
the seat runs under it."

## Considered Options

* **Retire the number from the refiner only.** Fixes the propagation and leaves
  the measured seat holding its measured number.
* **Retire the number from both seats.** No vended role names a compaction
  figure; the seat keeps the cost rules the number was never load-bearing for.
* **Raise the number for both seats.** Keeps a watermark as the mechanism and
  re-picks its value.

Nico ruled on 2026-09-18, through the refiner seat's interview on bead
`pow-pkme`: "If we were going to hand off at every 150k we'd be handing off all
of the time." He chose retirement from BOTH seats rather than re-measuring or
re-siting the figure, because the failure was the mechanism — a number a seat
watches mid-session and acts on — and not the particular value.

## Decision Outcome

No vended seat role names a compaction watermark, and none tells a seat to
watch a context figure for one. The governor and the refiner each lose the
watermark bullet from their `## Cost` section, and the governor loses the
trailing sentence of the preceding bullet whose only referent was that
watermark.

Everything else in the cost posture stays, on both seats: the
`## Cost — a request costs what the context costs` section itself, its explicit
rank under the work it buys (the governor's "it NEVER outranks the throughput
rules in the mandate", the refiner's "none of them is a reason to refine
less"), the measurement the governor states, and the rule the watermark was
mistaken for — hand off at a clean boundary and compact only mid-thought, when
the next step depends on detail that is written down nowhere else. Cost is
never a reason to leave work undriven.

This UPDATES the accepted entry rather than obsoleting it: exactly one clause
of it, "The watermark is 150k", is withdrawn, and the posture, its rank, its
measurement and its handoff rule remain in force.

### Confirmation

`packages/grid_assets/test/assets/governor_posture_test.dart` reads BOTH role
files. One named test asserts the surviving posture per seat — the heading, the
seat's own rank sentence, the handoff-preference marker and the clean-boundary
sentence; a second fails if either role names the retired figure anywhere in
the file, not only inside its `## Cost` section.

### Consequences

* Good, because neither seat now carries a number that one of them never
  measured, and no seat can read a cost check as an instruction to end a
  session.
* Good, because the number is fenced by a negative test across BOTH vended
  roles, so it cannot return by the propagation that carried it to the second
  seat in the first place.
* Bad, because the seats now have no written compaction trigger at all:
  compaction stays a judgement the harness does not check, and a seat carrying
  a very large context has only the clean-boundary rule to act on.
* Bad, because the regrowth curve the watermark was aimed at is unchanged — the
  governor still compacts far above its floor — so the cost this posture
  measured is recorded rather than answered.
