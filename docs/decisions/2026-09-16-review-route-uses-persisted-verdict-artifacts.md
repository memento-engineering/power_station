---
status: accepted
date: 2026-09-16
decision-makers:
  - "governor (power_station)"
consulted: []
informed: []
register:
  spec: 1
  slug: review-route-uses-persisted-verdict-artifacts
  surfaces:
    - "packages/grid_assets/lib/src/code/committee.dart"
  obsoletes: []
  updates:
    - "a4-gate-integrity-3-bead-tg-bns-the-verdict-freshness-stamp"
  obsoleted-by: null
  updated-by: []
  bead: pow-bhn6
  legacy-id: null
---

# The review route decides from the lane's own persisted verdict, and a refused artifact is a HELD gate

## Context and Problem Statement

A review round graded `regression-risk` as `B`, wrote that grade to
`.grid/critique/regression-risk.json`, and seven seconds later the same round's
route escalated `a critic returned F (regression-risk) — rework`. No `F` existed
in any artifact for that round. The pattern then repeated four more times the
same day, across three substations and two different lanes, each time resolved
by hand at the gate with the grade the artifact already carried.

Two facts made it possible. First, the route sourced a lane's grade from a
channel other than the file the lane persisted, so the two could disagree and
nothing reconciled them. Second, the verdict reader's contract is that a present
artifact failing either freshness fence — the `nodePath` stamp or the round pin
— is treated as MISSING, and a missing grade normalises to the fail-closed `F`.
That fall-through is correct as a stop and wrong as a verdict: it renders an
artifact fault in the vocabulary of a critic's ruling, which is exactly the
sentence an operator cannot diagnose from. The stop must survive; the
impersonation must not.

## Decision Outcome

In a live workspace, every NON-GATING review lane's grade and rationale come
from the lane's own current-round artifact, read through the same
`_verdictFromFile` parser, the same `nodePath` and round fences, and the same
round the lane wrote with. The route and the lane hold one value because they
read one file. A present canonical artifact is the answer, accepted or refused:
the stray-path belt widens the search only when the canonical artifact is
absent, so a superseded file can never decide a lane.

A refused or absent artifact stays fail-closed and stops advancing, but renders
as a HELD gate, not as a grade. The reason names the lane, the check that failed
— shape, freshness stamp, `nodePath` mismatch, round-pin mismatch, or absence —
and the exact path, so the next disagreement between a gate and a lane's own
file is settled by reading the path the gate printed. Only a grade a critic
actually wrote routes as `a critic returned F`, and that escalation names the
artifact it was read from.

The deterministic gating lanes are unchanged: they persist no verdict JSON, so
their grades keep riding their own step results, and a missing gating grade
still fail-closes to a hard block. The offline posture is unchanged for the same
reason — with no real worktree there are no artifacts, so every lane joins off
its recorded step result. The matrix itself is untouched.

### Consequences

* Good, because a lane's grade now has exactly one source, so the false `F` that
  held five landable rounds in one day cannot recur, and any future disagreement
  is diagnosable from the gate text alone.
* Good, because the fail-closed floor is intact — nothing advances on an
  unreadable verdict; the round holds instead.
* Bad, because the live route now does filesystem I/O it previously avoided, and
  a real artifact fault surfaces as a hold that a human must clear rather than as
  a rework the circuit would have driven itself.
