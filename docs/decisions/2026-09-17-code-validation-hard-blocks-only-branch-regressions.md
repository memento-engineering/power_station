---
status: accepted
date: 2026-09-17
decision-makers:
  - "Nico Spencer"
consulted:
  - "governor"
informed: []
register:
  spec: 1
  slug: code-validation-hard-blocks-only-branch-regressions
  surfaces:
    - "packages/grid_assets/lib/src/code/committee.dart"
    - "packages/grid_assets/lib/src/code/code_capabilities.dart"
    - "packages/grid_assets/lib/src/code/landing.dart"
    - "packages/grid_assets/lib/src/code/pr_composition.dart"
  obsoletes: []
  updates:
    - "code-validation-preserves-diagnostics-and-reports-deadline"
    - "committee-gate-single-finding-advance-and-the-refinement-flag"
    - "declared-tests-evidence-is-scoped-to-the-path-it-governs"
    - "adr-0005-landing-policy-grade-gated-auto-merge"
  obsoleted-by: null
  updated-by: []
  bead: pow-8010
  legacy-id: null
---

# Code validation hard-blocks only branch regressions

## Context and Problem Statement

The deterministic `code-validation` lane hard-blocks a review round on ANY
failing test in the bead's Validation Plan. A failure that is identical on
main — a host-only flake, another bead's leak, a pre-existing red — therefore
gates the round exactly like a regression the round introduced, and because a
resolved gate does not re-arm the step (tg-2yx5) the false block costs an
operator round-trip and usually a rebuild. pow-5n53 (P1) measured the class and
proposed the delta; Nico ruled on it in chat on 2026-09-16: agreed — the hard
block becomes a delta.

## Decision Outcome

The lane runs the bead's Validation Plan twice on the same host — on the
branch and in a scratch worktree at the branch's merge-base with the review
base ref (`_reviewBaseRef`) — and hard-blocks ONLY on a normalized, named test
failure that is present on the branch and absent at the merge-base. A failure
present in both runs is pre-existing evidence: it is named in the critique
artifact as a NOTE and cannot gate. A run without a valid, comparable test
outcome on both sides (a lane failure: base worktree could not be cut, a plan
timed out, output could not be parsed) is reported as a lane failure and never
fabricated into a grade. `.grid/critique/code-validation.rc` is the effective
delta receipt (`0` when there are no regressions, otherwise the raw non-zero
branch exit) while the raw branch exit and the two failure sets stay in the
JSON artifact; the full branch output is still written to the log. The
committee route, declared-tests evidence and landing policy read the delta
result where they read the lane's verdict today; their own rules are unchanged.

### Consequences

* Good, because a round can no longer be blocked by a red it did not cause.
* Good, because a pre-existing red is still reported, by name, instead of
  hidden.
* Bad, because every code-validation run costs a second plan execution at the
  merge-base; a per-base, per-plan cache on the grid home bounds that cost.
