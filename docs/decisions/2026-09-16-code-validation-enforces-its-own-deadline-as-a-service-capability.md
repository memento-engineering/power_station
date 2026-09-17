---
status: accepted
date: 2026-09-16
decision-makers:
  - "Nico Spencer"
consulted:
  - "governor"
informed: []
register:
  spec: 1
  slug: code-validation-enforces-its-own-deadline-as-a-service-capability
  surfaces:
    - "packages/grid_assets/lib/src/code/committee.dart"
  obsoletes: []
  updates: ["code-validation-preserves-diagnostics-and-reports-deadline"]
  obsoleted-by: null
  updated-by: []
  bead: pow-qqrc
  legacy-id: null
---

# Code validation enforces its own deadline as a ServiceCapability

## Context and Problem Statement

pow-5n53 (P1) makes the `code-validation` lane's hard block a DELTA against the
merge-base: a failure identical on main must not gate a round. Its spec turns
`CodeValidationCapability` into a `ServiceCapability` (the house pattern used by
`DeclaredTestsCapability`, `FormatCleanCapability`, `SpecValidationCapability`)
that runs the Validation Plan twice — on the branch and in a scratch git
worktree at the merge-base — through a `SystemShellRunner`. A
`ServiceCapability` never returns a `RuntimeConfig` and is never watchdog-killed
by the `RuntimeProvider`, so the detection clause of
`code-validation-preserves-diagnostics-and-reports-deadline` — arm a stamp at
`.grid/critique-incarnation/code-validation.deadline`, complete only the watchdog
`Died` event that carries the exceeded-deadline-and-killed reason, read the
surviving stamp as the timeout verdict — has no event to match under the new
lane. The spec-review committee graded the spec F on decision alignment
(epoch 87, gate tranquility-vs59e) because the spec replaced that mechanism
without superseding it. The merge-base comparison run cannot live inside a
per-bead `RuntimeProvider` at all, so keeping the watchdog seam would mean two
deadline mechanisms for one lane.

## Decision Outcome

For the `code-validation` lane, the deadline is enforced by the lane itself:
`SystemShellRunner` terminates the plan's process group when `kGatingDeadline`
(ten minutes) elapses, awaits its exit, and returns `timedOut: true`; the lane
reports that as a durable grade-F result naming `kGatingDeadline`. The
runtime-provider watchdog `Died` arm, the `kGatingRubric` branch of
`CriticCapability.spawn`/`interpretEvent`/`result`, and the
`_gatingDeadlineStampRelativePath` stamp are retired for this lane in the same
change, as a named Touch of pow-5n53 — no dead detection code stays behind.
Everything else in `code-validation-preserves-diagnostics-and-reports-deadline`
stands: the full branch output of every Validation Plan is preserved and
reported, the ten-minute bound is unchanged, and a timeout is still a grade-F
verdict that names the deadline rather than a silent non-result. The LLM critic
lanes keep the runtime-provider watchdog; this entry governs only
`code-validation`.

### Consequences

* Good, because one lane has one deadline mechanism, and it works for the
  merge-base comparison run that no `RuntimeProvider` could watch.
* Good, because a timeout is still a loud, durable grade F naming the bound.
* Bad, because the runtime-provider watchdog no longer covers this lane: a
  shell runner bug that fails to kill the process group leaves a child running,
  so the lane's kill-and-await path must be tested directly.

### Confirmation

`grep -n kGatingRubric packages/grid_assets/lib/src/code/committee.dart` returns
nothing after pow-5n53 lands, and the lane's timeout test asserts
`timedOut: true` plus a grade-F verdict naming `kGatingDeadline`.
