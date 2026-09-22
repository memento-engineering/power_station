---
status: accepted
date: 2026-09-22
decision-makers: ["Nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: filing-rows-separate-checker-incompleteness-from-bead-failure
  surfaces:
    - "packages/grid_assets/lib/src/filing/filing_contract.dart"
    - "packages/grid_assets/lib/src/filing/filing_command.dart"
    - "packages/grid_assets/lib/src/filing/approve_command.dart"
    - "packages/grid_assets/lib/src/filing/park_command.dart"
    - "packages/grid_assets/lib/src/filing/mount_explanation.dart"
    - "packages/grid_assets/lib/grid_assets.dart"
    - "packages/grid_assets/test/filing/filing_contract_test.dart"
    - "packages/grid_assets/test/filing/filing_viability_test.dart"
    - "packages/grid_assets/CHANGELOG.md"
    - "packages/github_grid_assets/lib/src/intake/github_intake_store.dart"
    - "docs/decisions/2026-09-22-filing-rows-separate-checker-incompleteness-from-bead-failure.md"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-zqo1
  legacy-id: null
---

# A filing row separates checker incompleteness from bead failure

## Context and Problem Statement

Over one window on the lunar resident, every bead the filing preflight checked
came back the same way: `validation_plan_syntax` refusing, with

> no sh parse of the validation_plan was gathered; the plan checked is
> "&lt;plan&gt;" — restore complete evidence and rerun

It held across three consecutive reruns minutes apart, across two beads in two
different stores with different plan shapes, and across a bead that had passed
every row earlier the same day and had not been edited since. `/bin/sh` was
installed and parsed those exact strings. Later, with no bead edit and no code
change, the same checks passed six times running.

Because the approve verb re-runs the preflight before stamping, a row in that
state stops every approval on the station. It is intermittent and self-clearing,
which is worse than a hard break: a refiner sees a well-formed bead reported
not-approvable and cannot tell that from a real filing defect.

The row's shipped text was byte-identical across the releases involved, so the
release was never the variable. The defect is that ONE row conflates two
different statements:

* **"I evaluated this and it is bad."** A statement about the BEAD. Failing the
  verdict closed is right.
* **"I could not evaluate this."** A statement about the CHECKER. Failing the
  verdict closed converts a checker problem into a not-approvable verdict no
  caller can distinguish from a filing defect.

There is no graceful-degradation sibling to point at. `validation_plan_-`
`portability` reports `passed` with *"not probed — the validation_plan_syntax
row is answered first and carries this plan"* ONLY as a deliberate SHORT-CIRCUIT
on syntax's unparsed state. Its own gather-failure branch, a few lines below,
failed closed identically — a LATENT TWIN of the same defect, reachable whenever
syntax parses and portability's gather fails. Both are in scope here.

The package already models a NEARBY distinction deliberately: a portability
shell that is NOT INSTALLED is its own named refusal. An un-gathered parse from
an INSTALLED shell is a different condition and had no name.

## Considered Options

* **(A) Grow the row's verdict to a third state.** `FilingRequirementRow`'s
  boolean `passed` becomes a `FilingRequirementStatus` with a
  could-not-evaluate value, and the overall verdict decides separately how to
  treat it. Breaking for every consumer that reads a filing report.
* **(B) Keep `passed` binary and carry the distinction only in the detail
  text.** Non-breaking. Rejected: a caller deciding anything would have to
  pattern-match prose, and the one caller that matters — the approve verb —
  would keep refusing a bead nothing found fault with, under a label that says
  the bead is at fault.

Nico ruled on 2026-09-22, verbatim: **"tri-state"**. Arm (A). The ruling was
made after the pre-stamp advisory's bead-readiness lens correctly refused an
earlier draft of the work for deferring exactly this decision to whoever
implemented it.

## Decision Outcome

A requirement row reports `could_not_evaluate` only when its checker produced no
answer; report-level approval remains false, while row status and the report
flag keep checker incompleteness distinct from a filing defect.

### The shapes

`FilingRequirementStatus` has three values with stable wires — `passed`,
`failed`, `could_not_evaluate`. `FilingRequirementRow.passed` is REPLACED by
`FilingRequirementRow.status`, and a row serializes as `requirement`, `status`,
`detail`. The boolean is gone rather than kept beside the enum, and there is no
boolean accessor over the enum: either would let a caller keep reading two
states out of three and silently re-fold the third back into a filing defect,
which is the defect this decision exists to remove. Every consumer switches
exhaustively.

`FilingReport.passed` stays the APPROVAL boolean and stays fail-closed: it is
true only when every row is `passed`, so checker incompleteness never reaches a
stamp. Beside it, `FilingReport.couldNotEvaluate` (wire `could_not_evaluate`)
says whether any row went unanswered, and `refusalReason` answers with a
checker-specific text — one that names the unevaluated rows and states that
nothing there says the filing is wrong — instead of "correct the bead and rerun
approve". A report carrying both an evaluated failure and an unanswered row
names both, in that order, and never hides one behind the other.

### The two rows, and the one absence that still decides something

For a nonblank plan, `validation_plan_syntax` reports `could_not_evaluate`
whenever its own parse is absent, for any reason.

`validation_plan_portability` keeps the `passed` not-probed short-circuit
whenever syntax has no successful parse — a plan no shell parses must not refuse
twice over the same text. Once syntax succeeds and portability reaches its own
gather, a MISSING portability shell stays an evaluated `failed`: CI's shell is a
declared floor, so a plan this machine cannot check against it is not cleared
for the lane that will run it. That refusal is pre-existing and deliberate, and
the gather now carries the fact behind it (`FilingEvidence.missing-`
`ValidationPlanShells`) so the row decides on a fact rather than on a substring
of a message. Every OTHER absent portability parse is `could_not_evaluate`.

### No retry inside the gather

The gather asks each shell ONCE and does not retry. A filing report is the
evidence SNAPSHOT its approval revision is a receipt for; a second spawn that
happened to succeed would erase the first checker failure and mint a receipt
over a fault nobody can see. The retry is the OPERATOR's, made explicitly by
rerunning the verb — so the row carries the spawn error that tells them to.
That is the other half of the fix: a row that could not gather now names WHAT
failed, and a gather that never ran at all says so as the composition gap it is,
instead of the bare "was not gathered" the resident reported with no reason
attached.

### Confirmation

`packages/grid_assets/test/filing/filing_contract_test.dart` pins the three wire
names and the three-field row JSON, and evaluates ONE bead under two checker
postures — a lane shell that refused the plan and a lane shell that never
answered — requiring both to be unapprovable and requiring the report, the row
and the wire to tell them apart.
`packages/grid_assets/test/filing/filing_viability_test.dart` fences each row:
a crashed installed probe is `could_not_evaluate` and carries its spawn error,
an answered nonzero parse stays `failed`, a not-installed portability shell
stays `failed`, the short-circuit stays `passed`, and the probe is asked exactly
once. The verb suites assert the rendering and that no stamp is written.

### Consequences

* Good, because a refiner reading a refusal can tell a bead to correct from a
  station to fix, which is the whole point.
* Good, because approval is unchanged where it matters: an unevaluated row is
  not a passing row, so nothing reaches a stamp on a checker that went quiet.
* Good, because the latent twin was fixed with the observed instance rather
  than left to surface later with no bead behind it.
* Bad, because it is a BREAKING change to a published type. Every consumer of a
  filing report — the filing verb, approve, unpark, the mount explainer, the
  GitHub self-approval note, and any station composing its own `FilingService`
  — had to migrate to an exhaustive switch.
* Bad, because the OTHER rows that fail closed on unavailable evidence —
  `bead_references` and `decision_references`, each refusing when a catalog or
  the decision index did not answer — keep their old shape. They are the same
  CLASS of conflation, they were not in this bead's scope, and they now have a
  named state to move to when one is filed.
