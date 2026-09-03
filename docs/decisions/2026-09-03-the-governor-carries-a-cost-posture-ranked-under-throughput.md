---
status: accepted
date: 2026-09-03
decision-makers:
  - "Nico"
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: the-governor-carries-a-cost-posture-ranked-under-throughput
  surfaces:
    - "packages/grid_assets/extension/station_overlay/claude/agents/governor.md"
    - "packages/grid_assets/test/assets/governor_posture_test.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-8dwh
  legacy-id: null
---

# The governor carries a cost posture, ranked under throughput

## Context and Problem Statement

The governor seat is the most expensive thing this system runs and its vended
posture document said nothing about the cost of its own behaviour. Measured
2026-09-03, transcript usage deduped by provider request id: 14,502 requests at
347k average context and $0.52 per request; the interactive seats are 67.5% of
all measured inference spend against 31.3% for the whole per-bead pipeline. Two
behaviours carry most of the controllable part — the seat batches 1.106 tool
calls per message where the same harness sustains 1.544 elsewhere, and it
compacts at 400-860k against a floor that measures 57-65k every time.

Two things the measurement does not settle forced a call. First, a WATERMARK is
a number and the bead named none. Second, a cost posture sits directly against
`power_station#adr-0004-station-throughput-outranks-staging-ceremony`, whose D1
context records that "An idle station had been treated as a safe state. It is
not; it is a failure state" — a rule that reads as "spend less" is exactly the
shape that produces one.

## Decision Outcome

The vended governor carries a `## Cost` section, and it is RANKED UNDER the
mandate's throughput rules: the section says so in its own words ("it NEVER
outranks the throughput rules in the mandate"), and a test pins that sentence.
Cost is never a reason to leave work undriven; the rules buy the same work for
less.

The watermark is 150k. It is chosen against the measured floor rather than the
window: ~2.5x the 58k floor, so a compaction buys real working room instead of
thrashing, and low enough that the average carry lands near 100k against
today's 347k. The number is a check, not a habit, which is why it is written
down and tested for.

The section amends the CLAUDE leg alone, per
`power_station#a-harness-may-carry-its-own-instructions`; nothing mirrors it
into the codex leg and no test compares them.

### Consequences

* Good, because the seat's most expensive habits now have a written posture
  with the measurement attached, so a reader can tell posture from preference
  and a later edit that drops one of the four claims fails a named test.
* Good, because the explicit rank removes the reading that would have made this
  section a licence for the idle station ADR-0004 exists to prevent.
* Bad, because 150k is a judgement against one seat's measured curve, not a
  derived optimum; it will want re-measuring once the seat runs under it.
* Bad, because the posture is prose the harness does not enforce — the test
  proves the document SAYS it, never that the seat DID it.
