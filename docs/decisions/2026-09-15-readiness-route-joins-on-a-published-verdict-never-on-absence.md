---
status: accepted
date: 2026-09-15
decision-makers:
  - "governor (power_station)"
consulted: []
informed: []
register:
  spec: 1
  slug: readiness-route-joins-on-a-published-verdict-never-on-absence
  surfaces:
    - "packages/grid_assets/lib/src/code/readiness.dart"
    - "packages/grid_assets/test/readiness_test.dart"
  obsoletes: []
  updates:
    - "a17-bead-pow-q7n-the-spec-readiness-intake-lens-is-an-in-pip"
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# The readiness route joins on a PUBLISHED verdict: absence waits or fails loudly, and only a present failing grade holds

## Context and Problem Statement

`ReadinessRouteCapability` read the readiness lane's grade off the ambient
`SiblingView` and handed it to `decideReadiness`, which treated a MISSING grade
exactly as it treated a failing one: a hold, escalated as a human gate.

That conflation is a race, not a fail-close. On 2026-09-14 twelve rounds across
`power_station`, `the_grid`, `lenny` and `lunar_station` escalated here on "no
verdict" with the `bead-readiness` lens's grade already written to
`.grid/critique/bead-readiness.json` — seconds before or after the escalation.
One instance is fully traced: the lens spawned 16:52:41Z, exited 16:53:50Z
having written its verdict atomically, and at 16:53:53Z the route escalated on
"no verdict", minted a gate, then completed and advanced the round anyway. The
gate it left behind named no finding a governor could act on; every one cost a
governor wake and a hand resolve against the lens's own on-disk grade. Two fired
within three minutes of each other on a fresh boot, making this the dominant
governor interrupt on the soak.

The constraint is that the hold arm still has to be safe. A17's ratified **Why**
paragraph is explicit: *"the fail direction is SAFE by construction (A13(7)):
`decideReadiness` fail-closes a MISSING verdict to a hold (`no-verdict`) and an
off-ladder letter to `not-ready`... a lens whose whole job is to WITHHOLD an
expensive fan-out must never let a transport miss buy a free pass to it."* The
principle is right and stays. What it got wrong is the remedy: a hold is not the
only non-advancing outcome available, and it is the one that costs a human.

## Considered Options

* **Keep A17's literal fail-close and cure the race elsewhere** — leave the
  route holding on absence and make the lane's result visible sooner. Rejected:
  the visibility latency is this station's durable store write, measured in
  seconds and not under this pack's control, so the race would remain open and
  the false gate would keep firing.
* **Hoist the bounded wait into `RouteCapability`** so every route in the pack
  joins the same way. Rejected for this change: `CodeRouteCapability` and the
  two committee routes are unaffected surfaces here, and changing their entry
  shape to fix a readiness defect widens the blast radius past the evidence.

## Decision Outcome

**`ReadinessRouteCapability` decides over THREE states of the lane's result,
never two, and absence is never a hold.**

1. **PRESENT and passing** (`A`–`C`) ⇒ `Advance`, carrying the existing
   `verdict`/`grade`/`lane`/`rule` provenance plus the verdict's own source
   (`source-state`, `source-path`, `transport`).
2. **PRESENT and failing** (`D`–`F`, or an off-ladder letter) ⇒ `Escalate`
   carrying `renderRefinementAsk` verbatim, with one appended line naming the
   source. This is the ONLY hold the ladder mints.
3. **ABSENT** ⇒ neither. `decideReadiness` returns a new `ReadinessAbsent` arm
   and the route WAITS (`lanePoll`) and re-reads. A lane already at a positive
   terminal has finished without publishing — a missing invocation, a broken
   LANE — and that throws `RouteFailure` naming the lane node path and the
   canonical verdict path. A lane still silent at `laneWaitBudget` throws too.

**This AMENDS A17's missing-verdict fail-close and KEEPS its no-free-pass
half.** Absence still never advances a bead; what changes is that it no longer
parks one at a governor gate. A17's ratified clause (7) — the hold is a
content-carrying refinement ask with no machine-actionable token — is untouched
and still governs arm 2, which is now the only arm that reaches it. A17(8)'s
`IntakeCapability` critique-dir wipe is what makes arm 3's loud failure honest:
the round starts artifact-free, so a present current-round artifact can only be
this round's.

**The join reuses the existing mechanisms; it mints none.** The bounded
mid-wave wait is `SpecRouteCapability`'s shape (`respec.dart`), reused exactly
as `DiscoveryRouteCapability` reuses it, and kept local to this route. The live
candidate is read through `currentVerdictOnDisk` — the one strict parser, the
canonical→round-fresh-stray transport, the `nodePath` fence
(`a4-gate-integrity-3-bead-tg-bns-the-verdict-freshness-stamp`) and the `round`
fence (`a34-bead-pow-uok-a15-5-alt-a-s-round-stamp-gets-a-capability`) that
`CriticCapability.result()` already reads through — so no second parser exists
and a foreign or stale verdict still cannot join. Offline, where there is no
worktree and no artifact, the lane's recorded step result remains the candidate.
The failure channel is the pack's existing `RouteFailure`; the ambient reads
stay on the effect verb, with the mounted- and cancel-checks before each
re-read (`a8-bead-tg-kx1-the-d-h-doctrine-rides-the-coding-agent-worki`).

**Classifying absence as a broken lane rather than a verdict follows
`a21-bead-pow-96y-the-discovery-circuit-a-nested-read-only-ga`(3)** — *"A
MISSING lens report is a broken LANE, not a verdict"* — now applied to the
readiness lens for the same reason it was applied to the discovery lenses.

### Consequences

* Good, because the twelve-a-day orphan readiness gate stops being minted: a
  verdict that is merely late is waited for, and the governor is woken only by
  findings it can act on.
* Good, because a lane that genuinely did not run now says so loudly, naming
  the missing invocation and the exact artifact it looked for, instead of
  presenting as a bead that failed its readiness bar.
* Bad, because the route can now occupy its node for up to `laneWaitBudget`
  (20 minutes by default) instead of deciding immediately, and a stalled lane
  surfaces as a route failure routed to supervision rather than as a gate bead
  an operator sees directly.
* Bad, because the readiness route now performs filesystem I/O it previously
  did not, so its live behaviour depends on the workspace being readable —
  mitigated by the offline posture, which is unchanged.

### Confirmation

`packages/grid_assets/test/readiness_test.dart` fences all three states over a
real `Directory.systemTemp` workspace: a late current-round verdict is waited
for and advances without a gate (asserting the route had NOT settled while the
lane was silent); a positively-terminal lane with no artifact fails naming
`ABSENT` and the missing invocation; present `A`–`C` and `D`–`F` preserve the
routing matrix with source provenance, with foreign-`nodePath` and stale-`round`
negative controls proving the shared fences; and a lane silent past an injected
budget fails naming that budget.
