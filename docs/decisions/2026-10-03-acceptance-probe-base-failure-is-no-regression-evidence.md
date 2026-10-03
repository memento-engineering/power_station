---
status: accepted
date: 2026-10-03
decision-makers:
  - "Nico Spencer"
consulted: []
informed: []
register:
  spec: 1
  slug: acceptance-probe-base-failure-is-no-regression-evidence
  surfaces:
    - "packages/grid_assets/lib/src/code/validation.dart"
    - "packages/grid_assets/lib/src/code/committee.dart"
    - "packages/grid_assets/lib/src/code/landing.dart"
    - "packages/grid_assets/lib/src/code/pr_composition.dart"
  obsoletes: []
  updates:
    - "code-validation-hard-blocks-only-branch-regressions"
  obsoleted-by: null
  updated-by: []
  bead: pow-d8t8
  legacy-id: null
---

# An acceptance-probe base failure is no regression evidence

## Context and Problem Statement

`code-validation-hard-blocks-only-branch-regressions` runs the bead's
Validation Plan at the merge base and treats any run "without a valid,
comparable test outcome on both sides" as a lane failure. Many Validation
Plans are ACCEPTANCE PROBES rather than test runs — `flutter pub get && grep
-q isConnectable … && awk …` — and a probe MUST fail at the merge base,
because the feature it probes does not exist there yet. The base leg exits 1
naming no failing test, the lane reports that as an uncomparable base, and the
engine files the `noResult` under harness silence: on the first rounds under
the delta lane every probe-shaped plan raised `harness.throttled` with one
"silent exit" and parked at a human gate, although no model step had run at
all.

## Decision Outcome

A merge-base plan run that COMPLETES (no deadline cut, scratch worktree made
and unwound) with a non-zero exit and no named failing test contributes NO
regression evidence. The comparison treats its failure set as empty, so the
branch result alone decides: a passing branch passes, a named branch failure
is a regression, and a branch that fails naming no test is still a lane
failure. The verdict records the base's raw exit (`baseRc`) and its bounded,
pub-advice-stripped output tail (`baseOutputTail`), and the PR circuit
receipt states the fact on one line (`- base validation: <note>`). The
completed no-evidence base outcome is cached like any other comparable base.

A deterministic lane's completed process exit is never reported as an
artifact-less model step: a lane failure that is a completed, non-timeout
process exit is an `invalidResult`, and `noResult` is kept for operational
absence — a deadline cut or a merge-base worktree that could not be made.
Both kinds spend the lane's one-attempt park policy. True artifact-less model
silence keeps the engine's existing harness classification.

### Consequences

* Good, because a probe-shaped Validation Plan no longer parks every round at
  a false "harness throttled" gate.
* Good, because the base's exit and tail stay on record, so a base that fails
  for the wrong reason is still visible to a reviewer.
* Bad, because a base that is genuinely broken (a compile error at main) no
  longer stops the comparison; the branch result decides alone, so a branch
  that passes ships without a base-side comparison.
